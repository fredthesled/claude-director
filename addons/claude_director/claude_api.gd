@tool
extends Node

signal response_received(text: String)
signal tool_called(tool_name: String, tool_input: Dictionary)
signal tool_result_ready(tool_name: String, result: Dictionary)
signal error_occurred(message: String)
signal thinking_changed(is_thinking: bool)
signal conversation_finished

const API_URL := "https://api.anthropic.com/v1/messages"
const MODEL := "claude-sonnet-4-6"
const MAX_TOKENS := 8096
const MAX_TOOL_ROUNDS := 15
const MAX_RETRIES := 3

var _api_key: String = ""
var _system: String = ""
var _tools_def: Array = []
var _scene_tools: RefCounted = null
var _messages: Array = []
var _tool_round: int = 0
var _retry_count: int = 0
var _http: HTTPRequest
var _dl_http: HTTPRequest   # dedicated downloader — never shares with Claude API


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 120.0
	add_child(_http)
	_http.request_completed.connect(_on_completed)

	_dl_http = HTTPRequest.new()
	_dl_http.timeout = 300.0  # large asset packs can be slow
	add_child(_dl_http)


func configure(api_key: String, system: String, tools_def: Array, scene_tools: RefCounted) -> void:
	_api_key = api_key
	_system = system
	_tools_def = tools_def
	_scene_tools = scene_tools


func clear_history() -> void:
	_messages.clear()


func send(user_text: String) -> void:
	_tool_round = 0
	_messages.append({"role": "user", "content": user_text})
	_send_request()


func _send_request() -> void:
	if _api_key.strip_edges().is_empty():
		error_occurred.emit("API key not set — open ⚙ Settings and paste your Anthropic key.")
		conversation_finished.emit()
		return

	thinking_changed.emit(true)

	# Wrap system as array block so the cache_control field is accepted
	var sys := [{"type": "text", "text": _system, "cache_control": {"type": "ephemeral"}}]

	# Tag the last tool entry for caching — tools list is static across all calls
	var tools := _tools_def.duplicate()
	if not tools.is_empty():
		var last: Dictionary = (tools[-1] as Dictionary).duplicate()
		last["cache_control"] = {"type": "ephemeral"}
		tools[-1] = last

	var body := JSON.stringify({
		"model": MODEL,
		"max_tokens": MAX_TOKENS,
		"system": sys,
		"tools": tools,
		"messages": _windowed_messages()
	})

	var err := _http.request(
		API_URL,
		PackedStringArray([
			"x-api-key: " + _api_key,
			"anthropic-version: 2023-06-01",
			"anthropic-beta: prompt-caching-2024-07-31",
			"content-type: application/json"
		]),
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		thinking_changed.emit(false)
		error_occurred.emit("Failed to send request (err=%d). Check your network." % err)
		conversation_finished.emit()


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	# Retry on rate-limit with exponential backoff before doing anything else
	if code == 429 and _retry_count < MAX_RETRIES:
		_retry_count += 1
		var wait := float(_retry_count * 5)  # 5 s, 10 s, 15 s
		await get_tree().create_timer(wait).timeout
		_send_request()
		return

	_retry_count = 0
	thinking_changed.emit(false)

	if result != HTTPRequest.RESULT_SUCCESS:
		error_occurred.emit("HTTP request failed (result=%d). Check your internet connection." % result)
		conversation_finished.emit()
		return

	if code != 200:
		error_occurred.emit("API error %d: %s" % [code, body.get_string_from_utf8()])
		conversation_finished.emit()
		return

	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		error_occurred.emit("Could not parse API response as JSON")
		conversation_finished.emit()
		return

	_handle_response(data as Dictionary)


func _handle_response(data: Dictionary) -> void:
	var content: Array = data.get("content", [])
	var stop_reason: String = data.get("stop_reason", "end_turn")

	_messages.append({"role": "assistant", "content": _compress_assistant_content(content)})

	var text_parts: PackedStringArray
	var tool_uses: Array = []

	for block in content:
		match block.get("type", ""):
			"text":
				text_parts.append(block.get("text", ""))
			"tool_use":
				tool_uses.append(block)

	if text_parts.size() > 0:
		response_received.emit("\n".join(text_parts))

	if stop_reason == "tool_use" and not tool_uses.is_empty():
		if _tool_round >= MAX_TOOL_ROUNDS:
			error_occurred.emit("Reached max tool rounds (%d). Stopping." % MAX_TOOL_ROUNDS)
			conversation_finished.emit()
			return

		_tool_round += 1
		var results: Array = []

		for tu in tool_uses:
			var tname: String = tu.get("name", "")
			var tinput: Dictionary = tu.get("input", {})
			var tid: String = tu.get("id", "")

			tool_called.emit(tname, tinput)
			# asset_fetch is async (HTTP download); everything else is sync.
			var result: Dictionary
			if tname == "asset_fetch":
				result = await _fetch_asset(tinput)
			else:
				result = _dispatch(tname, tinput)
			tool_result_ready.emit(tname, result)

			# Screenshot returns a vision content block; everything else is JSON.
			var tool_content: Variant
			if tname == "shot" and not result.has("error"):
				tool_content = _build_screenshot_content(result)
			else:
				tool_content = _compress_result(result)

			results.append({
				"type": "tool_result",
				"tool_use_id": tid,
				"content": tool_content
			})

		_messages.append({"role": "user", "content": results})
		_send_request()
	else:
		conversation_finished.emit()


func _dispatch(tool_name: String, input: Dictionary) -> Dictionary:
	if not _scene_tools:
		return {"error": "Scene tools not available"}

	match tool_name:
		"files":
			return _scene_tools.get_project_files(
				input.get("path", "res://"),
				input.get("ext", [])
			)
		"read":
			return _scene_tools.read_file(input.get("path", ""))
		"write":
			return _scene_tools.write_file(input.get("path", ""), input.get("content", ""))
		"node_add":
			return _scene_tools.create_node(
				input.get("type", ""),
				input.get("name", "Node"),
				input.get("parent", ".")
			)
		"node_rm":
			return _scene_tools.remove_node(input.get("path", ""))
		"node_prop":
			return _scene_tools.set_node_property(
				input.get("path", ""),
				input.get("prop", ""),
				input.get("value")
			)
		"node_script":
			return _scene_tools.set_node_script(
				input.get("node", ""),
				input.get("script", "")
			)
		"scene_new":
			return _scene_tools.create_scene(
				input.get("path", ""),
				input.get("root", "Node2D")
			)
		"scene_open":
			return _scene_tools.open_scene(input.get("path", ""))
		"scene_save":
			return _scene_tools.save_scene(input.get("path", ""))
		"run":
			return _scene_tools.run_project(input.get("action", "play"))
		"node_props":
			return _scene_tools.node_get_properties(
				input.get("path", "."),
				input.get("filter", "")
			)
		"node_find":
			return _scene_tools.node_find(
				input.get("query", ""),
				input.get("by", "name")
			)
		"patch":
			return _scene_tools.script_patch(
				input.get("path", ""),
				input.get("old", ""),
				input.get("new", "")
			)
		"sig_connect":
			return _scene_tools.signal_connect(
				input.get("source", "."),
				input.get("signal", ""),
				input.get("target", "."),
				input.get("method", "")
			)
		"logs":
			return _scene_tools.logs_read(input.get("lines", 80))
		"shot":
			return _scene_tools.take_screenshot()
		"info":
			return _scene_tools.get_editor_info()
		"setting":
			return _scene_tools.manage_setting(
				input.get("op", "get"),
				input.get("key", ""),
				input.get("value")
			)
		"autoload":
			return _scene_tools.manage_autoload(
				input.get("op", "list"),
				input.get("name", ""),
				input.get("path", "")
			)
		"node_dup":
			return _scene_tools.duplicate_node(
				input.get("path", ""),
				input.get("parent", ".")
			)
		"tree":
			return _scene_tools.get_scene_tree(input.get("depth", -1))
		"node_call":
			return _scene_tools.node_call(
				input.get("path", "."),
				input.get("method", ""),
				input.get("args", [])
			)
		"scene_instance":
			return _scene_tools.scene_instance(
				input.get("scene", ""),
				input.get("name", ""),
				input.get("parent", ".")
			)
		"signals":
			return _scene_tools.node_list_signals(input.get("path", "."))
		"sig_off":
			return _scene_tools.signal_disconnect(
				input.get("source", "."),
				input.get("signal", ""),
				input.get("target", "."),
				input.get("method", "")
			)
		"res_new":
			return _scene_tools.resource_new(
				input.get("type", ""),
				input.get("node", "."),
				input.get("prop", ""),
				input.get("init", {})
			)
		"group":
			return _scene_tools.node_group(
				input.get("op", "list"),
				input.get("path", "."),
				input.get("group", "")
			)
		"input":
			return _scene_tools.manage_input_action(
				input.get("op", "list"),
				input.get("action", ""),
				input.get("key", "")
			)
		"fs":
			return _scene_tools.manage_filesystem(
				input.get("op", "ls"),
				input.get("path", "res://")
			)
		"zip_extract":
			return _scene_tools.extract_zip(
				input.get("path", ""),
				input.get("dest", "res://assets/")
			)
		"res_load":
			return _scene_tools.res_load(
				input.get("node", "."),
				input.get("prop", ""),
				input.get("path", "")
			)
		"paint":
			return _scene_tools.tilemap_paint(
				input.get("node",      "."),
				input.get("cells",     []),
				input.get("grid",      []),
				input.get("tile_map",  {}),
				input.get("origin",    [0, 0]),
				input.get("source_id", 0),
				input.get("clear",     false)
			)
		"anim":
			return _scene_tools.anim_create(
				input.get("node",   ""),
				input.get("name",   ""),
				input.get("length", 1.0),
				input.get("tracks", []),
				input.get("loop",   0)
			)
		"node_move":
			return _scene_tools.node_reparent(
				input.get("path",       ""),
				input.get("parent",     "."),
				input.get("keep_xform", true)
			)
		"phys_layers":
			return _scene_tools.physics_layers_setup(input.get("layers", {}))
		"img_info":
			return _scene_tools.img_info(input.get("path", ""))
		"sprite_frames":
			return _scene_tools.sprite_frames_create(
				input.get("save_path", ""),
				input.get("source",    ""),
				input.get("tile_w",    16),
				input.get("tile_h",    16),
				input.get("animations", []),
				input.get("apply_to",  "")
			)
		"tileset":
			return _scene_tools.tileset_setup(
				input.get("save_path",    ""),
				input.get("source_image", ""),
				input.get("tile_w",       16),
				input.get("tile_h",       16)
			)
		"res_prop":
			return _scene_tools.res_prop(
				input.get("node",     "."),
				input.get("res_prop", ""),
				input.get("prop",     ""),
				input.get("value")
			)
		"asset_fetch":
			return {"error": "asset_fetch is async and cannot be used inside batch"}
		"batch":
			# Meta-tool: execute a sequence of tool calls without extra round-trips.
			var commands: Array = input.get("commands", [])
			var results: Array = []
			for cmd in commands:
				var tname: String = cmd.get("tool", "")
				var tinput: Dictionary = cmd.get("input", {})
				var r := _dispatch(tname, tinput)
				results.append({"tool": tname, "ok": not r.has("error"), "r": r})
				if r.has("error"):
					return {"error": "Stopped at '%s': %s" % [tname, r["error"]], "done": results.size() - 1, "results": results}
			return {"ok": 1, "count": results.size(), "results": results}

	return {"error": "Unknown tool: " + tool_name}


# ── Asset Download ────────────────────────────────────────────────────────────

func _fetch_asset(input: Dictionary) -> Dictionary:
	var url: String      = input.get("url", "")
	var dest: String     = input.get("dest", "res://assets/")
	var filename: String = input.get("name", url.get_file())
	var extract: bool    = input.get("extract", false)

	if url.is_empty():
		return {"error": "url is required"}
	if filename.is_empty():
		filename = "asset_%d.bin" % Time.get_ticks_msec()

	# Ensure the destination directory exists
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))

	var abs_file := ProjectSettings.globalize_path(dest.path_join(filename))
	_dl_http.download_file = abs_file

	var err := _dl_http.request(url, PackedStringArray(["User-Agent: ClaudeDirector/1.0"]))
	if err != OK:
		_dl_http.download_file = ""
		return {"error": "Could not start download (err=%d). Check the URL." % err}

	# Suspend until the download finishes — editor remains responsive.
	var response: Array = await _dl_http.request_completed
	_dl_http.download_file = ""

	var net_result: int = response[0]
	var http_code: int  = response[1]

	if net_result != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Download failed (network error %d)" % net_result}
	if http_code != 200:
		return {"error": "Download failed (HTTP %d) — verify the direct download URL" % http_code}

	var res_path := dest.path_join(filename)

	if extract and filename.get_extension().to_lower() == "zip":
		var zip_result: Dictionary = _scene_tools.extract_zip(res_path, dest)
		if not zip_result.has("error") and input.get("delete_zip", true):
			var dir := DirAccess.open(dest)
			if dir:
				dir.remove(filename)
		return zip_result

	EditorInterface.get_resource_filesystem().scan()
	var kb := FileAccess.get_file_as_bytes(abs_file).size() / 1024
	return {"ok": 1, "path": res_path, "size_kb": kb}


# ── Screenshot vision block ───────────────────────────────────────────────────

func _build_screenshot_content(result: Dictionary) -> Variant:
	var path: String = result.get("path", "")
	if not FileAccess.file_exists(path):
		return '{"error":"Screenshot file missing: ' + path + '"}'

	var img_bytes := FileAccess.get_file_as_bytes(path)
	if img_bytes.is_empty():
		return '{"error":"Screenshot file is empty"}'

	# Anthropic vision: image content block inside tool_result
	return [
		{
			"type": "image",
			"source": {
				"type": "base64",
				"media_type": "image/png",
				"data": Marshalls.raw_to_base64(img_bytes)
			}
		},
		{
			"type": "text",
			"text": "Editor viewport screenshot (%dx%d)" % [
				result.get("width", 0), result.get("height", 0)
			]
		}
	]


# ── History management ────────────────────────────────────────────────────────

func _windowed_messages() -> Array:
	# Cap history to last 24 messages, always starting at a valid plain user
	# text message (not a tool_result array) so the API sees a valid sequence.
	const MAX_MSGS := 24
	if _messages.size() <= MAX_MSGS:
		return _messages
	var start := _messages.size() - MAX_MSGS
	for i in range(start, _messages.size()):
		var m := _messages[i] as Dictionary
		if m.get("role") == "user" and m.get("content") is String:
			return _messages.slice(i)
	# Fallback: include everything (shouldn't normally happen)
	return _messages


# ── Result compression ────────────────────────────────────────────────────────

func _compress_result(result: Dictionary) -> String:
	if result.has("error"):
		return JSON.stringify(result)

	# ── Inspection / query: preserve data, cap total size ──────────────────
	# node_props, node_find, logs, autoload list, setting list/get, info,
	# signals, groups, input actions, fs entries, batch results
	if result.has("properties") or result.has("matches") or result.has("log") \
	or result.has("autoloads") or result.has("settings") or result.has("godot") \
	or result.has("key") or result.has("signals") or result.has("groups") \
	or result.has("actions") or result.has("entries") or result.has("results") \
	or result.has("sample") or result.has("grids") or result.has("animations") \
	or result.has("total_tiles"):
		return _cap_json(result, 3000)

	# ── read: truncate long file content ───────────────────────────────────
	if result.has("content"):
		var text := str(result["content"])
		if text.length() > 2500:
			var d := result.duplicate()
			d["content"] = text.left(2500) + "\n…[%d chars omitted]" % (text.length() - 2500)
			return JSON.stringify(d)
		return JSON.stringify(result)

	# ── files: cap listing ─────────────────────────────────────────────────
	if result.has("files"):
		var files := result["files"] as Array
		if files.size() > 50:
			var d := result.duplicate()
			d["files"] = files.slice(0, 50)
			d["showing"] = "50/%d" % files.size()
			return JSON.stringify(d)
		return JSON.stringify(result)

	# ── scene_tree: full pass-through ──────────────────────────────────────
	if result.has("root"):
		return JSON.stringify(result)

	# ── Mutation operations: minimal ok response ────────────────────────────
	# write, node_add/rm/prop/script/dup, scene_new/open/save, run, patch, sig_connect
	var m: Dictionary = {"ok": 1}
	if result.has("path"):     m["path"]     = result["path"]
	if result.has("new"):      m["new"]      = result["new"]       # node_dup
	if result.has("new_path"): m["new_path"] = result["new_path"]  # node_move
	if result.has("type"):     m["type"]     = result["type"]
	if result.has("action"):   m["action"]   = result["action"]
	if result.has("wired"):    m["wired"]    = result["wired"]      # sig_connect
	if result.has("note"):     m["note"]     = result["note"]
	if result.has("set"):      m["set"]      = result["set"]        # phys_layers
	if result.has("painted"):  m["painted"]  = result["painted"]    # paint
	if result.has("animation"):m["animation"]= result["animation"]  # anim
	if result.has("on"):       m["on"]       = result["on"]         # res_load/res_new
	return JSON.stringify(m)


func _cap_json(d: Dictionary, max_chars: int) -> String:
	var s := JSON.stringify(d)
	if s.length() <= max_chars:
		return s
	# Smart truncation for known large fields
	if d.has("properties"):
		var props := d["properties"] as Dictionary
		var trimmed := d.duplicate()
		var tp: Dictionary = {}
		var chars := 0
		for k in props.keys():
			var entry := JSON.stringify({k: props[k]})
			if chars + entry.length() > max_chars - 60:
				tp["…omitted"] = str(props.size() - tp.size()) + " more"
				break
			tp[k] = props[k]
			chars += entry.length()
		trimmed["properties"] = tp
		return JSON.stringify(trimmed)
	if d.has("log"):
		var trimmed := d.duplicate()
		trimmed["log"] = str(d["log"]).left(max_chars - 80) + "…"
		return JSON.stringify(trimmed)
	return s.left(max_chars) + "…"


func _compress_assistant_content(content: Array) -> Array:
	# Strip large text bodies from stored tool_use inputs so that write/patch
	# file content doesn't get re-sent verbatim on every subsequent tool round.
	var out: Array = []
	for block in content:
		var b := block as Dictionary
		if b.get("type") != "tool_use":
			out.append(b)
			continue
		var inp := b.get("input", {}) as Dictionary
		var big := false
		for key in ["content", "old", "new"]:
			if inp.has(key) and str(inp[key]).length() > 120:
				big = true
				break
		if not big:
			out.append(b)
			continue
		b = b.duplicate(true)
		var ni := (b["input"] as Dictionary).duplicate()
		for key in ["content", "old", "new"]:
			if ni.has(key) and str(ni[key]).length() > 120:
				ni[key] = str(ni[key]).left(120) + "…"
		b["input"] = ni
		out.append(b)
	return out
