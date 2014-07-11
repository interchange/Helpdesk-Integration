package Helpdesk::Integration::IMAP;

use strict;
use warnings;
use Net::IMAP::Client;
use Email::MIME;

use Moo;
extends 'Helpdesk::Integration::Instance';

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

sub imap {
    my $self = shift;
    my $imap = $self->imap_obj;
    unless ($imap) {
        print "Imap object is empty, creating\n";
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

sub login {
    my $self = shift;
    $self->imap->login or die $self->imap->last_error;
}

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
        print "Parsing $id\n";
        my $body = $self->imap->get_rfc822_body($id);
        unless ($body && $$body) {
            warn "Couldn't retrieve the body mail for $id!";
            next;
        };
        my $email = Email::MIME->new($$body);
        my %details = (
                       date => $email->header("Date"),
                       from => $email->header("From"),
                       to   => $email->header("To"),
                       subject => $email->header("Subject"),
                      );
        my ($text, @attachments) = $self->parse_email($email);
        $details{body} = $text;
        $details{attachments} = \@attachments;
        my $simulated = Helpdesk::Integration::Ticket->new(%details);
        print $simulated->attachments_filenames;
        push @mails, [$id => $simulated ];
    }
    $self->_set_current_mail_objects(\@mails);
    return @mails;
}

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
        if ($content_type =~ m/text\/plain/) {
            $text .= $email->body_str;
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

sub imap_backup_folder_full_path {
    my $self = shift;
    my $name = $self->imap_backup_folder;
    my $separator = $self->imap->separator || ".";
    $name =~ s/^INBOX\Q$separator\E//; # strip the leading INBOX.
    die "No backup folder!" unless $name;
    return "INBOX" . $separator . $name;
}

sub type {
    return "imap";
}

1;