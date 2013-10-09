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
                                       Subject => $eml->header('Subject'),
                                      },
                               text => $body);
    return $ticket;
};

sub linuxia_comment {
    my ($self, $ticket, $body, $eml, $opts) = @_;
    return $self->comment(ticket_id => $ticket,
                          message => $body);
}

sub linuxia_correspond {
    my ($self, $ticket, $body, $eml, $opts) = @_;
    return $self->correspond(ticket_id => $ticket,
                             message => $body);

}

1;

