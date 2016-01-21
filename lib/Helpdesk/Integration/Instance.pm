package Helpdesk::Integration::Instance;

use strict;
use warnings;
use Moo::Role;
use Helpdesk::Integration::Ticket;

requires qw/type parse_messages login
            comment correspond create/;

=head1 NAME

Helpdesk::Integration::Instance - Moo role for Helpdesk classes

=head2 REQUIRES

The role requires the consumer to implement the following methods:

=over 4

=item type

=item login

=item parse_messages

=item create

=item comment

=item correspond

=back

=head1 ACCESSORS/METHODS

=head2 ACCESSORS

=over 4

=item debug_mode

=item error

=item search_params({ key => "value", key2 => "value2" })

Each subclass has its own set of keys/values to retrive the messages
to be copied to another instance.

=item project

The default project to use

=item queue

The default queue (also called todo-list) to use.

=item workers

The default workers for the instance. This is used only to store the
defaults on object building. You have to call
$self->assign_ticket($self->list_workers) to assign.

=back

RT instances can define the custom fields. Keys to be passed to the
constructor to define the custom field mapping:

=over 4

=item target_name_field 

=item target_queue_field

=item target_id_field

=back

After the message parsing, the targets can be accessed with the
following accessors:

=over 4

=item target_name

=item target_queue

=item target_id

=back

They will return false if there is nothing set.

=head2 INTERNALS

=over 4

=item message_cache

=item clean_cache

=item conf_name

The name used in the configuration.

=back

=cut


has debug_mode => (is => 'ro');
has error => (is => 'rwp');
has search_params => (is => 'rw',
                      default => sub { return {} },
                      isa => sub {
                          die "search_params must be a hashref"
                            unless (ref($_[0]) && ref($_[0]) eq 'HASH');
                      });

has message_cache => (is => 'rw',
                      default => sub { return {} });
has target_name_field   => (is => 'ro');
has target_id_field     => (is => 'ro');
has target_queue_field  => (is => 'ro');

has target_name  => (is => 'rwp');
has target_id    => (is => 'rwp');
has target_queue => (is => 'rwp');

has conf_name => (is => 'rwp');

sub clean_cache {
    my $self = shift;
    $self->message_cache({});
}

# No op methods, to be override by subclasses

=head2 METHODS

=over 4

=item search_target

Try to set C<target_name>, C<target_id> and C<target_id> looking into
the messages.

=item assign_tickets(@workers).

Assign the ticket to workers. This method just sets the internal
C<_assign_to> accessor, and doesn't edit the ticket. Normally, the
assignment is done on creation.

=item list_workers

Return the workers as a list.

=item archive_messages

Archive the messages parsed

=item project

Set the project (if supported by the backend)

=item image_upload_support

Return true if the class support image upload. False by default.

=back

=cut

has _assign_to => (is => 'rw',
                   isa => sub {
                       unless (ref($_[0]) and
                               ref($_[0]) eq 'ARRAY') {
                           die "Assign to should be an arrayref!";
                       }
                   },
                   default => sub { return [] });

sub assign_tickets {
    my ($self, @whos) = @_;
    my @ids;
    foreach my $who (@whos) {
        $who =~ s/^\s+//;
        $who =~ s/\s+$//;
        if ($who) {
            push @ids, $who;
        }
    }
    if (@ids) {
        $self->_assign_to(\@ids);
    }
}

sub set_owner {
    warn "set_owner is not implemented for this system!\n";
    return;
}

sub search_target {
    return;
}

sub archive_messages {
    return;
}

has project => (is => 'rw');
has append  => (is => 'rw');
has queue   => (is => 'rw');
has workers => (is => 'rw');
has subject => (is => 'rw');
has is_comment => (is => 'rw');

=head2 default_search_status

If the backend support the search (currently, github and rt), the
default status of the tickets to return. Can be C<open>, C<closed>,
C<all>.

Can be set in the configuration file as:

  github:
    type: github
    user: XXX
    password: XXXX
    repo: XXXX
    default_search_status: all


=cut

has default_search_status => (is => 'rw',
                              isa => sub { die "permitted values are open, closed, all"
                                             unless ($_[0] eq 'open' or
                                                     $_[0] eq 'closed' or
                                                     $_[0] eq 'all');
                                         },
                              default => sub { 'open' });


sub list_workers {
    my $self = shift;
    my $workers = $self->workers;
    return unless $workers;
    my @works = split(/\s*,\s*/, $workers);
    @works = grep { $_ } @works;
    return @works;
}

sub image_upload_support {
    return 0;
}

=head2 can_upload_files_on_creation

If a backend manage to upload files on creation, the C<create> method
should take care of them and the instance should overload this method
returning true.

=cut

sub can_upload_files_on_creation {
    return 0;
}

1;



