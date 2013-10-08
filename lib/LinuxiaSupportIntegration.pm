package LinuxiaSupportIntegration;
use strict;
use warnings;

use Net::IMAP::Client;
use Email::MIME;

use Moo;

has imap_server => (
                    is => 'ro',
                    required => 1,
                   );

has imap_user => (
                  is => 'ro',
                  required => 1,
                 );

has imap_pass => (
                  is => 'ro',
                  required => 1,
                 );

has imap_ssl => (is => 'ro');
has imap_port => (is => 'ro');
has imap_target_folder => (is => 'rw',
                           default => sub { return 'INBOX' });

has rt_url => (is => 'ro');
has rt_user => (is => 'ro');
has rt_password => (is => 'ro');

has teamwork_api_key => (is => 'ro');
has teamwork_host => (is => 'ro');

has ua_obj => (is => 'rwp');
has imap_obj => (is => 'rwp');

has error => (is => 'rwp');
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
        my %credentials = (
                           server => $self->imap_server,
                           user   => $self->imap_user,
                           pass   => $self->imap_pass,
                          );
        if (my $port = $self->imap_port) {
            $credentials{port} = $port;
        }
        if (my $ssl = $self->imap_ssl) {
            $credentials{ssl} = $ssl;
        }
        $imap = Net::IMAP::Client->new(%credentials);
        die "Couldn't connect to " . $imap->server . " for user " . $self->imap_user
          unless ($imap);
        $imap->login or die $imap->last_error;
        $self->_set_imap_obj($imap);
    }
    return $self->imap_obj;
}


sub list_mails {
    my ($self, %search) = @_;
    $self->imap->select($self->imap_target_folder);
    my %do_search;
    foreach my $k (keys %search) {
        if ($search{$k}) {
            $do_search{$k} = $search{$k};
        }
    }
    my $ids = [];

    # to do: set sorting
    if (%do_search) {
        $ids = $self->imap->search({ %do_search }, 'DATE');
    }
    else {
        $ids = $self->imap->search('ALL', 'DATE');
    }
    unless (@$ids) {
        $self->_set_error("No mail with the matching criteria found");
        return;
    }

    $self->_set_current_mail_ids($ids);
    return @$ids
}


sub parse_mails {
    my ($self, @ids) = @_;
    unless (@ids) {
        @ids = $self->list_mails;
    }
    my @mails;
    foreach my $id (@ids) {
        my $body = $self->imap->get_rfc822_body($id);
        push @mails, [$id => Email::MIME->new($$body) ];
    }
    $self->_set_current_mail_objects(\@mails);
    return @mails;
}

sub show_mails {
    my $self = shift;
    my @summary;
    foreach my $mail ($self->parse_mails) {
        push @summary,
          join(" ",
               $mail->[0],
               ".",
               From => $mail->[1]->header("From"),
               To   => $mail->[1]->header("To"),
               $mail->[1]->header("Date"),
               $mail->[1]->header("Subject"),
               substr($mail->[1]->body, 0, 50) . "\n");
    }
    return @summary;
}

sub move_mails_to_rt_ticket {
    my ($self, $ticket) = @_;
    return $self->_add_mails_to_ticket($ticket);
}

sub move_mails_to_rt_ticket_comment {
    my ($self, $ticket) = @_;
    return $self->_add_mails_to_ticket($ticket, "is_comment");
}

sub _add_mails_to_ticket {
    my ($self, $ticket, $comment) = @_;
    $self->prepare_backup_folder;
    my @ids = $self->list_mails;
    $self->archive_mails(@ids);
}

sub archive_mails {
    my ($self, @ids) = @_;
    return unless @ids;
    $self->imap->copy([@ids], $self->imap_backup_folder_full_path);
    $self->imap->delete_message([@ids]);
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
    $name =~ s/^INBOX\.//; # strip the leading INBOX.
    die "No backup folder!" unless $name;
    return "INBOX.$name";
}


sub create_rt_ticket {
    my $self = shift;
}




1;
