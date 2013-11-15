package LinuxiaSupportIntegration;
use strict;
use warnings;

use Net::IMAP::Client;
use LinuxiaSupportIntegration::TeamWork;
use LinuxiaSupportIntegration::RT;
use LinuxiaSupportIntegration::IMAP;
use LinuxiaSupportIntegration::Ticket;
use Email::MIME;
use Error qw(try otherwise);
use Data::Dumper;

our $VERSION = '0.01';

=head1 NAME

LinuxiaSupportIntegration -- moving request tickets across systems

=cut

use Moo;

=head1 ACCESSORS

=cut

has imap_server => (
                    is => 'ro',
                   );

has imap_user => (
                  is => 'ro',
                 );

has imap_pass => (
                  is => 'ro',
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
has configuration => (is => 'ro',
                      default => sub { return {} },
                      isa => sub {
                          my $conf = $_[0];
                          die "Empty conf passed"
                            unless $conf;
                          die "Conf is not a reference"
                            unless ref($conf);
                          die "Conf is not an hashref"
                            unless ref($conf) eq 'HASH';
                          # validate the structure
                          foreach my $k (keys %$conf) {
                              foreach my $v (qw/type/) {
                                  die "Missing $k configuration"
                                    unless exists $conf->{$k}->{$v};
                              }
                              foreach my $v (keys %{$conf->{$k}}) {
                                  die "Found deeper level"
                                    if ref($conf->{$k}->{$v});
                              }
                          }
                      });

has target => (is => 'rwp');
has source => (is => 'rwp');

sub _create_object {
    my ($self, $name) = @_;
    my %credentials = %{$self->configuration->{$name}};
    my $type = lc(delete $credentials{type});
    my %map = (
               rt => 'RT',
               imap => 'IMAP',
               teamwork => 'TeamWork',
              );
    my $class = $map{$type};
    die "Unsupported type $type!" unless $class;
    $class = __PACKAGE__ . '::' . $class;
    my $obj = $class->new(%credentials);
    print "Logging in with $class\n";
    $obj->login;
    return $obj;
}

sub set_target {
    my ($self, $name) = @_;
    my $obj = $self->_create_object($name);
    $self->_set_target($obj);
}

sub set_source {
    my ($self, $name) = @_;
    my $obj = $self->_create_object($name);
    $self->_set_source($obj);
}

sub summary {
    my $self = shift;
    return $self->_format_mails($self->source->parse_messages);
}

sub execute {
    my $self = shift;
    my @archive;
    my @messages;
    my $opts;
    foreach my $mail ($self->source->parse_messages) {
        my $id = $mail->[0];
        my $eml = $mail->[1];
        die "Unexpected failure" unless $eml;

        # the REST interface doesn't seem to support the from header
        # (only cc and attachments), so it should be OK to inject
        # these info in the body
        try {
            my $body = $eml->as_string;
            # if no ticket provided, we create it and queue the other
            # mails as correspondence to this one
            if (!$self->target->append) {
                my ($ticket, $msg) = $self->target->linuxia_create($body, $eml, $opts);
                push @messages, $msg;
                die "No ticket returned!" unless $ticket;
                $self->target->append($ticket);
                if (my @attachments = $eml->attachments_filenames) {
                    $self->target->linuxia_correspond($ticket, "Attached file",
                                                     $eml, $opts);
                }
            }
            elsif ($self->target->is_comment) {
                push @messages,
                  $self->target->linuxia_comment($self->target->append, $body, $eml, $opts);
            }
            else {
                push @messages,
                  $self->target->linuxia_correspond($self->target->append, $body, $eml, $opts);
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
            if (my $project = $self->target->project) {
                $identifier .= " (Project $project)";
            }
            warn "$identifier couldn't be processed: "  . shift . "\n";
        };
    }
    $self->source->archive_messages(@archive) unless $self->debug_mode;
    return join("\n", @messages) . "\n";
}



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
        $self->_set_teamwork_obj($tm);
    }
    return $tm;
}

sub rt {
    my $self = shift;
    my $rt = $self->rt_obj;
    unless ($rt) {
        $rt = LinuxiaSupportIntegration::RT->new(
                                                 url => $self->rt_url,
                                                 timeout => 30,
                                                 user => $self->rt_user,
                                                 password => $self->rt_password,
                                                );
        # initialize, log in, and store the object
        try {
            $rt->login;
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
        print "No imap object, creating\n";
        $imap = LinuxiaSupportIntegration::IMAP->new(
                                                     server => $self->imap_server,
                                                     user => $self->imap_user,
                                                     pass => $self->imap_pass,
                                                     ssl => $self->imap_ssl,
                                                     port => $self->imap_port,
                                                     target_folder => $self->imap_target_folder,
                                                     debug_mode => $self->debug_mode,
                                                    );
        $imap->login;
        $self->_set_imap_obj($imap);
    }
    return $imap;
}


=head2 parse_mails(@ids)

Given the mail ids in the list passed as argument, retrive them and
return a list of arrayrefs, where the first element is the numeric id
of the IMAP mail, and the second is an L<Email::MIME> object.

=cut


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
    return $self->rt->parse_messages(ticket => $ticket);
}

sub parse_mails {
    my ($self, @ids) = @_;
    return $self->imap->parse_messages(ids => \@ids);
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
               ".", $mail->[1]->summary);
    }
    return @summary;
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
    $self->imap->prepare_backup_folder;
    my @ids = $self->imap->list_mails;
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
    # test if we can get a valid object for rt or teamwork
    my $test = $self->$type;
    die "Cannot retrieve $type object" unless $test;

    foreach my $mail (@mails) {
        my $id = $mail->[0];
        my $eml = $mail->[1];
        die "Unexpected failure" unless $eml;

        # the REST interface doesn't seem to support the from header
        # (only cc and attachments), so it should be OK to inject
        # these info in the body
        try {
            my $body = $eml->as_string;
            # if no ticket provided, we create it and queue the other
            # mails as correspondence to this one
            if (!$ticket) {
                ($ticket) = $self->$type->linuxia_create($body, $eml, $opts);
                die "Couldn't create ticket!" unless $ticket;
                my $msg;
                if ($type eq 'rt') {
                    $msg = "Created ticket " . $self->rt_url . "/Ticket/Display.html?id=$ticket";
                }
                elsif ($type eq 'teamwork') {
                    $msg = "Created ticket " . $self->teamwork_host . "/tasks/$ticket";
                }
                push @messages, $msg;
                if (my @attachments = $eml->attachments_filenames) {
                    $self->$type->linuxia_correspond($ticket, "Attached file",
                                                     $eml, $opts);
                }
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
            if ($type eq 'teamwork') {
                $identifier .= " (TW project '" . $self->$type->project . "') :";
            }
            warn "$identifier couldn't be processed: "  . shift . "\n";
        };
    }
    $self->imap->archive_messages(@archive);
    return join("\n", @messages) . "\n";
}



1;
