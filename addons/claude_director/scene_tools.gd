@tool
extends RefCounted

# ── File System ──────────────────────────────────────────────────────────────

func get_project_files(path: String = "res://", extensions: Array = []) -> Dictionary:
	var files: Array = []
	_collect_files(path, extensions, files)
	return {"files": files, "count": files.size()}


func _collect_files(dir_path: String, extensions: Array, result: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				if entry not in [".godot", ".import", ".git"]:
					_collect_files(full, extensions, result)
			else:
				if extensions.is_empty() or ("." + entry.get_extension()) in extensions:
					result.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "File not found: " + path}
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {"error": "Cannot open file: " + path}
	var content := f.get_as_text()
	f.close()
	return {"content": content, "path": path}


func write_file(path: String, content: String) -> Dictionary:
	var abs_dir := ProjectSettings.globalize_path(path.get_base_dir())
	var dir_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		return {"error": "Could not create directory: " + path.get_base_dir()}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return {"error": "Cannot write file: " + path}
	f.store_string(content)
	f.close()
	EditorInterface.get_resource_filesystem().scan()
	return {"success": true, "path": path, "bytes": content.length()}


# ── Scene Tree ───────────────────────────────────────────────────────────────

func get_scene_tree(max_depth: int = -1) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return {"error": "No scene is currently open in the editor"}
	return {
		"scene_path": root.scene_file_path,
		"root": _node_to_dict(root, root, 0, max_depth)
	}


func _node_to_dict(node: Node, scene_root: Node, depth: int = 0, max_depth: int = -1) -> Dictionary:
	var script_path := ""
	var s = node.get_script()
	if s:
		script_path = (s as Resource).resource_path

	var rel_path := "." if node == scene_root else str(scene_root.get_path_to(node))

	var children: Array = []
	if max_depth < 0 or depth < max_depth:
		for child in node.get_children():
			if child.owner == scene_root or child == scene_root:
				children.append(_node_to_dict(child, scene_root, depth + 1, max_depth))

	return {
		"name": node.name,
		"type": node.get_class(),
		"path": rel_path,
		"script": script_path,
		"children": children
	}


# ── Node Creation / Removal ──────────────────────────────────────────────────

func create_node(type: String, node_name: String, parent: String = ".") -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}

	if not ClassDB.class_exists(type):
		return {"error": "Unknown node type: " + type}

	var parent_node: Node
	if parent in [".", "", "/"]:
		parent_node = scene_root
	else:
		parent_node = scene_root.get_node_or_null(parent)
	if not parent_node:
		return {"error": "Parent node not found: " + parent}

	var node: Node = ClassDB.instantiate(type)
	node.name = node_name
	parent_node.add_child(node, true)
	node.owner = scene_root

	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)

	return {
		"success": true,
		"path": str(scene_root.get_path_to(node)),
		"type": type
	}


func remove_node(node_path: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}

	var node := scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}
	if node == scene_root:
		return {"error": "Cannot remove the scene root"}

	node.queue_free()
	return {"success": true, "removed": node_path}


# ── Node Properties ──────────────────────────────────────────────────────────

func set_node_property(node_path: String, property: String, value: Variant) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}

	var node: Node
	if node_path in [".", ""]:
		node = scene_root
	else:
		node = scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}

	var coerced := _coerce_value(value, node, property)
	node.set(property, coerced)
	return {"success": true, "node": node_path, "property": property}


func _coerce_value(value: Variant, node: Node, property: String) -> Variant:
	if not (value is Array):
		return value

	var arr: Array = value

	# Check declared property type first
	for prop_info in node.get_property_list():
		if prop_info.name == property:
			match prop_info.type:
				TYPE_VECTOR2:
					if arr.size() >= 2:
						return Vector2(arr[0], arr[1])
				TYPE_VECTOR2I:
					if arr.size() >= 2:
						return Vector2i(int(arr[0]), int(arr[1]))
				TYPE_VECTOR3:
					if arr.size() >= 3:
						return Vector3(arr[0], arr[1], arr[2])
				TYPE_COLOR:
					if arr.size() == 3:
						return Color(arr[0], arr[1], arr[2])
					elif arr.size() == 4:
						return Color(arr[0], arr[1], arr[2], arr[3])
				TYPE_RECT2:
					if arr.size() == 4:
						return Rect2(arr[0], arr[1], arr[2], arr[3])
			break

	# Fallback: infer from size
	match arr.size():
		2: return Vector2(arr[0], arr[1])
		3: return Vector3(arr[0], arr[1], arr[2])
		4: return Color(arr[0], arr[1], arr[2], arr[3])

	return value


func set_node_script(node_path: String, script_path: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}

	var node: Node
	if node_path in [".", ""]:
		node = scene_root
	else:
		node = scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}

	if not ResourceLoader.exists(script_path):
		return {"error": "Script not found: " + script_path + " — use write_file first"}

	var script: Script = ResourceLoader.load(
		script_path, "GDScript", ResourceLoader.CACHE_MODE_REPLACE
	)
	if not script:
		return {"error": "Failed to load script: " + script_path}

	node.set_script(script)
	return {"success": true, "node": node_path, "script": script_path}


# ── Scene Files ──────────────────────────────────────────────────────────────

func create_scene(path: String, root_type: String = "Node2D") -> Dictionary:
	if not ClassDB.class_exists(root_type):
		return {"error": "Unknown node type: " + root_type}

	var abs_dir := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(abs_dir)

	var root: Node = ClassDB.instantiate(root_type)
	root.name = path.get_file().get_basename()

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	root.free()

	if pack_err != OK:
		return {"error": "Failed to pack scene: " + str(pack_err)}

	var save_err := ResourceSaver.save(packed, path)
	if save_err != OK:
		return {"error": "Failed to save scene: " + str(save_err)}

	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)
	return {"success": true, "path": path, "root_type": root_type}


func open_scene(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {"error": "Scene file not found: " + path}
	EditorInterface.open_scene_from_path(path)
	return {"success": true, "path": path}


func save_scene(path: String = "") -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene is currently open"}

	if path.is_empty():
		var err := EditorInterface.save_scene()
		if err != OK:
			return {"error": "Save failed: " + str(err)}
		return {"success": true, "path": scene_root.scene_file_path}
	else:
		EditorInterface.save_scene_as(path)
		return {"success": true, "path": path}


# ── Project Control ──────────────────────────────────────────────────────────

func run_project(action: String = "play") -> Dictionary:
	match action:
		"play":
			EditorInterface.play_main_scene()
			return {"success": true, "action": "play"}
		"play_current":
			EditorInterface.play_current_scene()
			return {"success": true, "action": "play_current"}
		"stop":
			EditorInterface.stop_playing_scene()
			return {"success": true, "action": "stop"}
	return {"error": "Unknown action: " + action + ". Use 'play', 'play_current', or 'stop'"}


# ── Node Property Inspection ─────────────────────────────────────────────────

func node_get_properties(node_path: String, filter: String = "") -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var node: Node
	if node_path in [".", ""]:
		node = scene_root
	else:
		node = scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}

	var props: Dictionary = {}
	var filter_lower := filter.to_lower()

	for info in node.get_property_list():
		var pname: String = info["name"]
		var usage: int    = info["usage"]
		if info["type"] == TYPE_NIL:
			continue
		if not ((usage & PROPERTY_USAGE_EDITOR) or (usage & PROPERTY_USAGE_STORAGE)):
			continue
		if pname.begins_with("_") or pname == "script" or pname == "Script Variables":
			continue
		if filter_lower != "" and not pname.to_lower().contains(filter_lower):
			continue
		props[pname] = _variant_to_json(node.get(pname))

	return {"node": node_path, "type": node.get_class(), "properties": props}


func _variant_to_json(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_RECT2:
			return [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_NODE_PATH:
			return str(value)
		TYPE_OBJECT:
			if value == null:
				return null
			if value is Resource:
				return (value as Resource).resource_path
			return str(value)
		TYPE_ARRAY:
			var arr: Array = []
			for i in mini((value as Array).size(), 8):
				arr.append(_variant_to_json(value[i]))
			return arr
		TYPE_DICTIONARY:
			var d: Dictionary = {}
			var count := 0
			for k in value:
				if count >= 8: break
				d[str(k)] = _variant_to_json((value as Dictionary)[k])
				count += 1
			return d
		_:
			return str(value)


# ── Node Search ───────────────────────────────────────────────────────────────

func node_find(query: String, by: String = "name") -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var results: Array = []
	_find_recursive(scene_root, scene_root, query.to_lower(), by, results)
	return {"matches": results, "count": results.size()}


func _find_recursive(node: Node, scene_root: Node, query: String, by: String, out: Array) -> void:
	var hit := false
	match by:
		"name": hit = node.name.to_lower().contains(query)
		"type": hit = node.get_class().to_lower() == query or node.is_class(query)
		"script":
			var s = node.get_script()
			if s:
				hit = (s as Resource).resource_path.to_lower().contains(query)

	if hit:
		var rel := "." if node == scene_root else str(scene_root.get_path_to(node))
		var s   = node.get_script()
		out.append({
			"name":   node.name,
			"type":   node.get_class(),
			"path":   rel,
			"script": (s as Resource).resource_path if s else ""
		})

	for child in node.get_children():
		if child.owner == scene_root or child == scene_root:
			_find_recursive(child, scene_root, query, by, out)


# ── Script Patching ───────────────────────────────────────────────────────────

func script_patch(path: String, old_text: String, new_text: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "File not found: " + path}

	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {"error": "Cannot read: " + path}
	var content := f.get_as_text()
	f.close()

	if not content.contains(old_text):
		return {"error": "Exact text not found. Verify whitespace and indentation match precisely."}

	var occurrences := content.count(old_text)
	if occurrences > 1:
		return {"error": "Text found %d times — ambiguous. Add more surrounding context to old_text." % occurrences}

	var wf := FileAccess.open(path, FileAccess.WRITE)
	if not wf:
		return {"error": "Cannot write: " + path}
	wf.store_string(content.replace(old_text, new_text))
	wf.close()

	EditorInterface.get_resource_filesystem().scan()
	return {"ok": 1, "path": path}


# ── Signal Wiring ─────────────────────────────────────────────────────────────

func signal_connect(source_path: String, signal_name: String, target_path: String, method_name: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var source: Node = scene_root if source_path in [".", ""] else scene_root.get_node_or_null(source_path)
	if not source:
		return {"error": "Source node not found: " + source_path}

	var target: Node = scene_root if target_path in [".", ""] else scene_root.get_node_or_null(target_path)
	if not target:
		return {"error": "Target node not found: " + target_path}

	if not source.has_signal(signal_name):
		return {"error": "Signal '%s' not found on %s" % [signal_name, source.get_class()]}

	if not target.has_method(method_name):
		return {"error": "Method '%s' not found on %s (attach and reload script first)" % [method_name, target.name]}

	var callable := Callable(target, method_name)
	if source.is_connected(signal_name, callable):
		return {"ok": 1, "note": "already connected"}

	# CONNECT_PERSIST = 2: connection is saved with the scene file
	var err := source.connect(signal_name, callable, 2)
	if err != OK:
		return {"error": "connect() failed: " + str(err)}

	return {
		"ok": 1,
		"wired": "%s.%s → %s.%s" % [source_path, signal_name, target_path, method_name],
		"note": "call scene_save to persist"
	}


# ── Log Reader ────────────────────────────────────────────────────────────────

func logs_read(last_lines: int = 80) -> Dictionary:
	var log_path := OS.get_user_data_dir() + "/logs/godot.log"
	if not FileAccess.file_exists(log_path):
		return {
			"error": "Log not found at " + log_path,
			"hint": "Run the project at least once to generate the log file."
		}

	var f := FileAccess.open(log_path, FileAccess.READ)
	if not f:
		return {"error": "Cannot open log: " + log_path}
	var content := f.get_as_text()
	f.close()

	var lines   := content.split("\n")
	var start   := maxi(0, lines.size() - last_lines)
	var recent  := lines.slice(start)

	return {
		"log":         "\n".join(recent),
		"total_lines": lines.size(),
		"showing":     recent.size()
	}


# ── Screenshot ────────────────────────────────────────────────────────────────

func take_screenshot() -> Dictionary:
	# Prefer the focused 2D editor viewport; fall back to full editor window.
	var img: Image
	var vp2d := EditorInterface.get_editor_viewport_2d()
	if vp2d:
		img = vp2d.get_texture().get_image()
	if not img or img.is_empty():
		img = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	if not img or img.is_empty():
		return {"error": "Could not capture viewport image"}

	# Resize to keep token cost reasonable while staying readable.
	if img.get_width() > 960:
		var h := int(960.0 * img.get_height() / img.get_width())
		img.resize(960, h, Image.INTERPOLATE_BILINEAR)

	var path := OS.get_user_data_dir() + "/claude_director_shot.png"
	var err  := img.save_png(path)
	if err != OK:
		return {"error": "Failed to save screenshot: " + str(err)}

	return {"path": path, "width": img.get_width(), "height": img.get_height()}


# ── Editor / Project Info ─────────────────────────────────────────────────────

func get_editor_info() -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	var v          := Engine.get_version_info()
	return {
		"godot":        "%d.%d.%d" % [v["major"], v["minor"], v["patch"]],
		"project":      ProjectSettings.get_setting("application/config/name"),
		"project_path": ProjectSettings.globalize_path("res://"),
		"main_scene":   ProjectSettings.get_setting("application/run/main_scene"),
		"open_scene":   scene_root.scene_file_path if scene_root else "",
		"scene_type":   scene_root.get_class() if scene_root else ""
	}


# ── Project Settings ──────────────────────────────────────────────────────────

func manage_setting(op: String, key: String, value: Variant = null) -> Dictionary:
	match op:
		"get":
			if not ProjectSettings.has_setting(key):
				return {"error": "Setting not found: " + key}
			return {"key": key, "value": _variant_to_json(ProjectSettings.get_setting(key))}
		"set":
			ProjectSettings.set_setting(key, value)
			ProjectSettings.save()
			return {"ok": 1, "key": key}
		"list":
			# key is used as a name prefix filter here
			var results: Dictionary = {}
			for prop in ProjectSettings.get_property_list():
				var pname: String = prop["name"]
				if pname.begins_with(key) and not pname.begins_with("_"):
					results[pname] = _variant_to_json(ProjectSettings.get_setting(pname))
			return {"settings": results, "count": results.size()}
	return {"error": "Unknown op '%s'. Use get/set/list." % op}


# ── Autoload Management ───────────────────────────────────────────────────────

func manage_autoload(op: String, name: String = "", path: String = "") -> Dictionary:
	match op:
		"list":
			var autoloads: Dictionary = {}
			for prop in ProjectSettings.get_property_list():
				var pname: String = prop["name"]
				if pname.begins_with("autoload/"):
					var al := pname.substr("autoload/".length())
					autoloads[al] = ProjectSettings.get_setting(pname)
			return {"autoloads": autoloads}
		"add":
			if name.is_empty() or path.is_empty():
				return {"error": "name and path are required"}
			ProjectSettings.set_setting("autoload/" + name, "*" + path)
			ProjectSettings.save()
			return {"ok": 1, "autoload": name, "path": path}
		"remove":
			if name.is_empty():
				return {"error": "name is required"}
			var key := "autoload/" + name
			if not ProjectSettings.has_setting(key):
				return {"error": "Autoload not found: " + name}
			ProjectSettings.set_setting(key, "")
			ProjectSettings.save()
			return {"ok": 1, "removed": name}
	return {"error": "Unknown op '%s'. Use list/add/remove." % op}


# ── Node Duplication ──────────────────────────────────────────────────────────

func duplicate_node(node_path: String, new_parent: String = ".") -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var source: Node = scene_root if node_path in [".", ""] else scene_root.get_node_or_null(node_path)
	if not source:
		return {"error": "Node not found: " + node_path}
	if source == scene_root:
		return {"error": "Cannot duplicate the scene root"}

	var parent: Node = scene_root if new_parent in [".", ""] else scene_root.get_node_or_null(new_parent)
	if not parent:
		return {"error": "Parent not found: " + new_parent}

	var dup := source.duplicate()
	parent.add_child(dup, true)
	_set_owner_recursive(dup, scene_root)

	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(dup)

	return {"ok": 1, "original": node_path, "new": str(scene_root.get_path_to(dup))}


func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive(child, owner)


# ── Method Call ───────────────────────────────────────────────────────────────

func node_call(node_path: String, method: String, args: Array = []) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var node: Node
	if node_path in [".", ""]:
		node = scene_root
	else:
		node = scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}

	if not node.has_method(method):
		return {"error": "Method '%s' not found on %s" % [method, node.get_class()]}

	# Coerce Array args to Godot types so callers can pass [r,g,b,a] for Color,
	# [x,y] for Vector2, etc. without needing a separate encoding.
	var coerced: Array = []
	for arg in args:
		coerced.append(_coerce_arg(arg))

	var ret: Variant = node.callv(method, coerced)
	var out: Dictionary = {"ok": 1}
	if ret != null:
		out["returned"] = _variant_to_json(ret)
	return out


func _coerce_arg(arg: Variant) -> Variant:
	if not (arg is Array):
		return arg
	var a := arg as Array
	match a.size():
		2: return Vector2(a[0], a[1])
		3: return Vector3(a[0], a[1], a[2])
		4: return Color(a[0], a[1], a[2], a[3])
	return arg


# ── Scene Instancing ──────────────────────────────────────────────────────────

func scene_instance(scene_path: String, node_name: String = "", parent: String = ".") -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	if not ResourceLoader.exists(scene_path):
		return {"error": "Scene not found: " + scene_path}

	var packed: PackedScene = ResourceLoader.load(scene_path, "PackedScene")
	if not packed:
		return {"error": "Failed to load: " + scene_path}

	var instance := packed.instantiate()
	if not node_name.is_empty():
		instance.name = node_name

	var parent_node: Node
	if parent in [".", ""]:
		parent_node = scene_root
	else:
		parent_node = scene_root.get_node_or_null(parent)
	if not parent_node:
		instance.free()
		return {"error": "Parent not found: " + parent}

	parent_node.add_child(instance, true)
	_set_owner_recursive(instance, scene_root)

	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(instance)

	return {
		"ok": 1,
		"path": str(scene_root.get_path_to(instance)),
		"type": instance.get_class()
	}


# ── Signal Listing & Disconnection ────────────────────────────────────────────

func node_list_signals(node_path: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}
	var node: Node
	if node_path in [".", ""]:
		node = scene_root
	else:
		node = scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}

	var sigs: Array = []
	for sig_info in node.get_signal_list():
		var args: PackedStringArray
		for arg in sig_info.get("args", []):
			args.append(arg.get("name", "?"))
		sigs.append("%s(%s)" % [sig_info["name"], ", ".join(args)])

	return {"node": node_path, "type": node.get_class(), "signals": sigs}


func signal_disconnect(source_path: String, signal_name: String, target_path: String, method_name: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var source: Node = scene_root if source_path in [".", ""] else scene_root.get_node_or_null(source_path)
	if not source:
		return {"error": "Source not found: " + source_path}

	var target: Node = scene_root if target_path in [".", ""] else scene_root.get_node_or_null(target_path)
	if not target:
		return {"error": "Target not found: " + target_path}

	var callable := Callable(target, method_name)
	if not source.is_connected(signal_name, callable):
		return {"ok": 1, "note": "was not connected"}

	source.disconnect(signal_name, callable)
	return {"ok": 1, "disconnected": "%s.%s → %s.%s" % [source_path, signal_name, target_path, method_name]}


# ── Resource Creation ─────────────────────────────────────────────────────────

func resource_new(res_type: String, node_path: String, prop: String, init: Dictionary = {}) -> Dictionary:
	if not ClassDB.class_exists(res_type):
		return {"error": "Unknown class: " + res_type}

	var obj: Variant = ClassDB.instantiate(res_type)
	if not obj is Resource:
		if obj is Object:
			(obj as Object).free()
		return {"error": res_type + " is not a Resource"}

	var res := obj as Resource
	for key in init:
		res.set(key, _coerce_arg(init[key]))

	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var node: Node
	if node_path in [".", ""]:
		node = scene_root
	else:
		node = scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}

	node.set(prop, res)
	return {"ok": 1, "resource": res_type, "on": node_path + "." + prop}


# ── Node Groups ───────────────────────────────────────────────────────────────

func node_group(op: String, node_path: String, group: String = "") -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var node: Node
	if node_path in [".", ""]:
		node = scene_root
	else:
		node = scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}

	match op:
		"add":
			if group.is_empty():
				return {"error": "group required"}
			node.add_to_group(group, true)   # persist=true saves to scene file
			return {"ok": 1, "node": node_path, "group": group}
		"remove":
			if group.is_empty():
				return {"error": "group required"}
			node.remove_from_group(group)
			return {"ok": 1, "removed": group}
		"list":
			return {"groups": node.get_groups(), "node": node_path}

	return {"error": "Unknown op '%s'. Use add/remove/list." % op}


# ── Input Action Management ───────────────────────────────────────────────────

func manage_input_action(op: String, action: String = "", key: String = "") -> Dictionary:
	match op:
		"list":
			var result: Dictionary = {}
			for action_name in InputMap.get_actions():
				var an := str(action_name)
				if an.begins_with("ui_"):
					continue
				var keys: Array = []
				for event in InputMap.action_get_events(action_name):
					if event is InputEventKey:
						var ke := event as InputEventKey
						var kc := ke.physical_keycode if ke.physical_keycode != KEY_NONE else ke.keycode
						keys.append(OS.get_keycode_string(kc))
					elif event is InputEventMouseButton:
						keys.append("mouse_%d" % (event as InputEventMouseButton).button_index)
				result[an] = keys
			return {"actions": result}

		"add_key":
			if action.is_empty() or key.is_empty():
				return {"error": "action and key are required"}
			var kc := _key_from_string(key)
			if kc == KEY_NONE:
				return {"error": "Unknown key '%s'. Use A-Z, 0-9, F1-F12, Space, Enter, Escape, Left/Right/Up/Down, Shift, Ctrl, Alt, Tab, Delete, Backspace, etc." % key}
			if not InputMap.has_action(action):
				InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = kc
			InputMap.action_add_event(action, event)
			ProjectSettings.set_setting("input/" + action, {
				"deadzone": 0.5,
				"events": InputMap.action_get_events(action)
			})
			ProjectSettings.save()
			return {"ok": 1, "action": action, "key": key}

		"remove":
			if action.is_empty():
				return {"error": "action required"}
			if InputMap.has_action(action):
				InputMap.erase_action(action)
			if ProjectSettings.has_setting("input/" + action):
				ProjectSettings.set_setting("input/" + action, null)
				ProjectSettings.save()
			return {"ok": 1, "removed": action}

	return {"error": "Unknown op '%s'. Use list/add_key/remove." % op}


func _key_from_string(key: String) -> Key:
	var m: Dictionary = {
		"A": KEY_A, "B": KEY_B, "C": KEY_C, "D": KEY_D, "E": KEY_E,
		"F": KEY_F, "G": KEY_G, "H": KEY_H, "I": KEY_I, "J": KEY_J,
		"K": KEY_K, "L": KEY_L, "M": KEY_M, "N": KEY_N, "O": KEY_O,
		"P": KEY_P, "Q": KEY_Q, "R": KEY_R, "S": KEY_S, "T": KEY_T,
		"U": KEY_U, "V": KEY_V, "W": KEY_W, "X": KEY_X, "Y": KEY_Y, "Z": KEY_Z,
		"0": KEY_0, "1": KEY_1, "2": KEY_2, "3": KEY_3, "4": KEY_4,
		"5": KEY_5, "6": KEY_6, "7": KEY_7, "8": KEY_8, "9": KEY_9,
		"F1": KEY_F1, "F2": KEY_F2, "F3": KEY_F3, "F4": KEY_F4,
		"F5": KEY_F5, "F6": KEY_F6, "F7": KEY_F7, "F8": KEY_F8,
		"F9": KEY_F9, "F10": KEY_F10, "F11": KEY_F11, "F12": KEY_F12,
		"Space": KEY_SPACE, "Enter": KEY_ENTER, "Escape": KEY_ESCAPE,
		"Tab": KEY_TAB, "Shift": KEY_SHIFT, "Ctrl": KEY_CTRL, "Alt": KEY_ALT,
		"Left": KEY_LEFT, "Right": KEY_RIGHT, "Up": KEY_UP, "Down": KEY_DOWN,
		"Delete": KEY_DELETE, "Backspace": KEY_BACKSPACE,
		"Home": KEY_HOME, "End": KEY_END,
		"PageUp": KEY_PAGEUP, "PageDown": KEY_PAGEDOWN,
		"Insert": KEY_INSERT, "Minus": KEY_MINUS, "Period": KEY_PERIOD,
		"Comma": KEY_COMMA, "Slash": KEY_SLASH, "Semicolon": KEY_SEMICOLON,
		"Backslash": KEY_BACKSLASH, "Grave": KEY_QUOTELEFT
	}
	return m.get(key, KEY_NONE) as Key


# ── Filesystem Operations ─────────────────────────────────────────────────────

func manage_filesystem(op: String, path: String) -> Dictionary:
	match op:
		"exists":
			return {
				"path":   path,
				"is_file": FileAccess.file_exists(path),
				"is_dir":  DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))
			}
		"delete":
			if not FileAccess.file_exists(path):
				return {"error": "File not found: " + path}
			var dir := DirAccess.open(path.get_base_dir())
			if not dir:
				return {"error": "Cannot open directory: " + path.get_base_dir()}
			var err := dir.remove(path.get_file())
			if err != OK:
				return {"error": "Delete failed (err=%d): %s" % [err, path]}
			EditorInterface.get_resource_filesystem().scan()
			return {"ok": 1, "deleted": path}
		"mkdir":
			var abs := ProjectSettings.globalize_path(path)
			var err := DirAccess.make_dir_recursive_absolute(abs)
			if err != OK and err != ERR_ALREADY_EXISTS:
				return {"error": "mkdir failed: " + str(err)}
			EditorInterface.get_resource_filesystem().scan()
			return {"ok": 1, "created": path}
		"ls":
			var entries: Array = []
			var dir := DirAccess.open(path)
			if not dir:
				return {"error": "Cannot open: " + path}
			dir.list_dir_begin()
			var entry := dir.get_next()
			while entry != "":
				if not entry.begins_with("."):
					var full := path.path_join(entry)
					entries.append(full + ("/" if dir.current_is_dir() else ""))
				entry = dir.get_next()
			dir.list_dir_end()
			return {"entries": entries, "count": entries.size()}

	return {"error": "Unknown op '%s'. Use exists/delete/mkdir/ls." % op}


# ── ZIP Extraction ────────────────────────────────────────────────────────────

func extract_zip(zip_path: String, dest_dir: String) -> Dictionary:
	if not FileAccess.file_exists(zip_path):
		return {"error": "ZIP not found: " + zip_path}

	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		return {"error": "Cannot open ZIP (err=%d): %s" % [err, zip_path]}

	var extracted := 0
	var sample: Array = []

	for entry in reader.get_files():
		if entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(
				ProjectSettings.globalize_path(dest_dir.path_join(entry))
			)
			continue

		var data := reader.read_file(entry)
		var out  := dest_dir.path_join(entry)
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(out.get_base_dir())
		)
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f:
			f.store_buffer(data)
			f.close()
			extracted += 1
			if sample.size() < 12:
				sample.append(out)

	reader.close()
	EditorInterface.get_resource_filesystem().scan()
	return {"ok": 1, "extracted": extracted, "dest": dest_dir, "sample": sample}


# ── Resource Load & Assign ────────────────────────────────────────────────────

func res_load(node_path: String, prop: String, resource_path: String) -> Dictionary:
	if not ResourceLoader.exists(resource_path):
		return {"error": "Resource not found: " + resource_path + " (scan filesystem or check path)"}

	var res: Resource = ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if not res:
		return {"error": "Failed to load: " + resource_path}

	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var node: Node
	if node_path in [".", ""]:
		node = scene_root
	else:
		node = scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}

	node.set(prop, res)
	return {"ok": 1, "loaded": resource_path, "on": node_path + "." + prop}


# ── Image Info ────────────────────────────────────────────────────────────────

func img_info(path: String) -> Dictionary:
	var w := 0
	var h := 0

	# Prefer the resource system (works after Godot import scan)
	if ResourceLoader.exists(path):
		var r = ResourceLoader.load(path)
		if r is Texture2D:
			var img := (r as Texture2D).get_image()
			if img:
				w = img.get_width()
				h = img.get_height()

	# Fallback: read raw file bytes (works on freshly-extracted assets)
	if w == 0:
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(path)) == OK:
			w = img.get_width()
			h = img.get_height()

	if w == 0:
		return {"error": "Cannot read image: " + path + " (run asset_fetch or scan first)"}

	# Pre-calculate tile grid dimensions at common pixel sizes so Claude
	# doesn't have to do the arithmetic before calling sprite_frames/tileset.
	var grids: Dictionary = {}
	for sz in [8, 16, 32, 48]:
		if w % sz == 0 and h % sz == 0:
			grids[str(sz)] = [w / sz, h / sz]

	return {"path": path, "width": w, "height": h, "grids": grids}


# ── SpriteFrames Creation ─────────────────────────────────────────────────────

func sprite_frames_create(
		save_path: String,
		source: String,
		tile_w: int,
		tile_h: int,
		animations: Array,
		apply_to: String = "") -> Dictionary:

	# Load the spritesheet once (may be empty string for individual-image mode)
	var source_tex: Texture2D = null
	if not source.is_empty():
		if not ResourceLoader.exists(source):
			return {"error": "Spritesheet not found: " + source}
		source_tex = ResourceLoader.load(source, "Texture2D")
		if not source_tex:
			return {"error": "Cannot load spritesheet: " + source}

	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")

	for anim in animations:
		var aname: String = anim.get("name", "idle")
		var fps:   float  = float(anim.get("fps",  8.0))
		var loop:  bool   = anim.get("loop", true)

		sf.add_animation(aname)
		sf.set_animation_speed(aname, fps)
		sf.set_animation_loop(aname, loop)

		if anim.has("images"):
			# Individual image files per frame
			for img_path in anim["images"]:
				var t: Texture2D = ResourceLoader.load(img_path, "Texture2D")
				if t:
					sf.add_frame(aname, t)
				else:
					push_warning("ClaudeDirector: skipping missing frame: " + str(img_path))

		elif source_tex:
			# Spritesheet slice: row + optional col offset
			var row:       int = anim.get("row",    0)
			var frames:    int = anim.get("frames", 1)
			var col_start: int = anim.get("col",    0)

			for c in range(col_start, col_start + frames):
				var atlas := AtlasTexture.new()
				atlas.atlas  = source_tex
				atlas.region = Rect2(c * tile_w, row * tile_h, tile_w, tile_h)
				sf.add_frame(aname, atlas)

	# Save resource
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(save_path.get_base_dir())
	)
	var err := ResourceSaver.save(sf, save_path)
	if err != OK:
		return {"error": "Failed to save SpriteFrames: " + str(err)}

	EditorInterface.get_resource_filesystem().scan()

	# Optionally wire directly to an AnimatedSprite2D
	if not apply_to.is_empty():
		var apply_result := res_load(apply_to, "sprite_frames", save_path)
		if apply_result.has("error"):
			return {"ok": 1, "path": save_path, "apply_warning": apply_result["error"]}

	return {
		"ok": 1,
		"path": save_path,
		"animations": Array(sf.get_animation_names()),
		"applied_to": apply_to if not apply_to.is_empty() else null
	}


# ── TileSet Creation ──────────────────────────────────────────────────────────

func tileset_setup(
		save_path: String,
		source_image: String,
		tile_w: int = 16,
		tile_h: int = 16) -> Dictionary:

	if not ResourceLoader.exists(source_image):
		return {"error": "Tileset image not found: " + source_image}

	var tex: Texture2D = ResourceLoader.load(source_image, "Texture2D")
	if not tex:
		return {"error": "Cannot load tileset image: " + source_image}

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(tile_w, tile_h)

	var src := TileSetAtlasSource.new()
	src.texture              = tex
	src.texture_region_size  = Vector2i(tile_w, tile_h)

	var cols := tex.get_width()  / tile_w
	var rows := tex.get_height() / tile_h
	for r in range(rows):
		for c in range(cols):
			src.create_tile(Vector2i(c, r))

	tileset.add_source(src, 0)

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(save_path.get_base_dir())
	)
	var err := ResourceSaver.save(tileset, save_path)
	if err != OK:
		return {"error": "Failed to save TileSet: " + str(err)}

	EditorInterface.get_resource_filesystem().scan()
	return {
		"ok": 1,
		"path": save_path,
		"tile_size": [tile_w, tile_h],
		"cols": cols,
		"rows": rows,
		"total_tiles": cols * rows
	}


# ── Sub-Resource Property ─────────────────────────────────────────────────────

func res_prop(node_path: String, res_property: String, sub_prop: String, value: Variant) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var node: Node
	if node_path in [".", ""]:
		node = scene_root
	else:
		node = scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}

	var res: Resource = node.get(res_property) as Resource
	if not res:
		return {"error": "No resource at '%s.%s' (use res_load first)" % [node_path, res_property]}

	# Type-aware coercion using the sub-resource's own property list
	var coerced: Variant = value
	if value is Array:
		for pinfo in res.get_property_list():
			if pinfo.name == sub_prop:
				coerced = _coerce_value(value, node, "")  # size-based fallback
				match pinfo.type:
					TYPE_VECTOR2: if (value as Array).size() >= 2: coerced = Vector2(value[0], value[1])
					TYPE_VECTOR2I: if (value as Array).size() >= 2: coerced = Vector2i(int(value[0]), int(value[1]))
					TYPE_COLOR: if (value as Array).size() == 4: coerced = Color(value[0], value[1], value[2], value[3])
					TYPE_RECT2: if (value as Array).size() == 4: coerced = Rect2(value[0], value[1], value[2], value[3])
				break

	res.set(sub_prop, coerced)
	return {"ok": 1, "resource": res_property, "property": sub_prop}


# ── TileMapLayer Painting ─────────────────────────────────────────────────────

func tilemap_paint(
		node_path: String,
		cells: Array = [],
		grid: Array = [],
		tile_map: Dictionary = {},
		origin: Array = [0, 0],
		source_id: int = 0,
		clear_first: bool = false) -> Dictionary:

	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var node := scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}
	if not node is TileMapLayer:
		return {"error": "%s is a %s, not a TileMapLayer" % [node_path, node.get_class()]}

	var tml := node as TileMapLayer

	if clear_first:
		tml.clear()

	var ox := int(origin[0]) if origin.size() >= 1 else 0
	var oy := int(origin[1]) if origin.size() >= 2 else 0
	var painted := 0

	# ── Grid mode: 2D array of tile-ID strings mapped via tile_map ───────────
	for row_idx in range(grid.size()):
		var row: Array = grid[row_idx] as Array
		for col_idx in range(row.size()):
			var key := str(row[col_idx])
			if not tile_map.has(key):
				continue
			var tile_val = tile_map[key]
			if tile_val == null:
				tml.erase_cell(Vector2i(ox + col_idx, oy + row_idx))
				continue
			var tv: Array = tile_val as Array
			tml.set_cell(
				Vector2i(ox + col_idx, oy + row_idx),
				source_id,
				Vector2i(int(tv[0]), int(tv[1]))
			)
			painted += 1

	# ── Cells mode: explicit list of {x, y, tile:[col,row], src, alt} ────────
	for cell in cells:
		var cx: int  = cell.get("x",   0)
		var cy: int  = cell.get("y",   0)
		var src: int = cell.get("src", source_id)
		var alt: int = cell.get("alt", 0)
		var tv: Array = cell.get("tile", [0, 0])
		tml.set_cell(Vector2i(cx, cy), src, Vector2i(int(tv[0]), int(tv[1])), alt)
		painted += 1

	return {"ok": 1, "painted": painted}


# ── AnimationPlayer Clip Creation ─────────────────────────────────────────────

func anim_create(
		node_path: String,
		anim_name: String,
		length: float,
		tracks: Array,
		loop_mode: int = 0) -> Dictionary:

	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var node := scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}
	if not node is AnimationPlayer:
		return {"error": "%s is a %s, not an AnimationPlayer" % [node_path, node.get_class()]}

	var ap := node as AnimationPlayer

	# Ensure the default (empty-name) library exists
	var lib: AnimationLibrary
	if ap.has_animation_library(""):
		lib = ap.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		ap.add_animation_library("", lib)

	if lib.has_animation(anim_name):
		lib.remove_animation(anim_name)

	var anim := Animation.new()
	anim.length    = length
	anim.loop_mode = loop_mode as Animation.LoopMode

	for td in tracks:
		var type_str: String = str(td.get("type", "value")).to_lower()
		var atype: int = Animation.TYPE_VALUE
		if   type_str == "method":  atype = Animation.TYPE_METHOD
		elif type_str == "bezier":  atype = Animation.TYPE_BEZIER

		var ti := anim.add_track(atype)
		anim.track_set_path(ti, NodePath(str(td.get("path", "."))))

		if atype == Animation.TYPE_VALUE:
			anim.value_track_set_update_mode(ti, Animation.UPDATE_CONTINUOUS)
			for kd in td.get("keys", []):
				var t := float(kd.get("t", 0.0))
				var v: Variant = kd.get("v")
				if v is Array:
					v = _coerce_arg(v)
				anim.track_insert_key(ti, t, v)

		elif atype == Animation.TYPE_METHOD:
			for kd in td.get("keys", []):
				anim.track_insert_key(ti, float(kd.get("t", 0.0)), {
					"method": str(kd.get("method", "")),
					"args":   kd.get("args", [])
				})

	lib.add_animation(anim_name, anim)
	return {"ok": 1, "animation": anim_name, "length": length, "tracks": tracks.size()}


# ── Node Reparenting ──────────────────────────────────────────────────────────

func node_reparent(node_path: String, new_parent: String, keep_xform: bool = true) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if not scene_root:
		return {"error": "No scene open"}

	var node := scene_root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}
	if node == scene_root:
		return {"error": "Cannot reparent the scene root"}

	var parent: Node
	if new_parent in [".", ""]:
		parent = scene_root
	else:
		parent = scene_root.get_node_or_null(new_parent)
	if not parent:
		return {"error": "New parent not found: " + new_parent}

	node.reparent(parent, keep_xform)
	_set_owner_recursive(node, scene_root)

	return {"ok": 1, "node": node.name, "new_path": str(scene_root.get_path_to(node))}


# ── Physics Layer Names ───────────────────────────────────────────────────────

func physics_layers_setup(layers: Dictionary) -> Dictionary:
	# layers = {"1": "walls", "2": "player", "3": "enemies", ...}
	var set_count := 0
	for layer_str in layers:
		var n := int(str(layer_str))
		if n < 1 or n > 32:
			continue
		ProjectSettings.set_setting(
			"layer_names/2d_physics/layer_%d" % n,
			str(layers[layer_str])
		)
		set_count += 1
	ProjectSettings.save()
	return {"ok": 1, "set": set_count}
