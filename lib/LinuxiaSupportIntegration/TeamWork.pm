package LinuxiaSupportIntegration::TeamWork;

use strict;
use warnings;
use JSON;
use LWP::UserAgent;
use Data::Dumper;

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
    
    # print Dumper(\@args);
    my $res = $self->ua->$method(@args);
    if ($res->is_success) {
        return $res;
    }
    else {
        print Dumper($res);
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

has projects => (is => 'rw',
                 default => sub { return {} });

sub get_projects {
    my $self = shift;
    my $res = $self->_do_api_request(get => '/projects.json');
    return unless $res;
    my $details = decode_json($res->decoded_content);
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

# interface similar to rt.

sub linuxia_create {
    my ($self, $body, $eml, $opts) = @_;
    my $name = $eml->header('Subject');
    my $description = $body;
    my $project = $opts->{queue};
    die "No project found!" unless $project;
    return $self->create_task_list($project, $name, $description);
}

sub create_task_list {
    my ($self, $project, $name, $description) = @_;
    die "Missing coordinates! project <$project> and name <$name>"
      unless ($project && $name);
    my %projects = %{ $self->projects };

    # look in keys and values of projects
    my $id = $self->_check_hash($project, \%projects);
    die "No project found" unless $id;
    my $details = { "todo-list" => {
                                  name => $name,
                                  description => $description
                                 }
                  };
    my $res = $self->_do_api_request(post => "/projects/$id/todo_lists.json",
                                     $self->_ua_params($details));

    # from the doc:

    # Returns HTTP status code 201 (“Created”) on success, with the
    # Location header set to the “Get list” URL for the new list. The new
    # list’s ID can be extracted from that URL. On failure, a non-200
    # status code will be returned, possibly with error information as the
    # response’s content.
    
    my $location = $res->header("location");
    if ($location =~ m!([0-9]+)$!) {
        return $1;
    }
    else {
        die "No id found in $location";
    }

}

sub linuxia_correspond {
    my ($self, $id, $body, $eml, $opts) = @_;
    my $details = {
                   "todo-item" => { content => $eml->header('Subject'),
                                    description => $body,
                                  }
                  };
    die "Missing todo_lists id!" unless $id;
    my $res = $self->_do_api_request(post => "/todo_lists/$id/todo_items.json",
                                     $self->_ua_params($details));
    return;
}

sub linuxia_comment {
    my ($self, $id, $body, $eml, $opts) = @_;
    my $details = {
                   comment => { body => $body }
                  };
    die "Missing todo_lists id!" unless $id;

    # we can't comment on a task list, but only on a particular task.
    my $res = $self->_do_api_request(post => "/todo_items/$id/comments.json",
                                     $self->_ua_params($details));
    return;
}


sub _ua_params {
    my ($self, $hash) = @_;
    my @params = (
                  Accept => 'application/json',
                  'Content-Type' => 'application/json' );
    push @params, Content => encode_json($hash);
    return @params;
}


sub _check_hash {
    my ($self, $id, $hash) = @_;
    die "wrong usage" unless defined($id);
    die "wrong hash" unless (ref($hash) eq 'HASH');
    # print Dumper($hash, $id);
    if ($hash->{$id}) {
        return $id;
    }
    # not a key? look into the values;
    my @matches;
    foreach my $k (keys %$hash) {
        if ($hash->{$k} eq $id) {
            push @matches, $k;
        }
    }
    if (@matches > 1) {
        warn "Multiple matches for $id";
        return;
    }
    elsif (@matches == 1) {
        return shift(@matches);
    }
    else {
        warn "No matches for $id";
        return;
    }
}


1;
