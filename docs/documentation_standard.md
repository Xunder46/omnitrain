# Documentation Standard

**Scope of this document.** This standard governs every Markdown file under
`docs/`. It defines what those documents are permitted to
contain and what they must never contain. It does not govern planning
artefacts (`docs/plans/`), agent instruction files, pipeline command
files, release notes under `docs/releases/`, or code comments.

**Read this in full before creating or editing any document in that folder.**

---

## 1. Why this standard exists

Documentation was being used to describe *what the app does*. That is a
category error.

Behaviour changes every sprint. Prose does not get recompiled, so a prose
description of behaviour goes stale silently — it keeps reading as
authoritative long after it stopped being true. Agents then plan against it and
produce incorrect work. This has already happened repeatedly in this
repository.

Tests describe behaviour and **fail when they go false**. That is the property
prose cannot have.

So the division of labour is:

| Question | Answered by |
|---|---|
| What does the app *do*? | Tests |
| What *is* the code, and *why* is it that way? | Documentation |

Documentation describes the things that survive a sprint: the shape of the
system, the reasoning behind it, the rules that must hold, and the words we
use. Everything else belongs in a test.

---

## 2. Permitted content — exactly four categories

A document in this folder may contain these four kinds of content and nothing
else.

### 2.1 Structure

What components exist, what each one is responsible for, where things live, and
how areas relate to one another.

Examples of permitted structure content: the screen inventory; which state
class owns which concern; the dependency graph; which file a primitive lives
in; the fact that `SessionCore` delegates timer creation to `TimerManager`.

### 2.2 Rationale

Why a design decision was made, what alternatives were considered and
rejected, and what problem the design solves.

Examples: why capabilities are flags rather than a join table; why round
timers use wall-clock timestamps rather than a `Stopwatch`; why the route-level
gradient doubling during a transition was accepted rather than fixed.

Rationale is the highest-value content in this folder, because it is the one
thing that cannot be recovered by reading the source.

### 2.3 Invariants and contracts

Rules that must always hold, cross-cutting constraints, and the consequences of
violating them.

Examples: state classes depend only on the `WorkoutRepository` interface;
navigation goes through `OmniNavigator`; effort classification derives from
`effortKind`, never the session modality; canonical values are stored in base
units and converted only at boundaries.

Every invariant must name where it is enforced (see §4.2).

### 2.4 Domain vocabulary

Definitions of internal terminology and concepts, so an agent understands what
our terms mean.

Examples: what a *modality*, an *effort kind*, a *capability*, a *rolling
session*, a *training period*, or the *current-state window* is.

---

## 3. Prohibited content — never include these

### 3.1 Step-by-step user flows or interactions

Numbered walkthroughs of what a user does and what the app does back
("1. User taps the tile → 2. System opens the picker → 3. …"). This is
behaviour; it belongs in a test.

### 3.2 Descriptions of visual presentation

Sizes, colours, hex values, icons, positions, labels, spacing, opacity,
typography, or layout. The rendered surface changes constantly and the source
is the only honest record of it.

### 3.3 Gesture, control, or input inventories

Tables or lists of gestures, buttons, taps, swipes, drags, long-presses, or
keyboard affordances and what each one triggers. This is the single most
drift-prone content type we have produced.

### 3.4 Any numeric value defined elsewhere in the codebase

Thresholds, durations, defaults, dimensions, caps, counts. Name the constant
and where it lives; never restate its value. A number copied into prose is a
second source of truth that no test guards.

### 3.5 Copied implementation content

Pasted code blocks, method bodies, field lists mirroring a class declaration,
or SQL reproduced from a schema file. Point at the file instead. Copied code is
stale the moment it is copied.

### 3.6 Roadmap, planned, or future-feature sections

"Future Enhancements", "Planned Features", "Phase 2 / Phase 3", "Deferred",
"Still deferred", "Recommended extension points", "forward-looking", "Not in
v1". Documentation describes **what exists**. Unbuilt ideas belong in planning
artefacts.

This category has a specific failure mode worth naming: a planned item ships,
nobody deletes the roadmap entry, and the document now asserts that a shipped
feature does not exist.

### 3.7 Scheduled-change or "not current" annotations

Notes describing behaviour that a pending PR *will* introduce or remove. These
invert the moment the PR lands: the doc then describes shipped behaviour as
future and removed behaviour as current. Keep the delivery plan in the plan.

### 3.8 Duplicated or superseded document bodies

A document must contain exactly one version of itself. Do not append an older
revision below a newer one, and do not carry a second copy of a section that
another document already owns.

---

## 4. Structural requirements

### 4.1 Every document states its scope at the top

The first content in every document, before any other section, must state:

- **what the document covers**, and
- **which parts of the codebase it describes** (paths, directories, or class
  names).

A reader must be able to tell from the top of the page whether this document is
the right one, and what source it is accountable to.

### 4.2 Point to verification instead of describing behaviour

Where a document would otherwise describe behaviour, it must instead point to
where that behaviour is verified — the test file, and the test or group name
where it is meaningful.

> The empty session does not auto-open the exercise picker.
> Verified by `test/pr6_routine_session_entry_navigation_test.dart`
> (`S-003 empty session no longer auto-opens picker`).

This is the mechanism that makes the standard work. The pointer stays correct
because a renamed or deleted test is a build failure, and the described
behaviour stays correct because the test fails when it goes false.

If a behaviour has no test, do not describe it. Either write the test or leave
it undocumented — an unverified prose claim is worse than silence, because it
carries the same authority as a verified one.

---

## 5. Applying this standard

**Writing a new document.** Start with the scope block. Then ask of every
paragraph: is this structure, rationale, an invariant, or vocabulary? If it is
none of those four, it does not belong.

**Editing an existing document.** Bring the section you touch into conformance.
Do not leave a conforming section next to a prohibited one without flagging it.

**Reviewing.** Prohibited content is a review blocker, not a suggestion. A
missing scope block is a review blocker. A behavioural claim with no
verification pointer is a review blocker.

**When behaviour genuinely needs recording** — because it is subtle, costly to
rediscover, or the reason a bug was fixed — the correct action is to write a
test. The test is the record. The document may then point at it.

---

## 6. Named exceptions — exactly two, scoped

These two documents are exempt from one prohibition each. **The exemptions are
exhaustive and narrow. Neither extends to any other document, and neither
extends within its own document beyond the scope written here.** A passage that
falls outside the scope below is prohibited in these documents exactly as it is
everywhere else.

### 6.1 `design_system.md` — visual rules, never values

**Exempt from:** §3.2 (descriptions of visual presentation).

**Scope of the exemption.** It is the single owner of visual *rules* and the
reasoning behind them: the design philosophy, the visual identity, the
mandatory shape rule, the bottom-CTA width and anchor rule with its forbidden
patterns, the section-header contract, and the component naming conventions.
Every other document defers to it rather than restating any of this.

**Explicitly NOT exempt.** It is not an owner of **values**. §3.4 applies to it
in full:

- No hexadecimal colour literals. Ever. `lib/core/constants/omni_theme.dart` is
  the sole owner of colour values, and the only place they may appear.
- No sizes, spacings, radii, durations, or opacities. Name the token and say
  what it is for; never state what it equals.
- No change-log narratives and no open to-do lists. Those belong in planning
  material and issue tracking respectively.

The distinction is: *"buttons are slightly-rounded rectangles, never pills, and
every button must set `shape` explicitly"* is a rule and belongs here.
*"`buttonBorderRadius` is 12.0"* is a value and does not.

### 6.2 `data_models.md` — relationships, never field lists

**Exempt from:** §3.5 (copied implementation content), for structural
description of the model graph only.

**Scope of the exemption.** It is the owner of how our data structures relate to
one another: which record owns which reference, what cascades on delete, what
freezing a snapshot means and which fields are frozen, which models are
persisted versus derived, and the lifecycle and terminal-state rules that govern
them.

**Explicitly NOT exempt.** It is not an owner of **field lists**. Per-class
field tables mirroring `lib/data/models/models.dart` are prohibited — the model
source owns those. This matters more here than anywhere else: copies of these
tables were found drifting inside other documents while still reading as
authoritative, which is the exact failure this standard exists to prevent.

The distinction is: *"`ConsumedFood` freezes the food's name, macros, and
reference amount at log time, so editing a library food never rewrites
history"* is a relationship and a lifecycle rule, and belongs here. A table
listing `ConsumedFood`'s twelve fields with their types does not.

---

## 7. Relationship to other rules

- `global_conventions.md` remains the authoritative list of cross-cutting
  engineering rules. It is an invariants document under §2.3 and is expected to
  conform to this standard.
- The 64 KiB per-file size ceiling enforced by
  `test/docs_indexing_contract_test.dart` continues to apply. Conforming to this
  standard should make most documents substantially shorter.
- Superseded snapshots under `docs/history/` are exempt from
  §2 and §3: they are deliberately frozen records of a past state. They must
  carry a `HISTORY` banner and must never be presented as current. They are
  **not** exempt from §4.1 — a history document must still state its scope and
  the date it froze.
- Dated audit records (this standard's own audit, `docs-audit-2026-07-26.md`)
  are likewise frozen records rather than reference documentation, and are
  exempt from §2 and §3 for the same reason.

---

## 8. The short version

> Documentation says what the code **is** and **why**.
> Tests say what it **does**.
> If prose would go stale, it belongs in a test.
> If a document cannot name where a claim is verified, the claim does not go in
> the document.
