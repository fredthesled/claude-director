@tool
extends EditorPlugin

var _dock: Control


func _enter_tree() -> void:
	var script = load("res://addons/claude_director/claude_dock.gd")
	if not script:
		push_error("ClaudeDirector: Could not load claude_dock.gd")
		return
	_dock = script.new()
	_dock.name = "Claude Director"
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_dock = null
