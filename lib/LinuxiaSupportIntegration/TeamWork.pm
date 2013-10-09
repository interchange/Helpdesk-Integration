package LinuxiaSupportIntegration::TeamWork;

use strict;
use warnings;
use JSON;
use LWP::UserAgent;

=head1 NAME

LinuxiaSupportIntegration::TeamWork - Perl module to interact with the
TeamWork API (using JSON).

=head1 DESCRIPTION

This module will connect your application with the API, and provides
some methods to create and update tasks.

Given that it's meant to have an interface similar to RT, the
following logic applies.

  RT Queues => TM Projects  /projects/$id
  RT Ticket => TM Task Lists /todo_lists/$id
  RT Correspondence => TM Task /todo_items/$id
  RT Comments => TM comments on an a todo_list

=head1 ACCESSORS/METHODS

The following parameters should be passed to the constructor:

=over 4

=item api_key

=item host

(with or without protocol). If protocol is omitted the http protocol 

=back

=cut

use Moo;

has api_key => (is => 'ro',
                required => 1);

has host => (is => 'ro',
             required => 1);

has auth_realm => (is => 'ro',
                   default => sub { return 'TeamworkPM' });

has _fqhostname => (is => 'rw');
sub _fqhost {
    my $self = shift;
    my $name = $self->_fqhostname;
    unless ($name) {
        my $host = $self->host;
        if ($host !~ m/^http/) {
            $name = "http://$host";
        }
        else {
            $name = $host;
        }
        # strip the trailing slash
        $name =~ s!/$!!;
        $self->_fqhostname($name);
    }
    return $name;
}

has _barehost => (is => 'rw');
sub _auth_host {
    my $self = shift;
    my $name = $self->_barehost;
    unless ($name) {
        if ($self->host =~ m!(https?://)?(.+?)/?$!) {
            $name = $2;
        }
        else {
            die "Bad host " . $self->host;
        }
        $self->_barehost($name);
    }
    return $name;
}

=head2 ua

The LWP::UserAgent object.

When doing an api request, the data structure will be returned, and
will throw an exception with the status line if the server returns a
failure.

=head2 login

Mimic the RT login retrieving the list of the projects and
initializing the User Agent with the authentication.

This operation is required before doing anything else.

=cut

has ua => (is => 'rw',
           default => sub {
               return LWP::UserAgent->new;
           });

sub login {
    my $self = shift;
    my $host = $self->_fqhost;
    my $port = 80;
    if ($host =~ m/^https/) {
        $port = 443;
    }
    $self->ua->credentials($self->_auth_host . ":" . $port,
                           $self->auth_realm,
                           $self->api_key,
                           1 # fake password, not needed
                          );
    return $self->get_projects;
}

sub _do_api_request {
    my ($self, $method, @args) = @_;
    my $url = $args[0];
    # prepend the server name
    die "Missing url" unless $url;
    $args[0] = $self->_fqhost . $url;
    my $res = $self->ua->$method(@args);
    if ($res->is_success) {
        my $body = $res->decoded_content;
        # decode the json and return the data structure, or just
        # return
        if ($body) {
            return decode_json($body);
        }
        else {
            return;
        }
    }
    else {
        die $res->status_line;
    }
}

=head2 Projects

The following methods are provided

=over 4

=item projects

An hashref with id => name pairs. This will be populated when login is
first called.

=cut

has projects => (is => 'rw');

sub get_projects {
    my $self = shift;
    my $details = $self->_do_api_request(get => '/projects.json');
    my %projects;

    if ($details && $details->{projects}) {
        foreach my $p (@{$details->{projects}}) {
            $projects{$p->{id}} = $p->{name};
        }
    }
    $self->projects(\%projects);
    if (%projects) {
        return $details->{projects};
    }
}



1;
