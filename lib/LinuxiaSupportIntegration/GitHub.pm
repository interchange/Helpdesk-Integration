package LinuxiaSupportIntegration::GitHub;
use strict;
use warnings;

use Net::GitHub;
use Data::Dumper;

use Moo;
extends 'LinuxiaSupportIntegration::Instance';

=head2 ACCESSORS

The following keys must be passed to the constructor:

=over 4

=item user

=item password

=back

B<or>, alternatively (you can create a token for your user at
L<https://github.com/settings/applications>, under I<Personal Access Tokens>)

=over 4

=item access_token

=back

The C<access_token> will be used if you set both C<password> and
C<access_token>

Optinally, for Enterprise installations:

=over 4

=item api_url

=back

=cut

has user => (is => 'ro',
             required => 1);
has password => (is => 'ro');
has access_token => (is => 'ro');
has api_url => (is => 'ro');

has gh_obj => (is => 'rwp');

sub gh {
    my $self = shift;
    my $gh = $self->gh_obj;
    unless ($gh) {

        my %new;
        if (my $token = $self->access_token) {
            %new = (
                    access_token => $token,
                   );
        }
        else {
            %new = (
                    login => $self->user,
                    pass => $self->password,
                   );
        }

        # Pass api_url for GitHub Enterprise installations
        if (my $api_url = $self->api_url) {
            $new{api_url} = $api_url;
        }

        # die on errors, we are going to catch the exceptions
        $new{RaiseError} = 1;
        $gh = Net::GitHub->new(%new);
    }
    return $gh;
}

sub create {
    my ($self, $eml) = @_;
    my $issue = $self->gh->issue;
    $issue->set_default_user_repo($self->user, $self->queue);
    my $ticket = $issue->create_issue({
                                       title => $eml->subject,
                                       body => $eml->as_string,
                                      });
    print Dumper($ticket);
}


1;
