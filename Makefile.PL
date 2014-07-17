use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Helpdesk::Integration',
    AUTHOR              => q{Marco Pessotto <melmothx@gmail.com>},
    VERSION_FROM        => 'lib/Helpdesk/Integration.pm',
    ABSTRACT_FROM       => 'lib/Helpdesk/Integration.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
                  'Net::IMAP::Client' => 0,
                  'Email::MIME' => 0,
                  'Error' => 0,
                  'RT::Client::REST' => 0.45,
                  'Net::GitHub' => 0.47,
                  'JSON' => 0,
                  'LWP::UserAgent' => 0,
                  'Moo' => 0,
                  'YAML' => 0,
                  'Date::Parse' => 0,
                  'Google::API::Client' => 0.13,
    },
    EXE_FILES => [
                  'bin/helpdesk-integration',
                 ],
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Helpdesk-Integration-*' },
);
