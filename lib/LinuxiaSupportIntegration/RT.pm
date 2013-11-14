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
    my ($self, %params) = @_;
    my $ticket = $params{ticket};
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
#        print Dumper($self->rt->get_attachment(parent_id => $ticket,
#                                               id => $trx,
#                                              ));
#

=head3 Needed patch to RT::Client::REST

It seems that the request is first decoded (probably delegated to lwp)
and then parsed, but doing so binary attachments are mangled. Only the
raw request should be passed.

 @@ -155,7 +155,7 @@
      my $id = $self->_valid_numeric_object_id(delete($opts{id}));
  
      my $form = form_parse(
 -        $self->_submit("$type/$parent_id/attachments/$id")->decoded_content
 +        $self->_submit("$type/$parent_id/attachments/$id")->content
      );
      my ($c, $o, $k, $e) = @{$$form[0]};

=cut

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

sub archive_messages {
    # no op
    return;
}


1;

