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
has options => (is => 'rw',
                default => sub { return {} },
                isa => sub {
                    die "options must be a hashref"
                      unless (ref($_[0]) && ref($_[0]) eq 'HASH');
                });

# No op method, to be override by subclasses
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



