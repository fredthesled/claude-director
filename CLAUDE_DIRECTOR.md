# [Your Game Name] — Project Context

Claude Director reads this file automatically when the plugin loads.
After editing it, click **⚙ → Save** in the Claude Director dock to reload.

---

## Game Concept
[2–3 sentences describing what the game is and how it plays.]

## Viewport & Rendering
- Resolution: [e.g. 640×360 for retro, 1280×720 for modern]
- Stretch mode: [e.g. canvas_items for pixel-perfect scaling]
- Style: [e.g. 2D pixel art 16×16, top-down, platformer, 3D low-poly]

## Physics Layers
Define your layers here so Claude uses named constants rather than numbers.
- 1: [e.g. walls / terrain]
- 2: [e.g. player]
- 3: [e.g. enemies]

## Core Scenes
List your main scene paths once they exist:
- `res://scenes/...` — [description]

## Autoloads
List any singleton autoloads and their key API:
- `GameManager` (`res://scripts/game_manager.gd`) — [properties and methods]

## Input Actions
List the actions defined in project.godot:
- `move_left/right/up/down` → [keys]
- `action` → [key]

## Coding Conventions
[Any project-specific patterns Claude should follow, e.g.:]
- All scripts declare their extends type explicitly
- Signals typed at top of file
- @export for designer-tunable constants

## Asset Sources
[Where art/audio comes from, e.g. "Kenney 1-bit pack extracted to res://assets/kenney/"]

## Key Systems
[Describe important mechanics Claude should understand before writing code.]
