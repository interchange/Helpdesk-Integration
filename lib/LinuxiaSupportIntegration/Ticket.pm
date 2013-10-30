package LinuxiaSupportIntegration::Ticket;

=head1 NAME

LinuxiaSupportIntegration::Ticket -- generic ticket class

=head1 ACCESSORS

The following accessors are read/write and should be self-explanatory

=over 4

=item body

=item from

=item subject

=item date

=item to

=back

=cut

use Moo;

has body => (is => 'rw',
             default => sub { return "" });
has from => (is => 'rw',
             default => sub { return "" });
has subject => (is => 'rw',
                default => sub { return "" });
has date => (is => 'rw',
             default => sub { return "" });

has to => (is => 'rw',
           default => sub { return "" });

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



1;
