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

my ($ticket, $todo_list, $task, $help, $debug, $project, $workers);

GetOptions (
            "ticket=i"  => \$ticket, # numeric
            "todo-list=s" => \$todo_list,
            "task=s" => \$task,
            "project=s" => \$project,
            "workers=s" => \$workers,
            "help"      => \$help,
           );

my $conf_file = $ARGV[0] || getcwd() . "/mconf.yml";

if ($help || (! -f $conf_file)) {
    show_help();
    print "Tried to use $conf_file\n";
    exit 2;
}


my $conf = LoadFile($conf_file);
die "Bad configuration file $conf_file" unless $conf;

unless ($ticket) {
    show_help();
    print "Missing ticket number!\n";
    exit 2;
}

my $linuxia = LinuxiaSupportIntegration->new(debug_mode => $debug,
                                             configuration => $conf);

$linuxia->set_source("rt");
$linuxia->set_target("teamwork");

if ($project) {
    $linuxia->target->project($project);
}

if ($workers) {
    $linuxia->target->assign_tickets(split(/\s?,\s?/, $workers));
}

print Dumper($linuxia);

$linuxia->source->search_params({ ticket => $ticket });
$linuxia->target->options({ 
                           append => $task,
                           queue  => $todo_list,
                          });
my @mails = $linuxia->summary;
print join("\n", @mails);

print $linuxia->execute;


sub show_help {
    print <<EOF
Usage: move-ticket-to-tw.pl [ options ] [ configuration.file.yml ]

The configuration file argument is optional and defaults to "conf.yml"
located in the current directory. It's shared with the
copy-mail-to-rt.pl script. To see the details, please do

  copy-mail-to-rt.pl --help.

Options:

 --help

   Show this help and exit

 --ticket

   The RT ticket to fetch. Mandatory.

 --todo-list <name or id>

   String with the task list name or id (required if the name in the
   project is not unique).

 --task <id>

   Numeric id of the task where to append the mails found in RT as
   comments

 --project <name>

   Name or id of the current project. Usually set in the configuration
   file, but you can override it using this option.

 --workers <comma-separated list of username or emails>

   Assign the task to a user. The user must be present in the TW
   project. This for now works only on task creation.

The --task and --todo-list options are mutually exclusive. The --task
option will append the mails found in the RT ticket, while with the
--todo-list a new task will be created in the given task list.


EOF
}
