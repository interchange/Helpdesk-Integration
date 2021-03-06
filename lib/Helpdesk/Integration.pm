package Helpdesk::Integration;
use strict;
use warnings;

use Module::Load;
use Error qw(try otherwise);
use Data::Dumper;

our $VERSION = '0.01';

=head1 NAME

Helpdesk::Integration -- moving request tickets across systems

=head1 VERSION

0.01

=head1 SUPPORTED SYSTEMS

=over 4

=item GitHub

L<Helpdesk::Integration::GitHub>

=item Request Tracker

L<Helpdesk::Integration::RT>

=item IMAP

L<Helpdesk::Integration::IMAP>

=item Google Calendar

L<Helpdesk::Integration::GoogleCalendar>

=back

These are all subclasses of L<Helpdesk::Integration::Instance>.

Also there is a class for L<tickets|Helpdesk::Integration::Ticket>.

=cut

use Moo;

=head1 ACCESSORS

=head2 source

Source system.

=head2 target

Target system.

=head2 configuration

Configuration for Helpdesk::Integration.

=head2 debug_mode

Whether to enable debug_mode or not (default: off).

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


=head2 filter

An optional subroutine which acts as a filter. If returns true, it the
message will be processed. If returns false, the message will be
ignored.

=cut

has filter => (is => 'rw',
               isa => sub {
                   die "filter wants a sub reference"
                     unless ($_[0] and (ref($_[0]) eq 'CODE'));
               });


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
               github => 'GitHub',
               gcal => 'GoogleCalendar',
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
    $obj->login;
    return $obj;
}

=head1 Methods

=head2 set_target

Setter for C<target> attribute.

=cut

sub set_target {
    my ($self, $name) = @_;
    my $obj = $self->_create_object($name);
    $self->_set_target($obj);
}

=head2 set_source

Setter for C<source> attribute.

=cut

sub set_source {
    my ($self, $name) = @_;
    my $obj = $self->_create_object($name);
    $self->_set_source($obj);
}

=head2 summary

Returns summary from emails.

=cut

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

=head2 execute

Passes tasks from the source to the target, e.g. emails to RT.

=cut

sub execute {
    my $self = shift;
    my @archive;
    my @messages;

    my @mails = $self->source->parse_messages;

    # scan the mails and looks if we have attachments and if we can support them
    if (!$self->ignore_images and
        !$self->target->image_upload_support) {
        foreach my $m (@mails) {
            if ($m->[1]->file_attached) {
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

        # if there is a filter, try to see if it returns true
        if (my $filter = $self->filter) {
            next unless $filter->($eml);
        }
        if (my @events = $eml->ics_events) {
            warn "ICS file found, ignoring body\n";
            foreach my $event (@events) {
                try {
                    my ($ticket, $msg) = $self->target->create($event);
                    push @messages, $msg;
                }
                  otherwise {
                      warn "Failed to parse mail with ics files"  . shift . "\n";
                  };
            }
            next;
        }

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

                # if the backend is not able to upload files on
                # creation, we have to repeat, with a tweaked body.
                unless($self->target->can_upload_files_on_creation) {
                    my $emlbody = $eml->body;
                    my $emlsubject = $eml->subject;
                    $eml->body('');
                    $eml->subject('Attachments');
                    if (my @attachments = $eml->attachments_filenames) {
                        $self->target->correspond($eml);
                    }
                    # restore the original body
                    $eml->body($emlbody);
                    $eml->subject($emlsubject);
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

=head1 AUTHORS

Marco Pessotto, C<melmothx@gmail.com>

Stefan Hornburg (Racke), C<racke@linuxia.de>

=head1 LICENSE AND COPYRIGHT

Copyright 2013-2014 Stefan Hornburg (Racke), Marco Pessotto.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;
