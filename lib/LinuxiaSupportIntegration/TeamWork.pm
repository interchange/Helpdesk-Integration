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

=cut


1;
