# Future Work

Deferred changes that were consciously scoped out, with enough context to pick
them up cold. Newest first. Remove an entry when it ships.

---

## Muscle-group taxonomy: flat list → region/muscle hierarchy

**Deferred:** 2026-08-12 · **Raised during:** HIT Full Body routine seeding

### The problem

`SeedData.sampleMuscleGroups` is a flat list that mixes two different levels of
granularity:

- **Body regions** — `muscle-arms`, `muscle-legs`, `muscle-back`, `muscle-core`
- **Individual muscles** — `muscle-biceps`, `muscle-triceps`, `muscle-quads`,
  `muscle-hamstrings`, `muscle-glutes`

These overlap rather than nest. `muscle-arms` subsumes biceps and triceps;
`muscle-legs` subsumes quads, hamstrings, and glutes. Nothing in the model says
so, so an exercise tagged `muscle-legs` and one tagged `muscle-quads` are
unrelated as far as any query is concerned. That makes "show me everything that
trains legs" impossible to answer correctly, and it makes per-muscle volume
analytics unreliable — a session mixing both levels double-counts or
under-counts depending on how the exercises happen to be tagged.

### What was done instead (2026-08-12)

The flat list was completed rather than restructured: missing groups added
(calves, forearms, adductors, neck, traps), `muscle-arms` and `muscle-legs`
given real definitions, and 28 exercise→muscle mappings corrected. That fixed
the immediate gap — several exercises had no anatomically correct group to
point at — without touching the model.

Chosen deliberately: the flat fix is contained to seed data plus a catalog
refresh step, while the hierarchy change reaches into exercise ranking,
muscle-based filtering, and the stats aggregates.

### What the hierarchy change would involve

1. A parent/child relation on `MuscleGroup` (a nullable `parentId`, or a
   separate region entity — the latter avoids self-referential rows but adds a
   table).
2. Deciding whether an exercise tags the specific muscle only and regions are
   derived, or whether both are stored. Derived is cleaner and prevents the two
   levels drifting apart, but every consumer must then roll up.
3. Updating consumers to roll up: exercise ranking, muscle-group filters, and
   the stats volume aggregates.
4. Re-sweeping the catalog to tag specific muscles rather than regions, so the
   rollup produces the region tags currently stored by hand.

### Why it matters

Per-muscle volume tracking is a plausible near-term feature, and it cannot be
built correctly on a taxonomy where "legs" and "quads" are siblings. Do this
before that feature, not after.
