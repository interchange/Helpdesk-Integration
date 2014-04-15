#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use Cwd;
use lib "$FindBin::Bin/../lib";
use LinuxiaSupportIntegration;
use YAML qw/LoadFile Dump/;
use Data::Dumper;
my $conf_file = $ARGV[0] || getcwd() . "/conf.yml";
my $conf = LoadFile($conf_file);
my $linuxia = LinuxiaSupportIntegration->new(debug_mode => 1, %$conf);
print Dumper($linuxia);

print join("\n", $linuxia->show_mails);

print Dumper($linuxia);
