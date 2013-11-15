package LinuxiaSupportIntegration::RT;
use strict;
use warnings;
use RT::Client::REST;

use Moo;
extends 'LinuxiaSupportIntegration::Instance';

has rt_obj => (is => 'rwp');

has url => (is => 'ro',
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
        print "RT object empty, creating\n";
        $rt = RT::Client::REST->new(server => $self->url,
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
    return $ticket,
      "Created ticket " . $self->url ."/Ticket/Display.html?id=$ticket";
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
is a L<LinuxiaSupportIntegration::RT::Mail> object.

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
    my @trxs = $self->rt->get_transaction_ids(parent_id => $ticket, type => 'ticket');
    my $fullticket = $self->rt->show(type => 'ticket', id => $ticket);
    my %ticket_details = (
                          date => $fullticket->{Created},
                          from => $fullticket->{Creator},
                          subject => " #$ticket : " . $fullticket->{Subject},
                          body => "RT ticket $ticket in queue $fullticket->{Queue}",
                         );
    my @details = (LinuxiaSupportIntegration::Ticket->new(%ticket_details));
    # probably here we want to take the first mail and dump it as body
    # of the ticket creation action.
    my @attachments = $self->rt->get_attachment_ids(id => $ticket);
    my %rt_attachments;
    foreach (@attachments) {
        my $att = $self->rt->get_attachment(parent_id => $ticket,
                                            id => $_,
                                            undecoded => 1,
                                           );
        print $att->{id}, " => ",
          $att->{ContentType} || "", " => ", $att->{Filename} || "", "\n";
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
        my $obj = LinuxiaSupportIntegration::Ticket->new(
                                                         date => $mail->{Created},
                                                         body => $mail->{Content},
                                                         from => $mail->{Creator},
                                                         subject => " #$ticket: " . $mail->{Description},
                                                         attachments => \@current_atts,
                                                        );
        push @details, $obj;
    }
    # print Dumper(\@details);
    # mimic the output of parse_mails from IMAP, set index undef
    # so we don't end moving mails around.
    return map { [ undef, $_ ] } @details;
}


1;

