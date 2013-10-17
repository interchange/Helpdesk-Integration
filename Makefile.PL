use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'LinuxiaSupportIntegration',
    AUTHOR              => q{Marco Pessotto <melmothx@gmail.com>},
    VERSION_FROM        => 'lib/LinuxiaSupportIntegration.pm',
    ABSTRACT_FROM       => 'lib/LinuxiaSupportIntegration.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
                  'Net::IMAP::Client' => 0,
                  'Email::MIME' => 0,
                  'Error' => 0,
                  'RT::Client::REST' => 0,
                  'JSON' => 0,
                  'LWP::UserAgent' => 0,
                  'Moo' => 0,
                  'YAML' => 0,
    },
    EXE_FILES => [
                  'bin/copy-mail-to-rt.pl',
                  'bin/move-ticket-to-tw.pl',
                 ],
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Dancer-Plugin-LDAP-*' },
);
