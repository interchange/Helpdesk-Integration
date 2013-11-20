#!perl -T
use 5.010001;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 5;

BEGIN {
    for (qw/LinuxiaSupportIntegration
            LinuxiaSupportIntegration::IMAP
            LinuxiaSupportIntegration::RT
            LinuxiaSupportIntegration::TeamWork
            LinuxiaSupportIntegration::Instance/) {
        use_ok( $_ ) || print "Bail out!\n";
    }
}

diag( "Testing LinuxiaSupportIntegration $LinuxiaSupportIntegration::VERSION, Perl $], $^X" );
