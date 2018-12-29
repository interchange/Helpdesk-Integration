package Helpdesk::Integration::IMAP;

use strict;
use warnings;
use Net::IMAP::Client;

# we kind of use similar modules
use Email::MIME;
use MIME::Parser;
use Data::Dumper;
use Encode qw/decode/;
use Mail::GnuPG;
use Moo;

with 'Helpdesk::Integration::Instance';

=head1 Name

Helpdesk::Integration::IMAP - IMAP support

=head1 Description

I<with> L<Helpdesk::Integration::Instance>.

=head1 Accessors

=head2 server

Hostname of IMAP server (required).

=head2 port

Port of IMAP server.

=head2 ssl

Whether to enable SSL for communications with the IMAP server (default: on).

=head2 socket

Socket with the connection to the IMAP server.

=head2 user

Login username (required).

=head2 password

Login password (required).

=head2 target_folder

Currently selected folder (default: C<INBOX>).

=head2 imap_obj

Instance of L<Net::IMAP::Client>, automatically created based on the parameters above.

=head2 key

GnuPG key.

=head2 passphrase

GnuPG passphrase.

=head2 imap_backup_folder

Backup folder for processed emails (default: C<RT-Archive>).

=head2 current_mail_ids

List of current mail ids (as array reference).

=head2 current_mail_objects

List of current mail objects (as array reference).

=head2 mail_is_attached

Whether email is attached to another email (default: false).

=cut

has server => (
               is => 'ro',
               required => 1,
              );

has user => (
             is => 'ro',
             required => 1,
            );

has password => (
             is => 'ro',
             required => 1,
            );

has mail_is_attached => (
                       is => 'rw',
                       default => sub { 0 },
                      );

has key => ( is => 'ro');
has passphrase => (is => 'ro');

has ssl => (is => 'ro',
            default => sub { return 1 });
has port => (is => 'ro');
has socket => (is => 'rw');
has target_folder => (is => 'rw',
                      default => sub { return 'INBOX' });

has imap_obj => (is => 'rwp');

has current_mail_ids => (is => 'rwp',
                         default => sub { return [] });

has current_mail_objects => (is => 'rwp',
                             default => sub { return [] });

has imap_backup_folder => (is => 'rw',
                           default => sub { return "RT-Archive" });

=head1 Methods

=head2 imap

Main instance method.

=cut

sub imap {
    my $self = shift;
    my $imap = $self->imap_obj;
    unless ($imap) {
        # print "Imap object is empty, creating\n";
        my %credentials = (
                           server => $self->server,
                           user   => $self->user,
                           pass   => $self->password,
                          );
        if (my $port = $self->port) {
            $credentials{port} = $port;
        }
        if (my $ssl = $self->ssl) {
           $credentials{ssl} = $ssl;

           # let us create the socket on our own in order to get
           # better error messages
           my $socket = IO::Socket::SSL->new (Proto => 'tcp',
                                              PeerAddr=> $self->server,
                                              PeerPort=> 993);

           if ($socket) {
               $self->socket($socket);
               $credentials{socket} = $socket;
           }
           else {
               die "$0: unable to create SSL connection: ",
                   &IO::Socket::SSL::errstr(), "\n";
           }


        }
        $imap = Net::IMAP::Client->new(%credentials);
        die "Couldn't connect to " . $self->server . " for user " . $self->user
          unless ($imap);
        $self->_set_imap_obj($imap);
    }
    return $imap;
}

=head2 login

Login method.

=cut

sub login {
    my $self = shift;
    $self->imap->login or die $self->imap->last_error;
}

=head2 mail_search_params

Returns hash with current search parameters (for I<From> and I<Subject>).

=cut

sub mail_search_params {
    my $self = shift;
    my %search = %{$self->search_params};
    my %do_search;
    if (%search) {
        foreach my $k (qw/from subject/) {
            if ($search{$k}) {
                $do_search{$k} = $search{$k};
            }
        }
    }
    return %do_search;
}

=head2 list_mails

Returns a list of mail ids from the target folder with search parameters applied.

=cut

sub list_mails {
    my $self = shift;
    $self->imap->select($self->target_folder);
    my %do_search = $self->mail_search_params;
    my $ids = [];

    # to do: set sorting
    if (%do_search) {
        $ids = $self->imap->search({ %do_search }, 'DATE');
    }
    else {
        $ids = $self->imap->search('ALL', 'DATE');
    }
    unless (@$ids) {
        warn "No mail with matching criteria found";
        $self->_set_error("No mail with the matching criteria found");
        return;
    }

    $self->_set_current_mail_ids($ids);
    return @$ids
}


=head2 parse_messages(@ids)

Given the mail ids in the list passed as argument, retrive them and
return a list of arrayrefs, where the first element is the numeric id
of the IMAP mail, and the second is an L<Email::MIME> object.

=cut

sub parse_messages {
    my ($self, %params) = @_;
    my @ids;
    if ($params{ids}) {
        @ids = @{$params{ids}};
    }
    unless (@ids) {
        @ids = $self->list_mails;
    }
    my @mails;
    foreach my $id (@ids) {
        # print "Parsing $id\n";
        my $body = $self->imap->get_rfc822_body($id);
        unless ($body && $$body) {
            warn "Couldn't retrieve the body mail for $id!";
            next;
        }
        if (my $parsed = $self->parse_body_message($body)) {
            push @mails, [$id => $parsed ];
        }
    }
    $self->_set_current_mail_objects(\@mails);
    return @mails;
}

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
        return Helpdesk::Integration::Ticket->new(%details);
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
        }
        elsif ($filename) {
            my $bytes = $email->body;
            if ($filename =~ m/^\./ or $filename =~ m!/!) {
                warn "Illegal filename $filename, ignoring\n";
            }
            else {
                push @attachments, [ $filename, $bytes ];
            }
        }
        else {
            warn "Ignoring $content_type part\n";
        }
    }
    return $text, @attachments;
}



=head2 archive_messages(@ids)

Given the ids passed as arguments, copy those in the IMAP backup
folder.

The list is purged by eventual undefined values (when pulling from RT
the argument will be a list of undef).

=cut

sub archive_messages {
    my ($self, @ids) = @_;
    return unless @ids;
    @ids = grep { defined $_ } @ids;
    return unless @ids;
    $self->imap->copy([@ids], $self->imap_backup_folder_full_path);
    $self->imap->delete_message([@ids]) unless $self->debug_mode;
    $self->imap->expunge;
}

=head2 prepare_backup_folder

Creates L<backup folder|/imap_backup_folder> if it doesn't exist.

=cut

sub prepare_backup_folder {
    my $self = shift;
    my $name = $self->imap_backup_folder_full_path;
    unless ($self->_check_folders($name)) {
        $self->imap->create_folder($name);
    }
    die "No folder named $name" unless $self->_check_folders($name);
}

sub _check_folders {
    my ($self, $name) = @_;
    my @folders = $self->imap->folders;
    foreach my $f (@folders) {
        return 1 if ($f eq $name);
    }
    return 0;
}

=head2 imap_backup_folder_full_path

Determines full path of IMAP backup folder and returns it.

=cut

sub imap_backup_folder_full_path {
    my $self = shift;
    my $name = $self->imap_backup_folder;
    my $separator = $self->imap->separator || ".";
    $name =~ s/^INBOX\Q$separator\E//; # strip the leading INBOX.
    die "No backup folder!" unless $name;
    return "INBOX" . $separator . $name;
}

=head2 type

Returns type (C<imap>).

=cut

sub type {
    return "imap";
}

=head2 NOT IMPLEMENTED

The following methods are not implemented yet (because usually you
need IMAP as source, not as target, so they just return.

=over 4

=item create

=item correspond

=item comment

=back

=cut

sub create {
    return;
}

sub correspond {
    return;
}

sub comment {
    return;
}


1;
