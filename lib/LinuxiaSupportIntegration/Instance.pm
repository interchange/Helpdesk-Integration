package LinuxiaSupportIntegration::Instance;

use strict;
use warnings;

use Moo;

=head1 NAME

LinuxiaSupportIntegration::Instance - Base class for Helpdesk classes

=cut

has debug_mode => (is => 'ro');
has error => (is => 'rwp');
has search_params => (is => 'rw',
                      default => sub { return {} },
                      isa => sub {
                          die "search_params must be a hashref"
                            unless (ref($_[0]) && ref($_[0]) eq 'HASH');
                      });

has message_cache => (is => 'rw');
has target_name_field   => (is => 'ro');
has target_id_field     => (is => 'ro');
has target_queue_field  => (is => 'ro');

has target_name  => (is => 'rwp');
has target_id    => (is => 'rwp');
has target_queue => (is => 'rwp');

sub clean_cache {
    my $self = shift;
    $self->message_cache(undef);
}

# No op methods, to be override by subclasses

=head2 search_target

Try to set target_name and target_id looking into the messages.

=cut

sub search_target {
    return;
}

sub archive_messages {
    return;
}

sub project {
    return;
}

sub type {
    return "dummy";
}

has append  => (is => 'rw');
has queue   => (is => 'rw');
has subject => (is => 'rw');
has is_comment => (is => 'rw');

1;



