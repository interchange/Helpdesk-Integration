package Helpdesk::Integration::GitHub;
use strict;
use warnings;

use Net::GitHub;
use Data::Dumper;

use Moo;
with 'Helpdesk::Integration::Instance';

=head2 ACCESSORS

The following keys must be passed to the constructor:

=over 4

=item user

=item password

=back

B<or>, alternatively (you can create a token for your user at
L<https://github.com/settings/applications>, under I<Personal Access Tokens>)

=over 4

=item access_token

=back

The C<access_token> will be used if you set both C<password> and
C<access_token>

Optinally, for Enterprise installations:

=over 4

=item api_url

=back

=cut

has user => (is => 'ro',
             required => 1);
has password => (is => 'ro');
has access_token => (is => 'ro');
has api_url => (is => 'ro');

has gh_obj => (is => 'rwp');

=head2 login

Empty method, not needed.

=cut

sub login {
    return;
}

sub gh {
    my $self = shift;
    my $gh = $self->gh_obj;
    unless ($gh) {

        my %new;
        if (my $token = $self->access_token) {
            %new = (
                    access_token => $token,
                   );
        }
        else {
            %new = (
                    login => $self->user,
                    pass => $self->password,
                   );
        }

        # Pass api_url for GitHub Enterprise installations
        if (my $api_url = $self->api_url) {
            $new{api_url} = $api_url;
        }

        # die on errors, we are going to catch the exceptions
        $new{RaiseError} = 1;
        $gh = Net::GitHub->new(%new);
    }
    return $gh;
}

sub create {
    my ($self, $eml) = @_;
    my $issue = $self->gh->issue;
    $issue->set_default_user_repo($self->user, $self->queue);
    my %details = (
                   title => $eml->subject,
                   body => $eml->as_string,
                  );
    if (my @assigned = @{$self->_assign_to}) {
        $details{assignee} = $assigned[0]; # guaranteed to be only one.
    }
    my $ticket = $issue->create_issue(\%details);
    return $ticket->{number},
      "\nCreated GH issue $ticket->{html_url}";
}

sub create_comment {
    my ($self, $eml) = @_;
    my $issue = $self->gh->issue;
    $issue->set_default_user_repo($self->user, $self->queue);
    my $comment = $issue->create_comment($self->append,
                                         {
                                          body => $eml->as_string,
                                         });
    return "Created GH comment: " . $comment->{html_url};
}

sub correspond {
    my ($self, @args) = @_;
    return $self->create_comment(@args);
}

sub comment {
    my ($self, @args) = @_;
    return $self->create_comment(@args);
}

sub parse_messages {
    my $self = shift;
    my $id = $self->search_params->{ticket};
    return unless defined $id;
    if ($self->message_cache->{$id}) {
        warn "found message_cache\n";
        return @{ $self->message_cache->{$id} };
    }
    # my $issue = $self->gh->issue;
    # print Dumper([ $issue->repos_issues($self->user, $self->queue) ]);
    my $issue = $self->gh->issue;
    $issue->set_default_user_repo($self->user, $self->queue);
    my $main = $issue->issue($id);
    my %detail = (
                  date => $main->{created_at},
                  from => $main->{user}->{login} || "nobody",
                  subject => $main->{title},
                  body => $main->{body},
                 );
    my @details = (Helpdesk::Integration::Ticket->new(%detail));

    # and now check the comments

    my @comments = $issue->comments($id);
    foreach my $cmt (@comments) {
        # print Dumper($cmt);
        my %comment = (
                       date => $cmt->{created_at},
                       from => $cmt->{user}->{login} || "nobody",
                       subject => "Comment on #$id",
                       body => $cmt->{body},
                      );
        my $obj = Helpdesk::Integration::Ticket->new(%comment);
        push @details, $obj;
    }

    my @out = map { [ undef, $_ ] } @details;
    $self->message_cache({ $id => \@out});
    return @out;
}

sub type {
    return "github";
}

sub image_upload_support {
    return 0;
}

=head2 assign_tickets

The GitHub API seems not to permit multiple workers to be assigned.
Hence, we return only the first, and if more are found, a warning is
issued.

http://developer.github.com/v3/issues/#create-an-issue

The API doesn't return emails, so username has to be provided.

=cut

sub assign_tickets {
    my ($self, @workers) = @_;
    my @out;
    my $repos = $self->gh->repos;
    $repos->set_default_user_repo($self->user, $self->queue);
    my $repo = $repos->get;
    my @assignees = ($repo->{owner}->{login});
    foreach my $collaborator ($repos->collaborators) {
        # warn Dumper($collaborator);
        next if $collaborator->{login} eq $repo->{owner}->{login};
        push @assignees, $collaborator->{login};

    }
    foreach my $worker (@workers) {
        my $found;
        foreach my $avail (@assignees) {
            if ($avail eq $worker) {
                $found = $avail;
                last;
            }
        }
        if ($found) {
            push @out, $found;
        }
        else {
            warn "WARNING: $worker not found in assignees!\n";
        }
    }
    if (@out > 1) {
        warn "Multiple assignment found, using the first: $out[0]\n";
        @out = ($out[0]);
    }
    if (@out) {
        $self->_assign_to(\@out);
    }
    else {
        warn "Available assignees: " . join(", ", @assignees) . "\n";
    }
}

sub set_owner {
    my ($self, $issue_id) = @_;
    my ($worker) = @{$self->_assign_to};
    return unless $worker;
    my $issue = $self->gh->issue;
    $issue->set_default_user_repo($self->user, $self->queue);
    $issue->update_issue($issue_id, { assignee => $worker });
}

sub get_labels {
    my ($self) = @_;
    my $url = '/repos/' . $self->user . '/' . $self->queue . '/labels';
    return $self->gh->query($url);
}

sub set_labels {
    my ($self, @labels)  = @_;
    my @existing = $self->get_labels;
    my %existing_labels;
    foreach my $exist (@existing) {
        $existing_labels{$exist->{name}} = $exist->{color};
    }
    #    print Dumper(\%existing_labels);
    my (@create, @update);
    my $base_url = '/repos/' . $self->user . '/' . $self->queue . '/labels';
    foreach my $label (@labels) {
        my $set = {
                   color => $label->{color},
                   name => $label->{name},
                  };
        if (exists $existing_labels{$set->{name}}) {
            if ($existing_labels{$set->{name}} ne $set->{color}) {
                $self->gh->query(PATCH => $base_url . '/' . $set->{name}, $set);
                print "Updating $set->{name} with color $set->{color}\n";
            }
        }
        else {
            print "Creating $set->{name} with color $set->{color}\n";
            $self->gh->query(POST => $base_url, $set);
        }
    }
}

=head1 SEARCH

=head2 free_search(%params)

=head3 supported keys

See L<https://developer.github.com/v3/issues/>

=over 4

=item milestone

Integer or string.

If an integer is passed, it should refer to a milestone by its number field. If the string * is passed, issues with any milestone are accepted. If the string none is passed, issues without milestones are returned.

=item state

Indicates the state of the issues to return. Can be either open, closed, or all. Default: open

=item assignee

Can be the name of a user. Pass in none for issues with no assigned user, and * for issues assigned to any user.

=item creator

The user that created the issue.

=item mentioned

A user that's mentioned in the issue.

=item labels

A list of comma separated label names. Example: bug,ui,@high

=item sort

What to sort results by. Can be either created, updated, comments. Default: created

=item direction

The direction of the sort. Can be either asc or desc. Default: desc

=item since

Only issues updated at or after this time are returned. This is a timestamp in ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ.

=back

=cut

sub free_search {
    my ($self, %params) = @_;
    my %supported = (
                     milestone => 1,
                     state => 1,
                     assignee => 1,
                     creator => 1,
                     mentioned => 1,
                     labels => 1,
                     sort => 1,
                     direction => 1,
                     since => 1,
                    );
    my %query;
    foreach my $key (keys %params) {
        my $lckey = lc($key);
        if ($supported{$lckey}) {
            $query{$lckey} = delete $params{$key};
        }
    }
    if (%params) {
        warn "Unsupported parameters : " . join(' ', keys %params) . "\n";
    }
    print "Query is " . Dumper(\%query);
    my @issues = $self->gh->issue->repos_issues($self->user, $self->queue, { %query });
    return map { Helpdesk::Integration::Ticket
        ->new(url => $_->{html_url},
              subject => $_->{title},
              id => $_->{number});
    } @issues;
}


1;
