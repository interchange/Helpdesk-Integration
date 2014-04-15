#!perl -T
use 5.010001;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 6;

BEGIN {
    for (qw/Helpdesk::Integration
            Helpdesk::Integration::IMAP
            Helpdesk::Integration::RT
            Helpdesk::Integration::GitHub
            Helpdesk::Integration::TeamWork
            Helpdesk::Integration::Instance/) {
        use_ok( $_ ) || print "Bail out!\n";
    }
}

diag( "Testing Helpdesk::Integration $Helpdesk::Integration::VERSION, Perl $], $^X" );
