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

  RT Queues =>         TM Task Lists /todo_lists/$id
  RT Ticket =>         TM Task /todo_items/$id
  RT Correspondence => TM comments on an a todo_item
  RT Comments =>       TM comments on an a todo_item

Please note that comment and correspondence do the same thing on TM,
and just add a comment to a single task. Projects don't have a RT
equivalent, so it should be set in the object.


=head1 ACCESSORS/METHODS

The following parameters should be passed to the constructor:

=over 4

=item password

The API key

=item server

(with or without protocol). If protocol is omitted the http protocol 

=item project

The name or the id of the project.

=back

=cut

use Moo;

extends 'LinuxiaSupportIntegration::Instance';

has password => (is => 'ro',
                required => 1);

has server => (is => 'ro',
             required => 1);

has project => (is => 'rw');

has auth_realm => (is => 'ro',
                   default => sub { return 'TeamworkPM' });

has _fqhostname => (is => 'rw');
sub _fqhost {
    my $self = shift;
    my $name = $self->_fqhostname;
    unless ($name) {
        my $host = $self->server;
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
        if ($self->server =~ m!(https?://)?(.+?)/?$!) {
            $name = $2;
        }
        else {
            die "Bad host " . $self->server;
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
                           $self->password,
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

=over get_projects

Return the projects for the current account. It's called on login and
also checks if the current project set in the object is valid,
throwing an exception otherwise.

=back


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

=head2 create_task_list($name, $description)

Create in the current project the task list named $name, with
description $description. It returns the numeric id or die.

=cut

sub create_task_list {
    my ($self, $name, $description) = @_;
    die "Missing task list  name!" unless $name;
    my $id = $self->find_project_id($self->project);
    die "No project found" unless $id;

    my $details = { "todo-list" => {
                                  name => $name,
                                  description => $description,
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

=head2 create_task($id, $body, $email, $opts)

Create task with body $body from email object $email in todo-list with
numeric id $id. $opts is a hashref, but it's currently unused.

It returns the task id.

=cut

sub create_task {
    my ($self, $id, $eml) = @_;
    my $details = {
                   "todo-item" => { content => $self->subject || $eml->subject,
                                    description => $eml->as_string,
                                  }
                  };

    if (my @assigned = @{$self->_assign_to}) {
        $details->{'todo-item'}->{'responsible-party-id'} = join(",", @assigned);
    }

    die "Missing todo_lists id!" unless $id;
    my $res = $self->_do_api_request(post => "/todo_lists/$id/todo_items.json",
                                     $self->_ua_params($details));
    my $location = $res->header('location');
    if ($location =~ m!([0-9]+)$!) {
        return $1;
    }
    else {
        die "No id found in $location";
    }
}

=head2 create_comment($email)

Create comment on current task (retrieved from $self->append), using
the data stored in the object passed to the method.

This is aliased as

=over 4

=item correspond

=item comment

=back

=cut

sub upload_files {
    my ($self, @files) = @_;
    my @attachments;
    foreach my $att (@files) {
        die "Missing file $att" unless -f $att;
        # send up the file
        my $res = $self->_do_api_request(post => "/pendingfiles.json",
                                         Content_Type => 'multipart/form-data',
                                         Content => [ file => [$att]]);
        my $ref = decode_json($res->decoded_content);
        if ($ref && $ref->{pendingFile}->{ref}) {
            push @attachments, $ref->{pendingFile}->{ref};
            print "Uploaded file with " . $res->decoded_content . " response\n";
        }
        else {
            warn "Failure uploading $att\n";
        }
    };
    return @attachments;
}


sub create_comment {
    my ($self, $eml) = @_;
    my $details = {
                   comment => { body => $eml->as_string,
                                'emailed-from' => $eml->from,
                              },
                  };
    my $id = $self->append;
    die "Missing todo_lists id!" unless $id;

    if (my @attachments = $self->upload_files($eml->attachments_filenames)) {
        $details->{comment}->{pendingFileAttachments} = join(",", @attachments);
    }
    # we can't comment on a task list, but only on a particular task.
    my $res = $self->_do_api_request(post => "/todo_items/$id/comments.json",
                                     $self->_ua_params($details));
    return "Comment added on " . $self->_fqhost . "/tasks/$id ("
      . $res->header('location') . ")";

}

sub correspond {
    my ($self, @args) = @_;
    return $self->create_comment(@args);
}

sub comment {
    my ($self, @args) = @_;
    return $self->create_comment(@args);
}

=head2 create($eml)

Create a task in the $self->queue task list, which will be created
if it does not exist.

It ends up calling C<create_task> and returns its returning value (the
numeric id of the task).

=cut

sub create {
    my ($self, $eml) = @_;
    my $queue = $self->queue;
    die "Missing task list name or id" unless $queue;
    my $task_list = $self->find_task_list_id($queue)
      || $self->create_task_list($queue, "");
    die "No project found!" unless $task_list;
    my $id =  $self->create_task($task_list, $eml);
    return $id, "Created ticket " . $self->_fqhost . "/tasks/$id";
}




=head2 find_task_list_id($name)

Scan the current project's task lists and return the numeric id of the
task list with name $name. The argument may be the numeric id or the
name of the task. If you have multiple tasks with the same name you'll
get a failure and you have to use the numeric id.

=cut

sub find_task_list_id {
    my ($self, $queue) = @_;
    my $id = $self->find_project_id($self->project);
    my $res = $self->_do_api_request(get => "/projects/$id/todo_lists.json");
    return unless $res;
    my $details = decode_json($res->decoded_content);
    # find the right task list.
    my %task_lists;
    foreach my $det (@{$details->{'todo-lists'}}) {
        $task_lists{$det->{id}} = $det->{name};
    }
    # print Dumper(\%task_lists, $queue);
    return $self->_check_hash($queue, \%task_lists);
}

=head2 find_project_id

Get the numeric id of the current project (which could be the numeric
id as well).

If the project is not found, an exception is thrown.

=cut

sub find_project_id {
    my ($self, $project) = @_;
    die "Missing project name" unless $project;
    my %projects = %{ $self->projects };
    # print Dumper(\%projects, $project);
    my $id = $self->_check_hash($project, \%projects);
    my @avail_projects;
    if (defined $id) {
        return $id;
    }
    else {
        foreach my $k (keys %projects) {
            push @avail_projects, " - " . $projects{$k} . " (id $k)";
        }
        die qq{No project "$project" found in:\n} . join ("\n", @avail_projects) . "\n";
    }
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
    # still nothing? do a lowercase comparison
    unless (@matches) {
        my $wanted = lc($id);
        $wanted =~ s/^\s+//;
        $wanted =~ s/\s+$//;
        foreach my $k (keys %$hash) {
            my $to_check = lc($hash->{$k});
            $to_check =~ s/^\s+//;
            $to_check =~ s/\s+$//;
            if ($wanted eq $to_check) {
                push @matches, $k;
            }
        }
    }

    # print Dumper(\@matches);

    if (@matches > 1) {
        warn "Multiple matches for $id";
        return;
    }
    elsif (@matches == 1) {
        return shift(@matches);
    }
    else {
        # warn "No matches for $id";
        return;
    }
}

=head2 persons

Return a list of account details for the current project.

=cut

sub persons {
    my $self = shift;
    my $res = $self->_do_api_request(get => '/projects/'
                                     . $self->find_project_id($self->project)
                                     . '/people.json');
    return unless $res;
    my $persons = decode_json($res->decoded_content);
    if ($persons->{people}) {
        return @{$persons->{people}};
    }
}

sub assign_tickets {
    my ($self, @whos) = @_;
    my @ids;
    foreach my $who (@whos) {
        my $found = 0;
        $who =~ s/^\s+//;
        $who =~ s/\s+$//;
        # try to match against the usernames
        foreach my $existing ($self->persons) {
            if (lc($existing->{'user-name'}) eq lc($who) or
                lc($existing->{'email-address'}) eq lc($who)) {
                push @ids, $existing->{'id'};
                $found = 1;
                last;
            }
        }
        warn "$who was not found in the project " . $self->project unless $found ;
    }
    if (scalar(@ids) != scalar (@whos)) {
        warn "Some ids where not assigned!"
    }
    if (@ids) {
        $self->_assign_to(\@ids);
    }
}

sub _parse_attachments {
    my ($self, $dets) = @_;
    # because to add fun, in the task it's attachments-count, in the
    # comment attachments_count...
    return unless ($dets->{'attachments-count'} || $dets->{attachments_count});
    my @out;

    # for unknown reasons, we should try to download without the
    # stored authentication.
    my $ua = LWP::UserAgent->new;

    foreach my $att (@{$dets->{attachments}}) {
        my $id = $att->{id};
        # print "Found file $id\n";
        # at some point these raw request should be wrapped in a
        # module to get a cleaner interface, like for GH, but for now
        # will do
        my $res = $self->_do_api_request(get => "/files/$id.json");
        next unless $res;

        my $file = decode_json($res->decoded_content);
        if (my $url = $file->{file}->{'download-URL'}) {
            my $filebody = $ua->get($url);
            push @out, [$file->{file}->{name}, $filebody->content];
        }
    }
    if (@out) {
        return \@out
    }
    else {
        return;
    }
}

sub parse_messages {
    my $self = shift;
    my $id = $self->search_params->{ticket};
    return unless defined $id;
    if ($self->message_cache->{$id}) {
        warn "found message_cache\n";
        return @{ $self->message_cache->{$id} };
    }
    my $res = $self->_do_api_request(get => "/todo_items/$id.json");
    return unless $res;
    my $task = decode_json($res->decoded_content);
    # print Dumper($task);
    my $main = $task->{'todo-item'};
    my @items;
    my $iclass = 'LinuxiaSupportIntegration::Ticket';
    my %detail = (
                  subject => $main->{content},
                  body => $main->{description},
                  date => $main->{'created-on'},
                  due => $main->{'due-date'},
                  start => $main->{'start-date'},
                  from => $self->user_email($main->{'creator-id'}),
                 );
    if (my $atts = $self->_parse_attachments($main)) {
        $detail{attachments} = $atts;
    }
    # print Dumper(\%detail);
    push @items, $iclass->new(%detail);
    my $comment_count = $main->{'comments-count'};

    if ($comment_count) {
        my $url = "/todo_items/$id/comments.json?pageSize=$comment_count";
        my $res = $self->_do_api_request(get => $url);
        if ($res) {
            my $json = decode_json($res->decoded_content);
            foreach my $cmt (@{$json->{comments}}) {
                my %comment = (
                               date => $cmt->{datetime},
                               body => $cmt->{body},
                               from => $self->user_email($cmt->{'author-id'}),
                               subject => "Comment on $id",
                              );
                # print Dumper(\%comment);
                if (my $atts = $self->_parse_attachments($cmt)) {
                    $comment{attachments} = $atts;
                }
                push @items, $iclass->new(%comment);
            }
        }
        else {
            warn "Couldn't retrieve the comments for task $id!\n"
        }
    }
    my @out = map { [ undef, $_ ] } @items;
    $self->message_cache({ $id => \@out });
    return @out;
}

has _people_cache => (is => 'ro',
                      default => sub { return {} });

sub user_email {
    my ($self, $id) = @_;
    return $self->user_details($id)->{'email-address'};
}

sub user_details {
    my ($self, $id) = @_;
    my $person_cache = $self->_people_cache;
    if (!exists $person_cache->{$id}) {
        # not found in cache? do the request
        my $res = $self->_do_api_request(get => "/people/$id.json");
        if ($res) {
            my $person = decode_json($res->decoded_content);
            # print Dumper($person->{person});
            $person_cache->{$id} = $person->{person};
        }
        else {
            $person_cache->{$id} = {}; # so we don't spam requests for
                                       # users which we can't get.
        }
    }
    return $person_cache->{$id};
}


sub type {
    return "teamwork";
}

sub image_upload_support {
    return 1;
}

1;
