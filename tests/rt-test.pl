#!/usr/bin/env perl

use strict;
use warnings;

use Error qw(:try);
use RT::Client::REST;
use Data::Dumper;
use YAML qw/LoadFile/;

my $conf_file = shift || "conf.yml";

die "Missing configuration file" unless (-f $conf_file);

my $conf = LoadFile($conf_file);


my $user = $conf->{rt_user};
my $password = $conf->{rt_password};



my $rt = RT::Client::REST->new(
                               server => 'http://localhost/rt/',
                               timeout => 30,
                              );

try {
    $rt->login(username => $user, password => $password);
} catch Exception::Class::Base with {
    die "problem logging in: ", shift->message;
};

try {
    # Get ticket #1
    my $ticket = $rt->show(type => 'ticket', id => 1);
    print Dumper($ticket);
} catch RT::Client::REST::UnauthorizedActionException with {
    print "You are not authorized to view ticket #1\n";
} catch RT::Client::REST::Exception with {
    # something went wrong.
};


my @trxs = $rt->get_transaction_ids(parent_id => 1);
foreach my $trx (@trxs) {
    print Dumper($rt->get_transaction(parent_id => 1, id => $trx));
}


my $new_ticket = $rt->create(
                             type => 'ticket',
                             set => {
                                     Queue => "General",
                                     Subject => "Another test",
                                    },
                             text => "Test from rest");
print $new_ticket;

$rt->comment(ticket_id => $new_ticket, message => "Well, it seems to work");

$rt->correspond(ticket_id => $new_ticket, message => "And correspondence works");


