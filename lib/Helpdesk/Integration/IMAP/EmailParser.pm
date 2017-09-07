package Helpdesk::Integration::IMAP::EmailParser;

use strict;
use warnings;
use Types::Standard qw/Object InstanceOf Int/;
use Email::MIME;
use Moo;

=head1 NAME

Helpdesk::Integration::IMAP::EmailParser -- advanced mail parsing

=head1 ACCESSORS

=head2 mail

Set in the constructor, it is a L<Email::MIME> object.

=head2 id

Optional mail id to be set in the constructor. Meant create sensible
filenames, if needed.

=cut

has mail => (is => 'ro',
             isa => InstanceOf['Email::MIME'],
             required => 1,
             handles => [qw/header/]
            );
has id => (is => 'ro', isa => Int, default => sub { 0 });

sub BUILDARGS {
    my ($class, @args) = @_;
    if (@args % 2 == 0) {
        my %out = @args;
        return \%out;
    }
    if (@args == 1) {
        my $arg = shift @args;
        my $mail;
        if (ref($arg)) {
            $mail = Email::MIME->new($$arg);
        }
        else {
            local $/;
            open (my $fh, '<', $arg) or die "Cannot open $arg";
            my $body = <$fh>;
            close $fh;
            $mail = Email::MIME->new($body);
        }
        return { mail => $mail };
    }
    else {
        die "Too many arguments. Accept either a named list or a single scalar with a filename or a reference to a scalar with the mail body";
    }
}

1;
