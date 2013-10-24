#!/usr/bin/env perl
use strict;
use warnings;

use Email::MIME;
use lib '../lib';
use LinuxiaSupportIntegration::RT::Mail;
use File::Slurp qw/read_file/;

my $body = read_file(shift);

my $email = Email::MIME->new($body);

my %details = (
               date => $email->header("Date"),
               from => $email->header("From"),
               to   => $email->header("To"),
               subject => $email->header("Subject"),
              );
if (my @parts = $email->subparts) {
    foreach my $p (@parts) {
        if ($p->content_type =~ m/text\/plain/) {
            $details{body} = $p->body_str;
            last;
        }
    }
} else {
    $details{body} = $email->body_str;
}
my $simulated = LinuxiaSupportIntegration::RT::Mail->new(%details);
$email = $simulated;
print join("\n", $email->body_str,
           $email->header('From'),
           $email->header('To'),
           $email->header('Subject'),
           $email->header('Date')), "\n";


