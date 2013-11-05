package LinuxiaSupportIntegration::RT;
use strict;
use warnings;
use base 'RT::Client::REST';

sub linuxia_create {
    my ($self, $body, $eml, $opts) = @_;
    my $ticket = $self->create(type => 'ticket',
                               set => {
                                       Queue => $opts->{queue} || "General",
                                       Requestor => $eml->from,
                                       Subject => $opts->{subject} || $eml->subject,
                                      },
                               text => $body);
    return $ticket;
};

sub _linuxia_do {
    my ($self, $action, $ticket, $body, $eml, $opts) = @_;
    my @attach = $eml->attachments_filenames;
    foreach (@attach) {
        die "Couldn't find $_ " unless -f $_;
    }
    $self->$action(ticket_id => $ticket,
                   attachments => [ @attach ],
                   message => $body);
    return ucfirst($action) . " added on ticket $ticket";
}


sub linuxia_comment {
    my ($self, @args) = @_;
    return $self->_linuxia_do(comment => @args);
}

sub linuxia_correspond {
    my ($self, @args) = @_;
    return $self->_linuxia_do(correspond => @args);
}


=head2 parse_mails(ticket => $ticket)

Access via REST the ticket $ticket and return a list of arrayrefs.
Each arrayref has two elements: the first is always undef, the second
is a L<LinuxiaSupportIntegration::RT::Mail> object.

The first element is undef because we don't want to move around mails
when we look into RT.

=cut


sub parse_messages {
    my ($self, %params) = @_;
    my $ticket = $params{ticket};
    return unless defined $ticket;
    my @trxs = $self->get_transaction_ids(parent_id => $ticket, type => 'ticket');
    my $fullticket = $self->show(type => 'ticket', id => $ticket);
    my %ticket_details = (
                          date => $fullticket->{Created},
                          from => $fullticket->{Creator},
                          subject => " #$ticket : " . $fullticket->{Subject},
                          body => "RT ticket $ticket in queue $fullticket->{Queue}",
                         );
    my @details = (LinuxiaSupportIntegration::Ticket->new(%ticket_details));
    # probably here we want to take the first mail and dump it as body
    # of the ticket creation action.
    foreach my $trx (@trxs) {
        my $mail = $self->get_transaction(parent_id => $ticket,
                                              id => $trx,
                                              type => 'ticket');
        if ($mail->{Type} eq 'Status' and
            (!$mail->{Content} or
             $mail->{Content} eq 'This transaction appears to have no content')) {
            next;
        }
        my $obj = LinuxiaSupportIntegration::Ticket->new(
                                                         date => $mail->{Created},
                                                         body => $mail->{Content},
                                                         from => $mail->{Creator},
                                                         subject => " #$ticket: " . $mail->{Description},
                                                        );
        push @details, $obj;
    }
    # print Dumper(\@details);
    # mimic the output of parse_mails from IMAP, set index undef
    # so we don't end moving mails around.
    return map { [ undef, $_ ] } @details;
}


1;

