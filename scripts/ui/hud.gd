extends CanvasLayer
## Scoreboard, win banner, and basic instructions.

var _score_label: Label
var _status_label: Label
var _banner: Label


func _ready() -> void:
	layer = 60

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 32)
	_score_label.position = Vector2(24, 16)
	root.add_child(_score_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.position = Vector2(24, 56)
	root.add_child(_status_label)

	var help := Label.new()
	help.text = "WASD move  ·  Space jump  ·  Shift sprint  ·  LMB shoot  ·  RMB pass/steal\nFirst to 5 wins. The longer the game goes, the trippier it gets."
	help.add_theme_font_size_override("font_size", 14)
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(24, -56)
	root.add_child(help)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 48)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.position = Vector2(-260, -40)
	_banner.visible = false
	root.add_child(_banner)

	GameManager.score_changed.connect(_on_score_changed)
	GameManager.game_over.connect(_on_game_over)
	GameManager.state_changed.connect(_on_state_changed)
	_on_score_changed(0, 0)


func _on_score_changed(a: int, b: int) -> void:
	_score_label.text = "TEAM A %d  —  %d TEAM B" % [a, b]


func _on_state_changed(new_state: int) -> void:
	if new_state == GameManager.State.REPLAY:
		_status_label.text = "INSTANT REPLAY"
	elif new_state == GameManager.State.PLAYING:
		_status_label.text = ""


func _on_game_over(winning_team: int) -> void:
	var name := "TEAM A" if winning_team == GameManager.Team.A else "TEAM B"
	_banner.text = "%s WINS!" % name
	_banner.visible = true
