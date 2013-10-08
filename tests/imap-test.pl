#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Net::IMAP::Client;
use YAML qw/LoadFile/;

my $conf_file = shift || "conf.yml";

die "Missing configuration file" unless (-f $conf_file);

my $conf = LoadFile($conf_file);

print Dumper($conf);

my %credentials = (
                   server => $conf->{server},
                   user => $conf->{user},
                   pass => $conf->{pass},
                  );

for (qw/ssl port/) {
    if ($conf->{_}) {
        $credentials{$_} = $conf->{$_};
    }
}

print Dumper(\%credentials);

my $imap = Net::IMAP::Client->new(%credentials)
  or die "Could not connect to IMAP server for unknown reasons";

$imap->login; # or die ("Login failed" . $imap->last_error);

print join(", ", $imap->folders);
print Dumper($imap->status($imap->folders)), "\n";

$imap->select("INBOX");

my $messages = $imap->search(
                             { subject => 'library',
                               from => 'marco'
                             }
                            );

print Dumper($messages);

foreach my $msg_id (@$messages) {
    my $data = $imap->get_rfc822_body($msg_id);
    print $$data; # it's reference to a scalar
}


use Net::IMAP::Simple;

my %simple_opts;

if ($conf->{port}) {
    $simple_opts{port} = $conf->{port};
}
if ($conf->{ssl}) {
    $simple_opts{use_ssl} = $conf->{ssl};
}


$imap = Net::IMAP::Simple->new($conf->{server}, %simple_opts)
  or die "could  not connect";
if (!$imap->login($conf->{user} => $conf->{pass})) {
    die "Login failed " . $imap->errstr;
}

my @ids = $imap->search('FROM "melmothx"');

print join(", ", @ids), "\n";

print join(", ", $imap->mailboxes()), "\n";

my $msgs = $imap->select('INBOX');

foreach my $msg (1..$msgs) {
    if ($imap->seen( $msg )) {
        print "This message has been read before...\n"
    }

    # get the message, returned as a reference to an array of lines
    my $lines = $imap->get( $msg );

    # print it
    print $lines->[0];

    # get the message, returned as a temporary file handle
    # my $fh = $imap->getfh( $msg );
    # print <$fh>;
    # close $fh;
}

$imap->logout;

