package Helpdesk::Integration::EmailParser;

use strict;
use warnings;
use Moo::Role;

use Email::MIME;
use MIME::Parser;
use Mail::GnuPG;
use Encode qw/decode/;
use Helpdesk::Integration::Ticket;


=head1 NAME

Helpdesk::Integration::EmailParser - Moo role for parsing mails

=head1 ACCESSORS

=head2 key

GnuPG key.

=head2 passphrase

GnuPG passphrase.

=head2 mail_is_attached

Whether email is attached to another email (default: false).

=head2 save_all_attachments

Include text and html parts in the attachments.

=cut


has mail_is_attached => (
                         is => 'rw',
                         default => sub { 0 },
                        );
has key => ( is => 'ro');
has passphrase => (is => 'ro');
has save_all_attachments => (is => 'rw');

sub _extract_attached_mail {
    my ($self, $body) = @_;
    my $email = Email::MIME->new($$body);
    my @found;
    my $multipart_found = 0;
    foreach my $part ($email->parts) {
        if ($part->content_type =~ m/^multipart\//) {
            @found = ($part->as_string);
            $multipart_found = 1;
        }
        elsif (!$multipart_found) {
            if ($part->content_type =~ m/^text\/plain/) {
                push @found, $part->as_string;
            }
        }
    }
    if (@found == 1) {
        return $found[0];
    }
    if (@found > 1) {
        # and let's hope it's the good part.
        return $found[-1];
    }
    else {
        warn "You asked for an attached mail, but I found " . scalar(@found) . " related parts in the mail";
        return;
    }
}


=head1 METHODS

=head2 parse_body_message($body)

Parses email body.

=cut

sub parse_body_message {
    my ($self, $body) = @_;
    if ($self->mail_is_attached) {
        if (my $attached_body = $self->_extract_attached_mail($body)) {
            $body = \$attached_body;
        }
    }
    my $email = Email::MIME->new($$body);

    my %details = (
                   date => $email->header("Date"),
                   from => $email->header("From"),
                   to   => $email->header("To"),
                   subject => $email->header("Subject"),
                  );

    # check if it's encrypted
    my $body_copy = $$body;
    my $parser = MIME::Parser->new;
    # avoid leaving files around.
    $parser->output_to_core(1);
    my $entity = $parser->parse_data($body_copy);
    if (Mail::GnuPG->is_encrypted($entity)) {
        if (my $key = $self->key) {

            my $gnupg = Mail::GnuPG->new(key => $key,
                                         ($self->passphrase ?
                                          (passphase => $self->passphrase) :
                                          (use_agent => 1)));
            my ($result) = $gnupg->decrypt($entity);
            if ($result == 0) {
                if (my $lines = $gnupg->{plaintext}) {
                    my $body = Email::MIME->new(join('', @$lines));
                    my ($text, @attachments) = $self->parse_email($body);
                    $details{body} = $text;
                    $details{attachments} = \@attachments;
                }
                else {
                    die "Something went wrong\n";
                }
            }
            else {
                die join('', @{$gnupg->{last_message}});
            }
        }
        else {
            die "This is an encrypted message, but no key has been provided\n"
              . "in the IMAP configuration stanza. Unable to decrypt!\n";
        }
    }

    unless ($details{body}) {
        my ($text, @attachments) = $self->parse_email($email);
        $details{body} = $text;
        $details{attachments} = \@attachments;
    }
    return Helpdesk::Integration::Ticket->new(attachment_directory => $self->attachment_directory,
                                              filename_pattern => $self->filename_pattern,
                                              %details);
}

=head2 parse_email($email)

Parses email C<$email>.

=cut

sub parse_email {
    my ($self, $email) = @_;
    my @attachments;
    my $text = '';
    if (my @parts = $email->subparts) {
        # print "entering loop\n";
        foreach my $part (@parts) {
            my ($subtext, @subattach) = $self->parse_email($part);
            $text .= $subtext;
            push @attachments, @subattach;
        }
    }
    # here we got a real body
    else {
        my $content_type = $email->content_type;
        my $filename = $email->filename;
        my $bytes = $email->body;
        if (!$content_type # no content type, plain old email
            or $content_type =~ m/text\/plain/) {
            my $chunk = eval { $email->body_str };
            if ($@ && !$chunk) {
                warn "Email body couldn't be decoded: $@, assuming latin-1\n";
                $chunk = eval { decode('latin-1', $email->body) };
                if ($@) {
                    warn "Fallback decoding failed as well...";
                    $chunk = $email->body;
                }
            }
            $text .= $chunk;
            if ($self->save_all_attachments) {
                push @attachments, [ 'mail.txt',  $bytes ];
            }
        }
        elsif ($filename) {
            if ($filename =~ m/^\./ or $filename =~ m!/!) {
                warn "Illegal filename $filename, ignoring\n";
            }
            else {
                push @attachments, [ $filename, $bytes ];
            }
        }
        elsif ($self->save_all_attachments) {
            my $ext = $content_type;
            $ext =~ s/\//./g;
            push @attachments, [ 'mail.' . $ext, $bytes ];
        }
        else {
            warn "Ignoring $content_type part\n";
        }
    }
    return $text, @attachments;
}
  

1;
