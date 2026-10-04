# CLAUDE.md

WWW::Authentik — synchronous Perl client for authentik: OIDC against an application (discovery, JWKS, token verification, token and device endpoints) plus the REST API v3 (applications, providers, flows, users), a structural sibling of `WWW::Keycloak`. Moo-based; released to CPAN via Dist::Zilla `[@Author::GETTY]`.

Async twin: `p5-net-async-authentik` (`Net::Async::Authentik::*`), same API surface with `_f` suffixes returning Futures — keep them in sync. Skeleton state: nothing is implemented yet; the design goes to `docs/superpowers/specs/`, the work is on the karr board.

## Delegation

Delegate behavior-relevant code to the right agent instead of touching it yourself —
principle and lane are in `.claude/rules/www-authentik-rules.md`.

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `www-authentik-worker` (default) |
| Write/extend tests | `www-authentik-test-writer` |
| Commits, `Changes`, card → done, pre-release audit | `www-authentik-release-manager` |
| Write/maintain POD | `www-authentik-doc-writer` |

The agents carry their skills via `briefing.skills` (see `.claude/agents/`); the main
agent delegates rather than loading them. Skill sources live under `.claude/skills/`.

## Commands

```bash
prove -lr t          # full test suite (recursive; live tests skip by default)
dzil build           # build the distribution
dzil test            # test via Dist::Zilla
```

`LICENSE` is committed, not generated at build time; re-run `dzil genlicense` and
`git add LICENSE` after changing license, holder or year in `dist.ini`.
