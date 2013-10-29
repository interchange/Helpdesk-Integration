#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/../lib";
use LinuxiaSupportIntegration;
use YAML qw/LoadFile Dump/;
use Getopt::Long;
use Data::Dumper;
use Cwd;
binmode STDOUT, ":encoding(utf-8)";

my ($subject,
    $from,
    $ticket,
    $comment,
    $help,
    $dry_run,
    $threshold,
    $teamwork,
    $project,
    $force,
    $debug,
    $bts_subject,
    $queue);

GetOptions (
            "subject=s" => \$subject,
            "from=s"    => \$from,
            "ticket=i"  => \$ticket, # numeric
            "comment"   => \$comment, #boolean
            "queue=s"   => \$queue,
            "teamwork"  => \$teamwork,
            "project=s"   => \$project,
            "dry-run"   => \$dry_run,
            "force"     => \$force,
            "debug"     => \$debug,
            "threshold=i" => \$threshold,
            "help"      => \$help,
            "bts-subject=s" => \$bts_subject,
           );

$threshold ||= 5;

my $conf_file = $ARGV[0] || getcwd() . "/conf.yml";

if ($help || (! -f $conf_file)) {
    show_help();
    print "Tried to use $conf_file\n";
    exit 2;
}


my $conf = LoadFile($conf_file);
die "Bad configuration file $conf_file" unless $conf;

my $linuxia = LinuxiaSupportIntegration->new(debug_mode => $debug, %$conf);

if ($project) {
    $linuxia->teamwork_project($project);
}

# see if we can retrieve the teamwork object
if ($teamwork) {
    $linuxia->teamwork;
}

# print Dumper($linuxia->imap->folders_more);
# $linuxia->imap->select("INBOX.RT-backup-Archive");
# print Dumper($linuxia->imap->search("ALL"));

unless ($subject || $from) {
    warn "No search parameter specified! This would take the whole INBOX!\n";
    warn "Dry-run mode forced\n";
    $dry_run = 1;
}

$linuxia->mail_search_params(subject => $subject, from => $from);

my @mails = $linuxia->show_mails;
print join("\n", @mails);
exit if $dry_run;

if (!$force and @mails > $threshold) {
    warn "Total mail examined: " . scalar(@mails) . ". Threshold exceeded ($threshold), exiting\n";
    warn "Use --force to override or set an higher --threshold\n";
    exit;
}

if (!$ticket && $comment) {
    warn "You're creating a ticket, the --comment option is ignored, bailing out";
    exit;
}

if ($ticket) {
    if ($teamwork) {
        # teamwork doesn't care about the --comment switch
        print $linuxia->move_mails_to_teamwork_ticket($ticket); 
    }
    else {
        if ($comment) {
            print $linuxia->move_mails_to_rt_ticket_comment($ticket);
        }
        else {
            print $linuxia->move_mails_to_rt_ticket($ticket);
        }
    }
}
else {
    if ($teamwork) {
        print $linuxia->create_teamwork_ticket($queue, $bts_subject);
    }
    else {
        print $linuxia->create_rt_ticket($queue, $bts_subject);
    }
}

print "\n";

sub show_help {
    print <<'HELP';

Usage: copy-mail-to-rt.pl [ options ] [ configuration.file.yml ]

The configuration file argument is optional and defaults to "conf.yml"
located in the current directory.

It should contain the following keys:

  # IMAP credentials
  imap_server: "imap.server.net"
  imap_user: 'marco@test.me'
  imap_pass: "xxxxxxxxxxxxx"
  
  # optional, defaults to "RT-Archive"
  imap_backup_folder: "RT-backup-Archive"

  # optional
  imap_ssl: 1
  imap_port: 993
  
  # RT credentials
  rt_url: "http://localhost/rt"
  rt_user: pinco
  rt_password: pallino
  
  # Team work credentials, still unused
  teamwork_host: myhost.no.proto
  teamwork_api_key: xxxxxxx
  teamwork_project: Test project
  
Options for fetching the mails:

  --subject '<string>'

    The mails with the subject containing the given string will be
    added to RT.

  --from '<string>'

    The mails with the from header containing the given string will be
    added to RT.

Options for adding to RT/TeamWork

  --bts-subject "<New subject>"

    Overwrite the subject email when setting the subject of the
    ticket. This applies for RT and TW.

  --teamwork

    When this flag is set, the operation is not performed against RT
    but against the TeamWork.pm installation.

  --dry-run

    When this flag is set, no operation is performed on the target
    mails, but they are just listed (with the from, to, subject, date
    header and the first 50 characters of the body.

  --ticket '<id>'

    Add the mail to the given ticket. If none is provided, a new
    ticket will be created using the first mail, and the other will be
    added as correspondence (for RT) or as comment (for Teamwork).

  --comment

    If the comment flag is set, the mails will be added as comment
    when adding a mail to ticket. By default correspondence is added.
    This option is ignored if a new ticket is being created from the
    email in RT or if you passed the --teamwork flag (mails are
    comments).

  --queue '<string>'

    The target queue. Defaults to "General". For RT, the queue must
    exist. For Teamwork, if it doesn't exist the task list will be
    created in the project specified in the configuration.

  --threshold <num>

    The script will refuse to do anything if the number of the
    returned mails is greater than than <num> (defaults to 5), because
    if the search is too generic we will end up slurping most or all
    the INBOX. To override this you can use the --force options

  --project <name>

    Name or id of the current TeamWork project. Usually set in the
    configuration file, but you can override it using this option.

  --force

    Don't look at the threshold and just do the job.

  --debug

    Don't archive the mails moving them out of INBOX

Please note that the mails are not deleted but moved into the folder
specified in the imap_default_folder configuration directive.

HELP

}


