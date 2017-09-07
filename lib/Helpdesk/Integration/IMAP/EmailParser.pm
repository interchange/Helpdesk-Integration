package Helpdesk::Integration::IMAP::EmailParser;

use strict;
use warnings;
use Types::Standard qw/Object InstanceOf Int/;
use Email::MIME;
use Path::Tiny;
use Text::Unidecode;
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
             handles => [qw/header content_type parts/]
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

=head1 METHODS

=head2 get_html_parts

Return a list of decoded strings with HTML content.

=head2 save_html_parts_to_dir($directory)

Save the HTML into one or more files in the provided directory.
Use a temporary one if none is provided.

Return the list of file produced as L<Path::Tiny> objects which
stringify correctly.

=cut

sub get_html_parts {
    my $self = shift;
    my @out;
    $self->mail->walk_parts(sub {
                                my ($part) = @_;
                                return if $part->subparts;
                                if ($part->content_type =~ m{text/html}i) {
                                    push @out, $part->body_str;
                                }
                            });
    return @out;
}

sub save_html_parts_to_dir {
    my ($self, $dir) = @_;
    my $wd;
    if (defined $dir) {
        $wd = path($dir);
    }
    else {
        $wd = Path::Tiny->tempdir(CLEANUP => 0);
    }
    $wd->mkpath unless $wd->exists;
    die "$wd is not a directory" unless $wd->is_dir;
    my $counter = 0;
    my $basename = $self->output_basename;
    my @out;
    foreach my $html ($self->get_html_parts) {
        my $file = $wd->child($basename . '-' . $counter++ . '.html');
        $file->spew_utf8($html);
        push @out, $file;
    }
    return @out;
}

sub output_basename {
    my $self = shift;
    my @chunks = ();
    push @chunks, $self->id if $self->id;
    foreach my $h (qw/Date Subject/) {
        push @chunks, unidecode($self->header($h));
    }
    my $whole = join('-', @chunks);
    $whole =~ s/[^0-9a-zA-Z_-]/-/g;
    $whole =~ s/--+/-/g;
    $whole = substr($whole, 0, 230);
    $whole =~ s/^-+//;
    $whole =~ s/-+$//;
    return $whole;
}

1;
