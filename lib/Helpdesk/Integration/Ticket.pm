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

=item attachments

=item to

=item trxid

The backend system may have a reference for this specific message.

=back

=cut

use Moo;
use File::Temp;
use File::Spec;
use File::Slurp;
use File::Basename qw/fileparse/;

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

has _tmpdir => (is => 'rw',
                default => sub { return File::Temp->newdir() });

=head1 METHODS

=over 4

=item as_string

The full ticket stringified.

=item summary

The ticket with the body cut to a couple of lines.

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

sub attachments_filenames {
    my $self = shift;
    my @strings = @{ $self->attachments };
    my $dir = $self->_tmpdir->dirname;
    my @filenames;
    foreach my $att (@strings) {
        my ($provided_filename, $directories, $suffix) = fileparse($att->[0]);
        unless ($provided_filename and $provided_filename =~ m/\w/) {
            warn "Skipping filename without a name\n";
            next;
        }
        if ($provided_filename =~ m/^\./) {
            warn "Skipping hidden filename $provided_filename\n";
            next;
        }
        my $dest = File::Spec->catfile($dir, $provided_filename);
        die "Cannot write $dest" unless (write_file($dest, $att->[1]));
        push @filenames, $dest;
    }
    return @filenames;
}


1;
