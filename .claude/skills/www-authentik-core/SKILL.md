---
name: www-authentik-core
description: Use when working on WWW::Authentik — the synchronous Perl client for authentik's OIDC endpoints and REST API (v3), its module layout, error classes, or its tests.
---

# WWW::Authentik core

Synchronous Perl client for authentik, a structural sibling of `WWW::Keycloak`
(`~/dev/p5-www-keycloak`). **Phase 1 is built** against authentik 2026.8.3. The approved
design is `docs/superpowers/specs/2026-10-04-www-authentik-design.md` and the plan is
`docs/superpowers/plans/2026-10-04-www-authentik-phase-1.md`; where they and the map below
disagree, the design wins. Phase 2 and 3 are in section 10 of the design.

## Module map

- `WWW::Authentik` — facade: `base_url`, optional `application` (slug), optional API
  token; lazy `oidc` and `api` sub-clients sharing one `LWP::UserAgent` (injectable via
  `ua`).
- `WWW::Authentik::OIDC` — discovery, JWKS, token verification, userinfo, introspection,
  token endpoint helpers, device authorization endpoint.
- `WWW::Authentik::API` — REST API v3 with direct methods (`list_users`,
  `create_application`) and repeatable `ensure_*` methods; no nested sub-client objects.
  `list_*` follows authentik's pagination. `resolve` turns names into identifiers, one
  fixed shape per field, with `<field>_name` / `<field>_slug` to force the lookup.
- `WWW::Authentik::Diff` — compare a current object with the wanted state, without I/O.
- `WWW::Authentik::Role::HTTP` — `build_request` and `read_response` split from sending,
  so the async twin reuses them.
- `WWW::Authentik::Error` — base; `::Validation`, `::Network`, `::API` (with
  `http_status`, `api_message`, `field_errors`, `oauth_error`, `request_id`), one package
  per file.

## Invariants

- **Shape follows `WWW::Keycloak`, the code is its own.** OIDC, Diff and the HTTP role
  are copied and adapted, not shared: this dist does not depend on `WWW::Keycloak`
  (decided 2026-10-04). Two returns differ on purpose: `create_*`/`update_*` give back the
  representation, and `ensure_*` gives back `{ object, changed }`.
- **A duplicate is 400 with a field error, not 409; a refused token is 403, not 401.**
  There is no `is_conflict`.
- **The user agent must not announce TE.** authentik 2026.8.3 leaves every second such
  request unanswered; `WWW::Authentik->default_ua` sets `send_te => 0`.
- **authentik refuses a TOTP code twice.** A second login inside the same 30 second window
  fails; the test helper waits for the next one.
- **Sync/async twin.** `Net::Async::Authentik` (`~/dev/p5-net-async-authentik`) mirrors the
  public API with `_f` suffixes returning Futures. This repo leads; an API change here is
  incomplete until the twin has a ticket for it.
- **authentik facts are verified, not remembered.** Endpoint paths, payload shapes and
  claim contents differ between versions. Before encoding one, check a running instance
  or the documentation of the targeted version, and say which version in the POD.
- **There is no realm.** OIDC is addressed per application slug
  (`/application/o/<slug>/` for discovery and JWKS; token, device and userinfo endpoints
  are instance-wide); the API lives under `/api/v3/` and takes a bearer API token. This
  is from the documentation as of 2026-10-04 — confirm against the instance.
- **Live tests are opt-in** (`AUTHENTIK_LIVE_TEST=1 AUTHENTIK_URL=…`) and create and remove
  their own throwaway objects. A default `prove -lr t` passes with them skipped.

## Key files

- `lib/WWW/Authentik.pm` — facade, `default_ua`, the lazy `oidc` / `api` accessors
- `lib/WWW/Authentik/OIDC.pm` — the OIDC side: discovery, JWKS, token, userinfo, device
- `lib/WWW/Authentik/API.pm` — the REST side: direct methods, `ensure_*`, `resolve`
- `lib/WWW/Authentik/Diff.pm` — the comparison without I/O
- `lib/WWW/Authentik/Role/HTTP.pm` — `build_request` / `read_response` / `send_request`
- `lib/WWW/Authentik/Error.pm`, `lib/WWW/Authentik/Error/{Validation,Network,API}.pm`
- `t/lib/FakeAuthentik.pm` — the in-memory authentik (see below)
- `t/lib/AuthentikExecutor.pm` — the flow executor as a browser would drive it
- `t/authentik/docker-compose.yml`, `t/authentik/env.example` — a local instance to test
  against
- `docs/superpowers/specs/2026-10-04-www-authentik-design.md` — the approved design
- `docs/superpowers/plans/2026-10-04-www-authentik-phase-1.md` — the plan

## Test layout

| File | Covers |
|---|---|
| `t/00-load.t` | `all_uses_ok` over the `WWW::Authentik` namespace |
| `t/10-diff.t` | `Diff` — comparison without I/O, lists as sets |
| `t/20-errors.t` | the error classes and the fields they carry |
| `t/21-http.t` | `Role::HTTP` — `build_request` / `read_response` |
| `t/40-facade.t` | the facade — lazy sub-clients, one shared UA |
| `t/50-api.t` | the REST API v3 — direct methods, pagination |
| `t/51-api-ensure.t` | the `ensure_*` methods — `{ object, changed }` |
| `t/52-api-resolve.t` | `resolve` — names to identifiers, `<field>_name` / `<field>_slug` |
| `t/60-oidc.t` | discovery, JWKS, userinfo, introspection |
| `t/61-oidc-token.t` | the token endpoint, the device flow, revocation |
| `t/62-oidc-jwks.t` | JWKS and token verification against a local RSA key |
| `t/90-live-authentik.t` | the live suite — off unless the env vars are set |
| `t/cpanfile.t` | every module used in `lib/` and `t/` is declared in the `cpanfile` |

`t/lib/` holds the harness. `FakeAuthentik` is an in-memory authentik that answers the
way the real one was observed to answer (design spec, section 8): 201 with the whole
object and no `Location` header on a create, 400 with a field error for a duplicate,
403 for a token it does not know, 404 with `No <Model> matches the given query.`, the
OAuth shape at the token endpoint and a bare `WWW-Authenticate` header at the userinfo
endpoint. `AuthentikExecutor` drives authentik's flow executor over HTTP the way a
browser would, so the live suite can log a user in and read what the token says about
the second factor — the shape of a challenge is authentik's own and changes between
versions, so it is not part of the public API. The test files load the harness
themselves with `use lib 't/lib'`.

## Hazards

- **The live suite talks to a real identity system.** `t/90-live-authentik.t` skips
  unless `AUTHENTIK_LIVE_TEST=1`, `AUTHENTIK_URL` and `AUTHENTIK_TOKEN` are set. It
  prefixes every object it creates and deletes it again at the end; an aborted run
  leaves throwaway objects behind on the instance.
- **`prove` must be recursive** (`prove -lr t`). A non-recursive run (`prove -l t/`)
  only picks up `t/*.t` — a test that lands in a subdirectory later is silently
  skipped and the run still reports green.
- **A duplicate is 400, a refused token is 403.** authentik does not answer 409 and
  there is no `is_conflict`; a test that expects a conflict fails on the error class.
- **The user agent must not announce TE.** Every second request announcing the TE
  token goes unanswered, so `default_ua` sets `send_te => 0` — a UA built by hand
  without that flag hits a hanging request.
- **authentik refuses a TOTP code twice.** A second login inside the same 30 second
  window fails; the test helper waits for the next one.
- **A new module needs a `cpanfile` entry.** `t/cpanfile.t` fails when a module used
  in `lib/` or `t/` is not declared — the distribution that carries it (`CryptX` for
  `Crypt::PK::RSA`, `HTTP::Message` for `HTTP::Request`, …) is known to the test.

## Purpose beyond the client

This dist is the basis for a repeatable authentik setup from Perl (applications,
providers, flows, users) and gives `Airlock` (`~/dev/p5-airlock`) a second identity
provider to be tested against. Airlock does not depend on this dist at runtime.
