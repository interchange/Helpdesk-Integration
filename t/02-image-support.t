#!/usr/bin/env perl
use 5.010001;
use strict;
use warnings;
use Test::More;
use Module::Load;

my %classes = (
               Instance => 0,
               GitHub => 0,
               RT => 1,
               TeamWork => 1,
              );

foreach my $c (keys %classes) {
    my $class = "LinuxiaSupportIntegration::$c";
    load $class;
    is($class->image_upload_support, $classes{$c});
}

done_testing;
