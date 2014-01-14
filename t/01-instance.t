#!/usr/bin/env perl
use 5.010001;
use strict;
use warnings;
use Test::More;
use LinuxiaSupportIntegration::Instance;

plan tests => 2;

my $instance = LinuxiaSupportIntegration::Instance->new;

$instance->message_cache([ [1 => "test"], [ 2 => "test2"] ]);

ok($instance->message_cache);
$instance->clean_cache;
ok(!$instance->message_cache);
