extends CharacterBody3D
class_name CharacterBodyBase
## Shared character: an imported, rigged KayKit "Adventurers" model (CC0,
## see assets/kaykit_adventurers/LICENSE.txt) with its weapon/helmet/cape
## accessories stripped off, plus a procedural cartoony face (PEAK-style
## swappable expressions) mounted on its head bone. Both the human
## PlayerController and AiPlayer extend this.
##
## Team A uses Knight.glb, Team B uses Barbarian.glb — this also gives the
## two teams a distinct silhouette/palette for free, no material tinting
## needed.

const GRAVITY := 18.0
const MODEL_PATHS := {
	0: "res://assets/kaykit_adventurers/Knight.glb",     # GameManager.Team.A
	1: "res://assets/kaykit_adventurers/Barbarian.glb",  # GameManager.Team.B
}
const MOVE_ANIM := "Running_A"
const IDLE_ANIM := "Idle"
const JUMP_ANIM := "Jump_Idle"

@export var team: int = GameManager.Team.A
@export var actor_id: String = ""

var face: CharacterFace
var hand_marker: Marker3D
var has_ball: bool = false

var _visual_root: Node3D
var _skeleton: Skeleton3D
var _anim_player: AnimationPlayer
var _action_lock: float = 0.0
var _drunk_visual_amount: float = 0.0

const DoubleVisionGhost = preload("res://scripts/fx/double_vision_ghost.gd")


func _ready() -> void:
	collision_layer = (1 << 1) if team == GameManager.Team.A else (1 << 2)
	collision_mask = 1 # world only; characters don't need to collide with each other

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = 0.9
	add_child(col)

	_build_visuals()

	if actor_id == "":
		actor_id = name
	ReplayManager.register_actor(actor_id, self)


func _exit_tree() -> void:
	ReplayManager.unregister_actor(actor_id)


func _build_visuals() -> void:
	var model_path: String = MODEL_PATHS[team]
	var packed: PackedScene = load(model_path)
	_visual_root = packed.instantiate()
	_visual_root.name = "Model"
	add_child(_visual_root)

	_skeleton = _find_skeleton(_visual_root)
	_anim_player = _find_anim_player(_visual_root)
	if _anim_player:
		_anim_player.play(IDLE_ANIM)

	_strip_accessories(_visual_root)

	var head_attachment: BoneAttachment3D = _skeleton.get_node_or_null("head") if _skeleton else null
	if head_attachment:
		face = CharacterFace.new()
		face.name = "Face"
		face.position = Vector3(0, 0.02, 0.14)
		face.scale = Vector3.ONE * 0.85
		head_attachment.add_child(face)

	hand_marker = Marker3D.new()
	hand_marker.name = "HandMarker"
	var hand_attachment: BoneAttachment3D = _skeleton.get_node_or_null("handslot_r") if _skeleton else null
	if hand_attachment:
		hand_attachment.add_child(hand_marker)
	else:
		add_child(hand_marker)
		hand_marker.position = Vector3(0.42, 1.0, 0.32)

	var ghost := DoubleVisionGhost.new()
	ghost.target = _visual_root
	ghost.max_offset = 0.1
	add_child(ghost)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found:
			return found
	return null


## The pack's characters come with weapons/helmets/capes hung off dedicated
## BoneAttachment3D nodes (handslot_l/handslot_r/head/chest) — not what a
## basketball player should be carrying, so strip just those meshes. The
## actual body meshes (Model_Body, Model_Head, etc.) are siblings of the
## BoneAttachment3D nodes, not children of them, so they're untouched.
func _strip_accessories(node: Node) -> void:
	if node is BoneAttachment3D:
		for child in node.get_children():
			if child is MeshInstance3D:
				child.queue_free()
		return
	for child in node.get_children():
		_strip_accessories(child)


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	_update_animation(delta)


func _update_animation(delta: float) -> void:
	_action_lock = maxf(0.0, _action_lock - delta)
	if not _anim_player or _action_lock > 0.0:
		return

	var target_anim := IDLE_ANIM
	if not is_on_floor():
		target_anim = JUMP_ANIM
	elif Vector2(velocity.x, velocity.z).length() > 1.0:
		target_anim = MOVE_ANIM

	if _anim_player.current_animation != target_anim and _anim_player.has_animation(target_anim):
		_anim_player.play(target_anim, 0.2)


## Plays a one-shot action animation (e.g. "Throw" for shooting) and locks
## out the idle/run/jump animation logic until it's roughly finished.
func play_action_animation(anim_name: String, lock_time: float = 0.5) -> void:
	if _anim_player and _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
		_action_lock = lock_time


## Called by the ReplayCameraRig while this actor is being scrubbed through
## recorded history, scaled by current psychedelic intensity. Drives the
## "drunk/high/stumbling" replay-only look.
func apply_drunk_visual(amount: float) -> void:
	_drunk_visual_amount = amount
	if face and face.has_method("set_expression"):
		if amount > 0.5:
			face.set_expression(face.FaceExpression.DRUNK, amount)
		elif amount > 0.15:
			face.set_expression(face.FaceExpression.SHOCKED, amount)
