# WWW::Authentik Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `WWW::Authentik` phase 1: facade, errors, the REST API v3 with repeatable `ensure_*` methods, OIDC against an application, unit tests against an emulated authentik and a live suite against a real one.

**Architecture:** Moo classes following the pattern of `WWW::Keycloak`, but standalone: `WWW::Authentik` is the facade for an instance and optionally an application and builds `WWW::Authentik::OIDC` and `WWW::Authentik::API` with a shared `LWP::UserAgent`. Sending and mapping authentik's four error forms lives in the role `WWW::Authentik::Role::HTTP`, split into `build_request` / `read_response` / `send_request`, so the twin can reuse the first two. The comparison behind `ensure_*` is a pure function without I/O (`WWW::Authentik::Diff`). No dependency on `WWW-Keycloak`.

**Tech Stack:** Perl 5.20+, Moo, Types::Standard, LWP::UserAgent, HTTP::Message, JSON::MaybeXS, Crypt::JWT, URI. Dist::Zilla with `[@Author::GETTY]`.

**Spec:** `docs/superpowers/specs/2026-10-04-www-authentik-design.md` (approved 2026-10-04, with section 12 from the approval review).

## State of this plan

The plan is written for an implementer without prior knowledge, but it is **not a
complete code listing** like the Keycloak plan. Written out in full is what
cannot be derived from the spec and where a mistake is expensive: `Diff`, the
error classes and the mapping of the four error forms, the HTTP role, the
name resolution table, the `_ensure` core, `verify_token` and the pagination. For the
remaining methods the plan gives signature, HTTP call and return value in table form; the
spec sections 5.1, 5.2, 6 and 8 are the source for that and should be kept open while building.
Every row of the method tables is backed by spec section 8.

## Global Constraints

- Runtime dependencies exactly those in the `cpanfile` from task 1; nothing from `WWW-Keycloak`.
- One package per file, every file under `lib/` with `# ABSTRACT:` (ASCII only) and `our $VERSION = '0.001';`.
- No `require` for lazy loading under `lib/`.
- `croak` instead of `die` in non-class helper code; every error of the dist is an object from `WWW::Authentik::Error::*`, thrown with `->throw`.
- The API token appears in no error message and in no log.
- 2 spaces indentation, no trailing commas, `my ( $self, ... ) = @_;` as the first line, one-liners with `$_[0]->`.
- `is => 'ro'` is the default, `is => 'lazy'` with `sub _build_x` for anything non-trivial, `namespace::autoclean` in every class, types from `Types::Standard`.
- There is no realm: `base_url` is required, `application` (slug) and `token` are optional; `oidc` without a slug and `api` without a token throw `WWW::Authentik::Error::Validation` on first access.
- Every API path ends in `/`; without the slash authentik answers 404 (spec 8.1).
- `ensure_*` compares only the given keys, writes only on a difference, never deletes anything and returns `{ object, changed }` with `changed` equal to `created`, `updated` or empty. The deviation from Keycloak's `{ id, changed }` is intended (spec 12) and is stated in the facade's POD.
- Writing is `PATCH`, never `PUT` (spec 5.1).
- authentik behavior is not coded from memory: what `t/lib/FakeAuthentik.pm` does is what was observed in spec section 8, on authentik 2026.8.3.
- Every `.t` file starts with `#!/usr/bin/env perl`, `use strict; use warnings; use Test::More;` and ends with `done_testing;`. Tests run with `prove -lr t`.
- The live suite runs only with `AUTHENTIK_LIVE_TEST=1`, `AUTHENTIK_URL` and `AUTHENTIK_TOKEN` and never in a parallel run.
- The repos are public: no hostnames except `127.0.0.1` and `example.org`, no tokens, no internal addresses in files or commits.

## Review Focus

Five inputs the spec assumes, but which no task would check on its own.
Each gets its test in the task that owns the code.

1. **A name that looks like an identifier** — a provider named `123`, a flow slug in UUID form. Expected: `provider => '123'` is the PK 123, `provider_name => '123'` looks up the name; both at once is a validation error. Tests `looks like an identifier` in `t/52-api-resolve.t` (task 5).
2. **A setup that runs twice.** Expected: on the second run not a single writing call, `changed` empty, in particular for `property_mappings` (authentik reorders) and `redirect_uris` (authentik adds `redirect_uri_type`). Tests `writes nothing on the second run` in `t/51-api-ensure.t` (task 5) and `twice` in `t/90-live-authentik.t` (task 6).
3. **A password in the setup and a second run.** Expected: the password is set exactly once, on creation. Test `ensure_user sets the password only when it creates` in `t/51-api-ensure.t` (task 5).
4. **A list with more matches than fit on one page.** Expected: `list_*` returns all of them, follows `pagination.next`, stops at `next: 0` and does not loop forever on a broken response (`next` points back). Test `pagination` in `t/50-api.t` (task 4).
5. **A token that does not come from this application, has expired, is signed with a foreign key, with HMAC or with `alg: none`.** Expected: rejected with a validation error; a token with a newly rotated key, on the other hand, is accepted, but reloaded at most once per `jwks_min_age`. Tests `verify_token` and `key rotation` in `t/60-oidc.t` (task 3).

## Files

| File | Responsibility | Task |
|---|---|---|
| `cpanfile` | dependencies | 1 |
| `lib/WWW/Authentik/Diff.pm` | comparison without I/O, lists as sets, added defaults | 1 |
| `t/10-diff.t` | Diff | 1 |
| `lib/WWW/Authentik/Error.pm`, `Error/Validation.pm`, `Error/Network.pm`, `Error/API.pm` | error hierarchy, four error forms | 2 |
| `lib/WWW/Authentik/Role/HTTP.pm` | `build_request`, `read_response`, `send_request` | 2 |
| `t/lib/FakeAuthentik.pm` | emulated authentik for the unit tests | 2 |
| `t/20-errors.t` | error forms and predicates | 2 |
| `lib/WWW/Authentik/OIDC.pm` | discovery, JWKS, `verify_token`, token endpoint | 3 |
| `lib/WWW/Authentik.pm` | facade (the stub is replaced) | 3 |
| `t/40-facade.t`, `t/60-oidc.t` | facade, OIDC | 3 |
| `lib/WWW/Authentik/API.pm` (transport, pagination, basic operations) | API v3 | 4 |
| `t/50-api.t` | basic operations, pagination | 4 |
| `lib/WWW/Authentik/API.pm` (section `resolve` and `ensure`) | name resolution, repeatable methods | 5 |
| `t/51-api-ensure.t`, `t/52-api-resolve.t` | `ensure_*`, resolution | 5 |
| `t/lib/AuthentikExecutor.pm`, `t/90-live-authentik.t` | login via the flow executor, live suite | 6 |
| `README.md`, `Changes`, `CLAUDE.md`, `.claude/skills/www-authentik-core/SKILL.md`, `t/00-load.t` | bring up to date | 6 |

Order: 1 → 2 → 3 → 4 → 5 → 6, each builds on the previous one. One commit per task.

---

### Task 1: Dependencies and `WWW::Authentik::Diff`

**Files:**
- Modify: `cpanfile` (replace entirely)
- Create: `lib/WWW/Authentik/Diff.pm`
- Test: `t/10-diff.t`
- Modify: `t/00-load.t`

**Interfaces:**
- Produces: `WWW::Authentik::Diff->changes( \%current, \%wanted )` → HashRef of the keys to write (nested hashes merged), empty when there is nothing to do; `->merge( \%current, \%wanted )` → deeply merged hash; `->same( $a, $b )` → 1/0; `->list_defaults` → HashRef field name → default hash that authentik adds to list elements.

- [ ] **Step 1: Replace `cpanfile` and install**

`cpanfile`:

```perl
requires 'perl', '5.020';
requires 'Crypt::JWT';
requires 'HTTP::Message';
requires 'JSON::MaybeXS';
requires 'LWP::Protocol::https';
requires 'LWP::UserAgent';
requires 'Moo';
requires 'Type::Tiny';
requires 'URI';
requires 'namespace::autoclean', '0.16';

on test => sub {
    requires 'CryptX';
    requires 'Test::More', '0.96';
};
```

Run: `cpanm --installdeps .` — Expected: finishes without errors.

- [ ] **Step 2: Write `t/10-diff.t`**

Subtest `same`:
- equal and different strings; `3600` against `'3600'` equal; `undef`/`undef` equal; `undef` against `''` different.
- Booleans equal in every spelling: `\1`, `JSON::MaybeXS::true`, `'true'`, `1` among each other; `\1` against `\0` different; `'true'` against `'yes'` different.
- **Lists are sets**: `[qw( a b )]` equals `[qw( b a )]`; `[qw( a b )]` differs from `[qw( a b b )]`; lists of hashes as a set: `[ { a => 1 }, { b => 2 } ]` equals `[ { b => 2 }, { a => 1 } ]`; key order within a hash does not matter.
- empty list equals empty list, differs from `undef`.

Subtest `changes`:
- nothing to do for an equal state; a top-level key; a nested hash comes back merged (`attributes`), an already matching nested key yields nothing; a list is replaced; a key the current state does not have; a nested hash where there was none; a hash where there was a scalar; `undef` as the current state; the current state is not modified.
- `property_mappings` in a different order yields **no** change.
- `redirect_uris`: `[ { matching_mode => 'strict', url => 'https://a/cb' } ]` against the read state `[ { matching_mode => 'strict', url => 'https://a/cb', redirect_uri_type => 'authorization' } ]` yields **no** change; a different URL yields one.

Subtest `merge`: deep for hashes, everything else replaced; `undef` as the current state.

- [ ] **Step 3: Run the test, it must fail**

Run: `prove -lr t/10-diff.t` — Expected: FAIL with `Can't locate WWW/Authentik/Diff.pm in @INC`.

- [ ] **Step 4: Write `lib/WWW/Authentik/Diff.pm`**

```perl
package WWW::Authentik::Diff;

# ABSTRACT: Compare an authentik representation with the wanted state, without I/O

use strict;
use warnings;
use Scalar::Util qw( blessed );
use JSON::MaybeXS;

our $VERSION = '0.001';

my $JSON = JSON::MaybeXS->new( canonical => 1, allow_nonref => 1, convert_blessed => 1 );

sub list_defaults {
  return { redirect_uris => { redirect_uri_type => 'authorization' } };
}

sub changes {
  my ( $self, $current, $wanted, $key_prefix ) = @_;
  $current = {} unless ref $current eq 'HASH';
  my %changes;
  for my $key ( keys %$wanted ) {
    my ( $have, $want ) = ( $current->{$key}, $self->with_defaults( $key, $wanted->{$key} ) );
    if ( ref $want eq 'HASH' ) {
      my $inner = $self->changes( ref $have eq 'HASH' ? $have : {}, $want );
      $changes{$key} = $self->merge( ref $have eq 'HASH' ? $have : {}, $want ) if %$inner;
      next;
    }
    $changes{$key} = $wanted->{$key} unless $self->same( $have, $want );
  }
  return \%changes;
}

sub with_defaults {
  my ( $self, $key, $value ) = @_;
  my $defaults = $self->list_defaults->{$key};
  return $value unless $defaults && ref $value eq 'ARRAY';
  return [ map { ref $_ eq 'HASH' ? { %$defaults, %$_ } : $_ } @$value ];
}

sub merge {
  my ( $self, $current, $wanted ) = @_;
  my %merged = %{ $current || {} };
  for my $key ( keys %$wanted ) {
    $merged{$key} = ref $wanted->{$key} eq 'HASH' && ref $merged{$key} eq 'HASH'
      ? $self->merge( $merged{$key}, $wanted->{$key} )
      : $wanted->{$key};
  }
  return \%merged;
}

sub same {
  my ( $self, $have, $want ) = @_;
  return 1 if !defined $have && !defined $want;
  return 0 if !defined $have || !defined $want;
  my ( $have_bool, $want_bool ) = ( $self->_bool($have), $self->_bool($want) );
  return $have_bool eq $want_bool ? 1 : 0 if defined $have_bool && defined $want_bool
    && ( $self->_is_bool($have) || $self->_is_bool($want) );
  # authentik returns lists in its own order (property_mappings) and the order
  # never carries meaning, so every list is compared as a multiset
  if ( ref $have eq 'ARRAY' && ref $want eq 'ARRAY' ) {
    return 0 unless @$have == @$want;
    my @a = sort map { $JSON->encode($_) } @$have;
    my @b = sort map { $JSON->encode($_) } @$want;
    return $JSON->encode( \@a ) eq $JSON->encode( \@b ) ? 1 : 0;
  }
  return $JSON->encode($have) eq $JSON->encode($want) ? 1 : 0 if ref $have || ref $want;
  return "$have" eq "$want" ? 1 : 0;
}

sub _is_bool {
  my ( $self, $value ) = @_;
  return 1 if ref $value eq 'SCALAR' || ( blessed $value && $value->isa('JSON::PP::Boolean') );
  return 1 if JSON::MaybeXS::is_bool($value);
  return 1 if !ref $value && ( $value eq 'true' || $value eq 'false' );
  return 0;
}

sub _bool {
  my ( $self, $value ) = @_;
  return ${$value} ? 1 : 0 if ref $value eq 'SCALAR';
  return $value ? 1 : 0 if JSON::MaybeXS::is_bool($value);
  return if ref $value;
  return 1 if $value eq 'true' || $value eq '1';
  return 0 if $value eq 'false' || $value eq '0' || $value eq '';
  return;
}

1;
```

POD following `getty-perl-pod`: `=synopsis` with `changes`/`merge`, `=description` with the three
rules (only the named keys, lists as sets, defaults added by authentik),
`=method` for `changes`, `merge`, `same`, `with_defaults`, `list_defaults`.

- [ ] **Step 5: Run the test**

Run: `prove -lr t/10-diff.t` — Expected: PASS.

- [ ] **Step 6: Extend `t/00-load.t` and commit**

`t/00-load.t` from now on lists every built module; in this task `WWW::Authentik` and
`WWW::Authentik::Diff`.

Run: `prove -lr t` — Expected: PASS.
Commit: subject `Add WWW::Authentik::Diff and the dependencies`, body one line per file.

---

### Task 2: Errors, HTTP role and the emulated authentik

**Files:**
- Create: `lib/WWW/Authentik/Error.pm`, `lib/WWW/Authentik/Error/Validation.pm`, `lib/WWW/Authentik/Error/Network.pm`, `lib/WWW/Authentik/Error/API.pm`, `lib/WWW/Authentik/Role/HTTP.pm`, `t/lib/FakeAuthentik.pm`
- Test: `t/20-errors.t`
- Modify: `t/00-load.t`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `WWW::Authentik::Error->new( message => $m )`, `->throw( message => $m )`, stringifies to `message`.
  - `WWW::Authentik::Error::API->new( message =>, http_status =>, api_message =>, field_errors =>, oauth_error =>, request_id => )` with `is_not_found`, `is_forbidden`, `is_unauthorized`, `is_bad_request`.
  - Role `WWW::Authentik::Role::HTTP` with `json_codec`, `api_error_class`, `network_error_class`, `validation_error_class`, `build_request( $method, $url, %arg )`, `read_response( $response, $method, $url, %arg )`, `send_request( $method, $url, %arg )`. `%arg`: `bearer`, `json`, `form`, `basic` (ArrayRef `[ $user, $password ]`). Result of `read_response`/`send_request`: `{ status, data, location }`.
  - `FakeAuthentik->new( %opt )` is an `LWP::UserAgent` subclass; `->base` returns `http://ak.test`, `->token` the valid API token, `->requests` the list `[ $method, $path, $body ]`, `->writes` the number of writing calls, `->reset_writes`, `->rotate_key`, `->add( $collection, \%rep )`, `->collection($name)`.

- [ ] **Step 1: Write `t/lib/FakeAuthentik.pm`**

An `LWP::UserAgent` with an overridden `request` that answers like authentik 2026.8.3,
as spec section 8 records it. Scope:

*General*
- Without `Authorization` → `403 {"detail":"Authentication credentials were not provided."}`; with an unknown bearer → `403 {"detail":"Token invalid/expired"}`.
- Path without a trailing `/` under `/api/v3/` → 404.
- Every call is logged in `requests`; `PATCH`, `POST`, `PUT`, `DELETE` increment `writes`.
- Non-JSON body on `POST`/`PATCH` → `400 {"detail":"JSON parse error - Input data was truncated"}`.

*Collections*, each with a key field, a PK field and a PK form:

| Collection | Path | Key | PK field | PK form |
|---|---|---|---|---|
| `users` | `/api/v3/core/users/` | `username` | `pk` | integer, from 1 |
| `groups` | `/api/v3/core/groups/` | `name` | `pk` | UUID |
| `tokens` | `/api/v3/core/tokens/` | `identifier` | `pk` | UUID, path via `identifier` |
| `applications` | `/api/v3/core/applications/` | `slug` | `pk` | UUID, path via `slug` |
| `providers` | `/api/v3/providers/oauth2/` | `name` | `pk` | integer |
| `mappings` | `/api/v3/propertymappings/provider/scope/` | `name` | `pk` | UUID |
| `flows` | `/api/v3/flows/instances/` | `slug` | `pk` | UUID, path via `slug` |
| `stages` | `/api/v3/stages/<type>/` and `/api/v3/stages/all/` | `name` | `pk` | UUID, name unique across **all** types |
| `bindings` | `/api/v3/flows/bindings/` | `(target, stage, order)` | `pk` | UUID |
| `certificates` | `/api/v3/crypto/certificatekeypairs/` | `name` | `pk` | UUID |

Behavior per collection:
- `GET` list: `{"pagination":{...},"results":[...]}`, `page` and `page_size` respected, `next` is the next page number or `0`, `count`, `current`, `total_pages`, `start_index`, `end_index`. Exact equality filters over every query parameter that is a field; `?page=<too large>` → `404 {"detail":"Invalid page."}`.
- `POST`: `201` with the whole object, PK added, **no** `Location`. Duplicate key → `400 { "<key>": [ "… already exists." ] }`, for the user `["This field must be unique."]`. Missing required field → `400 { "<field>": ["This field is required."] }` (provider: `authorization_flow`, `invalidation_flow`, `name`, `redirect_uris`; application: `name`, `slug`).
- `GET`/`PATCH`/`DELETE` detail: `200`/`200`/`204`; unknown → `404 {"detail":"No <Model> matches the given query."}`; second `DELETE` → 404.
- `PATCH` replaces `attributes` as a whole, silently ignores read-only fields (`pk`, `uid`, `component`, `assigned_application_slug`, everything ending in `_obj`) and unknown fields.
- Provider: `client_id`/`client_secret` generated on creation, `grant_types` default `[]`, `redirect_uris` get `redirect_uri_type => 'authorization'`, `property_mappings` are reordered when returned (reversed is enough), invalid `grant_types` value → `400 {"grant_types":{"0":["\"x\" is not a valid choice."]}}`.
- Application: `provider` already assigned → `400 {"provider":["Application with this provider already exists."]}`.
- Binding: `(target, stage, order)` duplicate → `400 {"non_field_errors":["The fields target, stage, order must make a unique set."]}`.
- Stage: `not_configured_action => 'configure'` without `configuration_stages` → `400 {"not_configured_action":["When \"Not configured action\" is set to \"Configure\", you must set a configuration stage."]}`.
- `POST /api/v3/core/users/{pk}/set_password/` → `204`, remembers the password in `passwords`.
- `POST /api/v3/core/tokens/{id}/set_key/` → `204`; `GET …/view_key/` → `200 {"key": …}`.
- `GET /api/v3/admin/version/` → `200 {"version_current":"2026.8.3", …}`; `GET /api/v3/core/users/me/` → `200 {"user":{…}}`.
- `PATCH /api/v3/stages/all/{uuid}/` → `405 {"detail":"Method \"PATCH\" not allowed."}`.

*OIDC* under `/application/o/`:
- `GET /application/o/<slug>/.well-known/openid-configuration` → the document observed in spec 8.2 with `issuer` = `<base>/application/o/<slug>/`, all endpoints, `claims_supported` with `amr`, `acr`, `auth_time`; unknown slug → 404.
- `GET /application/o/<slug>/jwks/` → the public RSA key with `kid`.
- `POST /application/o/token/`: `client_credentials` (with `client_secret` or `username`/`password`), `refresh_token` (rotated, the old one invalid afterwards), `authorization_code` (single use), `urn:ietf:params:oauth:grant-type:device_code` (first `authorization_pending`, after `->approve_device($user_code)` the tokens). Wrong secret → `400 invalid_grant`, unknown client → `400 invalid_client`, unknown grant → `400 unsupported_grant_type`, subset of the scopes on refresh → `400 invalid_scope`. Every error response carries `request_id`.
- `GET`/`POST /application/o/userinfo/`: `200` with the claims, unknown token → `401` with an empty body and `WWW-Authenticate: error="invalid_token", error_description="…"`.
- `POST /application/o/introspect/`: `200 {"active":true, …}` or `200 {"active":false}` (also with a wrong secret).
- `POST /application/o/revoke/`: `200 {}`, also for garbage; wrong secret → `401 invalid_client`.
- `POST /application/o/device/` → `{device_code, user_code, verification_uri, verification_uri_complete, expires_in, interval}`.
- Signing uses a generated RSA key (`Crypt::PK::RSA`, 256 bytes); `->rotate_key` swaps it and assigns a new `kid`. `->sign( \%claims, %opt )` builds a token; `%opt` allows `alg => 'none'`, `key => 'hmac'`, `exp`, `iss`, `kid`, so that `t/60-oidc.t` can build the cases to be rejected.

- [ ] **Step 2: Write `t/20-errors.t`**

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeAuthentik;
use WWW::Authentik;

my $fake = FakeAuthentik->new;
my $ak   = WWW::Authentik->new( base_url => $fake->base, application => 'probe-app', token => $fake->token, ua => $fake );

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

subtest 'classes and stringification' => sub {
  my $e = WWW::Authentik::Error::API->new( message => 'boom', http_status => 400 );
  isa_ok( $e, 'WWW::Authentik::Error' );
  is( "$e", 'boom', 'stringifies to the message' );
  ok( $e->is_bad_request && !$e->is_not_found && !$e->is_forbidden && !$e->is_unauthorized, 'predicates' );
  isa_ok( WWW::Authentik::Error::Validation->new( message => 'x' ), 'WWW::Authentik::Error' );
  isa_ok( WWW::Authentik::Error::Network->new( message => 'x' ), 'WWW::Authentik::Error' );
  isa_ok( error_of { WWW::Authentik::Error::Validation->throw( message => 'thrown' ) }, 'WWW::Authentik::Error::Validation' );
};

subtest 'detail' => sub {
  my $missing = error_of { $ak->api->get_user(999999) };
  isa_ok( $missing, 'WWW::Authentik::Error::API' );
  is( $missing->http_status, 404, 'status as a number' );
  is( $missing->api_message, 'No User matches the given query.', 'detail' );
  ok( $missing->is_not_found, 'is_not_found' );
  is_deeply( $missing->field_errors, {}, 'no field errors' );
  like( "$missing", qr{GET \Qhttp://ak.test/api/v3/core/users/999999/\E failed: 404}, 'message names the request' );
};

subtest 'field errors' => sub {
  $ak->api->create_user( { username => 'alice', name => 'Alice' } );
  my $dup = error_of { $ak->api->create_user( { username => 'alice', name => 'Alice' } ) };
  is( $dup->http_status, 400, '400, not 409' );
  ok( $dup->is_bad_request, 'is_bad_request' );
  is_deeply( $dup->field_errors, { username => ['This field must be unique.'] }, 'field_errors' );
  is( $dup->api_message, 'username: This field must be unique.', 'api_message names the field' );

  my $nested = error_of { $ak->api->update_oauth2_provider( $provider_pk, { grant_types => ['banana'] } ) };
  is_deeply( $nested->field_errors, { 'grant_types.0' => ['"banana" is not a valid choice.'] }, 'nested field errors are flattened' );
};

subtest 'a refused token' => sub {
  my $wrong = WWW::Authentik->new( base_url => $fake->base, token => 'nope', ua => $fake );
  my $error = error_of { $wrong->api->me };
  ok( $error->is_forbidden, '403, not 401' );
  is( $error->api_message, 'Token invalid/expired', 'detail' );
  unlike( "$error", qr/nope/, 'the token is not in the message' );
};

subtest 'the OAuth shape' => sub {
  my $oauth = error_of { $ak->oidc->client_credentials_token( client_id => 'probe', client_secret => 'wrong' ) };
  is( $oauth->oauth_error, 'invalid_grant', 'oauth_error' );
  like( $oauth->api_message, qr/\Ainvalid_grant: /, 'with the description' );
  ok( $oauth->request_id, 'request_id' );
  unlike( "$oauth", qr/wrong/, 'the secret is not in the message' );
};

subtest 'userinfo answers with a header and no body' => sub {
  my $error = error_of { $ak->oidc->userinfo('garbage') };
  is( $error->http_status, 401, '401' );
  ok( $error->is_unauthorized, 'is_unauthorized' );
  is( $error->oauth_error, 'invalid_token', 'oauth_error from WWW-Authenticate' );
};

subtest 'no answer at all' => sub {
  my $down = WWW::Authentik->new( base_url => 'http://127.0.0.1:9', application => 'x', ua => LWP::UserAgent->new( timeout => 2 ) );
  my $error = error_of { $down->oidc->discovery };
  isa_ok( $error, 'WWW::Authentik::Error::Network' );
  like( "$error", qr{GET http://127.0.0.1:9/application/o/x/\.well-known/openid-configuration}, 'names the request' );
};

done_testing;
```

`$provider_pk` is created in the subtest `field errors` via `create_oauth2_provider` with the four
required fields; the line comes before the `my $nested`.

- [ ] **Step 3: Run the test, it must fail**

Run: `prove -lr t/20-errors.t` — Expected: FAIL, `WWW/Authentik/Error.pm` is missing.

- [ ] **Step 4: Write the error classes**

`lib/WWW/Authentik/Error.pm` like `WWW::Keycloak::Error`: Moo, `has message`, `overload '""'`,
`sub throw { my ( $class, %arg ) = @_; die $class->new(%arg) }`, **no** `namespace::autoclean`
(it would remove the overload stub).

`Error/Validation.pm` and `Error/Network.pm`: `use Moo; extends 'WWW::Authentik::Error';` and
`$VERSION`, nothing else.

`lib/WWW/Authentik/Error/API.pm`:

```perl
package WWW::Authentik::Error::API;

# ABSTRACT: Raised when authentik answers with an HTTP error

use Moo;
extends 'WWW::Authentik::Error';

our $VERSION = '0.001';

has http_status  => ( is => 'ro', required => 1 );
has api_message  => ( is => 'ro' );
has field_errors => ( is => 'ro', default => sub { {} } );
has oauth_error  => ( is => 'ro' );
has request_id   => ( is => 'ro' );

sub is_bad_request  { $_[0]->http_status == 400 ? 1 : 0 }
sub is_unauthorized { $_[0]->http_status == 401 ? 1 : 0 }
sub is_forbidden    { $_[0]->http_status == 403 ? 1 : 0 }
sub is_not_found    { $_[0]->http_status == 404 ? 1 : 0 }
```

POD: `=description` names the four error forms from spec 7 and why there is no `is_conflict`
(a duplicate is 400 like any validation error); `=attr` for every field,
`=method` for the four predicates.

- [ ] **Step 5: Write `lib/WWW/Authentik/Role/HTTP.pm`**

```perl
package WWW::Authentik::Role::HTTP;

# ABSTRACT: Sending requests to authentik and turning failures into exceptions

use HTTP::Request;
use JSON::MaybeXS;
use MIME::Base64 qw( encode_base64 );
use URI;
use WWW::Authentik::Error::API;
use WWW::Authentik::Error::Network;
use WWW::Authentik::Error::Validation;
use Moo::Role;

our $VERSION = '0.001';

sub json_codec { JSON::MaybeXS->new( utf8 => 1, canonical => 1, convert_blessed => 1 ) }

sub api_error_class        { 'WWW::Authentik::Error::API' }
sub network_error_class    { 'WWW::Authentik::Error::Network' }
sub validation_error_class { 'WWW::Authentik::Error::Validation' }

sub build_request {
  my ( $self, $method, $url, %arg ) = @_;
  my $request = HTTP::Request->new( $method => $url );
  $request->header( Accept => 'application/json' );
  $request->header( Authorization => 'Bearer '.$arg{bearer} ) if defined $arg{bearer};
  $request->header( Authorization => 'Basic '.encode_base64( $arg{basic}[0].':'.$arg{basic}[1], '' ) ) if $arg{basic};
  if ( exists $arg{json} ) {
    $request->header( 'Content-Type' => 'application/json' );
    $request->content( $self->json_codec->encode( $arg{json} ) );
  }
  elsif ( $arg{form} ) {
    my $uri = URI->new('http:');
    $uri->query_form( map { $_ => $arg{form}{$_} } grep { defined $arg{form}{$_} } sort keys %{ $arg{form} } );
    $request->header( 'Content-Type' => 'application/x-www-form-urlencoded' );
    $request->content( $uri->query // '' );
  }
  return $request;
}

sub read_response {
  my ( $self, $response, $method, $url, %arg ) = @_;
  my $content = $response->decoded_content // '';
  my $data    = length $content ? eval { $self->json_codec->decode( $response->content ) } : undef;
  # authentik answers 302 on /application/o/authorize/ and in the flow executor;
  # that is an answer, not a failure
  return { status => $response->code, data => $data, location => scalar $response->header('Location') }
    if $response->code < 400;
  my ( $message, $oauth, $request_id, %fields );
  if ( ref $data eq 'HASH' ) {
    $request_id = $data->{request_id};
    if ( defined $data->{detail} ) {
      $message = $data->{detail};
    }
    elsif ( defined $data->{error} && !ref $data->{error} ) {
      $oauth   = $data->{error};
      $message = $data->{error}.( defined $data->{error_description} ? ': '.$data->{error_description} : '' );
    }
    else {
      %fields  = %{ $self->_flatten_fields($data) };
      $message = join '; ', map { $_.': '.join ', ', @{ $fields{$_} } } sort keys %fields;
    }
  }
  if ( !defined $message && ( my $challenge = $response->header('WWW-Authenticate') ) ) {
    ( $oauth )   = $challenge =~ /error="([^"]+)"/;
    ( $message ) = $challenge =~ /error_description="([^"]+)"/;
    $message = $oauth if !defined $message && defined $oauth;
  }
  $self->api_error_class->throw(
    message      => $method.' '.$url.' failed: '.$response->status_line.( defined $message && length $message ? ' - '.$message : '' ),
    http_status  => $response->code,
    api_message  => $message,
    field_errors => \%fields,
    oauth_error  => $oauth,
    request_id   => $request_id
  );
}

sub _flatten_fields {
  my ( $self, $data, $prefix ) = @_;
  my %flat;
  for my $key ( keys %$data ) {
    my $name  = defined $prefix ? $prefix.'.'.$key : $key;
    my $value = $data->{$key};
    if ( ref $value eq 'HASH' ) { %flat = ( %flat, %{ $self->_flatten_fields( $value, $name ) } ) }
    elsif ( ref $value eq 'ARRAY' ) { $flat{$name} = [ map { ref $_ ? $self->json_codec->encode($_) : $_ } @$value ] }
    else { $flat{$name} = [ defined $value ? $value : '' ] }
  }
  return \%flat;
}

sub send_request {
  my ( $self, $method, $url, %arg ) = @_;
  my $response = $self->ua->request( $self->build_request( $method, $url, %arg ) );
  $self->network_error_class->throw( message => $method.' '.$url.': '.$response->status_line )
    if $response->code == 500 && ( $response->header('Client-Warning') // '' ) eq 'Internal response';
  return $self->read_response( $response, $method, $url, %arg );
}

1;
```

POD: `=description` says that `build_request` and `read_response` are separate from sending,
so that `Net::Async::Authentik` can reuse them, and that a response below 400 counts
as success, because authentik answers with 302 where it redirects. `=method` for every method.
The bearer token appears in no error message — the message names only method and URL.

- [ ] **Step 6: Run the test**

Run: `prove -lr t/20-errors.t` — Expected: PASS. (The subtest `field errors` needs
`create_user` and `create_oauth2_provider` from task 4; until then it is written with
raw `$fake` calls via `$ak->api->call` and switched to the methods
in task 4.)

- [ ] **Step 7: Extend `t/00-load.t`, commit**

Run: `prove -lr t` — Expected: PASS.
Commit: subject `Add the error classes, the HTTP role and the fake authentik`.

---

### Task 3: OIDC and the facade

**Files:**
- Create: `lib/WWW/Authentik/OIDC.pm`
- Modify: `lib/WWW/Authentik.pm` (replace the stub)
- Test: `t/40-facade.t`, `t/60-oidc.t`
- Modify: `t/00-load.t`

**Interfaces:**
- Consumes: `WWW::Authentik::Role::HTTP`, the error classes, `FakeAuthentik`.
- Produces:
  - `WWW::Authentik->new( base_url =>, application =>, token =>, ua => )` with `->oidc`, `->api`, `->issuer`, `->application_url`, `->api_url`, `->for_application($slug)`.
  - `WWW::Authentik::OIDC->new( application_url =>, ua =>, algorithms =>, jwks_min_age =>, now => )` with the methods of the table below.

- [ ] **Step 1: Write `t/40-facade.t`**

- `base_url` missing or empty → `WWW::Authentik::Error::Validation` on construction.
- A trailing `/` on `base_url` is removed.
- `issuer` is `<base_url>/application/o/<slug>/`, `application_url` without a trailing `/`, `api_url` is `<base_url>/api/v3`.
- A slug is URI-encoded (`for_application('a b')`).
- `oidc` without `application` → validation error, with it → `WWW::Authentik::OIDC`.
- `api` without `token` → validation error, with it → `WWW::Authentik::API`.
- `for_application('other')` returns a new facade with the same `ua` object (`is( $a->ua, $b->ua )`) and the same token, but a different slug.
- The default `ua` follows no redirects: `is( WWW::Authentik->new( base_url => 'http://x' )->ua->max_redirect, 0 )`.
- `ua` is injectable and shared by `oidc` and `api`.

- [ ] **Step 2: Write `t/60-oidc.t`**

Subtest `discovery and endpoints`: `discovery` fetches once and remembers (a second call
sends no second request, checked via `$fake->requests`); `issuer` comes from the
document; `token_endpoint`, `userinfo_endpoint`, `introspection_endpoint`,
`revocation_endpoint`, `end_session_endpoint`, `device_endpoint`, `authorization_endpoint`,
`jwks_uri`; a missing name → validation error that names it.

Subtest `verify_token`:
- a freshly signed token is accepted, the claims come back;
- wrong `iss` → rejected; expired → rejected; `alg: none` → rejected; HMAC (`HS256`) → rejected; foreign RSA key → rejected; each time `WWW::Authentik::Error::Validation` with a message that names the reason;
- `audience => 'other'` → rejected, `audience => <client_id>` → accepted;
- `type => 'access'` accepts a token with `scope` and rejects one without; `type => 'id'` the other way round; without `type` nothing is checked;
- `verify_token(undef)` and `verify_token('')` → validation error.

Subtest `key rotation`: after `$fake->rotate_key` a token signed with the new key
is accepted (JWKS are reloaded exactly once); a second token with an unknown
`kid` within `jwks_min_age` triggers **no** further JWKS request (counted via
`$fake->requests`); with the clock moved forward (`now`) afterwards it does.

Subtest `the token endpoint`: `client_credentials_token` with secret and with
`username`/`password`; `exchange_authorization_code`; `refresh_token` (new refresh token,
the old one `invalid_grant` afterwards); `device_authorization` (`verification_uri_complete` contains
the `user_code`); `device_token` before confirmation throws with
`oauth_error eq 'authorization_pending'`, after `$fake->approve_device` it returns tokens;
`userinfo`; `introspect` (`active`); `revoke` (afterwards `introspect` `active` false); a
missing `client_id` → validation error.

Subtest `authorization_url`: contains `response_type=code`, the `client_id`, the encoded
`redirect_uri`, `scope`, `state`, `nonce`; additional parameters are appended; the URL
points to `authorization_endpoint`.

- [ ] **Step 3: Run the tests, they must fail**

Run: `prove -lr t/40-facade.t t/60-oidc.t` — Expected: FAIL.

- [ ] **Step 4: Write `lib/WWW/Authentik/OIDC.pm`**

Attributes: `application_url` (Str, required), `ua` (InstanceOf LWP::UserAgent, required),
`algorithms` (ArrayRef[Str], default `RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512`),
`jwks_min_age` (Int, 60), `now` (CodeRef, `sub { time }`), `discovery` (lazy, `init_arg undef`),
`_jwks`, `_jwks_fetched` (rw, `init_arg undef`).

```perl
sub _build_discovery {
  my ( $self ) = @_;
  my $data = $self->send_request( GET => $self->application_url.'/.well-known/openid-configuration' )->{data};
  WWW::Authentik::Error::Validation->throw( message => 'discovery for '.$self->application_url.' returned no JSON object' )
    unless ref $data eq 'HASH';
  return $data;
}

sub endpoint {
  my ( $self, $name ) = @_;
  my $url = $self->discovery->{$name};
  WWW::Authentik::Error::Validation->throw( message => 'the discovery document of '.$self->application_url.' has no '.$name )
    unless defined $url;
  return $url;
}

sub issuer                  { $_[0]->endpoint('issuer') }
sub authorization_endpoint  { $_[0]->endpoint('authorization_endpoint') }
sub token_endpoint          { $_[0]->endpoint('token_endpoint') }
sub userinfo_endpoint       { $_[0]->endpoint('userinfo_endpoint') }
sub introspection_endpoint  { $_[0]->endpoint('introspection_endpoint') }
sub revocation_endpoint     { $_[0]->endpoint('revocation_endpoint') }
sub end_session_endpoint    { $_[0]->endpoint('end_session_endpoint') }
sub device_endpoint         { $_[0]->endpoint('device_authorization_endpoint') }
sub jwks_uri                { $_[0]->endpoint('jwks_uri') }
```

`jwks( force_refresh => 1 )` as with Keycloak.

```perl
sub verify_token {
  my ( $self, $token, %opt ) = @_;
  WWW::Authentik::Error::Validation->throw( message => 'verify_token needs a token' ) unless defined $token && length $token;
  my %check = (
    token          => $token,
    verify_iss     => $self->issuer,
    verify_exp     => 1,
    accepted_alg   => $self->algorithms,
    decode_payload => 1,
    defined $opt{audience} ? ( verify_aud => $opt{audience} ) : ()
  );
  my $claims = eval { decode_jwt( %check, kid_keys => $self->jwks ) };
  my $error  = $@;
  # a key authentik rotated in since the keys were fetched: fetch them again,
  # but only for that reason and not more often than jwks_min_age allows
  if ( !$claims && $error =~ /kid_keys lookup failed/ && $self->now->() - ( $self->_jwks_fetched // 0 ) >= $self->jwks_min_age ) {
    $claims = eval { decode_jwt( %check, kid_keys => $self->jwks( force_refresh => 1 ) ) };
    $error  = $@;
  }
  $self->_reject( $error =~ s/ at \S+ line \d+.*//sr ) unless $claims;
  if ( defined $opt{type} ) {
    # authentik puts no typ into the header; the access token is the one that
    # carries scope. A heuristic, named as one in the POD.
    my $is_access = exists $claims->{scope} ? 1 : 0;
    $self->_reject( 'not an access token (no scope claim)' ) if $opt{type} eq 'access' && !$is_access;
    $self->_reject( 'not an ID token (it has a scope claim)' ) if $opt{type} eq 'id' && $is_access;
    WWW::Authentik::Error::Validation->throw( message => "verify_token: type must be 'access' or 'id'" )
      unless $opt{type} eq 'access' || $opt{type} eq 'id';
  }
  return $claims;
}
```

The `=method verify_token` POD says literally that `type` is a **heuristic**: authentik
sets no `typ` in the header, both token kinds are `RS256` JWTs, and they are told apart
by the claim `scope` (spec 6.1). Without `type` the token kind is not checked.

Token endpoint:

```perl
sub client_credentials_token { my ( $self, %arg ) = @_; $self->_grant( client_credentials => [qw( scope username password )], %arg ) }
sub refresh_token            { my ( $self, $refresh, %arg ) = @_; $self->_grant( refresh_token => [qw( refresh_token scope )], %arg, refresh_token => $refresh ) }
sub exchange_authorization_code { my ( $self, %arg ) = @_; $self->_grant( authorization_code => [qw( code redirect_uri code_verifier )], %arg ) }
sub device_token             { my ( $self, %arg ) = @_; $self->_grant( 'urn:ietf:params:oauth:grant-type:device_code' => ['device_code'], %arg ) }

sub _grant {
  my ( $self, $type, $fields, %arg ) = @_;
  return $self->_token_call( $self->token_endpoint,
    { grant_type => $type, map { $_ => $arg{$_} } grep { defined $arg{$_} } @$fields }, %arg );
}

sub _token_call {
  my ( $self, $url, $form, %arg ) = @_;
  WWW::Authentik::Error::Validation->throw( message => 'a client_id is needed' ) unless defined $arg{client_id};
  my %form = ( %$form, client_id => $arg{client_id}, defined $arg{client_secret} ? ( client_secret => $arg{client_secret} ) : () );
  return $self->send_request( POST => $url, form => \%form )->{data} // {};
}
```

`userinfo($access_token)` is `GET` on `userinfo_endpoint` with bearer.
`introspect($token, %client)` and `revoke($token, %client)` go to their endpoints with
`token` (and `token_type_hint`, if given); `revoke` returns 1.
`device_authorization( client_id =>, scope => )` calls `_token_call` on `device_endpoint`.

```perl
sub authorization_url {
  my ( $self, %arg ) = @_;
  WWW::Authentik::Error::Validation->throw( message => 'a client_id is needed' ) unless defined $arg{client_id};
  WWW::Authentik::Error::Validation->throw( message => 'a redirect_uri is needed' ) unless defined $arg{redirect_uri};
  my $uri = URI->new( $self->authorization_endpoint );
  $uri->query_form(
    response_type => $arg{response_type} // 'code',
    ( map { $_ => $arg{$_} } grep { defined $arg{$_} } qw( client_id redirect_uri scope state nonce code_challenge code_challenge_method prompt max_age acr_values ) )
  );
  return $uri->as_string;
}
```

- [ ] **Step 5: Replace `lib/WWW/Authentik.pm`**

```perl
package WWW::Authentik;

# ABSTRACT: Perl client for the authentik identity provider (OIDC + REST API v3)

use Moo;
use LWP::UserAgent;
use Types::Standard qw( InstanceOf Str );
use URI::Escape qw( uri_escape_utf8 );
use WWW::Authentik::API;
use WWW::Authentik::Error;
use WWW::Authentik::Error::API;
use WWW::Authentik::Error::Network;
use WWW::Authentik::Error::Validation;
use WWW::Authentik::OIDC;
use namespace::autoclean;

our $VERSION = '0.001';

has base_url    => ( is => 'ro', isa => Str, required => 1 );
has application => ( is => 'ro', isa => Str, predicate => 'has_application' );
has token       => ( is => 'ro', isa => Str, predicate => 'has_token' );

has ua => ( is => 'lazy', isa => InstanceOf['LWP::UserAgent'] );

sub _build_ua {
  # no redirects: authentik answers 302 where it wants a browser, and none of
  # those may carry the API token anywhere
  return LWP::UserAgent->new( timeout => 30, agent => 'WWW-Authentik/'.$VERSION,
    max_redirect => 0, ssl_opts => { verify_hostname => 1 } );
}

has oidc => ( is => 'lazy', init_arg => undef );
has api  => ( is => 'lazy', init_arg => undef );

sub _build_oidc {
  my ( $self ) = @_;
  WWW::Authentik::Error::Validation->throw( message => __PACKAGE__.'->oidc needs an application slug' )
    unless $self->has_application && length $self->application;
  return WWW::Authentik::OIDC->new( application_url => $self->application_url, ua => $self->ua );
}

sub _build_api {
  my ( $self ) = @_;
  WWW::Authentik::Error::Validation->throw( message => __PACKAGE__.'->api needs an API token' )
    unless $self->has_token && length $self->token;
  return WWW::Authentik::API->new( base_url => $self->base_url, token => $self->token, ua => $self->ua );
}

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

sub api_url          { $_[0]->base_url.'/api/v3' }
sub application_url  { $_[0]->base_url.'/application/o/'.uri_escape_utf8( $_[0]->application ) }
sub issuer           { $_[0]->application_url.'/' }

sub for_application {
  my ( $self, $slug ) = @_;
  return ref($self)->new(
    base_url    => $self->base_url,
    application => $slug,
    ua          => $self->ua,
    $self->has_token ? ( token => $self->token ) : ()
  );
}

1;
```

POD: `=synopsis` with both sides; `=description` states that there is no realm, that
the API is instance-wide and OIDC per application, that the API token is long-lived and
is not renewed — **and** the difference for people switching from `WWW::Keycloak`:
`ensure_*` returns `{ object, changed }` instead of `{ id, changed }`, and `create_*`/`update_*`
return the representation instead of an ID, because authentik has no uniform identifier
(slug, integer PK, UUID, identifier) and returns the whole object on creation.
`=attr`/`=method` for every attribute and every method; `issuer` says that it is the
address form (`issuer_mode: per_provider`) and that `WWW::Authentik::OIDC->issuer` is the
authoritative value from the discovery document.

- [ ] **Step 6: Run the tests, extend `t/00-load.t`, commit**

Run: `prove -lr t` — Expected: PASS.
Commit: subject `Add the OIDC client and the facade`.

---

### Task 4: `WWW::Authentik::API` — transport, pagination, basic operations

**Files:**
- Create: `lib/WWW/Authentik/API.pm`
- Test: `t/50-api.t`
- Modify: `t/00-load.t`, `t/20-errors.t` (switch raw calls to the methods)

**Interfaces:**
- Consumes: `WWW::Authentik::Role::HTTP`, the error classes.
- Produces: `WWW::Authentik::API->new( base_url =>, token =>, ua => )` with
  `call( $method, $path, \%body )` → `{ status, data, location }`,
  `_paged( $path, %query )` → ArrayRef of all matches, and the methods of the table.
  `diff_class` → `'WWW::Authentik::Diff'`.

- [ ] **Step 1: Write `t/50-api.t`**

Subtest `transport`:
- `call( GET => '/core/users/' )` builds `http://ak.test/api/v3/core/users/` and sends the bearer;
- a path without a leading `/` gets one, a missing trailing `/` is **not** added (the methods set it; a raw call gets what it ordered, and authentik then answers 404 — the test checks exactly that);
- without a token `WWW::Authentik->new(...)->api` already throws (task 3).

Subtest `pagination`:
- 25 users in the fake, `page_size => 10` → `list_users` returns 25 in one call by the caller and three HTTP requests;
- `pagination.next` equal to 0 ends; an empty list yields `[]`;
- **a broken response whose `next` points to a page already fetched stops instead of looping forever** (`$fake->break_pagination` makes `next` always point to 1; expected: at most as many requests as `total_pages`, then return).

Subtest `users`: `create_user`, `find_user` (exact, case-sensitive: `Probe-Bob`
does not find `probe-bob`), `get_user`, `update_user` (PATCH, `attributes` replaced),
`set_password`, `delete_user`, `delete_user` a second time throws `is_not_found`,
`create_service_account` returns `token`.

Subtest `applications and providers`: `create_oauth2_provider` without required fields throws with
`field_errors` for all four; fully created, `client_id`, `client_secret`,
`grant_types => []` come back; `find_oauth2_provider` by name; `create_application` with
`provider`; `find_application` by slug; a second provider on the same application
throws; `provider_setup_urls`.

Subtest `the rest`: one `create`/`find`/`update`/`delete` pass each for groups,
scope mappings, flows, stages (`password`), bindings, tokens (with `view_token_key` and
`set_token_key`); `list_stages` reads via `/stages/all/`, `update_stage` via the
typed path; `update_stage( all => ... )` is a validation error, because `/stages/all/`
can only read.

Subtest `instance`: `version`, `config`, `settings`, `me`.

- [ ] **Step 2: Run the test, it must fail**

Run: `prove -lr t/50-api.t` — Expected: FAIL, `WWW/Authentik/API.pm` is missing.

- [ ] **Step 3: Write the transport part**

```perl
package WWW::Authentik::API;

# ABSTRACT: authentik REST API v3 with idempotent ensure methods

use Moo;
with 'WWW::Authentik::Role::HTTP';
use Scalar::Util qw( blessed );
use Types::Standard qw( InstanceOf Str );
use URI::Escape qw( uri_escape_utf8 );
use WWW::Authentik::Diff;
use WWW::Authentik::Error;
use WWW::Authentik::Error::Validation;
use namespace::autoclean;

our $VERSION = '0.001';

has base_url => ( is => 'ro', isa => Str, required => 1 );
has token    => ( is => 'ro', isa => Str, required => 1 );
has ua       => ( is => 'ro', isa => InstanceOf['LWP::UserAgent'], required => 1 );

has page_size => ( is => 'ro', default => 100 );

sub diff_class { 'WWW::Authentik::Diff' }

sub api_url { $_[0]->base_url.'/api/v3' }

sub call {
  my ( $self, $method, $path, $body ) = @_;
  $path = '/'.$path unless $path =~ m{\A/};
  my %arg = defined $body ? ( json => $body ) : ();
  return $self->send_request( $method, $self->api_url.$path, %arg, bearer => $self->token );
}

sub _data { $_[0]->call( @_[ 1 .. $#_ ] )->{data} }
sub _done { $_[0]->call( @_[ 1 .. $#_ ] ); 1 }
sub _esc  { uri_escape_utf8( $_[1] ) }

sub _query {
  my ( $self, %query ) = @_;
  return '' unless %query;
  return '?'.join '&', map { $self->_esc($_).'='.$self->_esc( $query{$_} ) }
    grep { defined $query{$_} } sort keys %query;
}

sub _paged {
  my ( $self, $path, %query ) = @_;
  my $page_size = delete $query{page_size} // $self->page_size;
  my ( @all, %seen );
  my $page = 1;
  while ( defined $page && $page > 0 && !$seen{$page}++ ) {
    my $data = $self->_data( GET => $path.$self->_query( %query, page => $page, page_size => $page_size ) );
    last unless ref $data eq 'HASH';
    push @all, @{ $data->{results} || [] };
    $page = $data->{pagination} ? $data->{pagination}{next} : 0;
  }
  return \@all;
}

sub _missing {
  my ( $self, $error ) = @_;
  return 1 if blessed $error && $error->isa('WWW::Authentik::Error::API') && $error->is_not_found;
  die $error;
}

sub _find_one {
  my ( $self, $list, $key, $value ) = @_;
  my ( $found ) = grep { defined $_->{$key} && $_->{$key} eq $value } @$list;
  return $found;
}
```

`%seen` is the stop against a response whose `next` points back (Review Focus 4).

- [ ] **Step 4: Write the basic operations**

Each row is a one-liner or a short block following the same pattern. Paths and
behavior from spec 5.1 and 8.1.

| Method | Call |
|---|---|
| `version` | `GET /admin/version/` |
| `config` | `GET /root/config/` |
| `settings` | `GET /admin/settings/` |
| `me` | `GET /core/users/me/` |
| `list_users(%q)` | `_paged('/core/users/', %q)` |
| `find_user($username)` | `_find_one( list_users( username => $u ), 'username', $u )` |
| `get_user($pk)` | `GET /core/users/{pk}/` |
| `create_user(\%rep)` | `POST /core/users/` → object |
| `update_user($pk, \%c)` | `PATCH /core/users/{pk}/` → object |
| `delete_user($pk)` | `DELETE /core/users/{pk}/` → 1 |
| `set_password($pk, $pw)` | `POST /core/users/{pk}/set_password/` `{password}` → 1 |
| `create_service_account(name =>, %opt)` | `POST /core/users/service_account/` → object with `token` |
| `list_authenticators($pk)` | `GET /authenticators/admin/all/?user={pk}` (returns a bare list, no pagination) |
| `list_groups`, `find_group($name)`, `get_group($uuid)`, `create_group`, `update_group`, `delete_group` | `/core/groups/` |
| `add_user_to_group($uuid, $pk)`, `remove_user_from_group($uuid, $pk)` | `POST …/add_user/`, `…/remove_user/` `{pk}` → 1 |
| `list_tokens`, `get_token($id)`, `create_token`, `update_token`, `delete_token` | `/core/tokens/`, detail path via `identifier` |
| `view_token_key($id)` | `GET /core/tokens/{id}/view_key/` → `{key}` |
| `set_token_key($id, $key)` | `POST /core/tokens/{id}/set_key/` → 1 |
| `list_applications`, `find_application($slug)`, `create_application`, `update_application($slug, \%c)`, `delete_application($slug)` | `/core/applications/`, detail path via `slug`; `find_application` catches the 404 via `_missing` |
| `check_access($slug, %opt)` | `GET /core/applications/{slug}/check_access/` |
| `list_oauth2_providers`, `find_oauth2_provider($name)`, `get_oauth2_provider($pk)`, `create_oauth2_provider`, `update_oauth2_provider`, `delete_oauth2_provider` | `/providers/oauth2/` |
| `provider_setup_urls($pk)` | `GET /providers/oauth2/{pk}/setup_urls/` |
| `preview_user($pk, $user_pk)` | `GET /providers/oauth2/{pk}/preview_user/?for_user={user_pk}` |
| `list_scope_mappings`, `find_scope_mapping($name)`, `create_scope_mapping`, `update_scope_mapping`, `delete_scope_mapping` | `/propertymappings/provider/scope/` |
| `find_scope_mappings_by_scope(@names)` | one list per name via `?scope_name=`, order of the names kept; a name without a match → validation error that names it |
| `test_property_mapping($uuid, %arg)` | `POST /propertymappings/all/{uuid}/test/` |
| `list_flows`, `find_flow($slug)`, `create_flow`, `update_flow($slug, \%c)`, `delete_flow($slug)` | `/flows/instances/`, detail path via `slug` |
| `export_flow($slug)` | `GET /flows/instances/{slug}/export/`; the response is YAML, not JSON — the raw body is returned as a string |
| `stage_types` | `GET /stages/all/types/` |
| `list_stages(%q)` | `_paged('/stages/all/', %q)` |
| `find_stage($name)` | via `list_stages`, `name` is unique across all types |
| `get_stage($type, $uuid)`, `create_stage($type, \%rep)`, `update_stage($type, $uuid, \%c)`, `delete_stage($type, $uuid)` | `/stages/{type}/…`; `$type` equal to `all` → validation error ("/stages/all/ can only be read") |
| `list_bindings(%q)`, `create_binding`, `update_binding($uuid, \%c)`, `delete_binding($uuid)` | `/flows/bindings/`; `list_bindings( target => $uuid )` |
| `list_brands`, `current_brand`, `update_brand($uuid, \%c)` | `/core/brands/`, `/core/brands/current/` |
| `list_certificates`, `find_certificate($name)` | `/crypto/certificatekeypairs/` |
| `list_blueprints`, `get_blueprint($uuid)`, `create_blueprint`, `apply_blueprint($uuid)`, `delete_blueprint($uuid)` | `/managed/blueprints/` |

`export_flow` needs its own way around the JSON decoder: `send_request` returns
`data => undef`, because the response is YAML. The method fetches the raw body via its
own `build_request`/`$self->ua->request` call and returns `$response->decoded_content`;
at status 400 and above it goes through `read_response`, so the error has the same form.

Every method gets its `=method` POD with a call line and what it returns.

- [ ] **Step 5: Run the tests, switch `t/20-errors.t`**

Run: `prove -lr t` — Expected: PASS.

- [ ] **Step 6: Extend `t/00-load.t`, commit**

Commit: subject `Add the API v3 client with the basic operations`.

---

### Task 5: Name resolution and `ensure_*`

**Files:**
- Modify: `lib/WWW/Authentik/API.pm` (append the sections `resolve` and `ensure`)
- Test: `t/51-api-ensure.t`, `t/52-api-resolve.t`

**Interfaces:**
- Consumes: everything from task 4, `WWW::Authentik::Diff`.
- Produces: `resolvable_fields` → HashRef; `resolve( \%rep )` → new hash with resolved
  fields; `ensure_application`, `ensure_oauth2_provider`, `ensure_scope_mapping`,
  `ensure_user`, `ensure_group`, `ensure_token`, `ensure_flow`, `ensure_stage($type, %rep)`,
  `ensure_binding(%arg)`, each returns `{ object => \%rep, changed => 'created'|'updated'|'' }`.

- [ ] **Step 1: Write `t/52-api-resolve.t`**

```perl
subtest 'looks like an identifier' => sub {
  $api->create_oauth2_provider( { name => '123', authorization_flow => $flow, invalidation_flow => $flow,
    redirect_uris => [ { matching_mode => 'strict', url => 'http://127.0.0.1:1/cb' } ] } );   # pk 1
  $api->create_oauth2_provider( { name => 'real', ... } );                                     # pk 123 im Fake erzwungen

  is( $api->resolve( { provider => '123' } )->{provider}, '123', 'an integer is the pk, never a name' );
  is( $api->resolve( { provider_name => '123' } )->{provider}, 1, 'the _name form always looks the name up' );
  is( $api->resolve( { provider => 'real' } )->{provider}, 123, 'anything that is not an integer is a name' );
  my $both = error_of { $api->resolve( { provider => 1, provider_name => 'real' } ) };
  isa_ok( $both, 'WWW::Authentik::Error::Validation' );
  like( "$both", qr/provider and provider_name/, 'both at once is refused' );
  my $gone = error_of { $api->resolve( { provider_name => 'nope' } ) };
  like( "$gone", qr/no oauth2 provider named "nope"/, 'a name without a match names the field and the value' );
};

subtest 'uuid fields' => sub {
  # a flow whose slug has the shape of a UUID
  my $slugged = $api->create_flow( { name => 'x', slug => '11111111-2222-3333-4444-555555555555',
    title => 'x', designation => 'authentication' } );
  is( $api->resolve( { authorization_flow => '11111111-2222-3333-4444-555555555555' } )->{authorization_flow},
      '11111111-2222-3333-4444-555555555555', 'a UUID shape is the pk' );
  is( $api->resolve( { authorization_flow_slug => '11111111-2222-3333-4444-555555555555' } )->{authorization_flow},
      $slugged->{pk}, 'the _slug form looks the slug up even when it looks like a UUID' );
  is( $api->resolve( { authorization_flow => 'default-authentication-flow' } )->{authorization_flow},
      $default_flow_pk, 'anything else is a slug' );
};

subtest 'lists and scopes' => sub {
  is_deeply( $api->resolve( { groups => [ $uuid, 'probe-group' ] } )->{groups}, [ $uuid, $group_pk ], 'mixed list' );
  is_deeply( $api->resolve( { group_names => ['probe-group'] } )->{groups}, [ $group_pk ], 'the forced form' );
  is_deeply( $api->resolve( { scopes => [qw( openid email )] } )->{property_mappings}, [ $openid_pk, $email_pk ], 'scopes become property_mappings' );
  my $clash = error_of { $api->resolve( { scopes => ['openid'], property_mappings => [$uuid] } ) };
  like( "$clash", qr/scopes and property_mappings/, 'scopes together with property_mappings is refused' );
};
```

- [ ] **Step 2: Write `t/51-api-ensure.t`**

For every `ensure_*` method:
- first run `created`, `object` carries the identifier;
- second run with the same arguments: `changed` empty **and `$fake->writes` unchanged** (the count is the actual test, Review Focus 2);
- a changed key: `updated`, exactly one writing call, the fields not named stay.

In detail:
- `ensure_user`: `attributes` are merged, not replaced; **`password` is only set on creation** — the second run with the same `password` does not call `set_password` (`$fake->requests` contains exactly one `set_password`); `groups` as a list of names.
- `ensure_oauth2_provider`: `scopes` instead of `property_mappings`; the list reordered by authentik yields nothing on the second run; `redirect_uris` without `redirect_uri_type` yield nothing on the second run; **without `grant_types` on creation a validation error** that says why; with an existing provider `grant_types` is not needed.
- `ensure_application`: `provider_name`; a slug that already exists with a different name is updated, not created again.
- `ensure_token`: `expires` as an argument is a validation error (authentik ignores it, spec 5.2); `expiring => \0` works.
- `ensure_stage`: `not_configured_action` and `configuration_stages` come in **one** PATCH (checked via `$fake->requests`).
- `ensure_binding`: `flow` and `stage` as slug and name; a second run with the same `order` changes nothing; a different `order` updates the existing binding instead of creating a second one.
- `ensure_*` deletes nothing: a field that the current state has and the wanted one does not, stays.

- [ ] **Step 3: Run the tests, they must fail**

Run: `prove -lr t/51-api-ensure.t t/52-api-resolve.t` — Expected: FAIL.

- [ ] **Step 4: Write the section `resolve`**

```perl
####  resolve

my $UUID    = qr{\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z};
my $INTEGER = qr{\A[0-9]+\z};

sub resolvable_fields {
  return {
    provider            => { force => 'provider_name',            raw => $INTEGER, find => 'find_oauth2_provider', what => 'oauth2 provider' },
    authorization_flow  => { force => 'authorization_flow_slug',  raw => $UUID,    find => 'find_flow',            what => 'flow' },
    invalidation_flow   => { force => 'invalidation_flow_slug',   raw => $UUID,    find => 'find_flow',            what => 'flow' },
    authentication_flow => { force => 'authentication_flow_slug', raw => $UUID,    find => 'find_flow',            what => 'flow' },
    configure_flow      => { force => 'configure_flow_slug',      raw => $UUID,    find => 'find_flow',            what => 'flow' },
    signing_key         => { force => 'signing_key_name',         raw => $UUID,    find => 'find_certificate',     what => 'certificate' },
    encryption_key      => { force => 'encryption_key_name',      raw => $UUID,    find => 'find_certificate',     what => 'certificate' },
    user                => { force => 'user_name',                raw => $INTEGER, find => 'find_user',            what => 'user' },
    groups              => { force => 'group_names',              raw => $UUID,    find => 'find_group',           what => 'group', list => 1 },
    property_mappings   => { force => 'property_mapping_names',   raw => $UUID,    find => 'find_scope_mapping',   what => 'scope mapping', list => 1 }
  };
}

sub resolve {
  my ( $self, $rep ) = @_;
  my %out    = %$rep;
  my $fields = $self->resolvable_fields;
  if ( exists $out{scopes} ) {
    WWW::Authentik::Error::Validation->throw( message => 'give either scopes or property_mappings, not both' )
      if exists $out{property_mappings} || exists $out{property_mapping_names};
    $out{property_mappings} = [ map { $_->{pk} } @{ $self->find_scope_mappings_by_scope( @{ delete $out{scopes} } ) } ];
  }
  for my $field ( sort keys %$fields ) {
    my $spec = $fields->{$field};
    my $forced = exists $out{ $spec->{force} };
    WWW::Authentik::Error::Validation->throw( message => 'give either '.$field.' or '.$spec->{force}.', not both' )
      if $forced && exists $out{$field};
    next unless $forced || exists $out{$field};
    my $value = $forced ? delete $out{ $spec->{force} } : $out{$field};
    next unless defined $value;
    $out{$field} = $spec->{list}
      ? [ map { $self->_resolve_one( $field, $spec, $_, $forced ) } @{ ref $value eq 'ARRAY' ? $value : [$value] } ]
      : $self->_resolve_one( $field, $spec, $value, $forced );
  }
  return \%out;
}

sub _resolve_one {
  my ( $self, $field, $spec, $value, $forced ) = @_;
  return $value if !$forced && $value =~ $spec->{raw};
  my $find  = $spec->{find};
  my $found = $self->$find($value);
  WWW::Authentik::Error::Validation->throw( message => 'cannot set '.$field.': no '.$spec->{what}.' named "'.$value.'"' )
    unless $found;
  return $found->{pk};
}
```

The `=method resolve` POD lists the table: per field, what counts as a raw identifier
(integer PK or UUID form) and how the name is forced (`<field>_name` or
`<field>_slug`). It says explicitly that a provider named `123` has to be addressed via `provider_name`,
because `provider => '123'` is the PK 123 — and that both at once
are rejected.

- [ ] **Step 5: Write the section `ensure`**

```perl
####  ensure

sub _ensure {
  my ( $self, %arg ) = @_;
  my $current = $arg{find}->();
  unless ( $current ) {
    my $object = $arg{create}->();
    $arg{after_create}->($object) if $arg{after_create};
    return { object => $object, changed => 'created' };
  }
  my $changes = $self->diff_class->changes( $current, $arg{wanted} );
  return { object => $current, changed => '' } unless %$changes;
  return { object => $arg{update}->( $current, $changes ), changed => 'updated' };
}
```

Every `ensure_*` method is then:
1. check the required key (validation error if it is missing);
2. `my $rep = $self->resolve( \%rep )`;
3. take helper keys out of the comparison (`password` for the user);
4. `_ensure` with `find`, `create`, `update`, `wanted`.

The particulars per method:

```perl
sub ensure_user {
  my ( $self, %rep ) = @_;
  WWW::Authentik::Error::Validation->throw( message => 'ensure_user needs a username' ) unless defined $rep{username};
  my $wanted   = $self->resolve( \%rep );
  my $password = delete $wanted->{password};   # not a field of the user
  return $self->_ensure(
    wanted => $wanted,
    find   => sub { $self->find_user( $rep{username} ) },
    create => sub { $self->create_user($wanted) },
    # a password is set when the user is created and never again; call
    # set_password to change one
    after_create => sub { $self->set_password( $_[0]{pk}, $password ) if defined $password },
    update => sub { $self->update_user( $_[0]{pk}, $_[1] ) }
  );
}

sub ensure_oauth2_provider {
  my ( $self, %rep ) = @_;
  WWW::Authentik::Error::Validation->throw( message => 'ensure_oauth2_provider needs a name' ) unless defined $rep{name};
  my $wanted = $self->resolve( \%rep );
  return $self->_ensure(
    wanted => $wanted,
    find   => sub { $self->find_oauth2_provider( $rep{name} ) },
    create => sub {
      # a provider created without grant_types answers every token request
      # with invalid_grant, and this client does not guess which grants were meant
      WWW::Authentik::Error::Validation->throw( message => 'ensure_oauth2_provider needs grant_types to create a provider: '
        .'authentik defaults them to an empty list, and such a provider answers every token request with invalid_grant' )
        unless $wanted->{grant_types} && @{ $wanted->{grant_types} };
      $self->create_oauth2_provider($wanted);
    },
    update => sub { $self->update_oauth2_provider( $_[0]{pk}, $_[1] ) }
  );
}

sub ensure_token {
  my ( $self, %rep ) = @_;
  WWW::Authentik::Error::Validation->throw( message => 'ensure_token needs an identifier' ) unless defined $rep{identifier};
  # authentik ignores expires and sets it to now plus default_token_duration
  WWW::Authentik::Error::Validation->throw( message => 'ensure_token cannot set expires: authentik ignores it '
    .'and sets it from the instance setting default_token_duration; use expiring to say whether the token expires at all' )
    if exists $rep{expires};
  ...
}

sub ensure_binding {
  my ( $self, %arg ) = @_;
  for (qw( flow stage order )) {
    WWW::Authentik::Error::Validation->throw( message => 'ensure_binding needs '.$_ ) unless defined $arg{$_};
  }
  my $flow  = $arg{flow}  =~ $UUID ? $arg{flow}  : ( $self->find_flow( $arg{flow} )   || WWW::Authentik::Error::Validation->throw( message => 'ensure_binding: no flow "'.$arg{flow}.'"' ) )->{pk};
  my $stage = $arg{stage} =~ $UUID ? $arg{stage} : ( $self->find_stage( $arg{stage} ) || WWW::Authentik::Error::Validation->throw( message => 'ensure_binding: no stage "'.$arg{stage}.'"' ) )->{pk};
  my %wanted = ( %arg, target => $flow, stage => $stage );
  delete @wanted{qw( flow )};
  return $self->_ensure(
    wanted => \%wanted,
    # a flow binds a stage at most once; the order is what ensure changes
    find   => sub { $self->_find_one( $self->list_bindings( target => $flow, stage => $stage ), 'stage', $stage ) },
    create => sub { $self->create_binding( \%wanted ) },
    update => sub { $self->update_binding( $_[0]{pk}, $_[1] ) }
  );
}
```

`ensure_application` (key `slug`), `ensure_group` (`name`), `ensure_scope_mapping`
(`name`), `ensure_flow` (`slug`) and `ensure_stage( $type, %rep )` (`name`, looked up via
`find_stage`, created and changed via the typed path) follow the pattern without
particulars.

Each gets its `=method` POD with a call example, the key it looks up by,
and the return value `{ object, changed }`.

- [ ] **Step 6: Run the tests, commit**

Run: `prove -lr t` — Expected: PASS.
Commit: subject `Add name resolution and the ensure methods`.

---

### Task 6: Live suite, executor helper module, bring up to date

**Files:**
- Create: `t/lib/AuthentikExecutor.pm`, `t/90-live-authentik.t`
- Modify: `README.md`, `Changes`, `CLAUDE.md`, `.claude/skills/www-authentik-core/SKILL.md`, `t/00-load.t`

**Interfaces:**
- Consumes: the whole dist.
- Produces: `AuthentikExecutor->new( base_url =>, flow => $slug )` with
  `->start`, `->submit( \%answer )`, `->component`, `->challenge`, `->ua`,
  `->login( username =>, password =>, totp_secret => )` → 1 or death with the message of the
  executor, `->enroll_totp` → the Base32 secret, `->authorization_code( %param )` → the
  code from the 302, `->totp($secret)` → the current code.

- [ ] **Step 1: Write `t/lib/AuthentikExecutor.pm`**

Not part of the public API (spec 11, point 7). Its own `LWP::UserAgent` instance with
`cookie_jar` and `max_redirect => 0`. The flow is spec 8.3:

- `start`: `GET <base>/api/v3/flows/executor/<flow>/?query=` with `Accept: application/json`.
- `submit( \%answer )`: `POST` to the same address with JSON, header `X-authentik-CSRF` from
  the cookie `authentik_csrf`. A 302 response means "next stage": afterwards `GET` is
  repeated until a 200 comes (at most five times, then death).
- `login`: `ak-stage-identification` with `uid_field`, then `ak-stage-password` with
  `password`, then, if `ak-stage-authenticator-validate` comes and a secret is present,
  `code` plus `selected_challenge` from `device_challenges[0]`. `ak-stage-access-denied`
  aborts with `error_message` (that is the response for enforced TOTP without a device).
  At the end `xak-flow-redirect`.
- `enroll_totp`: the same flow against `default-authenticator-totp-setup`, the secret from
  the `config_url` (`secret=`), then `code` from the secret back.
- `authorization_code`: `GET <base>/application/o/authorize/?…` with the cookies, the code
  comes from the `Location`.
- `totp`: RFC 6238, HMAC-SHA1, six digits, 30 seconds, Base32 secret
  (`MIME::Base32` is not a core dependency — the decoding is ten lines in the module).

- [ ] **Step 2: Write `t/90-live-authentik.t`**

```perl
BEGIN {
  plan skip_all => 'set AUTHENTIK_LIVE_TEST=1, AUTHENTIK_URL and AUTHENTIK_TOKEN to run the authentik live test'
    unless $ENV{AUTHENTIK_LIVE_TEST} && $ENV{AUTHENTIK_URL} && $ENV{AUTHENTIK_TOKEN};
}
```

A prefix `wwwak-live-<8 random letters>` before every name and slug. An `END` block
cleans up in reverse order (binding, stage, flow, application, provider, mapping,
token, user, group) and swallows every error while doing so.

Helper function:

```perl
sub twice {
  my ( $name, $code ) = @_;
  my $first  = $code->();
  my $second = $code->();
  is( $first->{changed}, 'created', $name.': created' );
  is( $second->{changed}, '', $name.': second run changes nothing' );
  return $first;
}
```

Subtests:

1. `instance` — `version` reports the version via `diag`, `me` returns the admin.
2. `objects, twice` — `twice` for group, user (with `password` and `group_names`),
   scope mapping, provider (with `scopes`, `grant_types`, `redirect_uris` without
   `redirect_uri_type`, `authorization_flow` and `invalidation_flow` as a slug,
   `signing_key_name`), application (with `provider_name`), flow, stage, binding, token.
   Afterwards one changed key each → `updated`, and the fields not named are still there.
   `ensure_oauth2_provider` without `grant_types` throws.
3. `OIDC` — `discovery`, `issuer`, `jwks`; `client_credentials_token` with the provider's
   secret, `verify_token( type => 'access' )` and `type => 'id'`; `userinfo`;
   `introspect` (`active` true); `revoke`, afterwards `introspect` false and `userinfo` throws
   with 401; `device_authorization` and `device_token` up to `authorization_pending`.
4. `a login and the second factor` — the executor logs the user in with a password,
   fetches a code via `authorization_code`, exchanges it with
   `exchange_authorization_code` and checks `amr` equal to `['pwd']` as well as `auth_time`;
   then `enroll_totp`, a second login with the code, and `amr` equal to `['pwd','mfa']`.
   `refresh_token` keeps `amr` and `auth_time`.
5. `clean up` — everything deleted, a `find_*` returns nothing any more.

- [ ] **Step 3: Run against the throwaway instance**

Run: `AUTHENTIK_LIVE_TEST=1 AUTHENTIK_URL=http://127.0.0.1:9000 AUTHENTIK_TOKEN=<bootstrap token> prove -lv t/90-live-authentik.t`
Expected: PASS, five subtests, `diag` names `2026.8.3`. The suite runs green twice
in a row (it does not depend on the objects of the first run).

- [ ] **Step 4: Bring `README.md`, `Changes`, `CLAUDE.md`, the core skill and `t/00-load.t` up to date**

- `README.md`: synopsis, description, one example each for `oidc`, the basic operations and
  `ensure_*`, the section on the live tests with the compose file, the license.
- `Changes`: one entry per area under `{{$NEXT}}`, no "Initial skeleton" any more.
- `CLAUDE.md` and `.claude/skills/www-authentik-core/SKILL.md`: "Skeleton state" out, the
  built module map in, spec and plan linked.
- `t/00-load.t`: all nine modules.

- [ ] **Step 5: Run everything, commit**

Run: `prove -lr t && dzil test --all` — Expected: both PASS.
Commit: subject `Add the live suite and bring the docs to the built state`.

---

## Self-check against the spec

- **5.1 Basic operations** → task 4, method table; every row of the spec table appears.
- **5.2 `ensure_*`** → task 5, with all five rules (only what is named, compare first, lists as sets, defaults, password only on creation, delete nothing).
- **5.3 What comes back differently** → `Diff` (task 1) and `FakeAuthentik` (task 2).
- **6 OIDC** → task 3, all methods of the spec table; no `password_token`, as the spec says.
- **6.1 Issuer and token type** → `issuer` from the discovery document, `type` as a heuristic.
- **6.2 Second factor** → task 6, subtest 4, with enforced TOTP in the executor helper module.
- **7 Errors** → task 2, all four forms, `field_errors`, no `is_conflict`.
- **8 Observed** → `FakeAuthentik` answers like that; the live suite checks it on the real system.
- **9 Twin** → `build_request`/`read_response` separate (task 2), `_paged` and
  `resolve` as methods of their own (tasks 4 and 5), so the twin rebuilds them asynchronously.
- **10 Tests and phases** → tasks 1 to 6; phase 2 and 3 are not part of this plan.
- **11 Decisions** → `api` as the sub-client (task 4), no `Auth` class (task 3),
  `grant_types` required (task 5), resolution per field (task 5), executor in `t/lib`
  (task 6), compose file already present.
- **12 Review** → return shape in the facade's POD (task 3), resolution without guessing
  (task 5, Review Focus 1), `type` as a heuristic (task 3), enforced TOTP observed before
  the build and added in 6.2 and 8.3.
