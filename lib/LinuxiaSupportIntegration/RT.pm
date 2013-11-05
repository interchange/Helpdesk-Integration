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

sub linuxia_comment {
    my ($self, $ticket, $body, $eml, $opts) = @_;
    $self->comment(ticket_id => $ticket,
                   message => $body,
                   attachments => [ $eml->attachments_filenames ],
                  );
    return "Comment added on ticket $ticket";
}

sub linuxia_correspond {
    my ($self, $ticket, $body, $eml, $opts) = @_;
    $self->correspond(ticket_id => $ticket,
                      message => $body,
                      attachments => [ $eml->attachments_filenames ],
                     );
    return "Correspondence added on ticket $ticket";

}

1;

