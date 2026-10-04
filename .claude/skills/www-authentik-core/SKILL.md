---
name: www-authentik-core
description: Use when working on WWW::Authentik — the synchronous Perl client for authentik's OIDC endpoints and REST API (v3), its module layout, error classes, or its tests.
---

# WWW::Authentik core

Synchronous Perl client for authentik, a structural sibling of `WWW::Keycloak`
(`~/dev/p5-www-keycloak`). **Skeleton state: nothing is implemented yet.** The approved design is
`docs/superpowers/specs/2026-10-04-www-authentik-design.md`; where it and the map below
disagree, the design wins.

## Planned module map

- `WWW::Authentik` — facade: `base_url`, optional `application` (slug), optional API
  token; lazy `oidc` and `api` sub-clients sharing one `LWP::UserAgent` (injectable via
  `ua`).
- `WWW::Authentik::OIDC` — discovery, JWKS, token verification, userinfo, introspection,
  token endpoint helpers, device authorization endpoint.
- `WWW::Authentik::API` — REST API v3 with direct methods (`list_users`,
  `create_application`) and repeatable `ensure_*` methods; no nested sub-client objects.
- `WWW::Authentik::Diff` — compare a current object with the wanted state, without I/O.
- `WWW::Authentik::Role::HTTP` — `build_request` and `read_response` split from sending,
  so the async twin reuses them.
- `WWW::Authentik::Error` — base; `::Validation`, `::Network`, `::API` (with
  `http_status`, `api_message`), one package per file.

## Invariants

- **Shape follows `WWW::Keycloak`, the code is its own.** OIDC, Diff and the HTTP role
  are copied and adapted, not shared: this dist does not depend on `WWW::Keycloak`
  (decided 2026-10-04).
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

## Purpose beyond the client

This dist is the basis for a repeatable authentik setup from Perl (applications,
providers, flows, users) and gives `Airlock` (`~/dev/p5-airlock`) a second identity
provider to be tested against. Airlock does not depend on this dist at runtime.
