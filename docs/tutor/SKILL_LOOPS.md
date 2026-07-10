# Tutor and the Sigma Skill Loops

How the existing skill methodology (mining, iteration cycles, meta-review,
promotion) applies to tutorials. Companion to `DESIGN.md`.

A note on provenance: the loop cadence and stages below mirror the pipeline
already running in this ecosystem (`awesome-godot-miner` daily,
`template-iteration-cycle` every 3 hours, `template-meta-review` weekly,
feeding the `godot-*` skill library). The sigma tier definitions in Section 2
are written out explicitly here because no canonical written definition was
found in the repos; treat this file as the draft canon and correct it where
it diverges from the intended methodology.

## 1. Why tutorials fit the skill loop

A disseminated tutorial is a claim: "these locators ground, these actions
work, these conditions detect completion, in this editor version." Claims
rot (editors update, sources were wrong, dissemination hallucinated a
button). The skill loop is the machinery that continuously tests the claim
and only promotes artifacts that survive testing. The key enabler from
`DESIGN.md` is that every completion checker runs headless via each
program's CLI, so most of the loop needs no human.

## 2. Sigma tiers

Each `*.tutorial.json` carries a `sigma_tier` (0..4). A tier is earned, never
assigned by the author.

| tier | name | gate | verified by |
|---|---|---|---|
| 0 | mined | exists; parses as JSON | miner |
| 1 | linted | schema-valid; no undefined locator/condition kinds; every non-`manual` condition well-formed; `manual` conditions justified in `detail` | schema validation, offline (any CI) |
| 2 | grounded | every locator resolves in a clean project on the pinned `editor_version` | headless locator lint: `godot --headless -e` / `blender -b --factory-startup` |
| 3 | replayed | every `replayable` step's machine action executes and its own completion condition then passes, in order, headless | replay harness (DESIGN.md 5.4 / 6.4) |
| 4 | guided | N or more human guided runs with per-step auto-detection accuracy at or above threshold (start: N=3, accuracy 95%, no step with 2+ false detections) | run telemetry + meta-review |

Demotion is automatic: an editor version bump re-runs the tier-2 and tier-3
gates; any failure drops the tutorial back to tier 1 with the failing steps
annotated, and it re-enters the iteration cycle.

Defect definitions for tier 4 telemetry (per step, per run):

- **ground failure**: locator did not resolve (fell back to text-only).
- **detection miss**: user pressed Done manually and the condition was
  actually satisfied (checker too strict or too slow).
- **false fire**: step auto-advanced before the user performed the action.
- **content defect**: user pressed Skip (instruction wrong or impossible).

## 3. The three loops, retargeted

### 3.1 Miner (daily)

Same shape as `awesome-godot-miner`. Sources, in priority order: official
Godot docs tutorials, official Blender manual walkthroughs, the
`awesome-godot` fork's curated tutorial links, and (later) video sources via
the Video-to-SOP-style vision pass. Each run: pick the next source, ingest,
disseminate, write a tier-0 `*.tutorial.json` into the library, run the
tier-1 lint immediately (cheap), and log what was mined. Output lands in a
`tutorials/` library directory (repo TBD; likely wherever the `godot-*`
skills live today so the dashboard can list both).

### 3.2 Iteration cycle (every 3 hours)

Same shape as `template-iteration-cycle`. Each run picks the
lowest-tier/oldest item and attempts exactly one tier promotion:

- tier 0 -> 1: run lint; on failure, re-disseminate with the lint errors fed
  back into the prompt (self-repair), max 2 attempts before parking it for
  meta-review.
- tier 1 -> 2: run the headless locator lint for the pinned editor version;
  on failure, attempt locator repair (the failing locator plus a dump of
  candidate controls/areas goes back to Claude for a corrected locator).
- tier 2 -> 3: run the replay harness; on failure, attach the JSON report
  and park for meta-review if self-repair fails twice.
- tier 3 -> 4: cannot be automated; the cycle's only job is to surface
  tier-3 tutorials as "ready to guide" so human runs accumulate telemetry.

One promotion attempt per run keeps each cycle bounded and keeps failures
isolated to a single artifact, which mirrors how the template cycle behaves
today.

### 3.3 Meta-review (weekly)

Same shape as `template-meta-review`. Inputs: the week's telemetry files,
parked items, and demotions. Jobs:

1. Promote tier-3 tutorials whose telemetry clears the tier-4 gate; demote
   tier-4 tutorials whose live defect rates degraded.
2. Triage parked items: fix, rewrite, or retire.
3. **Skill mining proper**: find step sequences that recur across tier-4
   tutorials (e.g. "create scene root + rename + save" in Godot, "add
   modifier + set level" in Blender) and extract them as parameterized
   skills in the existing `godot-*` / new `blender-*` library format. The
   machine actions are already skill-shaped; mining is mostly dedup and
   naming.
4. Adjust thresholds and prompt rules based on recurring defect classes
   (e.g. if `inspector_property` locators dominate ground failures, the
   dissemination prompt gains a rule about them).

## 4. Telemetry format

One JSON lines file per guided run, written by the host plugin
(Godot: `user://tutor/runs/`, Blender: extension user data dir):

```jsonc
{"run":"uuid","tutorial":"godot-first-player-scene","tier":3,
 "editor_version":"4.6","step":"s05","event":"auto_advanced","t_ms":8400}
{"run":"uuid","tutorial":"godot-first-player-scene","tier":3,
 "step":"s06","event":"manual_done","condition_state":"satisfied","t_ms":21000}
```

`event` is one of: `shown`, `auto_advanced`, `manual_done`, `skipped`,
`hint`, `ground_failed`, `false_fire_reported` (user pressed an explicit
"that advanced too early" affordance in the callout). `condition_state` on
`manual_done` distinguishes detection misses from genuine manual steps.
Collection path for meta-review: the dashboard host already runs scheduled
jobs on the machine where these directories live; the weekly job globs
them. Remote/multi-machine collection is out of scope until there is more
than one machine.

## 5. Dashboard integration

Two additions to claude-dashboard, matching existing tile idioms:

- A "tutorials" list like the current skills list: name, tier badge, date of
  last tier change, newest first.
- Three schedule rows: `tutorial-miner` (daily), `tutorial-iteration-cycle`
  (every 3 hours), `tutorial-meta-review` (weekly), toggleable like the
  existing template loops.
