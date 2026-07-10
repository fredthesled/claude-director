# Tutor: Guided Tutorial Overlays for Godot and Blender

Status: design draft (2026-07-10). No code exists yet; this document is the
research and architecture output that precedes a prototype.

## 1. Concept

Tutor turns an existing tutorial (a docs page, a blog post, a video, a set of
written instructions) into an interactive, in-editor guided experience, the
way a game's how-to-play tutorial walks a player through complex UI: "click
here", "drag this into this", "set this value to 0.5". The user follows the
steps in the real editor on their real project; Tutor highlights the target,
explains the action, detects when the step is actually done, and advances.

Two host programs are in scope, chosen because both are moddable from within
and drivable from without:

- **Godot 4.x**: an `EditorPlugin` (this repo's Claude Director plugin is the
  proving ground and prior art, but Tutor is designed standalone).
- **Blender 4.2+/5.x**: a Python add-on (Extensions-platform compatible).

A single tutorial format (Section 4) is shared across both hosts. The hosts
differ only in how they *ground* a step (find the thing on screen) and how
they *verify* it (detect completion).

## 2. Prior art in this ecosystem

Three existing projects supply proven pieces:

- **Claude Director** (`addons/claude_director/`, this repo): an in-editor
  dock that runs a Claude tool loop against ~40 editor-manipulation tools
  (`node_add`, `node_prop`, `sig_connect`, `scene_save`, ...). Two things
  carry over directly: (a) the API layer (`claude_api.gd`: retries, prompt
  caching, history windowing, orphaned-tool-use healing) and (b) the tool
  vocabulary, which doubles as Tutor's *machine action* vocabulary (Section
  4.4). Claude Director proves the editor state needed for completion
  detection is fully inspectable from a plugin.
- **Video-to-SOP-Generator**: a Gemini app that converts screen recordings
  into granular process docs. Its prompt discipline ("Do Not Summarize",
  exact click paths, capture typed values verbatim, timestamped screenshot
  anchors) is the template for Tutor's dissemination prompt (Section 3.2),
  with the output retargeted from markdown prose to schema-valid JSON.
- **The skill pipeline** (visible on claude-dashboard): `awesome-godot-miner`
  (daily), `template-iteration-cycle` (every 3 hours), `template-meta-review`
  (weekly), feeding a library of `godot-*` skills. Tutor's quality loop is
  the same shape applied to tutorials; see `SKILL_LOOPS.md`.

## 3. Pipeline

Six stages. The first two are editor-agnostic; the rest are per-host.

```
ingest -> disseminate -> ground -> guide -> verify -> mine
```

### 3.1 Ingest

Accept tutorial source material as: pasted text, a URL (fetched and
stripped), a markdown/HTML file, or a video (routed through the
Video-to-SOP-style vision pass first, producing a click-path transcript).
Output: normalized plain text with any code blocks and literal values
preserved verbatim.

### 3.2 Disseminate

A Claude call converts the normalized text into a `*.tutorial.json` document
(Section 4). Prompt rules, inherited from Video-to-SOP and hardened for
machine consumption:

1. Do not summarize; one editor action per step. "Create a Player scene with
   an Area2D root" is three steps (new scene, add node, rename), not one.
2. Every step names a target from the documented locator vocabulary of the
   host editor. No freeform "in the top-left area" targets.
3. Every step carries a machine-checkable completion condition. If nothing
   checkable exists, the condition is `manual` and that is flagged as a
   dissemination defect for review.
4. Literal values (property values, node names, shortcut keys, expressions)
   are captured exactly as the source states them.
5. Every step also carries the equivalent machine action (Section 4.4), the
   programmatic way to perform the same edit.
6. Steps declare `requires` preconditions so a tutorial can fail fast if the
   user's project is not in the expected state.

The dissemination model must know the locator and condition vocabularies;
they are embedded in the prompt as the JSON schema plus per-editor examples.

### 3.3 Ground

Resolve each step's locator to an on-screen rectangle in the running editor.
Grounding can fail (editor version moved a button, dock is closed, panel is
collapsed); a failed ground degrades gracefully to a text-only instruction
with a generic dock-level highlight, and the failure is telemetry (Section
3.6 and SKILL_LOOPS.md), not a crash.

### 3.4 Guide

The overlay itself:

- Dim the editor with a translucent scrim that has a cut-out "spotlight" over
  the target rect, plus a pulsing border. The scrim never intercepts mouse
  input; the user performs the real action on the real control.
- A callout panel adjacent to the spotlight shows: step number/total, the
  instruction, the literal value to enter if any, and buttons: Back, Skip,
  Hint, Done (manual advance, always available), and "Do it for me" (executes
  the step's machine action, borrowed straight from Claude Director's tools).
- Keyboard-driven steps (pervasive in Blender) show a shortcut chip (e.g.
  `Tab`, `Ctrl+B`) instead of a spotlight when there is no meaningful target
  rect.

### 3.5 Verify

Each step's completion condition is evaluated by a checker that runs on a
short poll (about 4 Hz) plus host-specific push signals where available.
Auto-advance fires on first success. The same checkers run headless (Section
5.4 / 6.4), which is what makes tutorial quality reviewable by automation
rather than only by humans; this is the load-bearing design decision.

### 3.6 Mine

Guided runs emit per-step telemetry (shown, auto-advanced, manually skipped,
hint used, time-to-complete, ground failure). Recurring step sequences that
users complete successfully are candidates for extraction into reusable
skills (the existing `godot-*` skill library shape). Details in
`SKILL_LOOPS.md`.

## 4. Shared tutorial format

Canonical schema: `docs/tutor/step-schema.json`. Worked examples:
`docs/tutor/examples/*.tutorial.json`. Summary:

```jsonc
{
  "tutor_version": 1,
  "id": "godot-first-player-scene",
  "editor": "godot",                  // "godot" | "blender"
  "editor_version": "4.6",            // version the locators were verified on
  "title": "...",
  "source": { "kind": "url", "ref": "https://..." },
  "sigma_tier": 0,                    // 0..4, see SKILL_LOOPS.md
  "requires": [ /* completion-condition objects, checked up front */ ],
  "steps": [ {
      "id": "s01",
      "instruction": "Click Scene > New Scene in the main menu.",
      "detail": "optional longer explanation shown under Hint",
      "target":     { /* locator object, per-editor vocabulary */ },
      "completion": { /* condition object, per-editor vocabulary */ },
      "machine_action": { /* programmatic equivalent */ },
      "value": "optional literal the user must type/set",
      "shortcut": "optional key chord, e.g. Ctrl+N"
  } ]
}
```

### 4.1 Locator vocabulary (Godot)

| kind | params | resolves via |
|---|---|---|
| `dock` | `name`: SceneTree, FileSystem, Inspector, Node, Import | class match on `EditorInterface.get_base_control()` descendants (`SceneTreeDock`, `FileSystemDock`, `EditorInspector`, ...) |
| `menu` | `path`: "Scene/New Scene" | `MenuBar` child of base control; highlight the menu button (see popup caveat, 5.5) |
| `button` | `scope` (a dock/toolbar locator), `text` or `tooltip` | scan for `Button`/`MenuButton`/`OptionButton` by text/tooltip within scope |
| `scene_tree_item` | `node_path` | `Tree` inside `SceneTreeDock`; item rect via `Tree.get_item_area_rect()` |
| `inspector_property` | `property` | `EditorProperty` descendants of `EditorInspector`, matched on `get_edited_property()` |
| `main_screen` | `name`: 2D, 3D, Script, AssetLib | main-screen toggle buttons row |
| `viewport` | (none) | the `CanvasItemEditor` / `Node3DEditor` viewport rect |
| `bottom_panel` | `name`: Output, Debugger, Animation, Shader Editor | bottom panel toggle buttons |

Godot's editor UI is a real Control tree, so per-widget rects are exact. The
editor classes are engine-internal (not in ClassDB docs) but stable enough to
match on `get_class()`; a per-editor-version locator lint (Section 5.4)
catches drift when a new Godot minor lands.

### 4.2 Locator vocabulary (Blender)

| kind | params | resolves via |
|---|---|---|
| `area` | `type`: VIEW_3D, PROPERTIES, OUTLINER, NODE_EDITOR, ... | `window.screen.areas[]` by `area.type`, rect from `area.x/y/width/height` |
| `region` | `area type` + `region`: WINDOW, HEADER, UI (N-panel), TOOLS (T-panel) | `area.regions[]` by `region.type` |
| `properties_tab` | `tab`: MODIFIER, MATERIAL, OBJECT, RENDER, ... | Properties area + nav-bar region; tab rows are fixed-order, rect estimated |
| `panel` | `area`/`region` + `bl_idname` or label | region-level highlight + callout naming the panel; exact panel rects are not queryable (see 6.5) |
| `shortcut` | `keys` | no rect; callout renders a key chip |
| `operator` | `bl_idname`, e.g. `mesh.primitive_torus_add` | used for completion far more than for targeting |

Blender's UI is rebuilt every draw from Python `draw()` functions; there is
no API to ask "where is this button on screen". Grounding is therefore
area/region-granular, with the instruction text carrying the precision. This
is the biggest host asymmetry and it is acceptable: Blender tutorials are
keyboard-and-menu heavy, and area-level spotlight plus an exact instruction
plus operator-level completion detection still yields a game-tutorial feel.

### 4.3 Completion condition vocabulary

Godot: `node_added {type,name?,parent?}`, `node_selected {path}`,
`property_equals {path,prop,value}`, `script_attached {path,script?}`,
`signal_connected {source,signal,target,method}`, `scene_open {path}`,
`scene_saved {path}`, `file_exists {path}`, `input_action_exists {name}`,
`main_screen {name}`, `manual`.

Blender: `operator_executed {bl_idname}` (via `wm.operators` history and a
handler), `property_equals {datapath,value}` (checked by `eval` of a
restricted datapath against `bpy.data`), `object_added {type,name?}`,
`mode_equals {mode}` (OBJECT/EDIT/SCULPT...), `modifier_added
{object,type}`, `node_added {tree,bl_idname}`, `datablock_exists
{collection,name}`, `saved {}`, `manual`.

Every condition is a pure read of program state so the identical checker
code runs interactively and headless.

### 4.4 Machine actions

The programmatic twin of the human step:

- Godot: a Claude Director tool call, e.g.
  `{"tool":"node_add","input":{"type":"Area2D","name":"Player","parent":"."}}`.
  The existing `scene_tools.gd` dispatch already implements the whole
  vocabulary.
- Blender: a single restricted Python statement, e.g.
  `{"python":"bpy.ops.mesh.primitive_torus_add(major_radius=1.0)"}`, executed
  in a namespace exposing only `bpy`.

Machine actions serve three purposes: the "Do it for me" button, headless
replay verification (each action executed, then the step's own completion
condition asserted), and skill mining (a verified action sequence is
already skill-shaped).

## 5. Godot host

### 5.1 Editor access

`EditorPlugin` + `EditorInterface` give everything needed:
`get_base_control()` (whole editor Control tree, for grounding and overlay
parenting), `get_edited_scene_root()` / `get_selection()` /
`get_editor_undo_redo()` (state, for checkers), `get_editor_scale()` (DPI),
`get_resource_filesystem()` (file checkers).

### 5.2 Overlay rendering

One full-rect `Control` added on top of `get_base_control()`:

- `mouse_filter = MOUSE_FILTER_IGNORE` on the scrim so every real editor
  control stays clickable; only the callout `PanelContainer` uses
  `MOUSE_FILTER_STOP`.
- `_draw()` paints four dim rects around the spotlight hole (no shader
  needed) plus an animated border; redraw driven by a `Timer` and by
  `resized` on the editor root.
- Rects re-ground on window resize, dock layout change, and editor scale.

### 5.3 Completion detection

Primary: a 4 Hz poll evaluating the active step's condition against
`get_edited_scene_root()` and friends (the checkers reuse the inspection
paths already proven in `scene_tools.gd`). Push accelerators where cheap:
`EditorSelection.selection_changed`, `EditorInspector.property_edited`,
`EditorPlugin.scene_changed`, `EditorFileSystem.filesystem_changed`,
`EditorUndoRedoManager.history_changed`. Polling remains the source of truth
so a missed signal can never wedge a tutorial.

### 5.4 CLI surface (research summary)

What matters from `godot --help` for Tutor:

| flag | use for Tutor |
|---|---|
| `--headless` | server display driver; combined with `-e` runs the real editor without a window |
| `-e, --editor` | required for anything touching editor state |
| `--path <dir>` | pick the project under test |
| `--quit-after <n>` | bounded editor runs in CI |
| `-s, --script <file>` | run a standalone script (SceneTree/MainLoop) for non-editor checks |
| `--check-only` | parse-only lint of generated GDScript |
| `--import` | force resource import before a headless editor run (avoids first-run import stalls) |
| `--doctool <path>` / `--dump-extension-api` | dump the class reference; used by dissemination to validate node/property names offline |
| `--log-file <file>` | capture editor log for replay harness assertions |
| `--lsp-port` (editor setting, default 6005) | GDScript LSP from a headless editor; optional richer lint |
| DAP port 6006 | debug adapter; not needed for MVP |

Replay harness pattern (all of this is proven by Claude Director's runtime
model): launch `godot --headless -e --path <project>` with the Tutor plugin
enabled and a `TUTOR_REPLAY=res://path.tutorial.json` env var; the plugin
executes each step's machine action, asserts the step's completion
condition, writes a JSON report, and quits. Exit code communicates
pass/fail to CI. Locator lint is the same run with actions skipped: only
resolve every locator against the live editor tree and report which ones
still ground on this Godot version.

### 5.5 Known limitations

- Menu popups (`PopupMenu`) are separate OS windows in Godot 4; the scrim
  cannot draw over them. Menu steps spotlight the `MenuBar` button and use
  the popup's `id_pressed` (or the resulting state change) for completion.
- Editor-internal class names (`SceneTreeDock`, ...) are not API-stable;
  the per-version locator lint is the mitigation, not hope.
- Modal dialogs (project settings, node creation dialog) are also separate
  windows; steps that open them rely on condition polling to detect the
  outcome rather than in-dialog spotlights (in-dialog guidance is a possible
  later enhancement by parenting a secondary overlay into that `Window`).

## 6. Blender host

### 6.1 Add-on shape

A single-package add-on (Extensions-platform manifest, works on 4.2 LTS
through 5.x): one modal operator (`tutor.run_tutorial`) owning the session,
draw handlers for rendering, a `bpy.app.timers` tick for condition polling,
and a small panel (N-panel in the 3D Viewport, category "Tutor") for
loading/starting tutorials and showing the step list.

### 6.2 Overlay rendering

`Space*.draw_handler_add(cb, args, 'WINDOW', 'POST_PIXEL')` per relevant
space type, drawing with the `gpu` module (shader-batched rects/borders) and
`blf` (text). The handler draws region-local, so the highlight for an
`area`/`region` locator is drawn by the handler registered on that space,
covering its own region fully or partially. The callout is drawn in the
active 3D Viewport (or the largest area) as a POST_PIXEL panel with hit
zones handled by the modal operator's mouse events (Back/Skip/Done/Hint as
drawn buttons), since real Blender UI buttons cannot float over arbitrary
regions. Menus and the top bar cannot be drawn over; steps there are
callout-plus-instruction only.

### 6.3 Completion detection

- `bpy.app.timers` poll (4 Hz) evaluating the condition, same as Godot.
- `bpy.msgbus.subscribe_rna` for property-equals accelerators (best effort;
  not all properties notify).
- `bpy.app.handlers.depsgraph_update_post` for object/datablock additions.
- Operator detection: scan `context.window_manager.operators` tail for the
  target `bl_idname` (covers REGISTER-flagged operators, which is nearly
  everything tutorial-relevant).

### 6.4 CLI surface (research summary)

| flag | use for Tutor |
|---|---|
| `-b, --background` | headless; the whole replay harness runs here |
| `-P, --python <file>` | run the replay driver script |
| `--python-expr <expr>` | one-liners for smoke checks |
| `--factory-startup` | clean prefs/startup so replays are deterministic |
| `--addons <a,b>` | force-enable the Tutor add-on for the run |
| `--python-exit-code <n>` | make uncaught Python exceptions fail CI properly |
| `-noaudio` | quiet CI |
| `--log <match>` / `--log-level <n>` | capture logs for report |
| `--command extension ...` (4.2+) | install/validate the add-on package in CI |

Replay harness: `blender -b --factory-startup --addons tutor -P replay.py --
--tutorial path.tutorial.json --report out.json`. The driver opens/creates
the expected start file, executes each machine action, asserts each
condition, writes the report. Caveat: some operators behave differently or
are unavailable without a window/context; the replayer uses
`context.temp_override(...)` to fabricate area/region context, and steps
whose operators are truly UI-bound are marked `replayable: false` and count
against the tutorial's sigma tier rather than silently passing.

### 6.5 Known limitations

- No per-button rects (Section 4.2). Spotlights are area/region/tab
  granular; precision lives in the instruction text and completion check.
- Draw handlers exist per space type; coverage of exotic editors is added
  lazily. Top bar, menus, and the splash are not drawable.
- `bpy.msgbus` misses some property changes (notably some operator-driven
  ones); the poll is the source of truth, msgbus is an accelerator only.

## 7. Program architecture (shared core, thin hosts)

```
tutor-core (spec + prompts + schema, editor-agnostic, versioned here)
  ├─ step-schema.json          the contract
  ├─ dissemination prompt      text -> tutorial.json
  └─ sigma policy              SKILL_LOOPS.md

tutor-godot (GDScript EditorPlugin)          tutor-blender (Python add-on)
  ├─ locator.gd     ground vocabulary          ├─ locator.py
  ├─ checkers.gd    condition vocabulary       ├─ checkers.py
  ├─ overlay.gd     scrim/spotlight/callout    ├─ overlay.py (gpu/blf)
  ├─ actions.gd     machine actions            ├─ actions.py (restricted exec)
  ├─ replay.gd      headless harness           ├─ replay.py (blender -b driver)
  └─ dock UI        ingest/disseminate/run     └─ N-panel UI
```

Dissemination calls Claude via each host's existing HTTP capability
(Godot: `HTTPRequest` as in `claude_api.gd`; Blender: `urllib`/`requests`),
or is done outside the editor entirely (a tutorial JSON authored by a Claude
Code session and dropped into the project); both paths produce the same
artifact, which keeps the hosts thin.

## 8. MVP plan

1. **M1, Godot guide MVP** (inside this repo as a second dock tab or sibling
   addon): schema v1, six locator kinds (dock, menu, button,
   scene_tree_item, inspector_property, main_screen), eight condition kinds,
   overlay, manual + auto advance, one golden tutorial
   (`godot-first-player-scene`, example committed).
2. **M2, Godot replay + lint harness**: `--headless -e` runner, JSON report,
   run it on the golden tutorial in CI; this activates the sigma loop.
3. **M3, Blender guide MVP**: add-on with area/region grounding, operator +
   property conditions, one golden tutorial (`blender-donut-base-mesh`,
   example committed), `blender -b` replayer.
4. **M4, loop wiring**: miner/iteration/meta-review routines for tutorials,
   telemetry file format, dashboard tiles (see SKILL_LOOPS.md).

## 9. Open questions

- Video ingestion: route through Video-to-SOP as-is (Gemini) or port the
  prompt to the Claude API for one-vendor operation? Leaning: port it; the
  prompt is the asset, not the vendor.
- Where do guided-run telemetry files live for a user project (Godot:
  `user://tutor/`; Blender: extension user dir), and how does the weekly
  meta-review collect them?
- In-dialog guidance for Godot modal windows (secondary overlay parented
  into the `Window`): worth it for M1 golden tutorial (the node-create
  dialog is step 2 of nearly every Godot tutorial) or accept callout-only?
