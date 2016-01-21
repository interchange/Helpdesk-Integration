package Helpdesk::Integration::RT;
use strict;
use warnings;
use Try::Tiny;
use RT::Client::REST;
use Date::Parse;
use DateTime;
use Helpdesk::Integration::Ticket;
use Data::Dumper;
use Moo;
with 'Helpdesk::Integration::Instance';

has rt_obj => (is => 'rwp');


=head2 ACCESSORS

The following keys must be passed to the constructor

=over 4

=item server

(the RT url, e.g. "http://localhost/rt")

=item user

=item password

=item timeout (optional)

=back

=cut

has server => (is => 'ro',
            required => 1);
has timeout => (is => 'ro',
                default => sub { return 30 });
has user => (is => 'ro',
             required => 1);
has password => (is => 'ro',
                 required => 1);

sub rt {
    my $self = shift;
    my $rt = $self->rt_obj;
    unless ($rt) {
        # print "RT object empty, creating\n";
        $rt = RT::Client::REST->new(server => $self->server,
                                    timeout => $self->timeout);
        $self->_set_rt_obj($rt);
    }
    return $rt;
}

sub login {
    my $self = shift;
    $self->rt->login(username => $self->user, password => $self->password);
}


sub create {
    my ($self, $eml) = @_;
    my $ticket = $self->rt->create(type => 'ticket',
                                   set => {
                                           Queue => $self->queue || "General",
                                           Requestor => $eml->from,
                                           Subject => $self->subject || $eml->subject,
                                          },
                                   text => $eml->as_string);
    $self->set_owner($ticket);
    return $ticket,
      "Created ticket " . $self->_format_ticket_link($ticket);
}

sub _format_ticket_link {
    my ($self, $id) = @_;
    die "Bad usage" unless defined $id;
    return $self->server ."/Ticket/Display.html?id=$id";
}

sub _rt_do {
    my ($self, $action, $eml) = @_;
    my @attach = $eml->attachments_filenames;
    foreach (@attach) {
        die "Couldn't find $_ " unless -f $_;
    }
    my $ticket = $self->append;
    $self->rt->$action(ticket_id => $ticket,
                       attachments => [ @attach ],
                       message => $eml->as_string);
    return ucfirst($action) . " added on ticket $ticket";
}


sub comment {
    my ($self, @args) = @_;
    return $self->_rt_do(comment => @args);
}

sub correspond {
    my ($self, @args) = @_;
    return $self->_rt_do(correspond => @args);
}


=head2 parse_messages(ticket => $ticket)

Access via REST the ticket $ticket and return a list of arrayrefs.
Each arrayref has two elements: the first is always undef, the second
is a L<Helpdesk::Integration::RT::Mail> object.

The first element is undef because we don't want to move around mails
when we look into RT.

=cut


sub _message_type_should_be_relayed {
    my ($self, $type) = @_;
    my %good = (
                Create => 1,
                Correspond => 1,
                Comment => 1,
               );
    return $good{$type};
}

sub parse_messages {
    my $self = shift;
    my $ticket = $self->search_params->{ticket};
    return unless defined $ticket;
    if ($self->message_cache->{$ticket}) {
        warn "found message_cache\n";
        return @{ $self->message_cache->{$ticket} };
    }
    my @trxs = $self->rt->get_transaction_ids(parent_id => $ticket, type => 'ticket');
    my $fullticket = $self->rt->show(type => 'ticket', id => $ticket);
    die "No ticket $ticket found" unless $fullticket;

    for my $n (qw/name id queue/) {
        my $field_method = "target_${n}_field";
        my $setter_method = "_set_target_${n}";
        if (my $cf_name = $self->$field_method) {
            if (my $target = $fullticket->{"CF.{$cf_name}"}) {
                warn "Found $n $cf_name => $target";
                $self->$setter_method($target);
            }
        }
    }


# if you have the relevant custom fields set, you would just need to
# specify the ticket and have it routed correctly, right? use

# Custom fields have pattern CF.{}

# $VAR1 = { 
#           'TimeEstimated' => '',
#           'Status' => 'open',
#           'Queue' => 'General',
#           'AdminCc' => '',
#           'CF.{Teamwork id}' => '13411234',
#           'Requestors' => '',
#           'Started' => 'Thu Oct 17 10:38:04 2013',
#           'InitialPriority' => '',
#           'Starts' => 'Not set',
#           'TimeWorked' => '',
#           'id' => 'ticket/2',
#           'LastUpdated' => 'Mon Nov 18 11:37:19 2013',
#           'CF.{Remote system}' => 'informa_teamwork',
#           'Told' => 'Not set',
#           'Cc' => '',
#           'Subject' => 'Another test',
#           'FinalPriority' => '',
#           'TimeLeft' => '',
#           'Creator' => 'root',
#           'Owner' => 'Nobody',
#           'Resolved' => 'Not set',
#           'Created' => 'Tue Oct 08 09:37:52 2013',
#           'Priority' => '',
#           'Due' => 'Not set'
#         };
# 

    my %ticket_details = (
                          date => $fullticket->{Created},
                          from => $fullticket->{Creator},
                          start => str2time($fullticket->{Starts}),
                          due   => str2time($fullticket->{Due}),
                          subject => " #$ticket : " . $fullticket->{Subject},
                          body => "RT ticket $ticket in queue $fullticket->{Queue}",
                         );
    my @details = (Helpdesk::Integration::Ticket->new(%ticket_details));
    # probably here we want to take the first mail and dump it as body
    # of the ticket creation action.
    my @attachments = $self->rt->get_attachment_ids(id => $ticket);
    my %rt_attachments;
    foreach (@attachments) {
        my $att = $self->rt->get_attachment(parent_id => $ticket,
                                            id => $_,
                                            undecoded => 1,
                                           );
        # print $att->{id}, " => ",
        #  $att->{ContentType} || "", " => ", $att->{Filename} || "", "\n";
        $rt_attachments{$att->{id}} = [ $att->{Filename}, $att->{Content} ];
    }
    foreach my $trx (@trxs) {
        my $mail = $self->rt->get_transaction(parent_id => $ticket,
                                              id => $trx,
                                              type => 'ticket');
        my @current_atts;
        if (my $att_desc = $mail->{Attachments}) {
            my @atts = split("\n", $att_desc);
            foreach my $att (@atts) {
                if ($att =~ m/\d+: untitled \(\d[kb]\)$/) {
                    next;
                }
                if ($att =~ m/^(\d+):/) {
                    # check if the attachment is present and has a name
                    if (exists $rt_attachments{$1} and $rt_attachments{$1}->[0]) {
                        push @current_atts, $rt_attachments{$1};
                    }
                }
            }
        }
        next unless $self->_message_type_should_be_relayed($mail->{Type});
        my $obj = Helpdesk::Integration::Ticket->new(
                                                         date => $mail->{Created},
                                                         body => $mail->{Content},
                                                         from => $mail->{Creator},
                                                         trxid => $trx,
                                                         subject => " #$ticket: " . $mail->{Description},
                                                         attachments => \@current_atts,
                                                        );
        push @details, $obj;
    }
    # print Dumper(\@details);
    # mimic the output of parse_mails from IMAP, set index undef
    # so we don't end moving mails around.
    my @out = map { [ undef, $_ ] } @details;
    $self->message_cache({ $ticket => \@out });
    return @out;
}

sub type {
    return "rt";
}

sub image_upload_support {
    return 1;
}

# search_target will just call parse_messages, which in turn will put
# the messages in the cache and set target_name and target_id, if any
sub search_target {
    my $self = shift;
    # print "Searching messages\n";
    $self->parse_messages;
}

=head3 set_owner($ticket)

Set the owner to the ticket passed as argument to the persons found in
the C<_assign_to> arrayref (to be set with the assign_tickets method)

=cut

sub set_owner {
    my ($self, $ticket) = @_;
    my @workers = @{$self->_assign_to};
    return unless @workers;
    my $worker_string = join(",", @workers);
    try {
        $self->rt->edit(type => 'ticket',
                        id => $ticket,
                        set => {
                                Owner => $worker_string,
                               });
    } catch {
        warn "Couldn't assign $ticket to $worker_string: $_\n";
    };
}

=head3 Timing

The following two methods set the Starts and the Due dates in the
given ticket. The first argument is the ticket, the second the Unix
epoch time. You can get the epoch out of almost any formatted date
with the L<Date::Parse> module (str2time).

=over 4

=item set_start_date($ticket, $epoch)

=item set_due_date($ticket, $epoch)

=back

=cut

sub set_start_date {
    my ($self, $ticket, $date) = @_;
    $self->_set_date_field_ticket(Starts => $ticket, $date);
}

sub set_due_date {
    my ($self, $ticket, $date) = @_;
    $self->_set_date_field_ticket(Due => $ticket, $date);
}

sub _set_date_field_ticket {
    my ($self, $field, $ticket, $epoch) = @_;
    return unless $field && $ticket && $epoch;
    my $date = DateTime->from_epoch(epoch => $epoch)->iso8601;
    try {
        $self->rt->edit(type => 'ticket',
                        id => $ticket,
                        set => {
                                $field => $date,
                               });
    } catch {
        warn "Couldn't set $field to " . localtime($epoch) . " for $ticket: $_\n";
    };
}

sub link_to_ticket {
    my ($self, $target, $type) = @_;
    my $src = $self->append;
    unless ($src) {
        warn "It looks like we don't have a ticket id to link, yet, couldn't proceed\n";
        return;
    }
    die "Missing target" unless $target;
    die "Missing type" unless $type;
    my @available = (qw/DependsOn
                        DependedOnBy
                        RefersTo
                        ReferredToBy
                        HasMember
                        MemberOf/);
    my %map;
    foreach my $avail (@available) {
        my $lc = lc($avail);
        $map{$lc} = $avail;
    }
    my $typelc = lc($type);
    $typelc =~ s/_//g;

    my $realtype = $map{$typelc};
    unless ($realtype) {
        die "$type is not a valid link type";
    }
    try {
        $self->rt->link_tickets(src => $src,
                                dst => $target,
                                link_type => $realtype);
    } catch {
        warn "Couldn't link src $src and dst $target as $realtype: $_\n"
    };
}

=head1 SEARCH

=head2 free_search(%parameters)

C<--from> becomes C<requestor>, C<--workers> becomes C<owner>,
C<--status> become C<status>

=cut

sub free_search {
    my ($self, %params) = @_;
    my @queries;
    my %mapped = (
                  '' => sub { },
                  '--from' => sub {
                      $params{requestor} = shift;
                  },
                  '--subject' => sub {
                      $params{subject} = shift;
                  },
                  '--workers' => sub {
                      $params{owner} = shift;
                  },
                 );
    foreach my $key (keys %mapped) {
        if (exists $params{$key}) {
            $mapped{$key}->(delete $params{$key});
        }
    }
    # handle the status if passed via --status, but don't do anything
    # if passed literally
    unless ($params{status} || $params{Status}) {
        my %statuses = (
                        open => sub {
                            push @queries, "(Status = 'new' or Status = 'open' or Status = 'stalled')";
                        },
                        closed => sub {
                            push @queries, "(Status = 'resolved' or Status = 'rejected')";
                        },
                        all => sub {
                            # do nothing
                            return;
                        },
                       );
        $statuses{$self->default_search_status}->();
    }

    foreach my $k (keys %params) {
        my $value = $params{$k};
        $value =~ s/'//g;
        if ($value =~ m/^!\s*(.+)/) {
            my $negated = $1;
            push @queries, "($k != '$negated') AND ($k NOT LIKE '$negated')";
        }
        else {
            push @queries, "(($k = '$value') OR ($k like '$value'))";
        }
    }
    my $query = join(' AND ', @queries);
    print "Query is $query\n";
    my @ids = $self->rt->search(type => 'ticket',
                        query => $query,
                        orderby => '-id',
                               );
    my @out;
    foreach my $id (@ids) {
        my $details = $self->rt->show(type => 'ticket', id => $id);
        $details->{id} = $id;
        push @out, $details;
    }
    # print Dumper(\@out);
    return map { Helpdesk::Integration::Ticket
        ->new(url => $self->_format_ticket_link($_->{id}),
              subject => $_->{Subject},
              id => $_->{id});
    } @out;
}


1;

