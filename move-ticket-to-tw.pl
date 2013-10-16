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

my ($ticket, $todo_list, $help, $debug);

GetOptions (
            "ticket=i"  => \$ticket, # numeric
            "todo-list=i" => \$todo_list,
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

$linuxia->move_mails_from_rt_to_teamwork_todo($ticket, $todo_list);

sub show_help {
    print <<EOF
Retrieve the details 
EOF
}
