#!/usr/bin/env perl
use 5.010001;
use strict;
use warnings;
use Test::More tests => 1;
use Helpdesk::Integration::Instance;

my $instance = Helpdesk::Integration::Instance->new;

ok ($instance);
