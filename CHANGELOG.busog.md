# Changelog — busoglabs fork patches

Release notes for the **busoglabs/parse-server-swift** fork. Upstream's own
notes live in `CHANGELOG.md`; this file exists separately so rebases onto
upstream never conflict. One entry per fork tag; each tag = upstream at the
rebase point + every patch listed up to that entry.

Fork discipline: clean patches only, **rebase never merge**; after an upstream
sync, retag as `1.0.4-busog.N+1` and bump the `exact:` pin in
lokalitycloud/busogcloud `Package.swift`. (Consumers pin `exact:` because these
tags are semver prereleases of 1.0.4 — a plain upstream `1.0.4` tag would
outrank them in a `from:` range.)

---

## [1.0.4-busog.3] — 2026-07-21

### Changed
- `PARSE_SERVER_SWIFT_SERVER_URL` is now **validated** (must be a full http(s)
  URL with a host, else boot fails fast with a clear `ParseError`) and resolved
  by a single `resolveServerPathname` helper used by both initializers — a
  set-but-empty or scheme-less value previously slipped through and silently
  killed every hook registration while the app looked healthy.

## [1.0.4-busog.2] — 2026-07-18

### Added
- `PARSE_SERVER_SWIFT_SERVER_URL` — advertised webhook-URL override. Hooks were
  always registered under the bind address, which is unreachable behind a proxy
  or on a PaaS (Heroku binds `0.0.0.0:$PORT`); the override advertises the
  public URL instead.

## [1.0.4-busog.1] — 2026-07-17

### Added
- In-memory primitive store — stops keychain prompts on every recompile
  (`f9c9f3c2`). First clean fork tag after the history rewrite (old messy tip
  recoverable at `530bd02f`).
