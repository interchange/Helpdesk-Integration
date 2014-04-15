#!/usr/bin/env perl

use strict;
use warnings;

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
use File::Spec;
binmode STDOUT, ":encoding(utf-8)";

my ($source, $target) = ("imap", "rt");

GetOptions (
            "source=s" => \$source,
            "target=s" => \$target,
           );

my $conf_file = $ARGV[0] || File::Spec->catfile(getcwd(), "mconf.yml");
my $conf = LoadFile($conf_file);

my $linuxia = LinuxiaSupportIntegration->new(configuration => $conf);

$linuxia->set_source($source);
$linuxia->set_target($target);
$linuxia->set_source("teamwork");
print Dumper($linuxia);
