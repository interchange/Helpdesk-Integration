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

my ($ticket, $todo_list, $task, $help, $debug);

GetOptions (
            "ticket=i"  => \$ticket, # numeric
            "todo-list=s" => \$todo_list,
            "task=s" => \$task,
            "help"      => \$help,
           );

my $conf_file = $ARGV[0] || "$FindBin::Bin/conf.yml";

if ($help || (! -f $conf_file)) {
    show_help();
    exit;
}


my $conf = LoadFile($conf_file);
die "Bad configuration file $conf_file" unless $conf;

my $linuxia = LinuxiaSupportIntegration->new(debug_mode => $debug, %$conf);

my @mails = $linuxia->show_ticket_mails($ticket);
print join("\n", @mails);

if ($task) {
    print $linuxia->move_rt_ticket_to_teamwork_task($ticket, $task);
}
else {
    print $linuxia->move_rt_ticket_to_teamwork_task_list($ticket, $todo_list);
}

sub show_help {
    print <<EOF
Retrieve the details 
EOF
}
