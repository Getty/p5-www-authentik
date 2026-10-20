#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeAuthentik;
use WWW::Authentik;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }
sub text_of { defined $_[0] ? "$_[0]" : '' }

my $fake = FakeAuthentik->new;
my $api  = WWW::Authentik->new( base_url => $fake->base, token => $fake->token, ua => $fake )->api;
my $html = '<html><head><title>502 Bad Gateway</title></head><body>nginx</body></html>';

subtest 'a 2xx that is not JSON' => sub {
  # a proxy, or a captive portal, answers with a page. Taking that for an
  # empty object would make a list come back empty and look like an instance
  # without users
  $fake->answer( qr{/api/v3/core/users/\z}, 200, $html );

  my $error = error_of { $api->list_users };
  isa_ok( $error, 'WWW::Authentik::Error::API', 'a 200 with HTML is an error' );
  is( $error ? $error->http_status : undef, 200, 'the status is carried' );
  like( text_of($error), qr/\AGET /, 'the message names the method' );
  like( text_of($error), qr{\Q/api/v3/core/users/\E}, 'and the path' );
  like( text_of($error), qr/502 Bad Gateway/, 'and a snippet of the body' );
  unlike( text_of($error), qr/\Qfake-api-token\E/, 'and never the token' );
};

subtest 'ensure_user does not create a user behind a page' => sub {
  $fake->answer( qr{/api/v3/core/users/\z}, 200, $html );

  my $error = error_of { $api->ensure_user( username => 'alice', name => 'Alice' ) };
  isa_ok( $error, 'WWW::Authentik::Error::API', 'ensure_user is an error, not a creation' );
  unlike( text_of($error), qr/created/, 'and it does not say that it created something' );
};

subtest 'the flow export is YAML and stays that way' => sub {
  # authentik answers the export with YAML and a text/html content type, so
  # the body is taken as it is
  $api->create_flow( { name => 'Probe', slug => 'probe-flow', title => 'Probe', designation => 'authentication' } );
  like( $api->export_flow('probe-flow'), qr/\Aversion: 1/, 'export_flow gives the YAML as a string' );
};

done_testing;
