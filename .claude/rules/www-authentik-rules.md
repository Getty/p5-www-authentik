# WWW-Authentik House Rules

The shared house rules come from skilletor — bundle `getty-cpan-dist@getty`: engineering
discipline, the delegation lock, the publish gate, karr coordination, CPAN release. They load
as `.claude/rules/.local.*.md`; if they are missing, run `skilletor sync` and publish nothing
until they load. This file adds what is true only here, and wins where it differs.

## What this repo is

Perl client for the authentik identity provider (OIDC + REST API v3). Read first: the callers
and the sibling module (`WWW::Authentik::OIDC` ↔ `WWW::Authentik::API`).

## Agent team

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `www-authentik-worker` (default) |
| Write/extend tests | `www-authentik-test-writer` |
| Write/maintain POD | `www-authentik-doc-writer` |
| Commits, `Changes`, card → done, pre-release audit | `www-authentik-release-manager` |
| Read-only research, audit, gap analysis | `www-authentik-worker` ("read-only, change nothing") |

Behavior-relevant = runtime behavior, the public API (`WWW::Authentik`, `::OIDC`, `::API`), the
sync/async sibling invariant, error handling, tests, performance. Pure prose docs and `Changes`
notes are not.

## Hazards

- **Live tests hit a real Authentik.** Opt-in via `AUTHENTIK_LIVE_TEST=1 AUTHENTIK_URL=…`, off by
  default. Never run them uncontrolled or fanned out; a default `prove -lr t` must pass with them
  skipped.
- **API calls change a real identity system.** Application, provider, flow and user mutations
  are not test fixtures on a shared instance; live tests create and remove their own throwaway
  objects.
- **Sync/async twin.** `p5-net-async-authentik` mirrors this repo's public API with `_f` suffixes
  and Futures. An API change here is incomplete until the twin matches — ticket the twin, never
  edit it.
- **Authentik facts come from a running instance or its documentation,** never from memory.
  Endpoint paths and claim contents differ between versions.
- **Test runner trap.** Plain `prove -l t/` is non-recursive; always use `prove -lr t` so subdir
  tests are never silently skipped.

## Perl specifics — reference, don't restate

Module loading, Moo patterns, dependency pinning, `[@Author::GETTY]` release metadata, POD
directives, and house style live in skills `getty-perl-core`, `getty-perl-moo`,
`perl-release-dist-ini`, `getty-perl-release-author-getty`, and `www-authentik-core`
(force-loaded for `www-authentik-*` agents).
