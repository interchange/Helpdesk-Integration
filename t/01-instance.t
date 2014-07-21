#!/usr/bin/env perl
use 5.010001;
use strict;
use warnings;
use Test::More tests => 5;

# if the role doesn't apply, it wouldn't load too

foreach my $c (qw/GitHub TeamWork GoogleCalendar IMAP RT/) {
    use_ok("Helpdesk::Integration::$c");
}


