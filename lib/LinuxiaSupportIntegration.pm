package LinuxiaSupportIntegration;
use strict;
use warnings;

use Net::IMAP::Client;
use LinuxiaSupportIntegration::TeamWork;
use LinuxiaSupportIntegration::RT;
use LinuxiaSupportIntegration::RT::Mail;
use Email::MIME;
use Error qw(try otherwise);
use Data::Dumper;

our $VERSION = '0.01';

=head1 NAME

LinuxiaSupportIntegration -- moving request tickets across systems

=cut

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

has imap_ssl => (is => 'ro',
                 default => sub { return 1 });
has imap_port => (is => 'ro');
has imap_target_folder => (is => 'rw',
                           default => sub { return 'INBOX' });

has rt_url => (is => 'ro');
has rt_user => (is => 'ro');
has rt_password => (is => 'ro');

has teamwork_api_key => (is => 'ro');
has teamwork_host => (is => 'ro');
has teamwork_project => (is => 'rw');

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
                           project => $self->teamwork_project,
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
        $rt = LinuxiaSupportIntegration::RT->new(
                                    server => $self->rt_url,
                                    timeout => 30,
                                   );
        # initialize, log in, and store the object
        my $user = $self->rt_user;
        my $password = $self->rt_password;
        try {
            $rt->login(username => $user, password => $password);
        } otherwise  {
            die "problem logging in: " . shift;
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
        die "Couldn't connect to " . $self->imap_server . " for user " . $self->imap_user
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


=head2 parse_mails(@ids)

Given the mail ids in the list passed as argument, retrive them and
return a list of arrayrefs, where the first element is the numeric id
of the IMAP mail, and the second is an L<Email::MIME> object.

=cut

sub parse_mails {
    my ($self, @ids) = @_;
    unless (@ids) {
        @ids = $self->list_mails;
    }
    my @mails;
    foreach my $id (@ids) {
        my $body = $self->imap->get_rfc822_body($id);
        my $email = Email::MIME->new($$body);
        my %details = (
                       date => $email->header("Date"),
                       from => $email->header("From"),
                       to   => $email->header("To"),
                       subject => $email->header("Subject"),
                      );
        if (my @parts = $email->subparts) {
            foreach my $p (@parts) {
                if ($p->content_type =~ m/text\/plain/) {
                    $details{body} = $p->body_str;
                    last;
                }
            }
        }
        else {
            $details{body} = $email->body_str;
        }
        my $simulated = LinuxiaSupportIntegration::RT::Mail->new(%details);
        push @mails, [$id => $simulated ];
    }
    $self->_set_current_mail_objects(\@mails);
    return @mails;
}

=head2 parse_rt_ticket($ticket)

Access via REST the ticket $ticket and return a list of arrayrefs.
Each arrayref has two elements: the first is always undef, the second
is a L<LinuxiaSupportIntegration::RT::Mail> object, which mimic the
L<Email::MIME> object. In this way C<parse_mails> or
C<parse_rt_ticket> return fully compatible lists.

The first element is undef because we don't want to move around mails
when we look into RT.

=cut

sub parse_rt_ticket {
    my ($self, $ticket) = @_;
    return unless $ticket;
    my @trxs = $self->rt->get_transaction_ids(parent_id => $ticket, type => 'ticket');
    my $fullticket = $self->rt->show(type => 'ticket', id => $ticket);
    my %ticket_details = (
                          date => $fullticket->{Created},
                          from => $fullticket->{Creator},
                          subject => $fullticket->{Subject},
                          body => "RT ticket $ticket in queue $fullticket->{Queue}",
                         );
    my @details = (LinuxiaSupportIntegration::RT::Mail->new(%ticket_details));
    # probably here we want to take the first mail and dump it as body
    # of the ticket creation action.
    foreach my $trx (@trxs) {
        my $mail = $self->rt->get_transaction(parent_id => $ticket,
                                              id => $trx,
                                              type => 'ticket');
        # print Dumper($mail);
        my $obj = LinuxiaSupportIntegration::RT::Mail->new(
                                                           date => $mail->{Created},
                                                           body => $mail->{Content},
                                                           from => $mail->{Creator},
                                                           subject => $mail->{Description}
                                                          );
        push @details, $obj;
    }
    # print Dumper(\@details);
    # mimic the output of parse_mails from IMAP, set index undef
    # so we don't end moving mails around.
    return map { [ undef, $_ ] } @details;
}


=head2 show_ticket_mails

List the mails found in the RT ticket $id;

=cut


sub show_ticket_mails {
    my ($self, $ticket) = @_;
    return $self->_format_mails($self->parse_rt_ticket($ticket));
}

=head2 show_mails

List the summary of the mails found in IMAP.

=cut

sub show_mails {
    my $self = shift;
    return $self->_format_mails($self->parse_mails);
}

sub _format_mails {
    my ($self, @mails) = @_;
    my @summary;
    foreach my $mail (@mails) {
        push @summary,
          join(" ",
               $mail->[0] // "virtual mail",
               ".",
               From => $mail->[1]->header("From"),
               To   => $mail->[1]->header("To"),
               $mail->[1]->header("Date"),
               "\nSubject: " . $mail->[1]->header("Subject"),
               "\n" . $self->_cut_mail($mail->[1]->body_str) . "\n");
    }
    return @summary;
}

sub _cut_mail {
    my ($self, $body) = @_;
    my $beginning = substr($body, 0, 50);
    $beginning =~ s/\r?\n/ /gs;
    return $beginning;
    
}

# RT

sub move_mails_to_rt_ticket {
    my ($self, $ticket) = @_;
    return $self->_add_mails_to_ticket(rt => $ticket);
}

sub move_mails_to_rt_ticket_comment {
    my ($self, $ticket) = @_;
    return $self->_add_mails_to_ticket(rt => $ticket, { comment => 1 });
}

sub create_rt_ticket {
    my ($self, $queue, $subject) = @_;
    return $self->_add_mails_to_ticket(rt => undef, { queue => $queue,
                                                      subject => $subject,
                                                    });
}

# Teamwork stuff

sub move_mails_to_teamwork_ticket {
    my ($self, $ticket) = @_;
    return $self->_add_mails_to_ticket(teamwork => $ticket);
}

sub create_teamwork_ticket {
    my ($self, $queue, $subject) = @_;
    return $self->_add_mails_to_ticket(teamwork => undef, { queue => $queue,
                                                            subject => $subject,
                                                          });
}

sub _add_mails_to_ticket {
    my ($self, $type, $ticket, $opts) = @_;
    $opts ||= {};
    $self->prepare_backup_folder;
    my @ids = $self->list_mails;
    my @mails = $self->parse_mails(@ids);
    return $self->process_emails($type, $ticket, $opts, @mails);
}

sub move_rt_ticket_to_teamwork_task {
    my ($self, $ticket, $tm_ticket) = @_;
    my @mails = $self->parse_rt_ticket($ticket);
    # print Dumper(\@mails);
    return $self->process_emails(teamwork => $tm_ticket, {}, @mails);
}

sub move_rt_ticket_to_teamwork_task_list {
    my ($self, $ticket, $task_list) = @_;
    my @mails = $self->parse_rt_ticket($ticket);
    return $self->process_emails(teamwork => undef, { queue => $task_list }, @mails);        
}

sub process_emails {
    my ($self, $type, $ticket, $opts, @mails) = @_;
    die "Wrong usage" unless ($type and ($type eq 'rt' or $type eq 'teamwork'));
    my @archive;
    my @messages;
    foreach my $mail (@mails) {
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
                $ticket = $self->$type->linuxia_create($body, $eml, $opts);
                die "Couldn't create ticket!" unless $ticket;
                my $msg;
                if ($type eq 'rt') {
                    $msg = "Created ticket " . $self->rt_url . "/Ticket/Display.html?id=$ticket";
                }
                elsif ($type eq 'teamwork') {
                    $msg = "Created ticket " . $self->teamwork_host . "/tasks/$ticket";
                }
                push @messages, $msg;
            }
            elsif ($opts->{comment}) {
                push @messages,
                  $self->$type->linuxia_comment($ticket, $body, $eml, $opts);
            }
            else {
                push @messages,
                  $self->$type->linuxia_correspond($ticket, $body, $eml, $opts);
            }
            push @archive, $id;

        } otherwise {
            my $identifier;
            if (defined $id) {
                $identifier = $id;
            }
            else {
                $identifier = "virtual mail";
            }
            warn "$identifier couldn't be processed: "  . shift . "\n";
        };
    }
    $self->archive_mails(@archive);
    return join("\n", @messages) . "\n";
}

=head2 archive_mails(@ids)

Given the ids passed as arguments, copy those in the IMAP backup
folder.

The list is purged by eventual undefined values (when pulling from RT
the argument will be a list of undef).

=cut

sub archive_mails {
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


1;
