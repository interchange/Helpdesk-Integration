package LinuxiaSupportIntegration;
use strict;
use warnings;

use Module::Load;
use Error qw(try otherwise);
use Data::Dumper;

our $VERSION = '0.01';

=head1 NAME

LinuxiaSupportIntegration -- moving request tickets across systems

=cut

use Moo;

=head1 ACCESSORS

=cut

has debug_mode => (is => 'rw');
has configuration => (is => 'ro',
                      default => sub { return {} },
                      isa => sub {
                          my $conf = $_[0];
                          die "Empty conf passed"
                            unless $conf;
                          die "Conf is not a reference"
                            unless ref($conf);
                          die "Conf is not an hashref"
                            unless ref($conf) eq 'HASH';
                          # validate the structure
                          foreach my $k (keys %$conf) {
                              foreach my $v (qw/type/) {
                                  die "Missing $k configuration"
                                    unless exists $conf->{$k}->{$v};
                              }
                              foreach my $v (keys %{$conf->{$k}}) {
                                  die "Found deeper level"
                                    if ref($conf->{$k}->{$v});
                              }
                          }
                      });

has target => (is => 'rwp');
has source => (is => 'rwp');
has ignore_images => (is => 'rw',
                      default => sub { return 0 });

=head2 ignore_images

If true, don't check if the target backend can handle images (will be
ignored).

=head2 error

When the main C<execute> loop fails, the error is set. It will be an
arrayref where the first element is the error code, and the second the
error string.

Error codes:

=over 4

=item no_image_support

=back

=cut

has error => (is => 'rwp');

sub _create_object {
    my ($self, $name) = @_;
    die "No configuration found for $name" unless $self->configuration->{$name};
    my %credentials = %{$self->configuration->{$name}};
    $credentials{conf_name} = $name;
    my $type = lc(delete $credentials{type});
    my %map = (
               rt => 'RT',
               imap => 'IMAP',
               teamwork => 'TeamWork',
               github => 'GitHub',
              );
    my $class = $map{$type};
    die "Unsupported type $type!" unless $class;
    $class = __PACKAGE__ . '::' . $class;
    eval { load $class };
    die "Couldn't load $class $@" if $@;

    # manage some aliases
    foreach my $alias (qw/todo-list repo/) {
        if ($credentials{$alias} && !$credentials{queue}) {
            $credentials{queue} = delete $credentials{$alias};
        }
        elsif ($credentials{'todo-list'}) {
            warn "$alias is an alias for queue and you set both! Using queue!\n";
        }
    }

    my $obj = $class->new(%credentials);
    print "Logging in with $class\n";
    $obj->login;
    return $obj;
}

sub set_target {
    my ($self, $name) = @_;
    my $obj = $self->_create_object($name);
    $self->_set_target($obj);
}

sub set_source {
    my ($self, $name) = @_;
    my $obj = $self->_create_object($name);
    $self->_set_source($obj);
}

sub summary {
    my $self = shift;
    return $self->_format_mails($self->source->parse_messages);
}

sub _format_mails {
    my ($self, @mails) = @_;
    my @summary;
    foreach my $mail (@mails) {
        push @summary,
          join(" ",
               $mail->[0] // "virtual mail",
               ".", $mail->[1]->summary);
    }
    return @summary;
}


sub execute {
    my $self = shift;
    my @archive;
    my @messages;

    my @mails = $self->source->parse_messages;

    # scan the mails and looks if we have attachments and if we can support them
    if (!$self->ignore_images and
        !$self->target->image_upload_support) {
        foreach my $m (@mails) {
            if (@{$m->[1]->attachments}) {
                my $subject = $m->[1]->subject;
                $self->_set_error([no_image_support => "$subject: has images!"]);
                return;
            }
        }
    }

    foreach my $mail (@mails) {
        my $id = $mail->[0];
        my $eml = $mail->[1];
        die "Unexpected failure" unless $eml;

        # the REST interface doesn't seem to support the from header
        # (only cc and attachments), so it should be OK to inject
        # these info in the body
        try {
            # if no ticket provided, we create it and queue the other
            # mails as correspondence to this one
            if (!$self->target->append) {
                my ($ticket, $msg) = $self->target->create($eml);
                push @messages, $msg;
                die "No ticket returned!" unless $ticket;
                $self->target->append($ticket);
                if (my @attachments = $eml->attachments_filenames) {
                    $self->target->correspond($eml);
                }
            }
            elsif ($self->target->is_comment) {
                push @messages,
                  $self->target->comment($eml);
            }
            else {
                push @messages,
                  $self->target->correspond($eml);
            }
            push @archive, $id;

        } otherwise {
            my $identifier;
            if (defined $id) {
                $identifier = $id;
            }
            else {
                $identifier = "virtual mail";
            }
            if (my $project = $self->target->project) {
                $identifier .= " (Project $project)";
            }
            warn "$identifier couldn't be processed: "  . shift . "\n";
        };
    }
    $self->source->archive_messages(@archive) unless $self->debug_mode;
    return join("\n", @messages) . "\n";
}


1;
