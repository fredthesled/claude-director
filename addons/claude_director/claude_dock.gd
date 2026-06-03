@tool
extends VBoxContainer

const CONFIG_PATH := "user://claude_director.json"

var _config: Dictionary = {}
var _api: Node
var _tools: RefCounted
var _is_busy: bool = false

# UI refs
var _settings_panel: PanelContainer
var _api_key_field: LineEdit
var _chat_label: RichTextLabel
var _chat_scroll: ScrollContainer
var _thinking_label: Label
var _user_input: TextEdit
var _send_btn: Button

var _system_prompt: String
var _tools_def: Array


func _ready() -> void:
	_load_config()
	_build_prompts()
	_build_ui()
	_setup_api()
	# Auto-open settings if no key saved yet
	if _config.get("api_key", "").is_empty():
		_settings_panel.visible = true


# ── Config ─────────────────────────────────────────────────────────────────

func _load_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f:
			var parsed := JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_config = parsed
			f.close()


func _save_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_config))
		f.close()


# ── Prompts & Tools Definition ─────────────────────────────────────────────

func _build_prompts() -> void:
	# Base prompt is fully game-agnostic. Project-specific context comes
	# from CLAUDE_DIRECTOR.md at the project root — edit that file to
	# describe your game. Click ⚙ → Save to reload after editing.
	var base := (
		"You are Claude Director in Godot 4.6. Build games by directly creating/modifying scenes and scripts.\n\n"
		+ "GDScript 4 only (never Godot 3): @export @onready signal s(p:T) await(not yield)\n"
		+ "Input.get_vector(\"move_left\",\"move_right\",\"move_up\",\"move_down\")\n\n"
		+ "Workflow: inspect first (tree/files/info) → write scripts → node_add → node_prop → node_script → sig_connect → scene_save\n"
		+ "Inspect with node_props before setting props. patch=surgical edits. logs=runtime errors. shot=see viewport.\n"
		+ "node_call: invoke method — node_call(path,'set_anchors_and_offsets_preset',[15]) for fullscreen layout.\n"
		+ "scene_instance=add .tscn as child. signals=list signals. res_new=create Resource (shapes/materials).\n"
		+ "group=node groups. input=input actions. fs=file ops. batch=multi-tool sequence. node_move=reparent.\n"
		+ "phys_layers: name collision layers {\"1\":\"walls\",\"2\":\"player\",...}.\n"
		+ "── Asset pipeline ──────────────────────────────────────────────────────\n"
		+ "Pixel art: setting(op=set,key='rendering/textures/canvas_textures/default_texture_filter',value=0)\n"
		+ "Sprites: asset_fetch→img_info→sprite_frames(save_path,source,tile_w,tile_h,animations,apply_to)\n"
		+ "  animations: [{name,row,frames,fps,loop}] (sheet) or [{name,images:[...],fps}] (individual files)\n"
		+ "Tiles: asset_fetch→tileset(save_path,source_image,tile_w,tile_h)→res_load(TileMapLayer,tile_set,path)\n"
		+ "Audio: asset_fetch→res_load(node,stream,path)→res_prop(node,stream,loop,true)\n"
		+ "paint: TileMapLayer from 2D grid+tile_map. anim: AnimationPlayer clip+tracks.\n"
		+ "res_prop: sub-resource props. kenney.nl: Claude knows free pack URLs.\n"
		+ "────────────────────────────────────────────────────────────────────────\n"
		+ "Complete code only, no stubs. Node paths from scene root.\n"
	)

	var ctx := _load_project_context()
	if ctx.is_empty():
		_system_prompt = (base
			+ "\nNo CLAUDE_DIRECTOR.md found at project root. Create one to define game-specific context "
			+ "(architecture, physics layers, autoloads, scene structure). "
			+ "Claude will ask clarifying questions until it is created.\n"
		)
	else:
		_system_prompt = base + "\n── Project Context (res://CLAUDE_DIRECTOR.md) ─────────────────────────\n" + ctx


func _load_project_context() -> String:
	var path := "res://CLAUDE_DIRECTOR.md"
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return ""
	var text := f.get_as_text().strip_edges()
	f.close()
	return text

	_tools_def = [
		{
			"name": "files",
			"description": "List project files. path=res:// by default; ext=['.gd','.tscn'] to filter.",
			"input_schema": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"ext": {"type": "array", "items": {"type": "string"}}
				}
			}
		},
		{
			"name": "read",
			"description": "Read a file's full contents.",
			"input_schema": {
				"type": "object",
				"properties": {"path": {"type": "string"}},
				"required": ["path"]
			}
		},
		{
			"name": "write",
			"description": "Write/create a file (auto-creates dirs).",
			"input_schema": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"content": {"type": "string"}
				},
				"required": ["path", "content"]
			}
		},
		{
			"name": "node_add",
			"description": "Add node to scene. type=Godot class; parent='.' for root.",
			"input_schema": {
				"type": "object",
				"properties": {
					"type": {"type": "string"},
					"name": {"type": "string"},
					"parent": {"type": "string"}
				},
				"required": ["type", "name"]
			}
		},
		{
			"name": "node_rm",
			"description": "Remove a node and its children.",
			"input_schema": {
				"type": "object",
				"properties": {"path": {"type": "string"}},
				"required": ["path"]
			}
		},
		{
			"name": "node_prop",
			"description": "Set node property. [x,y]→Vector2, [r,g,b,a]→Color(0-1). path='.' for root.",
			"input_schema": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"prop": {"type": "string"},
					"value": {}
				},
				"required": ["path", "prop", "value"]
			}
		},
		{
			"name": "node_script",
			"description": "Attach script to node. write the .gd file first.",
			"input_schema": {
				"type": "object",
				"properties": {
					"node": {"type": "string"},
					"script": {"type": "string"}
				},
				"required": ["node", "script"]
			}
		},
		{
			"name": "scene_new",
			"description": "Create a new .tscn and open it.",
			"input_schema": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"root": {"type": "string"}
				},
				"required": ["path", "root"]
			}
		},
		{
			"name": "scene_open",
			"description": "Open an existing scene.",
			"input_schema": {
				"type": "object",
				"properties": {"path": {"type": "string"}},
				"required": ["path"]
			}
		},
		{
			"name": "scene_save",
			"description": "Save current scene. path=optional save-as.",
			"input_schema": {
				"type": "object",
				"properties": {"path": {"type": "string"}}
			}
		},
		{
			"name": "run",
			"description": "Playback: action=play|play_current|stop.",
			"input_schema": {
				"type": "object",
				"properties": {
					"action": {"type": "string", "enum": ["play", "play_current", "stop"]}
				},
				"required": ["action"]
			}
		},
		{
			"name": "node_props",
			"description": "Get node property values. filter=name substring to narrow.",
			"input_schema": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"filter": {"type": "string"}
				},
				"required": ["path"]
			}
		},
		{
			"name": "node_find",
			"description": "Search scene nodes. by=name/type/script.",
			"input_schema": {
				"type": "object",
				"properties": {
					"query": {"type": "string"},
					"by": {"type": "string", "enum": ["name", "type", "script"]}
				},
				"required": ["query"]
			}
		},
		{
			"name": "patch",
			"description": "Replace unique text block in script file.",
			"input_schema": {
				"type": "object",
				"properties": {
					"path": {"type": "string"},
					"old": {"type": "string"},
					"new": {"type": "string"}
				},
				"required": ["path", "old", "new"]
			}
		},
		{
			"name": "sig_connect",
			"description": "Wire signal→method. scene_save to persist.",
			"input_schema": {
				"type": "object",
				"properties": {
					"source": {"type": "string"},
					"signal": {"type": "string"},
					"target": {"type": "string"},
					"method": {"type": "string"}
				},
				"required": ["source", "signal", "target", "method"]
			}
		},
		{
			"name": "logs",
			"description": "Read last N lines from game log.",
			"input_schema": {
				"type": "object",
				"properties": {"lines": {"type": "integer"}}
			}
		},
		{
			"name": "shot",
			"description": "Capture viewport. Returns vision image.",
			"input_schema": {"type": "object"}
		},
		{
			"name": "info",
			"description": "Editor state: version, project, scenes.",
			"input_schema": {"type": "object"}
		},
		{
			"name": "setting",
			"description": "Read/write ProjectSettings. op=get/set/list.",
			"input_schema": {
				"type": "object",
				"properties": {
					"op":  {"type": "string", "enum": ["get", "set", "list"]},
					"key": {"type": "string"},
					"value": {}
				},
				"required": ["op", "key"]
			}
		},
		{
			"name": "autoload",
			"description": "Manage autoloads. op=list/add/remove.",
			"input_schema": {
				"type": "object",
				"properties": {
					"op":   {"type": "string", "enum": ["list", "add", "remove"]},
					"name": {"type": "string"},
					"path": {"type": "string"}
				},
				"required": ["op"]
			}
		},
		{
			"name": "node_dup",
			"description": "Duplicate a node to parent.",
			"input_schema": {
				"type": "object",
				"properties": {
					"path":   {"type": "string"},
					"parent": {"type": "string"}
				},
				"required": ["path"]
			}
		},
		{
			"name": "tree",
			"description": "Scene hierarchy. depth=-1=full.",
			"input_schema": {
				"type": "object",
				"properties": {"depth": {"type": "integer"}}
			}
		},
		{
			"name": "node_call",
			"description": "Call any method on a node. Array args auto-convert: [x,y]→Vector2, [r,g,b,a]→Color. Use for: set_anchors_and_offsets_preset(15) fullscreen layout; add_theme_font_size_override('font_size',48); add_theme_color_override('font_color',[r,g,b,a]).",
			"input_schema": {
				"type": "object",
				"properties": {
					"path":   {"type": "string"},
					"method": {"type": "string"},
					"args":   {"type": "array"}
				},
				"required": ["path", "method"]
			}
		},
		{
			"name": "scene_instance",
			"description": "Instantiate a .tscn file as a child node in the current scene.",
			"input_schema": {
				"type": "object",
				"properties": {
					"scene":  {"type": "string"},
					"name":   {"type": "string"},
					"parent": {"type": "string"}
				},
				"required": ["scene"]
			}
		},
		{
			"name": "signals",
			"description": "List all signals a node exposes with arg names. Use before sig_connect.",
			"input_schema": {
				"type": "object",
				"properties": {"path": {"type": "string"}},
				"required": ["path"]
			}
		},
		{
			"name": "sig_off",
			"description": "Disconnect a signal from a method.",
			"input_schema": {
				"type": "object",
				"properties": {
					"source": {"type": "string"},
					"signal": {"type": "string"},
					"target": {"type": "string"},
					"method": {"type": "string"}
				},
				"required": ["source", "signal", "target", "method"]
			}
		},
		{
			"name": "res_new",
			"description": "Create a Resource and assign it to a node property. Use for collision shapes (RectangleShape2D, CircleShape2D, CapsuleShape2D), physics materials, etc. init sets initial properties: {size:[w,h]} for Rectangle, {radius:10} for Circle.",
			"input_schema": {
				"type": "object",
				"properties": {
					"type": {"type": "string"},
					"node": {"type": "string"},
					"prop": {"type": "string"},
					"init": {"type": "object"}
				},
				"required": ["type", "node", "prop"]
			}
		},
		{
			"name": "group",
			"description": "Node groups (persist to scene). op=add/remove/list. Common groups: enemies, bullets, pickups.",
			"input_schema": {
				"type": "object",
				"properties": {
					"op":    {"type": "string", "enum": ["add", "remove", "list"]},
					"path":  {"type": "string"},
					"group": {"type": "string"}
				},
				"required": ["op", "path"]
			}
		},
		{
			"name": "input",
			"description": "Input actions. op=list shows all project actions with keys. op=add_key adds keyboard binding (key=A-Z,0-9,F1-F12,Space,Enter,Escape,Left/Right/Up/Down,Shift,Ctrl,Alt,Tab,Delete). op=remove deletes action.",
			"input_schema": {
				"type": "object",
				"properties": {
					"op":     {"type": "string", "enum": ["list", "add_key", "remove"]},
					"action": {"type": "string"},
					"key":    {"type": "string"}
				},
				"required": ["op"]
			}
		},
		{
			"name": "fs",
			"description": "Filesystem ops on project files. op=exists/delete/mkdir/ls.",
			"input_schema": {
				"type": "object",
				"properties": {
					"op":   {"type": "string", "enum": ["exists", "delete", "mkdir", "ls"]},
					"path": {"type": "string"}
				},
				"required": ["op", "path"]
			}
		},
		{
			"name": "batch",
			"description": "Execute multiple tools in one round-trip. Stops on first error. Use for known sequences of node_add + node_prop + node_call steps.",
			"input_schema": {
				"type": "object",
				"properties": {
					"commands": {
						"type": "array",
						"description": "Array of {tool: string, input: object} objects"
					}
				},
				"required": ["commands"]
			}
		},
		{
			"name": "asset_fetch",
			"description": "Download a file from a URL into the project. Automatically extracts ZIP archives when extract=true. Use for Kenney.nl packs, itch.io free assets, and any direct download URL. name overrides the filename if auto-detection fails.",
			"input_schema": {
				"type": "object",
				"properties": {
					"url":        {"type": "string"},
					"dest":       {"type": "string", "description": "Destination folder in project, e.g. 'res://assets/sprites/'"},
					"name":       {"type": "string", "description": "Override filename (auto-detected from URL if omitted)"},
					"extract":    {"type": "boolean", "description": "Extract ZIP after download (default false)"},
					"delete_zip": {"type": "boolean", "description": "Delete the ZIP after extraction (default true)"}
				},
				"required": ["url"]
			}
		},
		{
			"name": "zip_extract",
			"description": "Extract a ZIP file already in the project to a destination folder.",
			"input_schema": {
				"type": "object",
				"properties": {
					"path": {"type": "string", "description": "ZIP file path in project, e.g. 'res://assets/pack.zip'"},
					"dest": {"type": "string", "description": "Destination folder, e.g. 'res://assets/sprites/'"}
				},
				"required": ["path", "dest"]
			}
		},
		{
			"name": "res_load",
			"description": "Load a resource file (PNG, OGG, WAV, .tres, etc.) and assign it to a node property. Use after asset_fetch to attach sprites, sounds, and shapes.",
			"input_schema": {
				"type": "object",
				"properties": {
					"node": {"type": "string", "description": "Node path from scene root"},
					"prop": {"type": "string", "description": "Property name, e.g. 'texture', 'stream', 'shape'"},
					"path": {"type": "string", "description": "Resource path in project, e.g. 'res://assets/player.png'"}
				},
				"required": ["node", "prop", "path"]
			}
		},
		{
			"name": "img_info",
			"description": "Read an image file's dimensions and pre-calculate tile grids at 8/16/32/48px. Call this before sprite_frames or tileset to get the correct row/col counts.",
			"input_schema": {
				"type": "object",
				"properties": {"path": {"type": "string"}},
				"required": ["path"]
			}
		},
		{
			"name": "sprite_frames",
			"description": "Create a SpriteFrames resource (.tres) from a spritesheet or individual images and optionally apply it to an AnimatedSprite2D. Spritesheet mode: provide source + tile_w/h + animations with row/frames. Individual mode: provide animations with images:[...]. save_path is where the .tres is saved.",
			"input_schema": {
				"type": "object",
				"properties": {
					"save_path":  {"type": "string", "description": "e.g. 'res://resources/player_frames.tres'"},
					"source":     {"type": "string", "description": "Spritesheet PNG path (omit for individual-image mode)"},
					"tile_w":     {"type": "integer", "description": "Tile width in pixels"},
					"tile_h":     {"type": "integer", "description": "Tile height in pixels"},
					"animations": {
						"type": "array",
						"description": "Array of animation defs. Spritesheet: {name, row, frames, fps, loop, col(opt)}. Individual: {name, images:[...], fps, loop}"
					},
					"apply_to":   {"type": "string", "description": "Optional AnimatedSprite2D node path to assign immediately"}
				},
				"required": ["save_path", "animations"]
			}
		},
		{
			"name": "tileset",
			"description": "Create a TileSet resource from a tileset image, auto-populating all tile cells. Assign to TileMapLayer.tile_set with res_load afterward.",
			"input_schema": {
				"type": "object",
				"properties": {
					"save_path":    {"type": "string", "description": "e.g. 'res://resources/dungeon_tiles.tres'"},
					"source_image": {"type": "string", "description": "Tileset PNG path"},
					"tile_w":       {"type": "integer"},
					"tile_h":       {"type": "integer"}
				},
				"required": ["save_path", "source_image"]
			}
		},
		{
			"name": "res_prop",
			"description": "Set a property on a sub-resource held by a node (one level deeper than node_prop). Use for: audio loop (node=MusicPlayer, res_prop=stream, prop=loop, value=true), SpriteFrames animation speed, AtlasTexture margins, etc.",
			"input_schema": {
				"type": "object",
				"properties": {
					"node":     {"type": "string", "description": "Node path from scene root"},
					"res_prop": {"type": "string", "description": "Property on the node that holds the resource, e.g. 'stream', 'sprite_frames', 'shape'"},
					"prop":     {"type": "string", "description": "Property on the sub-resource to set"},
					"value":    {}
				},
				"required": ["node", "res_prop", "prop", "value"]
			}
		},
		{
			"name": "paint",
			"description": "Paint tiles onto a TileMapLayer. Grid mode: grid=[[0,1,1],[1,0,1]] + tile_map={\"0\":null,\"1\":[atlas_col,atlas_row]} + optional origin=[x,y]. Cells mode: cells=[{x,y,tile:[c,r],src,alt}]. clear=true erases first. source_id defaults to 0.",
			"input_schema": {
				"type": "object",
				"properties": {
					"node":      {"type": "string"},
					"grid":      {"type": "array"},
					"tile_map":  {"type": "object"},
					"cells":     {"type": "array"},
					"origin":    {"type": "array"},
					"source_id": {"type": "integer"},
					"clear":     {"type": "boolean"}
				},
				"required": ["node"]
			}
		},
		{
			"name": "anim",
			"description": "Create or replace an animation clip in an AnimationPlayer. Track path is relative to the AnimPlayer's parent (e.g. 'Sprite2D:modulate', '.:position'). Value track keys: {t:seconds, v:value}. Method track keys: {t:seconds, method:str, args:[]}. loop: 0=none 1=loop 2=ping-pong.",
			"input_schema": {
				"type": "object",
				"properties": {
					"node":   {"type": "string"},
					"name":   {"type": "string"},
					"length": {"type": "number"},
					"loop":   {"type": "integer"},
					"tracks": {
						"type": "array",
						"description": "Array of {type:'value'|'method', path:str, keys:[...]}"
					}
				},
				"required": ["node", "name", "length", "tracks"]
			}
		},
		{
			"name": "node_move",
			"description": "Reparent a node to a different parent, preserving global transform by default.",
			"input_schema": {
				"type": "object",
				"properties": {
					"path":       {"type": "string"},
					"parent":     {"type": "string"},
					"keep_xform": {"type": "boolean"}
				},
				"required": ["path", "parent"]
			}
		},
		{
			"name": "phys_layers",
			"description": "Name the 2D physics collision layers in Project Settings so layer numbers become readable in the inspector. layers={\"1\":\"walls\",\"2\":\"player\",\"3\":\"enemies\",\"4\":\"enemy_bullets\",\"8\":\"player_bullets\"}",
			"input_schema": {
				"type": "object",
				"properties": {
					"layers": {"type": "object"}
				},
				"required": ["layers"]
			}
		}
	]


# ── UI ─────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	add_theme_constant_override("separation", 4)

	# ── Toolbar ──────────────────────────────────────────────────────
	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	var title := Label.new()
	title.text = "Claude Director"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bold_font = get_theme_font("bold", "EditorFonts")
	if bold_font:
		title.add_theme_font_override("font", bold_font)
	toolbar.add_child(title)

	var settings_btn := Button.new()
	settings_btn.text = "⚙"
	settings_btn.tooltip_text = "API Key Settings"
	settings_btn.flat = true
	settings_btn.pressed.connect(_toggle_settings)
	toolbar.add_child(settings_btn)

	var clear_btn := Button.new()
	clear_btn.text = "↺"
	clear_btn.tooltip_text = "Clear conversation history"
	clear_btn.flat = true
	clear_btn.pressed.connect(_clear_chat)
	toolbar.add_child(clear_btn)

	# ── Settings panel ────────────────────────────────────────────────
	_settings_panel = PanelContainer.new()
	_settings_panel.visible = false
	add_child(_settings_panel)

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	_settings_panel.add_child(sv)

	var key_lbl := Label.new()
	key_lbl.text = "Anthropic API Key:"
	sv.add_child(key_lbl)

	_api_key_field = LineEdit.new()
	_api_key_field.placeholder_text = "sk-ant-api03-..."
	_api_key_field.secret = true
	_api_key_field.text = _config.get("api_key", "")
	sv.add_child(_api_key_field)

	var save_key_btn := Button.new()
	save_key_btn.text = "Save Key"
	save_key_btn.pressed.connect(_save_api_key)
	sv.add_child(save_key_btn)

	# ── Chat history ──────────────────────────────────────────────────
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_chat_scroll)

	_chat_label = RichTextLabel.new()
	_chat_label.bbcode_enabled = true
	_chat_label.fit_content = true
	_chat_label.selection_enabled = true
	_chat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chat_scroll.add_child(_chat_label)

	_chat_label.append_text("[color=#666666]Welcome to Claude Director.\nAsk me to build or modify anything in your game.\nCtrl+Enter to send.[/color]\n\n")

	# ── Thinking indicator ────────────────────────────────────────────
	_thinking_label = Label.new()
	_thinking_label.text = ""
	_thinking_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thinking_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	add_child(_thinking_label)

	# ── Input row ─────────────────────────────────────────────────────
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 4)
	add_child(input_row)

	_user_input = TextEdit.new()
	_user_input.placeholder_text = "Ask Claude to build something..."
	_user_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_user_input.custom_minimum_size.y = 60
	_user_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_user_input.gui_input.connect(_on_input_event)
	input_row.add_child(_user_input)

	_send_btn = Button.new()
	_send_btn.text = "▶"
	_send_btn.tooltip_text = "Send (Ctrl+Enter)"
	_send_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_send_btn.custom_minimum_size.x = 32
	_send_btn.pressed.connect(_submit)
	input_row.add_child(_send_btn)


# ── API Setup ──────────────────────────────────────────────────────────────

func _setup_api() -> void:
	var tools_script = load("res://addons/claude_director/scene_tools.gd")
	_tools = tools_script.new()

	var api_script = load("res://addons/claude_director/claude_api.gd")
	_api = api_script.new()
	add_child(_api)

	_api.configure(_config.get("api_key", ""), _system_prompt, _tools_def, _tools)
	_api.response_received.connect(_on_response)
	_api.tool_called.connect(_on_tool_called)
	_api.tool_result_ready.connect(_on_tool_result)
	_api.error_occurred.connect(_on_error)
	_api.thinking_changed.connect(_on_thinking)
	_api.conversation_finished.connect(_on_finished)


# ── Settings Handlers ──────────────────────────────────────────────────────

func _toggle_settings() -> void:
	_settings_panel.visible = not _settings_panel.visible


func _save_api_key() -> void:
	_config["api_key"] = _api_key_field.text.strip_edges()
	_save_config()
	_build_prompts()  # re-reads CLAUDE_DIRECTOR.md so context changes take effect
	_api.configure(_config.get("api_key", ""), _system_prompt, _tools_def, _tools)
	_settings_panel.visible = false
	_append_bbcode("[color=#88ff88]✓ Settings saved. Project context reloaded.[/color]\n\n")


# ── Chat Handlers ──────────────────────────────────────────────────────────

func _clear_chat() -> void:
	if _api:
		_api.clear_history()
	_chat_label.clear()
	_chat_label.append_text("[color=#666666]Conversation cleared.[/color]\n\n")


func _on_input_event(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.ctrl_pressed and ke.keycode == KEY_ENTER:
			_submit()
			get_viewport().set_input_as_handled()


func _submit() -> void:
	if _is_busy:
		return
	var text := _user_input.text.strip_edges()
	if text.is_empty():
		return
	_user_input.text = ""
	_is_busy = true
	_set_interactive(false)
	_append_bbcode("[color=#66aaff][b]You:[/b][/color] " + _esc(text) + "\n\n")
	_api.send(text)


func _set_interactive(enabled: bool) -> void:
	_user_input.editable = enabled
	_send_btn.disabled = not enabled


# ── API Signal Handlers ────────────────────────────────────────────────────

func _on_response(text: String) -> void:
	_append_bbcode("[color=#cc99ff][b]Claude:[/b][/color] " + _esc(text) + "\n\n")


func _on_tool_called(tool_name: String, tool_input: Dictionary) -> void:
	var summary := JSON.stringify(tool_input)
	if summary.length() > 100:
		summary = summary.left(100) + "…"
	_append_bbcode("[color=#ffcc55]▶ [b]" + tool_name + "[/b][/color]  [color=#888888]" + _esc(summary) + "[/color]\n")


func _on_tool_result(tool_name: String, result: Dictionary) -> void:
	var ok := result.has("success") or result.has("files") or \
			  result.has("content") or result.has("root") or result.has("bytes")
	var col := "#77dd77" if ok else "#ff7777"
	var summary := JSON.stringify(result)
	if summary.length() > 120:
		summary = summary.left(120) + "…"
	_append_bbcode("[color=" + col + "]  ✓ " + _esc(summary) + "[/color]\n")


func _on_error(message: String) -> void:
	_append_bbcode("[color=#ff6666][b]Error:[/b] " + _esc(message) + "[/color]\n\n")


func _on_thinking(is_thinking: bool) -> void:
	_thinking_label.text = "⏳  Claude is thinking…" if is_thinking else ""


func _on_finished() -> void:
	_is_busy = false
	_set_interactive(true)
	_thinking_label.text = ""
	_scroll_bottom()


# ── Helpers ────────────────────────────────────────────────────────────────

func _append_bbcode(bbcode: String) -> void:
	_chat_label.append_text(bbcode)
	_scroll_bottom()


func _esc(text: String) -> String:
	# Escape BBCode bracket so user/AI text doesn't accidentally trigger tags
	return text.replace("[", "[lb]")


func _scroll_bottom() -> void:
	call_deferred("_do_scroll")


func _do_scroll() -> void:
	if is_instance_valid(_chat_scroll):
		_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)
