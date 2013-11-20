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
    $workers,
    $project,
    $force,
    $debug,
    $source,
    $target,
    $bts_subject,
    $queue);

GetOptions (
            "source=s"  => \$source,
            "target=s"  => \$target,
            "subject=s" => \$subject,
            "from=s"    => \$from,
            "ticket=i"  => \$ticket, # numeric
            "comment"   => \$comment, #boolean
            "queue=s"   => \$queue,
            "workers=s" => \$workers,
            "project=s"   => \$project,
            "dry-run"   => \$dry_run,
            "force"     => \$force,
            "debug"     => \$debug,
            "threshold=i" => \$threshold,
            "help"      => \$help,
            "bts-subject=s" => \$bts_subject,
           );

$threshold ||= 5;

my $conf_file = $ARGV[0] || getcwd() . "/mconf.yml";

if ($help || (! -f $conf_file)) {
    show_help();
    print "Tried to use $conf_file\n";
    exit 2;
}


my $conf = LoadFile($conf_file);
die "Bad configuration file $conf_file" unless $conf;

my $linuxia = LinuxiaSupportIntegration->new(debug_mode => $debug,
                                             configuration => $conf);

$linuxia->set_source($source || "imap");

$linuxia->set_target($target || "rt");

if ($linuxia->target->type eq 'teamwork' and $project) {
    $linuxia->target->project($project);
}

# see if we can retrieve the teamwork object
if ($workers) {
    $linuxia->target->assign_tickets(split(/\s?,\s?/, $workers));
}

# print Dumper($linuxia->imap->folders_more);
# $linuxia->imap->select("INBOX.RT-backup-Archive");
# print Dumper($linuxia->imap->search("ALL"));

unless ($subject || $from) {
    warn "No search parameter specified! This would take the whole INBOX!\n";
    warn "Dry-run mode forced\n";
    $dry_run = 1;
}

$linuxia->source->search_params({subject => $subject, from => $from});

my @mails = $linuxia->summary;
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

# preparation
$linuxia->target->append($ticket) if $ticket;
$linuxia->target->subject($bts_subject) if $bts_subject;
$linuxia->target->queue($queue) if $queue;
$linuxia->target->is_comment($comment) if $comment;
print $linuxia->execute, "\n";
exit;

sub show_help {
    print <<'HELP';

Usage: copy-mail-to-rt.pl [ options ] [ configuration.file.yml ]

The configuration file argument is optional and defaults to "mconf.yml"
located in the current directory.

Multiple instance are supported. Every defined instance must have its
own settings listed as in the example below.

Common keys: type, server, user (not needed for teamwork), password.

imap:
  type: imap
  server: "mx1.cobolt.net"
  user: 'marco@linuxia.de'
  password: "xxxxxxxxxx"
  backup_folder: "RT-backup-Archive" 
  ssl: 0
imap2:
  type: imap
  server: "mx1.cobolt.net"
  user: 'marco@linuxia.de'
  password: "xxxxxxxxx"
  backup_folder: "RT-backup-Archive" 
  ssl: 0
rt:
  type: rt
  server: http://localhost/rt
  user: root
  password: xxxxxx
  target_name_field: "Remote system"
  target_id_field: "Teamwork id"
  target_queue_field: "Remote queue"
teamwork:
  type: teamwork
  password: xxxxxxxxxx
  server: https://linuxiahr.teamworkpm.net
  project: Linuxia testing
informa_teamwork:
  type: teamwork
  password: xxxxxxxxxxxxxx
  server: https://linuxiahr.teamworkpm.net
  project: Linuxia testing

Options to define the source and target:

  --source <string>
    (<string> must exist in the configuration file). Defaults to "imap"

  --target <string>
    (<string> must exist in the configuration file). Defaults to "rt"
  

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

  --workers <comma-separated list of username or emails>

    Assign the task to a user. The user must be present in the TW
    project. This for now works only on task creation for Teamwork.

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


