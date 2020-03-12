package Helpdesk::Integration::GoogleCalendar;

use strict;
use warnings;
use Moo;
with 'Helpdesk::Integration::Instance';

use Google::API::Client;
use Google::API::OAuth2::Client;
use Data::Dumper;
use Date::Parse;
use DateTime;
use Encode qw/encode/;

=head1 NAME

Helpdesk::Integration::GoogleCalendar - Helpdesk instance for Google Calendar

=head1 Google calendar token setup

Procedure is as follow.

The default and suggested configuration in config.yml stores the token
files in C<data>, so create or cleanup that directory.

Login into the google account or create a new one

Go to L<https://www.google.com/calendar/render>

Create a new calendar.

Got to L<https://console.developers.google.com/project>

Create a new project and give it a name and a code.

After a while it will redirect to the console.

Click on B<Enable an API>

Find the Calendar API and enable that.

On the left-hand menu, it should appear "APIS & AUTH". Go to Credentials.

Don't be fooled by the existing OAuth and click on "Create new Client
ID" Application type must be B<Installed application> and "Installed
application type" must be B<other>

The console now will show Client ID for native application.

Click Download JSON and save it. That is the file we need for the
GoogleCalendar module and its filename must match the C<secrets_file>
value in the configuration stanza, which looks like this:

  calendar:
    type: gcal
    secrets_file: data/secrets.json
    token_file: data/gcal-token.json
    calendar_id: xxxxxxxxxxx@group.calendar.google.com

The token file is written by the application, so in the configuration
you just set it as a destination file.

Last, but not the least, we need the calendar id to operate on.

From the main Google calendar page, click on the C<My calendars>
dropdown and go to "Settings". Find your calendar and click on it. At
the bottom, you'll find calendar address, with links to xml, ical,
html. There you'll find the ID as well, so store it in the
configuration.

=head1 ACCESSORS/METHODS

=head2 Configuration

See above for an explanation.

=over 4

=item type

Always return C<gcal>

=item secrets_file

=item token_file

=item calendar_id

=item time_zone

Being a calendar, the timezone is crucial. You can set the timezone
for the newly created tickets. Defaults to UTC.

=back

=cut

sub type {
    return "gcal";
}

has secrets_file => (is => 'ro',
                    required => 1,
                    isa => sub {
                        die "secrets_file $_[0] must be an existent file"
                          unless -f $_[0];
                    });

has token_file => (is => 'ro',
                   required => 1);

has calendar_id => (is => 'ro',
                    required => 1);

has time_zone => (is => 'rw',
                  default => sub { 'UTC' });


=head2 Methods

The following methods are aliases:

=over 4

=item create($message)

=item create_comment($message)

=item correspond($message)

=item comment($message)

=back

All of them do the same thing: adding an entry to the target calendar.

=cut

sub create {
    my ($self, $eml) = @_;
    my $start = $eml->start;
    my $end = $eml->due;
    die "Missing start/end" unless ($start && $end);
    my $start_dt = DateTime->from_epoch(epoch => $start,
                                        time_zone => $self->time_zone);
    my $end_dt = DateTime->from_epoch(epoch => $end,
                                      time_zone => $self->time_zone);
    my $event = {
                 start => {
                           dateTime => $start_dt->iso8601,
                           timeZone => $start_dt->time_zone->name,
                          },
                 end => {
                           dateTime => $end_dt->iso8601,
                           timeZone => $end_dt->time_zone->name,
                        },
                 summary => encode('UTF-8', $eml->subject),
                 transparency => 'transparent',
                 # location ?
                 confirmed => 'confirmed',
                 description => encode('UTF-8', $eml->body),
                };
    my $ev = $self->insert_event($event);
    if ($ev->{id}) {
        return $ev->{id}, "Event created: $ev->{htmlLink}";
    }
    else {
        return;
    }
}

sub _event_append {
    my ($self, $eml) = @_;
    my $id = $self->append;
    die "No id found" unless $id;
    my $event = $self->get_event($id);
    # update the description
    $event->{description} .= "\n\n" . encode('UTF-8', $eml->body);
    $self->update_event($event);
    return;
}

sub comment {
    my ($self, @args) = @_;
    $self->_event_append(@args);
}

sub correspond {
    my ($self, @args) = @_;
    $self->_event_append(@args);
}

sub create_comment {
    my ($self, @args) = @_;
    $self->_event_append(@args);
}

=head2 login

=cut

sub login {
    shift->get_or_restore_token;
}

=head2 parse_messages

List the entries in the calendar and create the Ticket objects.

=cut

sub parse_messages {
    my $self = shift;
    my @events = $self->events;
    my @tickets;
    foreach my $event (@events) {
        my %details = (
                       date => $event->{updated},
                       from => $event->{creator}->{email},
                       to => $event->{organizer}->{email},
                       subject => $event->{summary} || 'No subject',
                       body => $event->{description},
                       start => str2time($event->{start}->{dateTime}),
                       due => str2time($event->{end}->{dateTime}),
                       trxid => $event->{id},
                       filename_pattern => $self->filename_pattern,
                       attachment_directory => $self->attachment_directory,
                      );
        push @tickets, Helpdesk::Integration::Ticket->new(%details);
    }
    return map { [ undef, $_ ] } @tickets;
}

=head1 INTERNALS

=head2 service

=head2 auth_driver

=cut

has service => (is => 'lazy');


sub _build_service {
    my $self = shift;
    my $client = Google::API::Client->new;
    my $service = $client->build('calendar', 'v3');
    return $service;
}

has auth_driver => (is => 'lazy');


sub _build_auth_driver {
    my $self = shift;
    my $secret = $self->secrets_file;
    unless (-f $secret) {
        die "$secret was not found!";
    }
    my $auth_driver = Google::API::OAuth2::Client
      ->new_from_client_secrets($self->secrets_file,
                                $self->service->{auth_doc});
    return $auth_driver;
}


sub _authen {
    my $self = shift;
    return { auth_driver => $self->auth_driver };
}

=head2 events

Return a list of events.

=cut

sub events {
    my $self = shift;
    my $page_token;
    my @events;
    do {
        my %body = (
                    calendarId => $self->calendar_id,
                   );
        if ($page_token) {
            $body{pageToken} = $page_token;
        }
        my $res = $self->service->events->list(
                                               body => \%body,
                                              )->execute($self->_authen);
        $page_token = $res->{nextPageToken};
        push @events, @{ $res->{items} };
    } until (!$page_token);
    return @events;
}

=head2 insert_event(\%event)

Event structure description:

https://developers.google.com/google-apps/calendar/v3/reference/events/insert

Returns the inserted calendar event.

=cut

sub insert_event {
    my ($self, $event) = @_;
    my $added = $self->service->events->insert(
                                               calendarId => $self->calendar_id,
                                               body => $event,
                                              )->execute($self->_authen);
    return $added;
}

=head2 delete_event($event_id)

Delete event with id $event_id from calendar with id $cal_id.

=cut

sub delete_event {
    my ($self, $event_id) = @_;
    $self->service->events->delete(
                                   calendarId => $self->calendar_id,
                                   eventId => $event_id,
                                  )->execute($self->_authen);
}

=head2 update_event(\%event)

The id is retrieved from $event->{id}.

=cut

sub update_event {
    my ($self, $event) = @_;
    my $id = delete $event->{id};
    die "Missing id" unless $id;
    my $patched = $self->service->events->patch(
                                                 calendarId => $self->calendar_id,
                                                 eventId => $id,
                                                 body => $event,
                                                )->execute($self->_authen);
    return $patched;
}

=head2 get_event($event_id)

Return the event with event id $event_id.

=cut

sub get_event {
    my ($self, $event_id) = @_;
    die "Missing id " unless $event_id;
    my $event = $self->service->events->get(
                                            calendarId => $self->calendar_id,
                                            eventId => $event_id,
                                           )->execute($self->_authen);
    return $event;
}

=head2 get_or_restore_token

Method to be called right after new to get the authentication in place.

If the token has not been retrieved yet, will issue a request and ask
the user to visit an url and paste on the console the token.

=cut

sub get_or_restore_token {
    my $self = shift;
    my $file = $self->token_file;
    my $auth_driver = $self->auth_driver;
    my $access_token;
    if (-f $file) {
        open my $fh, '<', $file;
        if ($fh) {
            local $/;
            require JSON;
            $access_token = JSON->new->decode(<$fh>);
            close $fh;
        }
        $auth_driver->token_obj($access_token);
    } else {
        my $auth_url = $auth_driver->authorize_uri;
        print "Go to the following link in your browser:\n";
        print "$auth_url\n";
    
        print "Enter verification code:\n";
        my $code = <STDIN>;
        chomp $code;
        $access_token = $auth_driver->exchange($code);
        # and save it for the next requests
        $self->store_token;
    }
    return $access_token;
}

=head2 store_token

Save the token for future accesses.

=cut

sub store_token {
    my $self = shift;
    my $file = $self->token_file;
    my $auth_driver = $self->auth_driver;
    my $access_token = $auth_driver->token_obj;
    my $old_umask = umask 0077;
    open my $fh, '>', $file;
    if ($fh) {
        require JSON;
        print $fh JSON->new->encode($access_token);
        close $fh;
    }
    umask $old_umask;
}

=head2 update_or_create_event( $event)

Try to get the event $event with id $event->{id}. If found, update it,
if not, create it.

=cut

sub update_or_create_event {
    my ($self, $event) = @_;
    my $ev;
    if (my $id = $event->{id}) {
        local $SIG{__WARN__} = sub {};
        eval {
            $ev = $self->get_event($self->calendar_id, $id);
        };
    }
    if ($ev) {
        print "Updating $event->{id}\n";
        $self->update_event($event);
    }
    else {
        print "Inserting new event\n";
        $self->insert_event($event);

    }
}


1;
