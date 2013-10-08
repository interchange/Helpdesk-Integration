#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/lib";
use LinuxiaSupportIntegration;
use YAML qw/LoadFile Dump/;
use Getopt::Long;
use Data::Dumper;
binmode STDOUT, ":encoding(utf-8)";

my ($subject,
    $from,
    $ticket,
    $comment,
    $help,
    $dry_run,
    $threshold,
    $force,
    $queue);

GetOptions (
            "subject=s" => \$subject,
            "from=s"    => \$from,
            "ticket=i"  => \$ticket, # numeric
            "comment"   => \$comment, #boolean
            "queue=s"   => \$queue,
            "dry-run"   => \$dry_run,
            "force"     => \$force,
            "threshold=i" => \$threshold,
            "help"      => \$help,
           );

$threshold ||= 5;

my $conf_file = $ARGV[0] || "$FindBin::Bin/conf.yml";

if ($help || (! -f $conf_file)) {
    show_help();
    exit;
}


my $conf = LoadFile($conf_file);
die "Bad configuration file $conf_file" unless $conf;

my $linuxia = LinuxiaSupportIntegration->new(debug_mode => 1, %$conf);

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

if ($ticket) {
    if ($comment) {
        $linuxia->move_mails_to_rt_ticket_comment($ticket);
    }
    else {
        $linuxia->move_mails_to_rt_ticket($ticket);
    }
}
else {
    $linuxia->create_rt_ticket($queue);
}

sub show_help {
    print <<'HELP';

Usage: copy-mail-to-rt.pl [ options ] [ configuration.file.yml ]

The configuration file argument is optional and defaults to "conf.yml"
located in the same directory of this executable.

It should contain the following keys:

  # IMAP credentials
  imap_server: "imap.server.net"
  imap_user: 'marco@test.me'
  imap_pass: "xxxxxxxxxxxxx"
  
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
  
Options for fetching the mails:

  --subject '<string>'

    The mails with the subject containing the given string will be
    added to RT.

  --from '<string>'

    The mails with the from header containing the given string will be
    added to RT.

Options for adding to RT

  --dry-run

    When this flag is set, no operation is performed on the target
    mails, but they are just listed (with the from, to, subject, date
    header and the first 50 characters of the body.

  --ticket '<id>'

    Add the mail to the given ticket. If none is provided, a new
    ticket will be created.

  --comment

    If the comment flag is set, the mails will be added as comment
    when adding a mail to ticket. By default correspondence is added.
    This option is ignored if a new ticket is being created from the
    email.

  --queue '<string>'

    The target queue. Defaults to "General".

  --threshold <num>

    The script will refuse to do anything if the number of the
    returned mails is greater than than <num> (defaults to 5), because
    if the search is too generic we will end up slurping most or all
    the INBOX. To override this you can use the --force options

  --force

    Don't look at the threshold and just do the job.

HELP

}


