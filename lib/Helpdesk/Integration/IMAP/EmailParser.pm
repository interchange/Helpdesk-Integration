package Helpdesk::Integration::IMAP::EmailParser;

use strict;
use warnings;
use Types::Standard qw/Object InstanceOf Int/;
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

has mail => (is => 'ro', isa => InstanceOf['Email::MIME'], required => 1);
has id => (is => 'ro', isa => Int, default => sub { 0 });
1;
