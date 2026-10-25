# WWW::Authentik – Design

Date: 2026-10-04
Status: approved on 2026-10-04; the decisions from section 11 have been made.
Distribution: `WWW-Authentik` (repo `p5-www-authentik`), CPAN-ready, `[@Author::GETTY]`
Twin: `Net-Async-Authentik` (repo `p5-net-async-authentik`), follows this design with `_f` methods.
Model: `WWW-Keycloak` (`docs/superpowers/specs/2026-10-02-www-keycloak-design.md` there); shape and names follow it, the code is copied and adapted, not shared.

## 1. What WWW::Authentik is

**WWW::Authentik is the Perl client for authentik: OIDC against an application and the
REST API v3, with which you bring an authentik into a desired state from Perl.**

The trigger is the same as with Keycloak: next to `Airlock::Upstream::Keycloak`, Airlock is to
get an `Airlock::Upstream::Authentik`, and for that it needs an authentik that can be set up
repeatably for tests (application, provider, users with password and TOTP), and
certainty about what the token says about the second factor. With this dist it should look like this:

```perl
my $ak = WWW::Authentik->new(
  base_url    => 'http://127.0.0.1:9000',
  application => 'airlock-test',
  token       => $ENV{AUTHENTIK_TOKEN},
);

my $provider = $ak->api->ensure_oauth2_provider(
  name               => 'airlock-test',
  authorization_flow => 'default-provider-authorization-implicit-consent',
  invalidation_flow  => 'default-provider-invalidation-flow',
  client_type        => 'confidential',
  grant_types        => [qw( authorization_code refresh_token urn:ietf:params:oauth:grant-type:device_code )],
  redirect_uris      => [ { matching_mode => 'strict', url => 'http://127.0.0.1:1/cb' } ],
  scopes             => [qw( openid email profile offline_access )],
);
$ak->api->ensure_application( slug => 'airlock-test', name => 'Airlock Test', provider => 'airlock-test' );

my $claims = $ak->oidc->verify_token($jwt);   # $claims->{amr} = ['pwd', 'mfa']
```

### What WWW::Authentik is not

- **Not a deployment tool.** Starting authentik, PostgreSQL, worker, certificates belong to
  the operator. This dist talks to an authentik that is already running.
- **Not a replacement for blueprints.** What can be described as a YAML blueprint and is never
  touched again from Perl may stay a blueprint (section 11, point 4).
- **Not a browser.** The flow executor is a JSON API, and the live tests use it
  for the login (section 8.3). A public class for it is phase 2 (section 11,
  point 7), not part of phase 1.
- **No complete coverage of API v3.** The API has 607 paths. Phase 1 takes what an
  OIDC setup and a user with a second factor need; policies, sources, outposts, SAML,
  LDAP, RBAC roles and events come when they are needed.

## 2. Structure

```
WWW::Authentik                    facade: base_url, application (slug), token, ua
  ├─ ->oidc    WWW::Authentik::OIDC       discovery, JWKS, verify token, fetch token
  ├─ ->api     WWW::Authentik::API        REST API v3, direct methods and ensure_*
  └─ ->for_application('x')              the same facade for another application

WWW::Authentik::Diff              comparison without I/O, used by both dists
WWW::Authentik::Role::HTTP        build_request / read_response / send_request
WWW::Authentik::Error             ::Validation, ::Network, ::API (one package per file)
```

Moo, one class per concern, one shared `LWP::UserAgent` instance (injectable via `ua`),
direct methods instead of nested sub-clients (`$api->list_users`, not
`$api->users->list`).

Four things are different in authentik than in Keycloak and shape the structure:

1. **There is no realm.** The API lives under `<base_url>/api/v3/` for the whole instance.
   OIDC is addressed per *application*: discovery, JWKS and end-session live under
   `<base_url>/application/o/<slug>/`, authorize, token, userinfo, introspect, revoke and
   device are instance-wide under `<base_url>/application/o/`. The application slug is therefore
   an optional attribute of the facade: without it there is `api`, with it also `oidc`.
2. **The API token lives long.** An API token (`intent: api`, `expiring: false`) does not
   expire. There is nothing to renew; an `Auth` class as in Keycloak is dropped
   (section 4, section 11 point 3).
3. **Duplicate objects are 400, not 409.** authentik answers a second creation with
   `400 {"slug": ["Application with this slug already exists."]}`, i.e. a field error
   like any other validation error. `ensure_*` has to look up first and must not rely on
   a conflict status (section 7).
4. **Objects are connected differently.** An application has at most one provider
   (`provider`, integer PK) and is addressed in the path by its slug; a provider has a
   unique `name`, flows as UUIDs and property mappings as a UUID list; flows have a slug in the
   path, a UUID in references; stages have their own endpoint per type; bindings are
   objects of their own (flow, stage, `order`). The human-readable keys `ensure_*`
   looks up by are in section 5.2.

## 3. Facade

```perl
my $ak = WWW::Authentik->new(
  base_url    => 'https://id.example.org',   # required, without /api/v3
  application => 'my-app',                   # optional, slug; needed for ->oidc
  token       => $api_token,                 # optional; needed for ->api
  ua          => $lwp,                       # optional
);

$ak->oidc;                       # WWW::Authentik::OIDC for 'my-app'
$ak->api;                        # WWW::Authentik::API
$ak->issuer;                     # https://id.example.org/application/o/my-app/
$ak->for_application('other');   # facade for another application, same ua, same token
```

`base_url` empty: `WWW::Authentik::Error::Validation`. A trailing `/` is removed.
`oidc` without `application` and `api` without `token` throw a validation exception on first
access. The default `ua` follows no redirects (as with Keycloak; the
authorize endpoint answers with 302, whose `Location` the caller or the tests' executor helper module reads).

## 4. Login to the API

Every API call carries `Authorization: Bearer <token>`. Three sources for the token, all
observed:

| Source | Lifetime | Observed |
|---|---|---|
| Bootstrap token (`AUTHENTIK_BOOTSTRAP_TOKEN`) | `expiring: false` | listed as `authentik-bootstrap-token`, `intent: api`, user `akadmin` |
| Token created via the API (`POST /core/tokens/`, `intent: api`, `expiring: false`) | unlimited | key via `view_key`, own value via `set_key` |
| OIDC access token with scope `goauthentik.io/api` | `expires_in` 300 | client credentials token as bearer against `/core/users/me/` 200; permissions are those of the service account (list of users: 403) |

Phase 1 knows only a fixed `token`. It is not renewed; authentik answers an invalid or
expired token with `403 {"detail": "Token invalid/expired"}`, a
missing one with `403 {"detail": "Authentication credentials were not provided."}`. Both
become `WWW::Authentik::Error::API` with `is_forbidden` (section 7). Without login
`oidc` works.

The token appears in no exception and in no log.

## 5. API (`WWW::Authentik::API`)

### 5.1 Basic operations

Each method is a thin call of one endpoint under `<base_url>/api/v3`. Paths end in
`/`; without the slash authentik answers 404. Return values: `get_*` and `find_*` return the
representation as a hash (or nothing for `find_*` without a match), `list_*` an array reference
with all matches (the method follows `pagination.next` until `0` comes), `create_*` the
representation of the new object (authentik answers `201` with the whole object, without a
`Location` header), `update_*` the new representation, `delete_*` true.

Lists come as `{"pagination": {"next", "previous", "count", "current", "total_pages",
"start_index", "end_index"}, "results": [...]}`, `next` is `0` on the last page.
`page_size` is a query parameter; a page beyond the last is `404 {"detail":
"Invalid page."}`. Filters are exact equality (`?username=probe-alice` finds
`probe-alice`, `?username=probe` nothing), `?search=` searches fuzzily, `?ordering=` sorts.

`update_*` sends `PATCH`. authentik's `PUT` requires the mandatory fields, but leaves fields
not named in place (observed on user, group, application; the provider
requires `redirect_uris`), so it is not a replacement. Since `PATCH` does the same without mandatory fields,
there is no reason for `PUT`. `attributes` (user, group) are replaced as a whole by `PATCH`,
not merged; `ensure_*` merges them itself before writing.

| Area | Methods |
|---|---|
| Instance | `version` (`/admin/version/`), `config` (`/root/config/`), `settings` (`/admin/settings/`), `me` (`/core/users/me/`) |
| Applications | `list_applications(%query)`, `find_application($slug)`, `create_application(\%rep)`, `update_application($slug, \%changes)`, `delete_application($slug)`, `check_access($slug, for_user => $pk)` |
| OAuth2 providers | `list_oauth2_providers(%query)`, `find_oauth2_provider($name)`, `get_oauth2_provider($pk)`, `create_oauth2_provider(\%rep)`, `update_oauth2_provider($pk, \%changes)`, `delete_oauth2_provider($pk)`, `provider_setup_urls($pk)`, `preview_user($pk, $user_pk)` |
| Scope mappings | `list_scope_mappings(%query)`, `find_scope_mapping($name)`, `find_scope_mappings_by_scope(@scope_names)`, `create_scope_mapping(\%rep)`, `update_scope_mapping($uuid, \%changes)`, `delete_scope_mapping($uuid)`, `test_property_mapping($uuid, user => $pk)` |
| Users | `list_users(%query)`, `find_user($username)`, `get_user($pk)`, `create_user(\%rep)`, `update_user($pk, \%changes)`, `delete_user($pk)`, `set_password($pk, $password)`, `create_service_account(name => $n, %opt)`, `list_authenticators($pk)` |
| Groups | `list_groups(%query)`, `find_group($name)`, `get_group($uuid)`, `create_group(\%rep)`, `update_group($uuid, \%changes)`, `delete_group($uuid)`, `add_user_to_group($uuid, $user_pk)`, `remove_user_from_group($uuid, $user_pk)` |
| Tokens | `list_tokens(%query)`, `get_token($identifier)`, `create_token(\%rep)`, `update_token($identifier, \%changes)`, `delete_token($identifier)`, `view_token_key($identifier)`, `set_token_key($identifier, $key)` |
| Flows | `list_flows(%query)`, `find_flow($slug)`, `create_flow(\%rep)`, `update_flow($slug, \%changes)`, `delete_flow($slug)`, `export_flow($slug)` (YAML as a string) |
| Stages | `list_stages(%query)` (`/stages/all/`), `stage_types`, `get_stage($type, $uuid)`, `create_stage($type, \%rep)`, `update_stage($type, $uuid, \%changes)`, `delete_stage($type, $uuid)` |
| Bindings | `list_bindings(flow => $slug)`, `create_binding(\%rep)`, `update_binding($uuid, \%changes)`, `delete_binding($uuid)` |
| Brand | `list_brands`, `current_brand`, `update_brand($uuid, \%changes)` |
| Certificates | `list_certificates(%query)`, `find_certificate($name)` |
| Blueprints | `list_blueprints`, `create_blueprint(\%rep)`, `apply_blueprint($uuid)`, `get_blueprint($uuid)`, `delete_blueprint($uuid)` |
| Raw | `call($method, $path, \%body)` for every endpoint without a method of its own |

`$type` for stages is the path part after `/stages/`: `password`, `identification`,
`user_login`, `authenticator/validate`, `authenticator/totp`, `consent`, `prompt`, …
(`stage_types` returns `component` and `model_name` of all 25 types). `/stages/all/` can only
read; `PATCH` there is 405.

`find_user` searches with `?username=` exactly and case-sensitively; authentik allows
`Probe-Bob` and `probe-bob` side by side. `find_application` is `GET /core/applications/<slug>/`
and catches the 404.

`create_service_account` is `POST /core/users/service_account/`: authentik creates a user and
an app password token and returns the token exactly once (`{username, user_pk,
user_uid, token}`). This token is the `password` for `client_credentials` with
`username` (section 6).

### 5.2 `ensure_*`: desired state instead of a single step

As with Keycloak: look up, create or reconcile, say what was done.

```perl
my $r = $api->ensure_user( username => 'alice', name => 'Alice', attributes => { dept => 'x' } );
$r->{object};    # the representation after the run
$r->{changed};   # 'created', 'updated' or ''
```

Instead of `id`, `ensure_*` returns the whole object, because authentik has no uniform
identifier (slug, integer PK, UUID, identifier) and a caller usually needs the next key
(the provider PK for the application, the flow UUID for the binding).

| Method | Key used for the lookup | Resolution of human-readable names |
|---|---|---|
| `ensure_application(%rep)` | `slug` | `provider => $name` → provider PK |
| `ensure_oauth2_provider(%rep)` | `name` | `authorization_flow`, `invalidation_flow`, `authentication_flow => $slug` → UUID; `signing_key => $name` → UUID; `scopes => [@scope_names]` → `property_mappings` |
| `ensure_scope_mapping(%rep)` | `name` | – |
| `ensure_user(%rep)` | `username` | `groups => [@names]` → UUIDs |
| `ensure_group(%rep)` | `name` | – |
| `ensure_token(%rep)` | `identifier` | `user => $username` → PK |
| `ensure_flow(%rep)` | `slug` | – |
| `ensure_stage($type, %rep)` | `name` (unique across all stage types) | `configure_flow => $slug` → UUID |
| `ensure_binding(flow => $slug, stage => $name, order => $n, %rep)` | flow and stage | both → UUID |

Rules that apply to all of them:

- **Only what is given is reconciled.** Keys the caller does not name
  stay. `attributes` are merged key by key and then sent as a whole,
  because `PATCH` replaces them.
- **Compare first, then write.** If the state is right, there is no writing
  call and `changed` is empty.
- **Lists are sets.** `property_mappings` come back in a different order than
  sent; `grant_types` and `redirect_uris` keep the order, but it has no
  meaning. `Diff` compares every list as a set, including lists of hashes
  (canonical JSON per element). Bindings with their order are objects of their own with
  an `order` field, not a list.
- **Defaults that authentik adds, `Diff` adds before comparing.** `redirect_uris`
  come back with `redirect_uri_type: "authorization"`, even if it was not sent.
  That is the only observed case in phase 1; the list lives in one place in `Diff`.
- **`ensure_user` touches the password only on creation.** `password` is not a field of the
  user; `ensure_user` calls `set_password` after creation, never again afterwards. Whoever
  wants that calls `set_password`. `set_password` accepts any password (`204`, even for `"a"`),
  password policies only apply in flows.
- **`ensure_oauth2_provider` requires `grant_types` on creation.** A provider created via the API without
  `grant_types` has `grant_types: []` and answers every token request
  with `invalid_grant` (log: "Invalid grant_type for provider"). Because the dist should not guess
  which grants are meant, their absence on creation is a validation error
  (section 11, point 5).
- **`ensure_token` cannot set an expiry date.** `expires` is ignored on creation and on
  `PATCH` and set to now plus `default_token_duration` (`days=1`); only
  `expiring` is controllable. `ensure_token` does not compare `expires` and throws a
  validation error when `expires` is given.
- **Nothing is deleted.** `ensure_*` removes no objects and no keys.
  Deleting a stage deletes its bindings (`DELETE` on the stage: bindings afterwards 0).

### 5.3 What comes back differently than written

Observed, and recorded for `Diff`:

- `client_secret` comes back in plain text and can be set; it is comparable.
  authentik also generates a secret for `client_type: public` (128 characters).
- Read-only fields (`pk`, `uid`, `component`, `assigned_application_slug`, `*_obj`, …) are silently
  ignored on write, unknown fields as well. A representation that was read can
  be written back unchanged (`PUT` with the `GET` body: 200 on user, application,
  provider, mapping, flow, stage, group, brand).
- User: `path` default `users`, `type` default `internal`, `attributes` arbitrarily
  nested (numbers, booleans, lists, hashes stay typed).
- Provider: `access_token_validity` and the like are strings like `minutes=5`, `days=30`;
  `grant_types` accepts only the eight values of `GrantTypeEnum`
  (`authorization_code`, `implicit`, `hybrid`, `refresh_token`, `client_credentials`,
  `password`, `urn:ietf:params:oauth:grant-type:device_code`,
  `urn:ietf:params:oauth:grant-type:token-exchange`); a wrong value is
  `400 {"grant_types": {"0": ["\"x\" is not a valid choice."]}}`.
- Scope mapping: `expression` is compiled on creation; a syntax error is
  `400 {"expression": ["Expression Syntax Error: …"]}`. `scope_name` is not unique,
  `name` is.
- Stage `name` is unique across all stage types (`400 {"name": ["stage with this name
  already exists."]}` also for another type).
- Binding: `(target, stage, order)` is unique (`400 {"non_field_errors": ["The fields
  target, stage, order must make a unique set."]}`); the same stage with a different `order`
  can be bound a second time.
- A provider belongs to at most one application (`400 {"provider": ["Application with
  this provider already exists."]}`).

## 6. OIDC (`WWW::Authentik::OIDC`)

Like `WWW::Keycloak::OIDC`, with the authentik quirks:

| Method | Purpose |
|---|---|
| `discovery`, `jwks`, `*_endpoint` | metadata, cached; `jwks(force_refresh => 1)` |
| `issuer` | from the discovery document, not computed (section 6.1) |
| `verify_token($jwt, audience => ..., type => 'access' \| 'id')` | signature, `iss`, `exp`, optional `aud` and token type |
| `userinfo($access_token)`, `introspect($token, client_id =>, client_secret =>)`, `revoke($token, client_id =>, client_secret =>)` | |
| `client_credentials_token(client_id =>, client_secret =>, scope =>)` | grant for the service account `ak-<provider>-client_credentials` created automatically by the provider |
| `client_credentials_token(client_id =>, client_secret =>, username =>, password =>, scope =>)` | grant for an own service account with an app password token |
| `refresh_token($refresh_token, client_id =>, client_secret =>)` | refresh tokens are rotated; the old one is `invalid_grant` afterwards |
| `exchange_authorization_code(code =>, redirect_uri =>, client_id =>, client_secret =>)` | |
| `device_authorization(client_id =>, scope =>)`, `device_token(device_code =>, client_id =>, client_secret =>)` | one step of the device flow; the poll loop is up to the caller |
| `authorization_url(%param)` | only build the URL; the browser is not part of the dist |

No `password_token` for end users: authentik's `grant_type=password` is the same path as
`client_credentials` with `username`/`password` of a service account and gives
`invalid_grant` for a normal user (observed). Whoever needs a user token for tests goes
through the flow executor (section 8.3).

The token endpoint accepts client authentication as `client_secret_post` and
`client_secret_basic` (both observed). All values are sent form-encoded; the
`device_code` contains quotes, `%` and `&` and is `invalid_grant` without encoding.

### 6.1 Issuer and token type

With `issuer_mode: per_provider` (default) `iss` is
`<base_url>/application/o/<slug>/`, with `issuer_mode: global` it is `<base_url>/`; JWKS and
end-session stay under the slug in both cases. `verify_token` therefore checks against the
`issuer` of the discovery document, which always lives under the slug.

ID and access tokens are both `RS256` JWTs with `"typ": "JWT"` in the header; the token type is
not in the header. The access token additionally carries `azp`, `scope` and `uid`, the ID token
`nonce` (if requested) and `at_hash` after a refresh. `type => 'access'` requires
`scope`, `type => 'id'` forbids it. `verify_token` accepts only `RS*`, `PS*`, `ES*`;
authentik reports `id_token_signing_alg_values_supported: ["RS256"]`.

### 6.2 Second factor in the token

Observed on authentik 2026.8.3 with the default configuration (`default-authentication-flow`
with identification, password, authenticator validation (`not_configured_action: skip`),
user login), without any change to flow, stage or mapping:

| Login | `amr` | `acr` | `auth_time` |
|---|---|---|---|
| Password | `["pwd"]` | `goauthentik.io/providers/oauth2/default` | time of the login |
| Password + TOTP | `["pwd", "mfa"]` | `goauthentik.io/providers/oauth2/default` | time of the login |
| Client credentials | missing | `goauthentik.io/providers/oauth2/default` | = `iat` |

`amr`, `acr` and `auth_time` are the same in ID token, access token and introspection response,
and `auth_time` is preserved across refresh and further authorize calls of the same session
(a second authorization 4 minutes after the login still carried the old `auth_time`).
`amr` stays after the refresh. `acr` is constant; `acr_values` and `max_age=0` in the
authorize call change nothing and force no new login (both observed, the code came
immediately). There is no mapping and no stage setting needed for this; discovery
lists `claims_supported: [..., "auth_time", "acr", "amr", ...]`.

For `Airlock::Upstream::Authentik` this means: `mfa` in `amr` is the signal for the second
factor; `acr` is no good for telling them apart.

**Enforced TOTP** (observed 2026-10-04, addendum from section 12). Whoever wants to require the second
factor switches `not_configured_action` on the validation stage:

```perl
$api->ensure_stage( 'authenticator/validate',
  name                 => 'default-authentication-mfa-validation',
  not_configured_action => 'deny',
);
```

| Setting | User without authenticator | User with TOTP |
|---|---|---|
| `skip` (default) | login goes through, `amr: ["pwd"]` | code required, `amr: ["pwd","mfa"]` |
| `deny` | `200 {"component":"ak-stage-access-denied","error_message":"No (allowed) MFA authenticator configured."}`, no session | unchanged `amr: ["pwd","mfa"]` |
| `configure` (needs `configuration_stages`) | the setup stage is inserted: `200 {"component":"ak-stage-authenticator-totp","config_url":"otpauth://…"}` | unchanged |

authentik rejects `configure` without `configuration_stages`:
`400 {"not_configured_action":["When \"Not configured action\" is set to \"Configure\", you
must set a configuration stage."]}`. Both fields have to come in **one** `PATCH`; `ensure_stage`
does that anyway, because it sends all differing keys together.

`deny` changes nothing about `amr`, `acr` and `auth_time` of a successful login: the same
values as with `skip`. The only difference is whether a user without a second factor
gets in.

## 7. Errors

One package per file, as with Keycloak:

- `WWW::Authentik::Error` — base with `message`, stringifies to it.
- `WWW::Authentik::Error::Validation` — wrong arguments, missing credentials, rejected tokens.
- `WWW::Authentik::Error::Network` — no response.
- `WWW::Authentik::Error::API` — HTTP 4xx/5xx, with `http_status`, `api_message`, `field_errors`
  (hash, may be empty), `oauth_error`, `request_id` and the predicates `is_not_found` (404),
  `is_forbidden` (403), `is_bad_request` (400), `is_unauthorized` (401).

authentik has four error forms, all observed:

| Form | Example | From |
|---|---|---|
| `{"detail": "…"}` | `403 {"detail": "Token invalid/expired"}`, `404 {"detail": "No User matches the given query."}`, `405 {"detail": "Method \"PATCH\" not allowed."}`, `400 {"detail": "JSON parse error - …"}`, `415 {"detail": "Unsupported media type …"}` | API, not field-related |
| `{"<field>": ["…"], "non_field_errors": ["…"]}` | `400 {"username": ["This field must be unique."]}`, `400 {"name": ["This field is required."], "slug": [...]}` | API, validation; nested for `grant_types` (`{"grant_types": {"0": [...]}}`) and at the transactional endpoint (`{"app": {"slug": [...]}}`) |
| `{"error": "…", "error_description": "…", "request_id": "…"}` | `400 invalid_grant`, `400 invalid_client`, `400 unsupported_grant_type`, `400 invalid_scope`, `400 authorization_pending`, `401 invalid_client` (revoke with a wrong secret) | token, device, revoke endpoint |
| empty body, `WWW-Authenticate: error="invalid_token", error_description="…"` | `401` | userinfo |

`api_message` is `detail`, otherwise the field errors joined into one line
(`username: This field must be unique.`), otherwise `error: error_description`. There is no
`is_conflict`: a duplicate cannot be told apart from another validation error, except
by the text. A 500 comes without a body (observed on `POST /authenticators/admin/totp/`).

## 8. Observed on a running authentik

authentik 2026.8.3 (`ghcr.io/goauthentik/server:2026.8.3`, PostgreSQL 16), 2026-10-04,
throwaway instance via Docker Compose on `127.0.0.1:9000`, bootstrap admin `akadmin`.
Every row is a call that was actually made. Paths in 8.1 relative to
`<base_url>/api/v3`, in 8.2 to `<base_url>`.

### 8.1 API v3

| Call | Response |
|---|---|
| any call without a token / with an invalid token | 403 `{"detail":"Authentication credentials were not provided."}` / 403 `{"detail":"Token invalid/expired"}` |
| `GET /admin/version/`, `GET /root/config/`, `GET /admin/settings/`, `GET /core/users/me/` | 200; `version_current: "2026.8.3"`; `default_token_duration: "days=1"` |
| `GET /core/users/?page_size=1` | 200; `pagination` with `next: 2`, `count`, `total_pages`; plus an `autocomplete` block |
| `GET /core/users/?page=99` | 404 `{"detail":"Invalid page."}` |
| `GET /core/users/?username=probe-alice` / `?username=probe` / `?username=PROBE-ALICE` / `?search=alice` | 200; 1 / 0 / 0 / 1 matches |
| `POST /core/users/` (`username`, `name`, `email`, `attributes`, `path`, `type`) | 201, whole object with `pk` (integer), `uuid`, `uid`; no `Location` |
| `POST /core/users/` second time | 400 `{"username":["This field must be unique."]}` |
| `POST /core/users/` with `Probe-Bob` after `probe-bob` | 201; both exist |
| `GET /core/users/{pk}/`, `GET /core/users/999999/` | 200 / 404 `{"detail":"No User matches the given query."}` |
| `PATCH /core/users/{pk}/` (`attributes`) | 200; `attributes` replaced as a whole (`{"one","two"}` → `{"three"}`); typed values stay |
| `PATCH /core/users/{pk}/` with `uid`, `pk`, unknown field | 200; silently ignored |
| `PUT /core/users/{pk}/` only `username` | 400 `{"name":["This field is required."]}` |
| `PUT /core/users/{pk}/` `username`+`name` | 200; `email`, `path`, `attributes`, `groups` stay |
| `PUT /core/users/{pk}/` with the `GET` body | 200 |
| `POST /core/users/{pk}/set_password/` `{"password": …}` | 204, even for `"a"` |
| `POST /core/users/{pk}/recovery/` | 400 `{"non_field_errors":"No recovery flow set."}` |
| `POST /core/users/service_account/` `{"name","create_group":false}` | 200 `{"username","user_uid","user_pk","token"}`; user `type: service_account`, `path: goauthentik.io/service-accounts` |
| `DELETE /core/users/{pk}/` twice | 204 / 404 |
| `GET /core/groups/?name=x`, `POST /core/groups/` | 200 / 201 (`pk` UUID, `num_pk`, `users`, `users_obj`, `parents`, `children`); second time 400 `{"name":["Group with this name already exists."]}` |
| `PATCH` / `PUT /core/groups/{uuid}/` | 200 / 200; `PUT` with only `name` leaves `attributes` in place |
| `POST /core/groups/{uuid}/add_user/` `{"pk": N}`, `…/remove_user/` | 204 / 204, `remove_user` also 204 for a non-member |
| `PATCH /core/users/{pk}/` `{"groups": [uuid]}` | 200; membership can also be set from the user side |
| `DELETE /core/groups/{uuid}/` twice | 204 / 404 |
| `GET /core/tokens/` | 200; `authentik-bootstrap-token` with `intent: api`, `expiring: false` |
| `POST /core/tokens/` (`identifier`, `intent: api`, `expiring: false`) | 201; second time 400 `{"identifier":["Token with this identifier already exists."]}` |
| `POST /core/tokens/` with `expires` +3 s; `PATCH` with `expires` +2 h | 201 / 200; `expires` both times now + 1 day |
| `GET /core/tokens/{id}/view_key/`, `POST …/set_key/` `{"key": …}` | 200 `{"key"}` / 204; the key set is immediately valid as a bearer |
| `POST /core/tokens/` `intent: app_password` | 201; `view_key` 60 characters |
| `PATCH` / `PUT /core/tokens/{id}/`, `DELETE` twice | 200 / 200 / 204 / 404 |
| `GET /core/applications/`, `POST /core/applications/` (`name`, `slug`, without `provider`) | 200 / 201 (`pk` = `pbm_uuid`, `provider: null`, `launch_url`, `meta_*`, `policy_engine_mode: any`) |
| `POST /core/applications/` second time | 400 `{"slug":["Application with this slug already exists."]}`; same `name` with a different slug 201 |
| `POST /core/applications/` `{}` / `slug: "Bad Slug!"` | 400 `{"name":[…],"slug":[…]}` / 400 `{"slug":["Enter a valid “slug” …"]}` |
| `GET /core/applications/{slug}/`, `?slug=x` / `?slug=part` | 200 / 1 / 0 matches |
| `PATCH /core/applications/{slug}/` (`meta_description`, `provider: N`, rename `slug`) | 200; after the rename the old slug 404 |
| `POST /core/applications/` with an already assigned `provider` | 400 `{"provider":["Application with this provider already exists."]}` |
| `GET /core/applications/{slug}/check_access/` | 200 `{"passing":true,"messages":[],"log_messages":[]}` |
| `DELETE /core/applications/{slug}/` unknown | 404 |
| `PUT /core/transactional/applications/` (`app`, `provider_model`, `provider`) | 200 `{"applied":true,"logs":[]}`; second time 400 `{"app":{"slug":[…already exists.]}}` – not repeatable |
| `GET /providers/oauth2/`, `POST /providers/oauth2/` `{"name"}` | 200 / 400 `{"authorization_flow":[required],"invalidation_flow":[required],"redirect_uris":[required]}` |
| `POST /providers/oauth2/` complete | 201; `pk` integer, `client_id` 40 characters, `client_secret` 128 characters in plain text, `grant_types: []`, `redirect_uris[*].redirect_uri_type: "authorization"` added, `property_mappings` reordered |
| `POST /providers/oauth2/` second time | 400 `{"name":["provider with this name already exists."], …}` |
| `GET /providers/oauth2/?name=x` / `?name=part` / `?search=part` | 1 / 0 / 1 matches |
| `PATCH /providers/oauth2/{pk}/` `redirect_uris` reversed / `client_secret` / `grant_types` / `issuer_mode` | 200; order of `redirect_uris` and `grant_types` stays; `grant_types: ["device_code"]` 400 `{"3":["\"device_code\" is not a valid choice."]}` |
| `PUT /providers/oauth2/{pk}/` without `redirect_uris` / with the `GET` body | 400 / 200 |
| `GET /providers/oauth2/{pk}/setup_urls/` before / after assignment to the application | 200 `issuer: null` / 200 with `issuer`, `provider_info`, `jwks`, `logout`, `dcr_registration` |
| `GET /providers/oauth2/{pk}/preview_user/?for_user=N` | 200 `{"preview": {iss, sub, aud, acr, auth_time, email, …}}` |
| `GET /providers/oauth2/{pk}/used_by/`, `GET /providers/all/` | 200 |
| `DELETE /providers/oauth2/{pk}/` | 204 |
| `GET /propertymappings/provider/scope/` | 200; 9 default mappings with `managed: goauthentik.io/providers/oauth2/scope-<name>` (plus one of the proxy provider), `scope_name`, `expression` |
| `POST /propertymappings/provider/scope/` (`name`, `scope_name`, `expression`) | 201 (`pk` UUID, `managed: null`); same `name` 400 `{"name":["Property Mapping with this name already exists."]}`; same `scope_name` 201 |
| `POST …/scope/` with `expression: "return {"` | 400 `{"expression":["Expression Syntax Error: …"]}` |
| `GET …/scope/?name=x` / `?scope_name=x` / `?managed=…` | 200 |
| `PATCH` / `PUT …/scope/{uuid}/`, `DELETE` | 200 / 200 / 204 |
| `POST /propertymappings/all/{uuid}/test/` `{"user": N}` | 200 `{"result":"{\"probe\": true}","successful":true}` |
| `GET /propertymappings/all/types/`, `GET /propertymappings/all/?managed__isnull=true` | 200 |
| `GET /flows/instances/` | 200; 15 default flows with `slug`, `designation`, `authentication`, `stages` (UUIDs) |
| `POST /flows/instances/` (`name`, `slug`, `title`, `designation`) | 201 (`pk` UUID, `stages: []`, `layout: stacked`, `denied_action: message_continue`); second time 400 `{"slug":["Flow with this slug already exists."]}` |
| `PATCH` / `PUT /flows/instances/{slug}/`, `PUT` with the `GET` body | 200 |
| `GET /flows/instances/{slug}/export/` | 200, `content-type: text/html`, body YAML (`version`, `entries`) |
| `DELETE /flows/instances/{slug}/` twice | 204 / 404 |
| `GET /stages/all/types/`, `GET /stages/all/`, `GET /stages/all/?name=x`, `GET /stages/all/{uuid}/` | 200; 25 types; `{uuid}` returns only `pk`, `name`, `component`, `verbose_name`, `meta_model_name`, `flow_set`, no typed fields |
| `PATCH /stages/all/{uuid}/` | 405 |
| `POST /stages/password/` (`name`, `backends`) | 201; same `name` 400 `{"name":["stage with this name already exists."]}`, also at `/stages/user_login/` |
| `PATCH` / `PUT /stages/password/{uuid}/` | 200; `backends` order stays |
| `GET /stages/authenticator/validate/`, `/stages/password/`, `/stages/identification/`, `/stages/authenticator/totp/`, `/stages/user_login/` | 200, typed fields (`not_configured_action: skip`, `device_classes`, `last_auth_threshold`, `backends`, `user_fields`, `digits`, `session_duration`) |
| `PATCH /stages/authenticator/validate/{uuid}/` `{"not_configured_action":"deny"}` | 200 |
| the same with `"configure"` without `configuration_stages` / with both fields in one `PATCH` | 400 `{"not_configured_action":["When \"Not configured action\" is set to \"Configure\", you must set a configuration stage."]}` / 200 |
| `PUT /stages/authenticator/validate/{uuid}/` with the `GET` body | 200 |
| `DELETE /stages/password/{uuid}/` with a binding | 204; binding gone afterwards |
| `GET /flows/bindings/?target=<slug>` / `?target=<uuid>` | 400 `{"target":["… is not a valid UUID."]}` / 200 with `order`, `stage`, `stage_obj`, `evaluate_on_plan`, `re_evaluate_policies` |
| `POST /flows/bindings/` (`target`, `stage`, `order`) | 201; same three 400 `{"non_field_errors":["The fields target, stage, order must make a unique set."]}`; different `order` 201 |
| `PATCH` / `PUT /flows/bindings/{uuid}/`, `DELETE` | 200 / 200 / 204 |
| `GET /policies/bindings/` | 200 (`target`, `policy`, `group`, `user`, `order`, `enabled`) |
| `GET /core/brands/`, `PATCH /core/brands/{uuid}/` `{"flow_device_code": uuid}`, `PUT` with the `GET` body | 200 / 200 / 200 |
| `GET /crypto/certificatekeypairs/` | 200; `authentik Self-signed Certificate`, `private_key_available: true` |
| `GET /managed/blueprints/`, `GET …/available/` | 200; 31 instances, 45 files |
| `POST /managed/blueprints/` with `content` (inline YAML, group `state: present`) | 201 `status: unknown` |
| `POST /managed/blueprints/{uuid}/apply/` | 200, `status` still `unknown`; 3 s later `successful`, `last_applied`, group present; a second `apply` changes nothing, group still exactly once |
| `POST /managed/blueprints/` with an unknown model | 400 `{"content":["Failed to validate blueprint","- App or Model does not exist",…]}` |
| `GET /oauth2/access_tokens/`, `GET /oauth2/refresh_tokens/` | 200; `scope` as a list, `revoked`, `expires`, `id_token`; the token itself is not returned |
| `GET /authenticators/admin/totp/?user=N`, `GET /authenticators/admin/all/?user=N` | 200 |
| `POST /authenticators/admin/totp/` `{"name"}` | 500, empty body (`IntegrityError: null value in column "user_id"`) |
| `POST /core/groups/` as a form instead of JSON / with broken JSON | 415 / 400 `{"detail":"JSON parse error - …"}` |
| `GET /core/users` without the slash | 404 |
| `OPTIONS /core/users/{pk}/` | `allow: GET, PUT, PATCH, DELETE, HEAD, OPTIONS` |

### 8.2 OIDC

| Call | Response |
|---|---|
| `GET /application/o/{slug}/.well-known/openid-configuration` | 200; `issuer` with slug, `device_authorization_endpoint`, `introspection_endpoint`, `revocation_endpoint`, `end_session_endpoint` with slug, `grant_types_supported` follows the provider's `grant_types`, `acr_values_supported: ["goauthentik.io/providers/oauth2/default"]`, `claims_supported` with `amr`, `acr`, `auth_time` |
| Discovery for an unknown slug / application without a provider | 404 / 404 |
| `GET /application/o/{slug}/jwks/` | 200; one RSA key with `kid`, `x5c` |
| `POST /application/o/token/` `client_credentials` on a provider with `grant_types: []` | 400 `invalid_grant` |
| `POST /application/o/token/` `client_credentials` + `client_secret` | 200 `{access_token, id_token, token_type, scope, expires_in: 300}`; user `ak-<provider>-client_credentials` is created (`type: service_account`, `path: goauthentik.io/apps/<slug>`) |
| the same with `-u client_id:client_secret` (Basic) | 200 |
| `client_credentials` + `username`/`password` (service account, app password token) | 200; `sub` of the service account |
| `grant_type=password` with a service account / with a normal user | 200 / 400 `invalid_grant` |
| wrong secret / unknown client / `grant_type=banana` / refresh token `garbage` / code `garbage` | 400 `invalid_grant` / 400 `invalid_client` / 400 `unsupported_grant_type` / 400 `invalid_grant` / 400 `invalid_grant` |
| `GET /application/o/authorize/?response_type=code…` without a session | 302 to `/if/flow/default-authentication-flow/?…&next=…` |
| the same with a session (implicit consent) | 302 `https://app.example.org/cb?code=…&state=…` |
| the same with `max_age=0` / `acr_values=…` | 302 with code, no new login |
| `POST /application/o/token/` `authorization_code` | 200 `{access_token, id_token, refresh_token, scope, token_type, expires_in}`; `refresh_token` 128 characters, not a JWT; code second time 400 `invalid_grant` |
| `GET /application/o/userinfo/` bearer / `POST` with `access_token` | 200 / 200 `{sub, email, name, preferred_username, groups, nonce}` |
| Userinfo with an invalid token | 401, empty body, `WWW-Authenticate: error="invalid_token"` |
| `POST /application/o/introspect/` access token / refresh token / ID token | 200 `{active: true, scope, client_id, amr, acr, auth_time, …}` / 200 `active: true` / 200 `{"active":false}` |
| Introspect with a wrong secret | 200 `{"active":false}` (no 401) |
| `POST /application/o/token/` `refresh_token` | 200, new refresh token; the old one afterwards 400 `invalid_grant`; `scope=openid` as a subset 400 `invalid_scope`; the old access token stays valid until `exp` |
| `POST /application/o/revoke/` access token / second time / `garbage` / wrong secret | 200 `{}` / 200 / 200 / 401 `invalid_client` |
| Introspect / userinfo after revoke | `{"active":false}` / 401 |
| `POST /application/o/device/` `client_id`, `scope` | 200 `{device_code (128 characters), user_code (9 digits), verification_uri: <base_url>/device, verification_uri_complete: <base_url>/device?code=<user_code>, expires_in: 60, interval: 5}`; unknown client 400 `invalid_client` |
| `POST /application/o/token/` `device_code` before confirmation / immediately again / after confirmation / afterwards / after 60 s | 400 `authorization_pending` / 400 `authorization_pending` (no `slow_down`) / 200 with `amr: ["pwd"]` / 400 `invalid_grant` / 400 `invalid_grant` |
| `GET /device?code=…` without / with a session | 302 `/flows/-/default/authentication/?next=…` / 302 `/if/flow/default-provider-authorization-implicit-consent/?code=…` |
| `GET /application/o/{slug}/end-session/` with a session | 302 `/if/flow/default-provider-invalidation-flow/`; the session lives until the flow has run |

### 8.3 Login via the flow executor API

The browser login is a JSON API and could be driven entirely over HTTP. A cookie jar is
needed (`authentik_session`, `authentik_csrf`); the CSRF value goes along as the header
`X-authentik-CSRF`. Every `302` response means "next stage": its `Location` is
the same executor address, which you then fetch with `GET`.

```
GET  /api/v3/flows/executor/default-authentication-flow/?query=
     200 {"component":"ak-stage-identification", "user_fields":["email","username"], …}
POST …  {"component":"ak-stage-identification","uid_field":"probe-alice"}
     302 → GET: 200 {"component":"ak-stage-password","pending_user":"probe-alice"}
POST …  {"component":"ak-stage-password","password":"…"}
     302 → GET: 302 → GET: 200 {"component":"xak-flow-redirect","to":"/","final_redirect":true}
GET  /api/v3/core/users/me/ (with cookies)   200 {"user":{"username":"probe-alice"}}
```

With TOTP set up, instead of the second 302 after the password comes:

```
     200 {"component":"ak-stage-authenticator-validate",
          "device_challenges":[{"device_class":"totp","device_uid":"2","challenge":{}}]}
POST …  {"component":"ak-stage-authenticator-validate","code":"123456",
         "selected_challenge":{"device_class":"totp","device_uid":"2","challenge":{},"last_used":null}}
     302 → GET: 200 {"component":"xak-flow-redirect", …}
```

A wrong password is `200` with the same `component` and
`response_errors: {"password":[{"string":"Invalid password","code":"invalid"}]}`; the stage
is repeated. Afterwards `GET /application/o/authorize/?…` with the cookies directly returns the
302 with the code; the authorization flow (implicit consent) runs without a further executor step.

Setting up TOTP only worked via the setup flow, the admin endpoint is broken (8.1):

```
GET  /api/v3/flows/executor/default-authenticator-totp-setup/?query=   (with login cookies)
     200 {"component":"ak-stage-authenticator-totp",
          "config_url":"otpauth://totp/authentik%3Aprobe-alice?secret=<Base32>&algorithm=SHA1&digits=6&period=30&issuer=authentik"}
POST …  {"component":"ak-stage-authenticator-totp","code":"<TOTP from secret>"}
     200 {"component":"xak-flow-redirect", …}
```

Afterwards `GET /api/v3/authenticators/admin/totp/?user=<pk>` lists the device. On the next
login the default validation stage requires the code (section 6.2).

With `not_configured_action: deny` the login of a user without an authenticator ends after the
password stage:

```
POST …  {"component":"ak-stage-password","password":"…"}
     302 → GET: 200 {"component":"ak-stage-access-denied","pending_user":"probe-dave",
                     "error_message":"No (allowed) MFA authenticator configured."}
GET  /api/v3/core/users/me/ (with cookies)   200 {"user":{"username":null}}
```

With `configure` and the TOTP setup stage in `configuration_stages`, the setup stage
comes instead in the middle of the login (`200 {"component":"ak-stage-authenticator-totp","config_url":…}`),
and the session is only created after it is completed. A user who already has TOTP
notices nothing of either setting.

For the device flow the brand needs a `flow_device_code`; an empty flow
with `designation: stage_configuration` was set. With login cookies `GET /device?code=<user_code>` leads
to `/if/flow/default-provider-authorization-implicit-consent/?code=…`; the executor for it
answers `200 {"component":"ak-provider-oauth2-device-code-finish"}`, and the next poll
returns the tokens.

### 8.4 Not observed

Therefore to be checked in the plan before building:

- The device flow **without** `flow_device_code` on the brand (`device_authorization` answers
  200 then too; what `GET /device?code=` does then was not checked).
- `slow_down` and `expired_token` at the device endpoint: the poll after expiry was
  `invalid_grant`, a poll that was too fast `authorization_pending`.
- `last_auth_threshold` on the validation stage; WebAuthn, static tokens, Duo, SMS, email
  as a second factor and the `amr` for them. (`not_configured_action: deny|configure` has
  been observed in the meantime, see 6.2 and 8.3.)
- Explicit consent flow (`default-provider-authorization-explicit-consent`) via the executor,
  PKCE (`code_challenge`), `response_mode=form_post`, `id_token_hint` and
  `post_logout_redirect_uri` at the end-session endpoint, backchannel logout.
- `issuer_mode: global` only on the discovery document, not on the token.
- Own scope mappings in the token (a mapping was created and checked with `test`, but
  not attached to the provider); `sub_mode` other than `hashed_user_id`; `encryption_key`.
- `PUT /core/transactional/applications/` as an update: failed with "slug already exists",
  no update mode was found.
- Blueprints that change existing objects or carry `state: absent`; whether an object created by a
  blueprint resists `PATCH` (the group carried no `managed` field).
- RBAC: roles, permissions of a non-superuser token (the service account got 403
  on `/core/users/`).
- Writing policies and policy bindings; sources; outposts; SAML, LDAP, proxy providers.
- `/core/users/{pk}/set_password_hash/`, `impersonate`, `account_lockdown`.
- `page_size` upper limit (1000 was accepted, the instance had 6 users).
- Behavior of older versions (2025.x) and of the enterprise features.

## 9. Twin

`Net::Async::Authentik` mirrors the public API with an `_f` suffix and futures, following the
pattern of `Net::Async::Keycloak`: same classes, same methods, same
error hierarchy. This dist leads; the twin follows per phase and depends on `WWW-Authentik`
for `WWW::Authentik::Role::HTTP` (`build_request`, `read_response`) and
`WWW::Authentik::Diff`. Everything with I/O is written independently in the twin.

Two things are more involved in the twin than with Keycloak and belong in the
design of the sync dist from the start, so both stay the same:

- **Pagination.** `list_*` follows `pagination.next`. The loop lives in a method
  `_paged($path, %query)`, which is rebuilt in the twin as `_paged_f` with `repeat`;
  the edge cases (`next: 0`, empty `results`) are in `Diff`-free unit tests of both dists.
- **Name resolution in `ensure_*`.** `ensure_oauth2_provider` resolves flows, certificate and
  scopes before it compares. This resolution is a method of its own, `_resolve(\%rep)`,
  with a table (field → lookup method), so the twin uses the same table
  and only makes the calls asynchronous.

## 10. Tests and phases

- **Unit tests** with mocked HTTP following the pattern of `p5-www-keycloak/t/50-admin.t` and
  `t/60-oidc.t`: every method against the responses observed in section 8, including the
  four error forms, pagination over three pages, 403 instead of 401, 400 instead of 409.
- **`WWW::Authentik::Diff`** pure, without HTTP: lists as sets (also of hashes), added
  defaults (`redirect_uri_type`), merging `attributes`, booleans, nothing to do.
- **Live suite** (`t/90-live-authentik.t`, only with `AUTHENTIK_LIVE_TEST=1 AUTHENTIK_URL=…
  AUTHENTIK_TOKEN=…`): creates user, group, scope mapping, provider, application, flow,
  stage, binding and token with a random prefix, runs every `ensure_*` method twice
  (first `created`, then empty), checks OIDC against the application (discovery, JWKS,
  client credentials, introspect, revoke, device authorization up to `authorization_pending`),
  logs the user in via the flow executor (helper module in `t/lib`), checks `amr: ["pwd"]`,
  sets up TOTP, logs in again and checks `amr: ["pwd","mfa"]`, and deletes everything again.
  The compose file of the throwaway instance lives in `t/authentik/` (without secrets; `.env` following
  `t/authentik/env.example`).

| Phase | Content |
|---|---|
| 1 | Facade, errors, `Role::HTTP`, `API` basic operations from 5.1, `ensure_*` from 5.2, `Diff`, `OIDC`, unit tests, live suite, executor helper module in `t/lib`. First user: Airlock's test setup for `Airlock::Upstream::Authentik`. |
| 2 | `WWW::Authentik::Flow` (executor as a public class, section 11 point 7), blueprint application with waiting for `status`, policies and policy bindings, non-superuser tokens (RBAC) |
| 3 | Sources, outposts, proxy providers, SAML, events |

The twin catches up after each phase.

Dependencies: `Moo`, `LWP::UserAgent`, `HTTP::Message`, `JSON::MaybeXS`, `Crypt::JWT`,
`URI`, `Type::Tiny`, `namespace::autoclean`; HTTPS via `LWP::Protocol::https`. Nothing from
`WWW-Keycloak`.

## 11. Decisions (made 2026-10-04, each as proposed)

1. **Name of the API sub-client: `api` or `admin`?** authentik calls it "API"; there is no
   separate admin API, the same endpoint serves self-service and administration, the token
   decides the permissions. `admin` would match `WWW::Keycloak->admin` and be familiar to
   people switching over, but a naming authentik does not know. **Proposal: `api`**,
   class `WWW::Authentik::API`. The skeleton (`CLAUDE.md`, `www-authentik-core`, the
   agent definitions) still says `Admin` and has to be adjusted after the decision.
2. **Which objects belong in phase 1?** The table in 5.1 is the proposal: everything
   the Airlock setup (provider, application, users with password and TOTP, device flow via
   the brand) and the live suite need, plus groups and tokens, because they are observed
   and trivial. Stages only via the typed endpoints with a `$type` parameter, no
   method per stage type. Blueprints only the five thin calls, without waiting for `status`
   (phase 2). **Proposal: like this.**
3. **Is `WWW::Authentik::Auth` needed?** No. The API token does not expire, authentik
   rejects it with 403, and there is nothing to renew. The third way from section 4
   (OIDC token with scope `goauthentik.io/api`) would be the only reason, and it brings nothing in phase 1:
   the automatically created service account has no permissions, and granting permissions
   means RBAC (phase 2). **Proposal: no `Auth` class; `token` is a string.** Whoever wants
   OIDC tokens for the API in phase 2 gets a `token` coderef or a small
   class that wraps `OIDC->client_credentials_token` with expiry; the facade stays the same.
4. **How does `ensure_*` relate to blueprints?** Blueprints are authentik's own
   declarative, repeatable way (YAML, `state: present`, `identifiers`), are applied
   asynchronously by the worker and report no difference per object; the API for them is
   observed (8.1). `ensure_*` is the programmatic way from Perl with an immediate answer
   and `changed`. Both write into the same tables; an object carries no marker that
   says whom it belongs to (only default mappings have `managed`). **Proposal:** `ensure_*` for
   everything decided from Perl (tests, Airlock setup); blueprints for
   flows with many stages and bindings, if someone wants to maintain them as a file, via
   `create_blueprint`/`apply_blueprint` plus waiting in phase 2. The dist does not protect
   blueprint objects from `ensure_*`; whoever points both at the same object gets
   what they ordered, and the POD says so.
5. **`grant_types` when creating a provider.** Without it the provider is useless
   (`invalid_grant` on everything). Three ways: (a) validation error, (b) a default like
   `[authorization_code, refresh_token]`, (c) all eight. **Proposal: (a)**, so that a
   provider with guessed behavior never comes into being; `create_oauth2_provider` stays raw and
   sends what it gets.
6. **Name resolution in `ensure_*` or raw identifiers?** authentik requires UUIDs and PKs
   where a human knows a slug, name or scope. Without resolution every caller first has to make five
   `find_*` calls; with resolution `ensure_oauth2_provider` has a vocabulary of its own
   (`scopes` instead of `property_mappings`). **Proposal:** resolution only for the fields named in 5.2,
   recognized by the value not being a UUID/integer; raw identifiers still
   pass through. `scopes` is an additional key, `property_mappings` stays allowed;
   both at once are a validation error.
7. **Flow executor as a public class?** Airlock's live tests and this live suite
   need the login over HTTP (8.3). For phase 1 it lives as a helper module in `t/lib`, so
   the public API stays small. **Proposal:** in phase 2 as `WWW::Authentik::Flow`
   (`start($slug)`, `submit(\%answer)`, `cookies`), as soon as Airlock needs it from its own
   `t/` and the shape has been seen twice.
8. **How is the test instance provided?** `t/authentik/docker-compose.yml` is the
   compose file of the throwaway instance (ports on `127.0.0.1`, no Docker socket, no root in the
   worker, image pinned), `t/authentik/env.example` the variables. A developer copies
   `env.example` to `.env`, fills in the four secrets, `docker compose up -d`, waits for
   `/-/health/ready/` (here 115 s) and sets `AUTHENTIK_URL=http://127.0.0.1:9000
   AUTHENTIK_TOKEN=<bootstrap token>`. For CI: a separate job `live` in
   `.github/workflows/ci.yml` that starts the same compose file with generated secrets,
   waits for readiness and runs the live suite; because of the image size (≈1 GB) and start time only
   on `main` and via `workflow_dispatch`, not per pull request. **Proposal: like this;** the
   default run `prove -lr t` stays green without an instance.
9. **What to do with the broken `POST /authenticators/admin/totp/`?** The live suite sets up
   TOTP via the setup flow (8.3), which is the way of a real user anyway.
   **Proposal:** no workaround in the dist, report the bug upstream (no initiative of our own
   here; that is Getty's decision).

## 12. From the review at approval (2026-10-04)

For the plan; where these points contradict or sharpen the text above, they win.

- **The return shape deliberately differs from Keycloak.** `ensure_*` returns `{ object, changed }`
  instead of `{ id, changed }`, and `create_*`/`update_*` return the representation instead of the ID.
  The reason is in 5.2; the facade's POD names the difference for people switching over.
- **Name resolution must not guess.** "Not a UUID/integer" as the detection (point 6)
  confuses a provider named `123` with a PK. The plan defines per field which
  form counts as a raw identifier, and tests the case of a name that looks like an identifier.
- **`verify_token( type => ... )` is a heuristic** (claim `scope`, section 6.1) and is
  named as such in the POD; without `type` the token type is not checked.
- **Enforced TOTP has to be observed before building.** `not_configured_action: deny` on the
  validation stage (6.2, 8.4) is the case Airlock needs: login without TOTP set up,
  the executor's response, and `amr` after the login with TOTP.

## 13. Clarified after the build (2026-10-04)

While building phase 1 and in an independent review with probes against the running
authentik 2026.8.3, points came up that the observation in section 8 had not
covered. They are fixed and pinned by tests; where they contradict the text above,
they win.

### 13.1 Found while building

- **A user agent must not announce `TE`.** LWP sends
  `TE: deflate,gzip;q=0.3` and `Connection: TE, close` by default. authentik does not answer
  **every second** request that carries the connection token `TE` at all: the call hangs until the
  timeout, the next one works, the one after that hangs again. Reproduced with raw sockets,
  so it is authentik's frontend and not LWP:

  | Request | Response |
  |---|---|
  | `Connection: close` four times in a row | 200 four times |
  | `Connection: TE, close` four times in a row | 200, nothing, 200, nothing |
  | `Connection: TE` four times in a row | nothing four times |

  `WWW::Authentik->default_ua` therefore sets `send_te => 0`, which makes `Net::HTTP` leave out the
  headers. An injected `ua` without this setting hangs; the facade's POD
  says so. Without this finding the dist would have been unusable against a real authentik,
  and no unit test against the emulated authentik would have shown it.
- **authentik does not accept the same TOTP code twice.** A login immediately after
  setup or a second login in the same 30-second window is rejected with
  `{"code":[{"code":"invalid","string":"Invalid Token. Please ensure the time on your device
  is accurate and try again."}]}`. The executor helper module therefore waits for the
  next window and sends the code again.
- **The client credentials grant's service account outlives its provider.** authentik
  creates a user `ak-<provider>-client_credentials`
  (`path: goauthentik.io/apps/<slug>`) on the first `client_credentials`; deleting provider and application does not take it
  along. Five runs of the live suite left five users behind. The suite now cleans it up
  itself, and `delete_oauth2_provider` is therefore not a complete cleanup.
- **A stage name belongs to exactly one stage type.** Names are unique across all types, and
  the typed detail endpoint of a foreign type answers 404
  (`GET /stages/user_login/<UUID of a password stage>/` →
  `{"detail":"No UserLoginStage matches the given query."}`). `ensure_stage` let this 404
  through and reported something incomprehensible; it now throws a validation error that says
  which type the name really belongs to. The emulated authentik also served the stage
  via the wrong type and hid the case — it now filters by type.

### 13.2 Found by the independent review

A review without build context, with probes against the same running instance.

- **authentik trims every text field, and `ensure_*` therefore did not converge.**
  Every `CharField` and `TextField` is stripped of whitespace at both ends on save
  (DRF with `trim_whitespace`), observed on `name`, `email`, `slug`,
  `meta_description` and `expression`:

  | sent | stored |
  |---|---|
  | `{"name":"  padded both  "}` | `"padded both"` |
  | `{"expression":"return {}\n"}` | `"return {}"` |
  | `{"meta_description":"two lines\n"}` | `"two lines"` |
  | `{"attributes":{"padded":"  keep me  "}}` | `{"padded":"  keep me  "}` — **not** trimmed |

  A wanted value with whitespace at the edge was thus never reachable: `ensure_*` reported
  `updated` on every run and wrote every time. Observed three times in a row on
  `ensure_scope_mapping` with an expression ending in `\n`. `WWW::Authentik::Diff`
  now treats a stored value as equal if it is exactly the trimmed
  form of the wanted one — only in this direction, so whitespace in `attributes`, which
  authentik keeps, still counts as a difference.

- **`verify_token` accepted the token of another application.** All providers of an
  authentik instance sign with the same key, so the issuer is the
  only thing separating two applications — and with `issuer_mode: global` it is the
  bare instance address for all of them. Two providers, both on `global`, on the running system:
  the access token and the ID token of one were accepted by the `oidc` of the other without
  `audience`. Fixed: `WWW::Authentik::OIDC` has an optional `client_id`,
  which is checked as `audience`, `issuer_names_the_application` says whether the issuer
  names the application, and `verify_token` refuses to verify if it does
  not and neither `audience` nor `client_id` nor `any_audience => 1` is present. With the
  default `issuer_mode: per_provider` nothing changes.
- **A compressed response got lost entirely.** `read_response` measured `decoded_content`,
  but decoded `content`. With an injected user agent that requests `gzip`,
  status 200 came back with `data => undef`, without an error: `get_user` returned nothing,
  `list_*` an empty list, and `ensure_*` would have created duplicates. Now
  `decoded_content( charset => 'none' )` is decoded.
- **A body that does not come from authentik was silent.** A proxy or a wrong
  `base_url` answers HTML or text; the error then carried only the status line. Now
  a trimmed excerpt is in `api_message` and the body (up to 500
  characters) in `WWW::Authentik::Error::API->body`.
- **`scopes => undef` would have removed every assignment.** It was read as an empty list and
  would have taken all property mappings from an existing provider. Now a
  validation error, as is `<field>_name => undef`, which previously lapsed silently,
  and a reference where a name belongs.
- **A `find_*` without a key fetched the whole table** and compared every row with
  `undef`, with a warning per row. Now a validation error.
- **`Diff::_bool` ended in a bare `return`,** which returns nothing in list context
  and would have shifted the second value into the first place. Now `return undef`.
- **`LWP::UserAgent` is pinned to 6.33,** the first version with `send_te`. An
  older one silently does not accept the option (it only warns under `-w`), and the hang from
  13.1 would be back. `default_ua` additionally checks it at runtime.
- **Not confirmed: `check_access` ignores an unknown `for_user`.** The review
  inferred that from `?for_user=1` → `passing: true`, although `/core/users/1/` gives 404. The
  re-check shows something else: a truly unknown key is
  `400 {"for_user": "User not found"}`, and key 1 belongs to authentik's internal
  `AnonymousUser`, which the user endpoints just do not show. Both are now in the
  POD and in the live suite.
