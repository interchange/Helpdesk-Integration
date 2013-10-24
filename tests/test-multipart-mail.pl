#!/usr/bin/env perl
use strict;
use warnings;

use Email::MIME;
use File::Slurp qw/read_file/;

my $body = read_file(shift);

my $email = Email::MIME->new($body);

if (my @parts = $email->subparts) {
    foreach my $p (@parts) {
        if ($p->content_type =~ m/text\/plain/) {
            $email = $p;
            last;
        }
    }
}

print $email->body_str, "\n";

