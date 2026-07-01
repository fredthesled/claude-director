# Psychedelic Basketball — Project Context
Claude Director reads this file automatically when the plugin loads.
After editing it, click **⚙ → Save** in the Claude Director dock to reload.

---

## Game Concept
3D cartoony 3-on-3 half-court basketball (single hoop, streetball "loser's
outball" possession), first team to 5 made baskets wins. As the combined
score climbs, the live view gets progressively more psychedelic (kaleidoscope
fold, hue cycling, chromatic aberration, fractal noise, double-vision ghosts
on players/ball/hoop). The instant replay after each made shot is shown from
a sideline POV camera and deliberately excludes all of that — instead, the
*players themselves* look increasingly drunk/high/stumbling/cross-eyed/
drooling in the replay as the game wears on.

## Viewport & Rendering
- Forward+ renderer, default window resolution.
- Style: stylized low-poly characters (imported KayKit "Adventurers" models)
  on a procedurally-built court/hoop/ball. Court/hoop/ball geometry is
  generated in code; characters are imported rigged/animated glb models with
  a procedural cartoony face grafted onto the head bone.

## Physics Layers
- 1: world (floor/walls/rim collider)
- 2: team_a (player characters)
- 3: team_b (player characters)
- 4: ball
- 5: hoop_sensor (Area3D that detects made baskets)

## Core Scenes
- `res://scenes/main.tscn` — the only hand-authored scene; root `Node3D`
  with `scripts/main.gd`, which builds the entire game (court, hoop, ball,
  6 characters, lighting, replay rig, FX overlay, HUD) in code at runtime.

## Autoloads
- `GameManager` (`res://scripts/autoload/game_manager.gd`) — score, state
  (`PLAYING`/`REPLAY`/`GAME_OVER`), possession, and
  `psychedelic_intensity` (0..1, driven by total points scored). Emits
  `score_changed`, `shot_made(team, world_pos)`, `possession_changed`,
  `game_over(team)`, `state_changed`.
- `ReplayManager` (`res://scripts/autoload/replay_manager.gd`) — every actor
  (players + ball) registers itself via `register_actor(id, node)`; records
  a rolling transform history each physics frame; on `shot_made`, waits 2s
  (still recording follow-through), freezes live play (`GameManager.state =
  REPLAY`), and emits `replay_requested(frames, shot_pos, team)` for the
  replay camera to consume. `is_replaying` is checked by all psychedelic FX
  to force themselves off during replays.

## Input Actions
- `move_forward/back/left/right` → WASD
- `action_jump` → Space
- `action_sprint` → Shift
- `action_shoot` → Left mouse button
- `action_pass` → Right mouse button (pass when holding the ball, steal
  attempt when defending close to the ball carrier)

## Coding Conventions
- Everything is assembled procedurally in `_ready()` — no hand-authored
  `.tscn` node trees beyond `main.tscn`'s single root. Geometry that doesn't
  need to be imported (court/hoop/ball) is generated in code; characters
  instance an imported `PackedScene` instead. Keep new gameplay objects
  consistent with this (a script that builds/instances its own
  visuals/collision).
- `DoubleVisionGhost` (`scripts/fx/double_vision_ghost.gd`) works by calling
  `target.duplicate()`, so `target` must always be a *plain* visual-only node
  with no gameplay script attached (an imported model instance, or a
  scriptless `"Visual"` wrapper `Node3D` around primitive meshes — see how
  `Basketball`/`Hoop`/`CharacterBodyBase` set it up). Pointing it at a
  scripted node re-runs that script's `_ready()` on the duplicate and
  recurses/double-registers.
- Shared character logic lives in `CharacterBodyBase`
  (`scripts/characters/character_body.gd`); `PlayerController` (human) and
  `AiPlayer` (FSM bot) both extend it and call `super._physics_process()`
  before doing their own movement + `move_and_slide()`.
- All scripts use `class_name` so cross-references don't need `preload()`.
- Avoid naming an enum `Expression` — it collides with Godot's built-in
  `Expression` class (this is why the face expression enum is called
  `FaceExpression`).

## Key Systems
- **Psychedelic overlay** (`scripts/fx/psychedelic_overlay.gd` +
  `shaders/psychedelic.gdshader`): full-screen `CanvasLayer`/`ColorRect`
  shader, intensity = `GameManager.psychedelic_intensity`, forced to 0 while
  `ReplayManager.is_replaying`.
- **Double-vision ghosts** (`scripts/fx/double_vision_ghost.gd`): attach as
  a child of any `Node3D` with `MeshInstance3D` descendants (players, ball,
  hoop already do this); clones those meshes into a translucent drifting
  ghost copy, scaled by intensity, hidden during replays.
- **Character faces** (`scripts/characters/character_face.gd`): procedural
  primitive face (eyes/pupils/brows/mouth/drool) mounted via a
  `BoneAttachment3D` on the imported model's `head` bone,
  `set_expression(FaceExpression.X, drunk_amount)` swaps look instantly.
- **Replay camera rig** (`scripts/world/replay_camera_rig.gd`): sideline
  `Camera3D` that scrubs recorded frames, applying a stumble/tilt/bob
  distortion to character transforms (and triggering their drunk face +
  drool) scaled by intensity — the ball and hoop play back undistorted.

## Asset Sources
- `assets/kaykit_adventurers/{Knight,Barbarian}.glb` — KayKit "Adventurers
  Character Pack" by Kay Lousberg (kaylousberg.com), **CC0** (see
  `assets/kaykit_adventurers/LICENSE.txt`). Fetched via `raw.githubusercontent.com`
  from the `KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0` repo —
  general asset hosts like kenney.nl are blocked by this sandbox's egress
  policy, so GitHub-hosted CC0 packs are the fallback path when re-fetching
  or adding more assets from outside an interactive session.
  - `CharacterBodyBase` (`scripts/characters/character_body.gd`) instances
    one of these per team (Team A → Knight, Team B → Barbarian — this also
    gives the teams distinct silhouettes/palettes for free), strips the
    weapon/helmet/cape meshes hanging off the `handslot_l/handslot_r/head/chest`
    `BoneAttachment3D` nodes (basketball players don't need swords), and
    drives the rig's own animations (`Idle`, `Running_A`, `Jump_Idle`,
    `Throw` for the shot release) via the model's `AnimationPlayer`.
  - The ball-holding point is the model's existing `handslot_r` bone
    attachment; the procedural face mounts on the `head` bone attachment.
- Court/hoop/ball geometry is still generated in code
  (`PrimitiveMesh` subclasses + `StandardMaterial3D`) — no need to import
  assets for those.

## Design Notes / Possible Follow-ups
- This is a half-court single-hoop interpretation of "3-on-3"; a full-court
  two-hoop version would need a second `Hoop`, side-switching, and AI that
  tracks which basket it's attacking — straightforward to add by
  parameterizing `Hoop` references per team instead of one shared hoop.
- AI is a deliberately simple FSM (chase ball / space near hoop / shoot on
  cooldown+chance; man-to-man mark on defense). Good first place to add
  depth (give-and-go passing, double-teams, shot contesting).
