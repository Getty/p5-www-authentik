package WWW::Authentik;

# ABSTRACT: Perl client for the authentik identity provider (OIDC + REST API v3)

use Moo;
use LWP::UserAgent;
use Types::Standard qw( InstanceOf Str );
use URI::Escape qw( uri_escape_utf8 );
use WWW::Authentik::API;
use WWW::Authentik::Diff;
use WWW::Authentik::Error;
use WWW::Authentik::Error::API;
use WWW::Authentik::Error::Network;
use WWW::Authentik::Error::Validation;
use WWW::Authentik::OIDC;
use namespace::autoclean;

our $VERSION = '0.001';

=synopsis

    use WWW::Authentik;

    my $ak = WWW::Authentik->new(
      base_url    => 'https://id.example.org',
      application => 'my-app',                   # the application slug, for OIDC
      token       => $ENV{AUTHENTIK_TOKEN},      # an API token, for the REST API
    );

    # OpenID Connect against the application
    my $claims = $ak->oidc->verify_token( $jwt, type => 'access' );

    # REST API v3, repeatable
    $ak->api->ensure_user( username => 'alice', name => 'Alice', password => $pw );
    my $r = $ak->api->ensure_application( slug => 'my-app', name => 'My App', provider_name => 'my-app' );
    print $r->{changed};   # 'created', 'updated' or ''

    # another application, same instance and token
    my $other = $ak->for_application('second-app');

=description

A client for authentik in two parts: L<WWW::Authentik::OIDC> for what an
application does with its OpenID Connect endpoints, and
L<WWW::Authentik::API> for bringing an authentik into a wanted state from
Perl, repeatably.

authentik has no realm. The API is instance-wide under C<< <base_url>/api/v3/ >>
and needs an API token; OpenID Connect is addressed per application, with
discovery, keys and the end-session endpoint under
C<< <base_url>/application/o/<slug>/ >> and the token, userinfo, introspection,
revocation and device endpoints shared by the whole instance. So L</token> and
L</application> are both optional: without a slug there is no L</oidc>,
without a token there is no L</api>, and either may be left out.

An authentik API token is long-lived and is used as it is. There is no login
to manage and nothing to renew; authentik answers a token it does not accept
with 403, not 401.

=head2 Coming from WWW::Keycloak

The two distributions have the same shape, but two return values differ, and
deliberately. C<create_*> and C<update_*> return the representation, not an
id, because authentik answers a create with the whole object and sends no
C<Location> header. And C<ensure_*> returns
C<< { object => \%rep, changed => ... } >>, not C<< { id => ..., changed => ... } >>,
because authentik has no single kind of identifier: an application is
addressed by its slug, a provider by an integer, a group by a UUID, a token by
its identifier. The caller almost always needs the next key out of the object
anyway.

Developed and tested against authentik 2026.8.3.

=cut

has base_url => (
  is       => 'ro',
  isa      => Str,
  required => 1
);

=attr base_url

Required. Where authentik is, without C</api/v3> and without
C</application/o/>. Trailing slashes are removed.

=cut

has application => (
  is        => 'ro',
  isa       => Str,
  predicate => 'has_application'
);

=attr application

The slug of the application L</oidc> talks to. Without it L</oidc> throws a
validation error.

=cut

has token => (
  is        => 'ro',
  isa       => Str,
  predicate => 'has_token'
);

=attr token

An authentik API token, sent as a bearer token with every call of L</api>.
Without it L</api> throws a validation error. It is used as it is and never
renewed.

=cut

has ua => (
  is  => 'lazy',
  isa => InstanceOf['LWP::UserAgent']
);

sub _build_ua {
  # no redirects: authentik answers 302 wherever it wants a browser, and none
  # of those may carry the API token anywhere
  return LWP::UserAgent->new(
    timeout      => 30,
    agent        => 'WWW-Authentik/'.$VERSION,
    max_redirect => 0,
    ssl_opts     => { verify_hostname => 1 }
  );
}

=attr ua

The L<LWP::UserAgent> every part shares. The default follows no redirects,
which matters here: authentik redirects at the authorize endpoint and between
the stages of a flow, and those answers are read, not followed.

=cut

has oidc => (
  is       => 'lazy',
  init_arg => undef
);

sub _build_oidc {
  my ( $self ) = @_;
  WWW::Authentik::Error::Validation->throw( message => __PACKAGE__.'->oidc needs an application slug' )
    unless $self->has_application && length $self->application;
  return WWW::Authentik::OIDC->new( application_url => $self->application_url, ua => $self->ua );
}

=attr oidc

The L<WWW::Authentik::OIDC> of L</application>.

=cut

has api => (
  is       => 'lazy',
  init_arg => undef
);

sub _build_api {
  my ( $self ) = @_;
  WWW::Authentik::Error::Validation->throw( message => __PACKAGE__.'->api needs an API token' )
    unless $self->has_token && length $self->token;
  return WWW::Authentik::API->new( base_url => $self->base_url, token => $self->token, ua => $self->ua );
}

=attr api

The L<WWW::Authentik::API> of this instance.

=cut

around BUILDARGS => sub {
  my ( $orig, $class, @args ) = @_;
  my $args = $class->$orig(@args);
  $args->{base_url} =~ s{/+\z}{} if defined $args->{base_url};
  return $args;
};

sub BUILD {
  my ( $self ) = @_;
  WWW::Authentik::Error::Validation->throw( message => __PACKAGE__.' needs a base_url' ) unless length $self->base_url;
  return;
}

sub api_url { $_[0]->base_url.'/api/v3' }

=method api_url

    print $ak->api_url;   # https://id.example.org/api/v3

=cut

sub application_url {
  my ( $self ) = @_;
  WWW::Authentik::Error::Validation->throw( message => __PACKAGE__.'->application_url needs an application slug' )
    unless $self->has_application && length $self->application;
  return $self->base_url.'/application/o/'.uri_escape_utf8( $self->application );
}

=method application_url

    print $ak->application_url;   # https://id.example.org/application/o/my-app

Where this application's OpenID Connect endpoints live, without the trailing
slash. The slug is URI encoded.

=cut

sub issuer { $_[0]->application_url.'/' }

=method issuer

    print $ak->issuer;   # https://id.example.org/application/o/my-app/

The issuer in its address form, which is what authentik puts into a token
while the provider is set to C<issuer_mode: per_provider> (its default). The
authoritative value is L<WWW::Authentik::OIDC/issuer>, read out of the
discovery document; with C<issuer_mode: global> the two differ.

=cut

sub for_application {
  my ( $self, $slug ) = @_;
  return ref($self)->new(
    base_url    => $self->base_url,
    application => $slug,
    ua          => $self->ua,
    $self->has_token ? ( token => $self->token ) : ()
  );
}

=method for_application

    my $other = $ak->for_application('second-app');

The same client for another application, sharing the user agent and the API
token.

=cut

1;
