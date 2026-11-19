# Review — 125d (lead's own read; no reviewer run, token spend)

Verdict: APPROVE, no blockers. Read: the three production hunks, the schema, the Swift and Dart `knownModality`, every fixture manifest entry, the docs diffs.

- Wire: the schema adds only an optional `modality` (string, `minLength` 1), no enum, `required` unchanged; the emit omits the key when the session has none or an empty one; converged-state frames are untouched (S-12599 (f) pins it).
- Wrist: one statement and one argument per client; the stamp reads only when the snapshot creates the wrist row, so a held session keeps its modality and nil stays nil (S-12595 a-e, killed mutants S1/D1/S3/D3). The filter drops display names, wrong case, padded and unknown keys (S4/D4).
- Minor, accepted: an unknown but well-typed key (a future modality) applies as a snapshot and stamps nothing, so the session falls back to the exercises' majority: the documented behaviour of an older wrist.
- Minor, accepted (A-6/OQ-2): a session the wrist created itself and the phone adopted keeps the wrist's modality or none; the phone's calendar keeps the phone's.
- Not verified here: the Apple Health type, the location prompt and the round words on a real watch (QA step 43, owner checks); no simulator run (owner rule).
- Noticed, not in scope: 125b's `WatchRoutine.startModality` and `knownModality` are the same filter; a later tidy can make one call the other.
