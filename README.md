# WWW-Authentik

Perl client for the [authentik](https://goauthentik.io/) identity provider: OpenID Connect
against an application plus the REST API v3, with repeatable `ensure_*` methods for
bringing an authentik into a wanted state from Perl. A structural sibling of
`WWW::Keycloak`, written independently of it.

Developed and live-tested against authentik 2026.8.3.

Async twin: [`Net::Async::Authentik`](https://github.com/Getty/p5-net-async-authentik),
same API with `_f` suffixes and Futures.

## Synopsis

```perl
use WWW::Authentik;

my $ak = WWW::Authentik->new(
  base_url    => 'https://id.example.org',
  application => 'my-app',                   # the application slug, for OIDC
  client_id   => $client_id,                 # its provider's client id, checked as the audience
  token       => $ENV{AUTHENTIK_TOKEN},      # an API token, for the REST API
);
```

authentik has no realm. The API is instance-wide and needs an API token; OpenID Connect is
addressed per application. Both parts are optional: without a slug there is no `oidc`,
without a token there is no `api`.

### OpenID Connect

```perl
my $oidc   = $ak->oidc;
my $tokens = $oidc->client_credentials_token( client_id => $id, client_secret => $secret, scope => 'openid' );
my $claims = $oidc->verify_token( $tokens->{access_token}, type => 'access' );

my $start = $oidc->device_authorization( client_id => $id, scope => 'openid' );
print $start->{verification_uri_complete};
my $done = eval { $oidc->device_token( device_code => $start->{device_code}, client_id => $id ) };
# $@->oauth_error eq 'authorization_pending' while nobody has approved
```

`verify_token` checks signature, issuer and expiry, and the audience — which is what
`client_id` above is for. **The audience is what separates two applications of one
authentik**: every provider of an instance signs with the same key, and with
`issuer_mode: global` they all issue under the same issuer too, so without an audience a
token of any other application would pass. On such an instance `verify_token` refuses to
verify without one, unless you say `any_audience => 1`.

`type` is a heuristic: authentik puts no `typ` into the JOSE header, so an access token is
told from an ID token by its `scope` claim.

### The REST API, one call at a time

```perl
my $api  = $ak->api;
my $user = $api->create_user( { username => 'alice', name => 'Alice' } );
$api->set_password( $user->{pk}, $password );
my $group = $api->find_group('staff');
$api->add_user_to_group( $group->{pk}, $user->{pk} );
```

`list_*` follows authentik's pagination and returns every match. Writing is `PATCH`.
A duplicate is **400 with a field error**, not 409, and a refused token is **403**, not 401;
`WWW::Authentik::Error::API` carries `field_errors`, `oauth_error` and `request_id`.

### A setup that can run twice

```perl
$api->ensure_group( name => 'staff' );
$api->ensure_user( username => 'alice', name => 'Alice', password => $pw, group_names => ['staff'] );

my $r = $api->ensure_oauth2_provider(
  name                    => 'my-app',
  authorization_flow_slug => 'default-provider-authorization-implicit-consent',
  invalidation_flow_slug  => 'default-provider-invalidation-flow',
  client_type             => 'confidential',
  grant_types             => [qw( authorization_code refresh_token )],
  redirect_uris           => [ { matching_mode => 'strict', url => 'https://app.example.org/cb' } ],
  scopes                  => [qw( openid email profile )],
);
$api->ensure_application( slug => 'my-app', name => 'My App', provider_name => 'my-app' );

print $r->{changed};        # 'created', 'updated' or '' on a run that changed nothing
print $r->{object}{pk};
```

Each `ensure_*` looks the object up by its readable key, creates it when it is missing,
otherwise writes only what differs. Only the keys given are compared, and nothing is ever
deleted. A password is set when the user is created and never again.

Where authentik wants an identifier and a person knows a name, `resolve` looks it up — and
never guesses: for every field one shape counts as the identifier, and `<field>_name` or
`<field>_slug` forces the lookup. So a provider named `123` is reached with
`provider_name => '123'`, because `provider => '123'` is the provider with the primary
key 123.

## Live tests

```bash
AUTHENTIK_LIVE_TEST=1 AUTHENTIK_URL=http://127.0.0.1:9000 AUTHENTIK_TOKEN=... prove -lv t/90-live-authentik.t
```

The suite prefixes everything it makes with a random name and deletes it again, so it can
run beside other work and twice in a row. A throwaway authentik for it:
`t/authentik/docker-compose.yml`, with `t/authentik/env.example` for the secrets.

## A note on the user agent

If you pass your own `ua`, keep `send_te => 0`. LWP announces the `TE` connection token by
default, and authentik 2026.8.3 does not answer every second request that carries it.
`WWW::Authentik->default_ua` builds a user agent with that and `max_redirect => 0`.

## License

This library is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.
