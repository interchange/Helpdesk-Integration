package LinuxiaSupportIntegration;
use strict;
use warnings;

use Net::IMAP::Client;
use RT::Client::REST;
use LinuxiaSupportIntegration::TeamWork;
use Email::MIME;
use Error qw(try otherwise);

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

# objects
has teamwork_obj => (is => 'rwp');
has imap_obj => (is => 'rwp');
has rt_obj => (is => 'rwp');

has error => (is => 'rwp');
has current_mail_ids => (is => 'rwp',
                         default => sub { return [] });

has current_mail_objects => (is => 'rwp',
                             default => sub { return [] });

has imap_backup_folder => (is => 'rw',
                           default => sub { return "RT-Archive" });

has debug_mode => (is => 'rw');

sub teamwork {
    my $self = shift;
    my $tm = $self->teamwork_obj;
    unless ($tm) {
        my %credentials = (
                           api_key => $self->teamwork_api_key,
                           host => $self->teamwork_host,
                          );
        $tm = LinuxiaSupportIntegration::TeamWork->new(%credentials);
        $tm->login;
    }
    return $tm;
}

sub rt {
    my $self = shift;
    my $rt = $self->rt_obj;
    unless ($rt) {
        $rt = RT::Client::REST->new(
                                    server => $self->rt_url,
                                    timeout => 30,
                                   );
        # initialize, log in, and store the object
        my $user = $self->rt_user;
        my $password = $self->rt_password;
        try {
            $rt->login(username => $user, password => $password);
        } otherwise  {
            die "problem logging in: ", shift->message;
        };
        $self->_set_rt_obj($rt);
    }
    return $rt;
}

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
    return $imap;
}

has _mail_search_hash => (is => 'rw',
                          default => sub { return {} },
                         );

sub mail_search_params {
    my ($self, %search) = @_;
    my %do_search;
    if (%search) {
        foreach my $k (keys %search) {
            if ($search{$k}) {
                $do_search{$k} = $search{$k};
            }
        }
        $self->_mail_search_hash(\%do_search);
    }
    return %{ $self->_mail_search_hash };
}

sub list_mails {
    my $self = shift;
    $self->imap->select($self->imap_target_folder);
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
               "\nSubject: " . $mail->[1]->header("Subject"),
               "\n" . substr($mail->[1]->body_str, 0, 50) . "\n");
    }
    return @summary;
}

sub move_mails_to_rt_ticket {
    my ($self, $ticket) = @_;
    return $self->_add_mails_to_ticket($ticket);
}

sub move_mails_to_rt_ticket_comment {
    my ($self, $ticket) = @_;
    return $self->_add_mails_to_ticket($ticket, { comment => 1 });
}

sub create_rt_ticket {
    my ($self, $queue) = @_;
    return $self->_add_mails_to_ticket(undef, { queue => $queue });
}

sub _add_mails_to_ticket {
    my ($self, $ticket, $opts) = @_;
    $opts ||= {};
    $self->prepare_backup_folder;
    my @ids = $self->list_mails;
    my @archive;

    foreach my $mail ($self->parse_mails(@ids)) {
        my $id = $mail->[0];
        my $eml = $mail->[1];
        die "Unexpected failure" unless $eml;

        # the REST interface doesn't seem to support the from header
        # (only cc and attachments), so it should be OK to inject
        # these info in the body
        try {
            my $body = "Mail from " . $eml->header('From')
              . " on " . $eml->header('Date')
                . "\n" . ($eml->header('Subject') || "")
                  . "\n" . $eml->body_str;

            # if no ticket provided, we create it and queue the other
            # mails as correspondence to this one
            if (!$ticket) {
                $ticket = $self->rt->create(type => 'ticket',
                                            set => {
                                                    Queue => $opts->{queue} || "General",
                                                    Requestor => $eml->header('From'),
                                                    Subject => $eml->header('Subject'),
                                                   },
                                            text => $body);
            }

            elsif ($opts->{comment}) {
                # here we could have attachments in the future
                $self->rt->comment(ticket_id => $ticket,
                                   message => $body);
            }
            else {
                $self->rt->correspond(ticket_id => $ticket,
                                      message => $body);
            }
            push @archive, $id;

        } otherwise {
            warn "$id couldn't be processed: "  . shift->message . "\n";
        };
    }
    $self->archive_mails(@archive);
}

sub archive_mails {
    my ($self, @ids) = @_;
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




1;
