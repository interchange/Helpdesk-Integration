package Helpdesk::Integration::EmailFile;

use strict;
use warnings;
use Moo;
use Path::Tiny;
with qw/Helpdesk::Integration::EmailParser/;

=head1 NAME

Helpdesk::Integration::EmailFile - Support for .eml

=head1 DESCRIPTION

Inherits from L<Helpdesk::Integration::EmailParser>

=head1 ACCESSORS

=head2 file

=head2 parsed_email

The L<Helpdesk::Integration::Ticket> object resulting from the
parsing.

=head1 METHODS

=head2 parse_messages

Same as the other H::I instances.

=cut



has file => (is => 'ro', required => 1);

has parsed_email => (is => 'lazy');

sub _build_parsed_email {
    my $self = shift;
    my $path = path($self->file);
    if ($path->exists) {
        my $body = $path->slurp_raw;
        my $parsed = $self->parse_body_message(\$body);
        return $parsed;
    }
    else {
        die $path . ' does not exist';
    }
}

sub parse_messages {
    my $self = shift;
    return [undef, $self->parsed_email];
}


1;
