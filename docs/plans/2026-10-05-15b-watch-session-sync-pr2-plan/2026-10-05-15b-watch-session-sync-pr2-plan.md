# Feature: watch-session-sync PR 2 — wrist logging surface over the in-memory store (OUTLINE)

> Status: SKELETON — full plan written when this PR is opened
> Next handoff: (deferred until PR 1 merges)
> Binding conventions: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md`
> Series: `docs/plans/2026-10-05-15-watch-session-sync-index.md`

## Goal

Host the wrist's own logging surface so the shared session has two logging endpoints: replace the
shell's post-start placeholder with the already-built `WatchLoggingView`/`WatchLoggingModel`/
`WatchLoggingState`, `WatchEndSessionView`, and `WatchEffortRatingView`, over the in-memory
`WatchSessionStore`. Wrist-logged sets already flow to the phone via the existing `observations_up`
→ inbox → import-on-end path, so this PR delivers "log on the wrist, see it on the phone's history"
without any protocol change.

## Scope

- Wire the logging/end/rating views into the shell's post-start surface (watchOS target; keep logic
  in the Swift package so `swift test` covers it).
- Log sets on the wrist into the in-memory store; send `observations_up` (idempotency + receipt ack
  per PROTOCOL.md) so the phone imports them on session end.
- End session on the wrist → `session_lifecycle` `completed` with `effort_rating`.
- No phone-side changes beyond what PR 1 already landed; no protocol change.

## Risks / open items

- watchOS views compile only in a watch target: keep them thin; put behavior in the package.
- Set-logging entry identity must match the phone's importer's expectations (`observations_up`
  shape) or entries will be dropped at import — re-check against `WatchSessionImporter`.
- In-memory store durability: a watch-session lost on wrist relaunch stays a known gap (PR 4).

## Predicted Files (folder level)

- `watch/watchos/Sources/WatchSessionEngine/` — the logging/end/rating views + store writes.
- `watch/watchos/Tests/` — new `swift test` coverage for the logging/end/rating flows.
- No `lib/` or `watch/sync_protocol/` changes expected.

## Note

Full Decision Ledger, fixture-enumerated scenarios and per-phase Done Criteria are written when
this PR opens, against PR 1's merged session-identity decisions.
