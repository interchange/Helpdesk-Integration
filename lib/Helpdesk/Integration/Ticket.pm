package Helpdesk::Integration::Ticket;

=head1 NAME

Helpdesk::Integration::Ticket -- generic ticket class

=head1 ACCESSORS

The following accessors are read/write and should be self-explanatory

=over 4

=item body

=item from

=item subject

=item date

=item start

The start date

=item due

The end date

=item attachments

=item to

=item trxid

The backend system may have a reference for this specific message.

=item url

=item id

=back

=cut

use Moo;
use File::Temp;
use File::Basename qw/fileparse/;
use Path::Tiny;
use Data::Dumper;
use Date::Parse qw/str2time/;
use Encode qw/decode/;

has body => (is => 'rw',
             default => sub { return "" });
has from => (is => 'rw',
             default => sub { return "" });
has subject => (is => 'rw',
                default => sub { return "" });
has date => (is => 'rw',
             default => sub { return "" });

has start => (is => 'rw',
              default => sub { return "" });

has due => (is => 'rw',
            default => sub { return "" });

has attachments => (is => 'rw',
                   default => sub { return [] });

has to => (is => 'rw',
           default => sub { return "" });

has trxid => (is => 'rw',
            default => sub { return "" });

has attachment_directory => (is => 'ro',
                             default => sub { Path::Tiny->tempdir });

has filename_pattern => (is => 'ro',
                         default => sub { '(%s)' });

has _attachment_files => (
                          is => 'rw',
                         );

has url => (is => 'rw', default => sub { '' });

has id => (is => 'rw', default => sub { '' });

=head2

=over 4

=item attachment_directory

The directory where to place (default: a temporary directory which
will be removed at the end of the run).

=item filename_pattern

A sprintf pattern to append between the basename and the suffix when
saving the attachments. Defaults to C<(%s)>. An incremental integer is
passed.

=back

=head1 METHODS

=head2 as_string

The full ticket stringified.

=head2 summary

The ticket with the body cut to a couple of lines.

=head2 file_attached

Returns a list of filenames for attachments (with the exception of iCal attachments).

=head2 ics_events

Returns a list of L<Helpdesk::Integration::Ticket> object if the
message has one or more iCal attachments.

=head2 ics_files

Returns a list of filenames if the message has one or more iCal attachments.

=cut

sub as_string {
    my $self = shift;
    my $body = "Mail from " . $self->from . " on " . $self->date
      . "\n" . $self->subject . "\n" . $self->body . "\n";
    return $body;
}


sub summary {
    my $self = shift;
    my $body = join(" ",
                    From => $self->from,
                    To   => $self->to,
                    $self->date,
                    "\nSubject:", $self->subject,
                    "\n" . $self->_short_body);
    if (my $start = $self->start) {
        $body .= "\nStart: " . localtime($start);
    }
    if (my $due = $self->due) {
        $body .= "\nDue: " . localtime($due);
    }
    if (my $trxid = $self->trxid) {
        $body .= "\nMessage id: $trxid";
    }
    $body .= "\n";
    return $body;
}

sub _short_body {
    my $self = shift;
    my $beginning = substr($self->body, 0, 70);
    $beginning =~ s/\r?\n/ /gs;
    # remove the last non-whitespace chars
    $beginning =~ s/[^ ]+$//s;
    return $beginning;
}

=head2 attachments_filenames

List of attachement filenames.

=cut

sub attachments_filenames {
    my $self = shift;
    my @strings = @{ $self->attachments };
    my $dir = path($self->attachment_directory);
    $dir->mkpath unless -d $dir;

    if (my $cached = $self->_attachment_files) {
        return @$cached;
    }

    my @filenames;

    for (my $i = 0; $i < @strings; $i++) {
        my $att = $strings[$i];
        my ($provided_filename, $directories, $suffix) = fileparse($att->[0], qr{\.[a-zA-Z0-9]+});
        $suffix //= '';
        unless ($provided_filename and $provided_filename =~ m/\w/) {
            warn "Skipping filename without a name\n";
            next;
        }
        if ($provided_filename =~ m/^\./) {
            warn "Skipping hidden filename $provided_filename\n";
            next;
        }

        my $dest = $dir->child($provided_filename . $suffix);

        my $try = 1;
        while (-e $dest) {
            $dest = $dir->child($provided_filename . (sprintf($self->filename_pattern, $try) || $try) . $suffix);
            $try++;
        }
        die "Cannot write $dest" unless $dest->spew($att->[1]);
        push @filenames, $dest;
    }
    $self->_attachment_files(\@filenames);
    return @filenames;
}

sub file_attached {
    my $self = shift;
    # don't consider the ics a real file, we parse it
    return grep { $_ !~  /\.ics$/ } $self->attachments_filenames;
}

sub ics_files {
    my $self = shift;
    return grep { /\.ics$/ } $self->attachments_filenames;
}

sub ics_events {
    my $self = shift;
    my @ics_files = $self->ics_files;
    return unless @ics_files;
    require Data::ICal;
    my @events;
    foreach my $ics (@ics_files) {
        my $cal = Data::ICal->new(filename => $ics);
        if (my $entries = $cal->entries) {
            foreach my $entry (@$entries) {
                next unless $entry->ical_entry_type eq 'VEVENT';
                if (my $event = $self->_parse_event($entry)) {
                    push @events, $event;
                }
            }
        }
    }
    my @out;
    foreach my $event (@events) {
        push @out,
          __PACKAGE__->new(
                           from => $self->from,
                           subject => $event->{summary} || $self->subject,
                           date => $event->{dtstamp} || $self->data,
                           to => $self->to,
                           start => $event->{dtstart} || $self->start,
                           due => $event->{dtend} || $self->end,
                           body => $event->{description} || $self->body,
                          );
    }
    return @out;
}

sub _parse_event {
    my ($self, $event) = @_;
    my %event;
    if (my $properties = $event->properties) {
        foreach my $props (values %$properties) {
            foreach my $prop (@$props) {
                my $k = $prop->key;
                my $value;
                if (my $tz = $prop->parameters->{TZID}) {
                    # it looks like a datetime
                    $value = str2time($prop->value, time_zone => $tz);
                    $event{$k} = $value;
                    next;
                }

                $value = $prop->value;
                next unless defined $value;
                if ($prop->parameters->{ENCODING} and
                    $prop->parameters->{ENCODING} eq 'QUOTED-PRINTABLE') {
                    $value = $prop->decoded_value;
                }
                else {
                    $value = decode('UTF-8', $prop->value);
                }
                if ($event{$k}) {
                    $event{$k} .= $value;
                }
                else {
                    $event{$k} = $value;
                }
            }
        }
        return \%event;
    }
    return;
}


1;
