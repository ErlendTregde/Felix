extends Node3D
class_name BodyRig

## Swap model_scene to change the character without touching anything else.
@export var model_scene: PackedScene:
	set(value):
		model_scene = value
		if is_inside_tree():
			_build_model()
## Scale to match the game's unit system (capsule height ~11, camera at Y=10).
@export var model_scale: float = 6.1

var _anim_player: AnimationPlayer = null
var _locomotion_state: String = ""
var _model_built: bool = false
var _head_modifier: HeadLookModifier = null

# Maps our generic IDs to whatever Mixamo/Godot named the clips after import.
const ANIM_ALIASES: Dictionary = {
	"walk": ["mixamo_com", "Walking", "walking", "Walk", "mixamo.com"],
	"idle": ["Take 001", "Breathing Idle", "Idle", "idle", "Stand", "T-Pose"],
}

func _ready() -> void:
	if model_scene:
		_build_model()

func _build_model() -> void:
	if _model_built:
		return
	_model_built = true

	var model: Node3D = model_scene.instantiate()
	model.scale = Vector3.ONE * model_scale
	# Mixamo characters face +Z; the player's forward is −Z, so flip 180°.
	model.rotation.y = PI
	add_child(model)

	# Find the AnimationPlayer that lives inside the imported FBX scene.
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		push_warning("BodyRig: no AnimationPlayer found in model_scene")
		return
	_anim_player = found[0] as AnimationPlayer

	# Each instance must OWN its animations. Instancing the same PackedScene shares
	# the imported AnimationLibrary resources between bodies, so two AnimationPlayers
	# end up driving the same animation data and visibly interfere (one body plays
	# walk while reporting "seated_idle"). Duplicate the libraries so each rig is
	# fully independent.
	for lib_name in _anim_player.get_animation_library_list():
		var shared_lib: AnimationLibrary = _anim_player.get_animation_library(lib_name)
		var unique_lib: AnimationLibrary = shared_lib.duplicate(true)
		_anim_player.remove_animation_library(lib_name)
		_anim_player.add_animation_library(lib_name, unique_lib)

	# Replace root-motion walk with the in-place version.
	_try_import_walk()
	# Merge idle animation from separately downloaded FBX.
	_try_import_idle()
	# Merge sitting idle animation.
	_try_import_sitting_idle()
	# Loop everything (Mixamo/FBX imports default to non-looping).
	_force_loop_animations()

	_setup_head_look(model)

	_play_loop("idle")

func _setup_head_look(model: Node3D) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		push_warning("BodyRig: no Skeleton3D found — head look disabled")
		return
	var skel: Skeleton3D = skels[0] as Skeleton3D
	# Find the head bone (Mixamo: "mixamorig_Head"). Match "Head" but skip the tip.
	var head_idx := -1
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		if bn.containsn("head") and not bn.containsn("headtop") and not bn.containsn("end"):
			head_idx = i
			break
	if head_idx < 0:
		push_warning("BodyRig: no head bone found — head look disabled")
		return
	_head_modifier = HeadLookModifier.new()
	_head_modifier.name = "HeadLookModifier"
	_head_modifier.head_bone = head_idx
	skel.add_child(_head_modifier)

func set_head_look(yaw: float, pitch: float) -> void:
	if _head_modifier:
		_head_modifier.target_yaw = yaw
		_head_modifier.target_pitch = pitch

func play_anim(anim_id: String) -> void:
	if not _anim_player:
		return
	# Strict: never fall back to an arbitrary clip (that caused the walk anim to
	# play when a one-shot like "seated_idle" was missing).
	var resolved := _resolve_strict(anim_id)
	if resolved != "":
		_anim_player.play(resolved)
	else:
		push_warning("BodyRig: animation '%s' not found — keeping current" % anim_id)

## Continuously ensure the seated idle is playing. Called every frame for seated
## bodies so a stray locomotion/one-shot animation can never stick.
func set_seated() -> void:
	if not _anim_player:
		return
	var resolved := _resolve_strict("seated_idle")
	if resolved == "":
		return
	# Reset locomotion state so standing up later re-evaluates walk/idle cleanly.
	_locomotion_state = ""
	if _anim_player.current_animation != resolved:
		_anim_player.play(resolved)

## Hysteresis band: start walking above WALK_ENTER, fall back to idle below WALK_EXIT.
## The gap prevents flicker when speed hovers around the threshold.
const WALK_ENTER: float = 0.6
const WALK_EXIT: float = 0.2

func set_locomotion(speed: float) -> void:
	var target := _locomotion_state
	if _locomotion_state == "walk":
		if speed < WALK_EXIT:
			target = "idle"
	else:
		if speed > WALK_ENTER:
			target = "walk"
	if target == "":
		target = "idle"
	if _locomotion_state == target:
		return
	_locomotion_state = target
	_play_loop(target)

func _play_loop(state: String) -> void:
	if not _anim_player:
		return
	var resolved := _resolve(state)
	if resolved == "" or _anim_player.current_animation == resolved:
		return
	_anim_player.play(resolved)

func _resolve(anim_id: String) -> String:
	if not _anim_player:
		return ""
	var strict := _resolve_strict(anim_id)
	if strict != "":
		return strict
	# Fallback: first non-RESET animation (only used by locomotion, never one-shots).
	for anim in _anim_player.get_animation_list():
		if anim != "RESET":
			return anim
	return ""

func _resolve_strict(anim_id: String) -> String:
	if not _anim_player:
		return ""
	if _anim_player.has_animation(anim_id):
		return anim_id
	if ANIM_ALIASES.has(anim_id):
		for alias in ANIM_ALIASES[anim_id]:
			if _anim_player.has_animation(alias):
				return alias
	return ""

func _force_loop_animations() -> void:
	if not _anim_player:
		return
	for lib_name in _anim_player.get_animation_library_list():
		var lib: AnimationLibrary = _anim_player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			if anim_name == "RESET":
				continue
			var anim: Animation = lib.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_LINEAR

func _try_import_walk() -> void:
	var walk_path := "res://assets/models/characters/body/animations/Walking.fbx"
	if not ResourceLoader.exists(walk_path):
		return
	var walk_packed := load(walk_path) as PackedScene
	if not walk_packed:
		return
	var walk_inst: Node = walk_packed.instantiate()
	var src_players := walk_inst.find_children("*", "AnimationPlayer", true, false)
	if src_players.is_empty():
		walk_inst.free()
		return
	var src: AnimationPlayer = src_players[0] as AnimationPlayer
	# Replace every animation from the in-place file, overwriting root-motion versions.
	for lib_name in src.get_animation_library_list():
		var src_lib: AnimationLibrary = src.get_animation_library(lib_name)
		for anim_name in src_lib.get_animation_list():
			# Find which library in our player holds this animation and replace it.
			for dest_lib_name in _anim_player.get_animation_library_list():
				var dest_lib: AnimationLibrary = _anim_player.get_animation_library(dest_lib_name)
				if dest_lib.has_animation(anim_name):
					dest_lib.remove_animation(anim_name)
					dest_lib.add_animation(anim_name, src_lib.get_animation(anim_name).duplicate())
					break
	walk_inst.free()

func _try_import_idle() -> void:
	var idle_path := "res://assets/models/characters/body/animations/Breathing Idle.fbx"
	if not ResourceLoader.exists(idle_path):
		push_warning("BodyRig: idle FBX not found: " + idle_path)
		return
	var idle_packed := load(idle_path) as PackedScene
	if not idle_packed:
		push_warning("BodyRig: could not load idle FBX")
		return
	var idle_inst: Node = idle_packed.instantiate()
	var src_players := idle_inst.find_children("*", "AnimationPlayer", true, false)
	if src_players.is_empty():
		push_warning("BodyRig: no AnimationPlayer in idle FBX")
		idle_inst.free()
		return
	var src: AnimationPlayer = src_players[0] as AnimationPlayer

	# Get/create default library in destination.
	if not _anim_player.has_animation_library(""):
		_anim_player.add_animation_library("", AnimationLibrary.new())
	var dest_lib: AnimationLibrary = _anim_player.get_animation_library("")

	# Mixamo always names its clip "mixamo_com" regardless of motion type.
	# Rename to "idle" explicitly so ANIM_ALIASES can find it without collision.
	if dest_lib.has_animation("idle"):
		idle_inst.free()
		return
	for lib_name in src.get_animation_library_list():
		var lib: AnimationLibrary = src.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			if anim_name == "RESET":
				continue
			dest_lib.add_animation("idle", lib.get_animation(anim_name).duplicate())
			idle_inst.free()
			return
	push_warning("BodyRig: no non-RESET animation found in idle FBX")
	idle_inst.free()

func _try_import_sitting_idle() -> void:
	var path := "res://assets/models/characters/body/Sitting Idle.fbx"
	if not ResourceLoader.exists(path):
		push_warning("BodyRig: Sitting Idle FBX not found: " + path)
		return
	var packed := load(path) as PackedScene
	if not packed:
		push_warning("BodyRig: could not load Sitting Idle FBX")
		return
	var inst: Node = packed.instantiate()
	var src_players := inst.find_children("*", "AnimationPlayer", true, false)
	if src_players.is_empty():
		inst.free()
		return
	var src: AnimationPlayer = src_players[0] as AnimationPlayer
	if not _anim_player.has_animation_library(""):
		_anim_player.add_animation_library("", AnimationLibrary.new())
	var dest_lib: AnimationLibrary = _anim_player.get_animation_library("")
	if dest_lib.has_animation("seated_idle"):
		inst.free()
		return
	for lib_name in src.get_animation_library_list():
		var lib: AnimationLibrary = src.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			if anim_name == "RESET":
				continue
			dest_lib.add_animation("seated_idle", lib.get_animation(anim_name).duplicate())
			inst.free()
			return
	push_warning("BodyRig: no non-RESET animation found in Sitting Idle FBX")
	inst.free()
