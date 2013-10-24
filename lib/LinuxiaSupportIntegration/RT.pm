package LinuxiaSupportIntegration::RT;
use strict;
use warnings;
use base 'RT::Client::REST';

sub linuxia_create {
    my ($self, $body, $eml, $opts) = @_;
    my $ticket = $self->create(type => 'ticket',
                               set => {
                                       Queue => $opts->{queue} || "General",
                                       Requestor => $eml->header('From'),
                                       Subject => $opts->{subject} || $eml->header('Subject'),
                                      },
                               text => $body);
    return $ticket;
};

sub linuxia_comment {
    my ($self, $ticket, $body, $eml, $opts) = @_;
    $self->comment(ticket_id => $ticket,
                   message => $body);
    return "Comment added on ticket $ticket";
}

sub linuxia_correspond {
    my ($self, $ticket, $body, $eml, $opts) = @_;
    $self->correspond(ticket_id => $ticket,
                      message => $body);
    return "Correspondence added on ticket $ticket";

}

1;

