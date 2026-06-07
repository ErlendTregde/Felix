extends Node3D
class_name FirstPersonArms

## First-person arm-only overlay for the LOCAL player.
##
## In third person the player sees their whole body (BodyRig). In first person the body is
## hidden and this arm-only rig is shown instead. It is placed with the SAME transform as
## BodyRig (same scale + facing, parented to the body — NOT the camera), and plays the same
## animation as the body, so the arms sit exactly where the player's real arms are. The
## first-person camera lives at the head, so you naturally see your own forearms/hands
## (e.g. reaching toward the table) without a head/torso blocking the view.
##
## The FP FBX exports only carry walk + smoke clips, but they use the same Mixamo skeleton
## as the body, so we also merge the body's idle/sitting clips onto this rig to mirror every
## state.

const WALK_PATH := "res://assets/models/characters/body/firstperson/walking/walking_fp.fbx"
const SMOKE_PATH := "res://assets/models/characters/body/firstperson/smoke/mafia_smoke_fp.fbx"
const IDLE_PATH := "res://assets/models/characters/body/animations/idle/Idle.fbx"
const SEATED_PATH := "res://assets/models/characters/body/animations/sitting/Sitting.fbx"

## Same scale as BodyRig so the arms overlay the body exactly.
@export var model_scale: float = 6.1
## Fine-tune offset relative to the body origin (overlay needs ~0; tweak only if arms clip).
@export var view_offset: Vector3 = Vector3(0.0, 0.5, 0.0):
	set(value):
		view_offset = value
		if is_instance_valid(_model):
			_model.position = value
## Mixamo faces +Z, the body faces −Z, so the model is flipped 180° (matches BodyRig).
@export var view_rotation_deg: Vector3 = Vector3(0.0, 180.0, 0.0):
	set(value):
		view_rotation_deg = value
		if is_instance_valid(_model):
			_model.rotation_degrees = value

var _model: Node3D = null
var _anim_player: AnimationPlayer = null
var _skel: Skeleton3D = null
var _clip_names: Dictionary = {}  # state -> animation name
var _state: String = ""

func _ready() -> void:
	_build()

func _build() -> void:
	if not ResourceLoader.exists(WALK_PATH):
		push_warning("FirstPersonArms: walk FBX missing: " + WALK_PATH)
		return
	var packed := load(WALK_PATH) as PackedScene
	if not packed:
		return
	_model = packed.instantiate()
	_model.scale = Vector3.ONE * model_scale
	_model.position = view_offset
	_model.rotation_degrees = view_rotation_deg
	add_child(_model)

	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_warning("FirstPersonArms: no AnimationPlayer in walk FBX")
		return
	_anim_player = players[0] as AnimationPlayer

	# Own the libraries — instanced scenes share AnimationLibrary resources otherwise.
	for lib_name in _anim_player.get_animation_library_list():
		var shared: AnimationLibrary = _anim_player.get_animation_library(lib_name)
		var unique: AnimationLibrary = shared.duplicate(true)
		_anim_player.remove_animation_library(lib_name)
		_anim_player.add_animation_library(lib_name, unique)

	var skels := _model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_skel = skels[0] as Skeleton3D

	# walk ships in this FBX; merge the rest (same Mixamo skeleton, so they retarget cleanly).
	_clip_names["walk"] = _first_non_reset()
	_clip_names["smoke"] = _import_clip(SMOKE_PATH, "smoke_fp")
	_clip_names["idle"] = _import_clip(IDLE_PATH, "idle")
	_clip_names["seated"] = _import_clip(SEATED_PATH, "seated_idle")
	_force_loop()
	visible = false

	# Large cull margin so the skinned arms (driven near the camera) are never frustum-culled.
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.visible = true
		mi.extra_cull_margin = 16384.0

## Drive the overlay to match the body: "walk", "idle", "seated", "smoke".
func set_state(state: String) -> void:
	if state == _state or not _anim_player:
		return
	_state = state
	var clip: String = _clip_names.get(state, "")
	if clip == "":
		clip = _clip_names.get("idle", "")  # fall back to idle if a clip is missing
	if clip != "" and _anim_player.current_animation != clip:
		_anim_player.play(clip)

func current_state() -> String:
	return _state

func _first_non_reset() -> String:
	if not _anim_player:
		return ""
	for a in _anim_player.get_animation_list():
		if a != "RESET":
			return a
	return ""

## Merge a clip from another FBX onto this rig's skeleton (retargeting bone-track paths).
func _import_clip(path: String, as_name: String) -> String:
	if not _anim_player or not ResourceLoader.exists(path):
		push_warning("FirstPersonArms: clip FBX missing: " + path)
		return ""
	var packed := load(path) as PackedScene
	if not packed:
		return ""
	var inst: Node = packed.instantiate()
	var src_players := inst.find_children("*", "AnimationPlayer", true, false)
	if src_players.is_empty():
		inst.free()
		return ""
	var src: AnimationPlayer = src_players[0] as AnimationPlayer
	if not _anim_player.has_animation_library(""):
		_anim_player.add_animation_library("", AnimationLibrary.new())
	var dest: AnimationLibrary = _anim_player.get_animation_library("")
	if dest.has_animation(as_name):
		inst.free()
		return as_name
	for lib_name in src.get_animation_library_list():
		var lib: AnimationLibrary = src.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			if anim_name == "RESET":
				continue
			var dup: Animation = lib.get_animation(anim_name).duplicate()
			_retarget_clip_to_skeleton(dup)
			dest.add_animation(as_name, dup)
			inst.free()
			return as_name
	inst.free()
	return ""

## Repoint a clip's bone tracks at this rig's skeleton, keeping only rotation tracks on real
## bones. The smoke export also carries a "Cigarette" mesh track and an "Armature/..." path
## that don't exist here; those are dropped. Rotation-only avoids the bind-pose-mismatch
## stretching that position/scale tracks from the re-exported clips would cause.
func _retarget_clip_to_skeleton(clip: Animation) -> void:
	if not _skel:
		return
	var anim_root := _anim_player.get_node_or_null(_anim_player.root_node)
	if anim_root == null:
		anim_root = _anim_player
	var skel_path := String(anim_root.get_path_to(_skel))
	for t in range(clip.get_track_count() - 1, -1, -1):
		var p := String(clip.track_get_path(t))
		var colon := p.rfind(":")
		if colon < 0:
			clip.remove_track(t)
			continue
		var bone_name := p.substr(colon + 1)
		if clip.track_get_type(t) == Animation.TYPE_ROTATION_3D and _skel.find_bone(bone_name) >= 0:
			clip.track_set_path(t, NodePath(skel_path + ":" + bone_name))
		else:
			clip.remove_track(t)

func _force_loop() -> void:
	if not _anim_player:
		return
	for lib_name in _anim_player.get_animation_library_list():
		var lib: AnimationLibrary = _anim_player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			if anim_name == "RESET":
				continue
			lib.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
