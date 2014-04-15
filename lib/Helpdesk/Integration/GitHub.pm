package LinuxiaSupportIntegration::GitHub;
use strict;
use warnings;

use Net::GitHub;
use Data::Dumper;

use Moo;
extends 'LinuxiaSupportIntegration::Instance';

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
    my @details = (LinuxiaSupportIntegration::Ticket->new(%detail));

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
        my $obj = LinuxiaSupportIntegration::Ticket->new(%comment);
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


1;
