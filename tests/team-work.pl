#!/usr/bin/env perl

use strict;
use warnings;

use YAML qw/LoadFile/;
use JSON;
use Data::Dumper;
use LWP::UserAgent;

my $conf_file = shift || "conf.yml";

die "Missing configuration file" unless (-f $conf_file);

my $conf = LoadFile($conf_file);

my $apikey = $conf->{teamwork_api_key};
my $host = $conf->{teamwork_host};

my $ua = LWP::UserAgent->new;

my $response = $ua->credentials("$host:80", "TeamworkPM", $apikey, 1);

my $projects = "http://" . $host . "/projects.json";

print $projects, "\n";
my $res = $ua->get($projects);
print $res->status_line, "\n";
my $details = decode_json($res->decoded_content);
print Dumper($details);

