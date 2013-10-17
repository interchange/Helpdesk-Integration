package LinuxiaSupportIntegration::RT::Mail;

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

sub header {
    my ($self, $header) = @_;
    # fake the header accessors;
    my $accessor = lc($header);
    if ($self->can($accessor)) {
        return $self->$accessor;
    }
    else {
        warn "Unsupported method $accessor!";
        return "";
    }
}

sub body_str {
    return shift->body;
}


1;

