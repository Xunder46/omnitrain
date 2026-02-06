# Universal Fitness Tracking App
## Consolidated Product & System Agreements

---

## 1. Product Goal & Scope

### Core Objective
- Enable **fast, low-friction workout logging**
- Support **any athlete / any sport**
- Provide **clear progress visibility** without heavy analytics

### Explicit Non-Goals (v1)
- Coaching-first experience
- Social network features
- Nutrition tracking
- Advanced predictive analytics

---

## 2. Foundational Design Principles

- Logging must be possible without understanding the full system
- Default paths > configuration
- Templates > blank states
- Inference > manual categorization
- Blocks > sport-specific rigid schemas
- One app, not multiple sport modes

---

## 3. High-Level System Architecture

### Core Entities
- **User**
- **SportProfile**
- **Session**
- **Block**
- **Exercise** (used only within certain Blocks)
- **Metric**
- **Template**

---

## 4. Session Model

### Session Definition
A Session represents one training event.

### Session Properties
- Date / time
- SportProfile (primary context)
- Modality (derived or editable)
- Intent (derived or editable)
- List of Blocks
- Notes
- Completion state

Sessions are immutable in identity but fully editable in content.

---

## 5. Block-Based Logging System

### Block Definition
A Block defines:
- how work is structured
- which metrics are logged
- how repetition occurs

### Core Block Types (MVP)

#### Strength Sets
- set index
- reps
- load
- RPE (optional)
- rest (optional)
- warmup flag
- notes

#### Timed Activity
- duration
- effort / intensity (optional)
- notes

#### Distance Intervals
- interval count
- distance per interval
- time or pace per interval
- rest between intervals
- notes

#### Round-Based
- round duration
- number of rounds
- intensity
- notes

#### AMRAP / For Time
- time cap
- score (reps / rounds / distance)
- notes

#### Drill / Skill
- reps or duration
- quality rating (optional)
- notes

#### Freeform
- text only

---

## 6. Metric System

### Core Metric Types
- time
- distance
- repetitions
- load
- sets
- rounds
- pace / speed
- heart rate (optional)
- RPE / effort
- notes

### Metric Rules
- Metrics are **attached to Blocks**, not Sessions
- Blocks declare supported metrics
- Metrics are optional unless required by Block type
- New metrics can be added without schema changes (extensible)

---

## 7. Taxonomy & Classification

### Three-Layer Model

#### SportProfile (Context)
- Running
- Bodybuilding
- Powerlifting
- Boxing
- BJJ
- Soccer
- Cycling
- Swimming
- Custom

Used for:
- templates
- default units
- suggested Blocks

#### Modality (Functional Type)
- Cardio / Endurance
- Strength / Resistance
- Skill / Technique
- Conditioning / Mixed
- Mobility / Flexibility
- Recovery / Rehab
- Competition / Match

#### Intent (Session Purpose)
- Easy / Base
- Intervals / Speed
- Tempo / Threshold
- Strength
- Hypertrophy
- Power
- Technique / Drills
- Sparring / Live
- Recovery
- Test / Benchmark

### Classification Rules
- Modality and Intent are auto-derived from Templates
- User can override but is not required to choose
- Used for filtering, summaries, and progress grouping

---

## 8. Home Screen Structure

### Primary Entry Categories
(Answer: “What kind of session am I doing today?”)

- Cardio / Endurance
- Strength / Resistance
- Martial Arts / Combat
- Sports / Games
- Mobility / Flexibility
- Recovery / Rehab

### Secondary / Nested Categories
- Conditioning / HIIT
- Skill / Technique
- Isometrics / Calisthenics

Home screen never shows individual exercises.

---

## 9. Templates

### Template Definition
A Template is:
- predefined Session structure
- pre-filled Blocks
- inferred Modality + Intent

### Template Rules
- Templates are sport- and equipment-aware
- Templates can be duplicated and customized
- Templates are the primary entry point for new users

---

## 10. Exercise Model

### Exercise Scope
- Exercises exist **only within Strength Sets Blocks**
- Other Blocks are exercise-agnostic

### Exercise Properties
- name
- movement pattern
- muscle group(s)
- equipment type
- aliases / synonyms

### Exercise Selection Rules
- Never present full library by default
- Always filtered by:
  - equipment
  - movement or muscle
- Default recommendations ≤ 15 items
- Custom exercises allowed with minimal input

---

## 11. New User Flow

### Onboarding Inputs
- Primary training type(s)
- Primary goal
- Available equipment

### Onboarding Outputs
- Default SportProfile
- Initial Templates
- Default Home Screen category ordering

No mandatory tutorials or explanations.

---

## 12. Typical Usage Patterns (System-Level)

### Endurance Athlete
- Sessions dominated by Timed and Distance Blocks
- Minimal interaction with Exercise entity
- Progress derived from time, distance, pace trends

### Strength Athlete
- Sessions dominated by Strength Sets Blocks
- Heavy reuse of previous Session data
- Progress derived from load, reps, volume, PRs

### Combat / Sport Athlete
- Sessions dominated by Round-Based and Drill Blocks
- Notes and intensity more important than numeric precision

All patterns use the same underlying data model.

---

## 13. Progress & History (Structural)

### History
- Calendar-based Session listing
- Session duplication supported
- Editing past Sessions allowed

### Progress (MVP)
- Block-type-specific trends
- Exercise-specific trends (for Strength only)
- Bodyweight and measurements optional

No global “score” or gamification required.

---

## 14. UX Constraints (Hard Requirements)

- ≤ 10 seconds to start a workout
- Auto-fill from last Session
- Minimal tap count per logged action
- Offline-first logging
- No forced notifications or nudges
- No required categorization during logging

---

## 15. MVP Boundary

### Must Have
- Session + Block system
- Core Block types
- Templates per Home category
- Exercise filtering and creation
- History + basic progress

### Deferred
- Advanced analytics
- Coaching logic
- Social features
- Nutrition tracking
- Wearable integrations (can be layered later)