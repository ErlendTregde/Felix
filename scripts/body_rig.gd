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
## Hand orientation while holding a card, in degrees, relative to the body's facing.
## Tune these three numbers until the palm cups the card (right-side up).
@export var hold_hand_euler_deg: Vector3 = Vector3(-90, 0, 0)
## Body-local offset for the hold target so the PALM (not the wrist) meets the card.
## The IK puts the wrist on the target; nudge it back/up so the card sits in the hand.
@export var hold_hand_offset: Vector3 = Vector3.ZERO
## A held card sits at the right hand bone plus this body-local offset.
## (The card keeps a fixed readable rotation set by the caller, so it always
## faces the holder — only its position tracks the hand.)
@export var card_in_hand_offset: Vector3 = Vector3.ZERO

var _anim_player: AnimationPlayer = null
var _locomotion_state: String = ""
var _model_built: bool = false
var _head_modifier: HeadLookModifier = null

# Right-hand IK for reaching (draw pile, holding cards). Prototype uses the built-in
# SkeletonIK3D (deprecated but functional in 4.6) — swap for a custom solver later.
var _hand_ik: SkeletonIK3D = null
var _hand_target: Marker3D = null
var _reach_tween: Tween = null
var _skel: Skeleton3D = null
var _hand_bone_idx: int = -1

# Smoking emote: a looping smoke pose + a particle puff that rides the hand/cigarette.
var _is_smoking: bool = false
var _smoke_emitter: Node3D = null
var _smoke_particles: GPUParticles3D = null
## World-space offset from the right hand to the cigarette tip where smoke is emitted.
@export var smoke_tip_offset: Vector3 = Vector3(0, 1.0, 0)

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
	# Merge the smoking emote (glTF clip — track paths get retargeted to this rig).
	_try_import_smoke()
	# Loop everything (Mixamo/FBX imports default to non-looping).
	_force_loop_animations()

	_setup_head_look(model)
	_setup_hand_reach(model)
	_setup_smoke_particles()

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

# ── Right-hand reach (IK) ───────────────────────────────────────────────────

func _setup_hand_reach(model: Node3D) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel: Skeleton3D = skels[0] as Skeleton3D
	_skel = skel
	# Mixamo arm chain: RightArm (upper) → RightForeArm → RightHand.
	var root_bone := ""
	var tip_bone := ""
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i).to_lower()
		if bn.ends_with("rightarm"):
			root_bone = skel.get_bone_name(i)
		elif bn.ends_with("righthand"):
			tip_bone = skel.get_bone_name(i)
			_hand_bone_idx = i
	if root_bone == "" or tip_bone == "":
		push_warning("BodyRig: right arm/hand bones not found — hand reach disabled")
		return

	_hand_target = Marker3D.new()
	_hand_target.name = "HandReachTarget"
	add_child(_hand_target)

	_hand_ik = SkeletonIK3D.new()
	_hand_ik.name = "HandIK"
	_hand_ik.root_bone = root_bone
	_hand_ik.tip_bone = tip_bone
	_hand_ik.interpolation = 0.0       # 0 = no effect until we reach
	_hand_ik.use_magnet = false        # tune later if the elbow bends oddly
	_hand_ik.override_tip_basis = true # orient the hand to the target (hold pose)
	skel.add_child(_hand_ik)
	_hand_ik.target_node = _hand_ik.get_path_to(_hand_target)

## Start reaching the right hand to a world point, blending the IK in over ~0.25s.
## The hand is oriented via hold_hand_euler_deg (relative to the body's facing).
func begin_reach(world_pos: Vector3) -> void:
	if not _hand_ik or not _hand_target:
		return
	_hand_target.global_position = world_pos
	_hand_target.rotation_degrees = hold_hand_euler_deg
	_hand_ik.start()
	_blend_ik(1.0, false)

## Smoothly slide the reach target to a new world point (e.g. pile → held card).
## Applies hold_hand_offset (body-local) so the palm seats on the card.
func move_reach(world_pos: Vector3, duration: float = 0.3) -> void:
	if not _hand_ik or not _hand_target:
		return
	var seated_pos := world_pos + global_transform.basis * hold_hand_offset
	var t := create_tween()
	t.tween_property(_hand_target, "global_position", seated_pos, duration)

## End the reach, blending back to the animated pose, then stop solving.
func end_reach() -> void:
	_blend_ik(0.0, true)

func _blend_ik(target: float, then_stop: bool) -> void:
	if not _hand_ik:
		return
	if _reach_tween and _reach_tween.is_valid():
		_reach_tween.kill()
	_reach_tween = create_tween()
	_reach_tween.tween_property(_hand_ik, "interpolation", target, 0.25)
	if then_stop:
		_reach_tween.tween_callback(_hand_ik.stop)

## World position a held card should sit at, tracking the right hand bone.
func get_hand_position() -> Vector3:
	if not _skel or _hand_bone_idx < 0:
		return global_position
	var hand_world: Vector3 = (_skel.global_transform * _skel.get_bone_global_pose(_hand_bone_idx)).origin
	# Offset is body-local (global_transform.basis is the body's facing, unit scale).
	return hand_world + global_transform.basis * card_in_hand_offset

func has_hand_tracking() -> bool:
	return _skel != null and _hand_bone_idx >= 0

# ── Smoking emote ────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	# While smoking, keep the smoke puff riding the hand/cigarette tip (world space).
	if _is_smoking and _smoke_emitter and has_hand_tracking():
		_smoke_emitter.global_position = get_hand_position() + global_transform.basis * smoke_tip_offset

## Play the smoking pose and start the smoke puff. Idempotent.
func start_smoke() -> void:
	if _is_smoking:
		return
	_is_smoking = true
	play_anim("smoke")
	if _smoke_particles:
		_smoke_particles.emitting = true

## Stop smoking. The caller resumes locomotion/idle. Idempotent.
func stop_smoke() -> void:
	if not _is_smoking:
		return
	_is_smoking = false
	if _smoke_particles:
		_smoke_particles.emitting = false
	# Force locomotion to re-apply (current anim is "smoke", so idle/walk must replay).
	_locomotion_state = ""

func is_smoking() -> bool:
	return _is_smoking

func _setup_smoke_particles() -> void:
	# Emitter lives under BodyRig (unscaled) and is driven to the hand each frame, so the
	# particle sizes/velocities stay in world units (not multiplied by the 6.1 model scale).
	var emitter := Node3D.new()
	emitter.name = "SmokeEmitter"
	add_child(emitter)

	var p := GPUParticles3D.new()
	p.name = "Smoke"
	p.amount = 12
	p.lifetime = 2.5
	p.emitting = false
	p.local_coords = false  # puffs drift in world space instead of snapping with the hand

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.1
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 10.0
	mat.initial_velocity_min = 0.8
	mat.initial_velocity_max = 1.6
	mat.gravity = Vector3(0, 1.0, 0)  # drifts upward
	mat.scale_min = 0.6
	mat.scale_max = 1.0
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(1.0, 1.5))  # small → larger over life
	var sct := CurveTexture.new()
	sct.curve = scale_curve
	mat.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.85, 0.85, 0.45))
	grad.set_color(1, Color(0.85, 0.85, 0.85, 0.0))  # fade alpha to 0 over life
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	mat.color_ramp = gt
	p.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dmat.albedo_texture = _make_soft_round_texture()
	dmat.vertex_color_use_as_albedo = true  # apply the per-particle color ramp
	quad.material = dmat
	p.draw_pass_1 = quad

	emitter.add_child(p)
	_smoke_emitter = emitter
	_smoke_particles = p

## A soft round white→transparent radial texture, so quad puffs look like smoke blobs.
func _make_soft_round_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t

func _try_import_smoke() -> void:
	# FBX export of the smoke pose. It was re-exported with an "Armature/Skeleton3D"
	# hierarchy plus a "Cigarette" mesh, so its track paths don't line up with THIS rig's
	# skeleton. Retarget every bone track onto our skeleton's actual node path (bone names
	# match: mixamorig_*) and drop non-bone tracks like the cigarette.
	var path := "res://assets/models/characters/body/animations/smoke/mafia_smoke.fbx"
	if not ResourceLoader.exists(path):
		push_warning("BodyRig: smoke FBX not found: " + path)
		return
	var packed := load(path) as PackedScene
	if not packed:
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
	if dest_lib.has_animation("smoke"):
		inst.free()
		return
	for lib_name in src.get_animation_library_list():
		var lib: AnimationLibrary = src.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			if anim_name == "RESET":
				continue
			var dup: Animation = lib.get_animation(anim_name).duplicate()
			_retarget_clip_to_skeleton(dup)
			dest_lib.add_animation("smoke", dup)
			inst.free()
			return
	push_warning("BodyRig: no non-RESET animation found in smoke FBX")
	inst.free()

## Repoint a clip's bone tracks at THIS rig's skeleton and discard tracks that don't name
## a real bone (e.g. an extra "Cigarette" mesh baked into the export). Needed when a clip
## was exported with a different node hierarchy/path than the destination character.
func _retarget_clip_to_skeleton(clip: Animation) -> void:
	var skels := find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel: Skeleton3D = skels[0] as Skeleton3D
	var anim_root := _anim_player.get_node_or_null(_anim_player.root_node)
	if anim_root == null:
		anim_root = _anim_player
	var skel_path := String(anim_root.get_path_to(skel))
	for t in range(clip.get_track_count() - 1, -1, -1):
		var p := String(clip.track_get_path(t))
		var colon := p.rfind(":")
		if colon < 0:
			clip.remove_track(t)
			continue
		var bone_name := p.substr(colon + 1)
		# Keep ONLY rotation tracks on real bones. The re-exported clip's position/scale
		# tracks don't match this skeleton's bind pose — they stretch the mesh (long
		# fingers / huge arms) and the bad scale persists into walk/idle afterwards.
		# Non-bone tracks (e.g. the cigarette mesh) are dropped too.
		if clip.track_get_type(t) == Animation.TYPE_ROTATION_3D and skel.find_bone(bone_name) >= 0:
			clip.track_set_path(t, NodePath(skel_path + ":" + bone_name))
		else:
			clip.remove_track(t)

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
	var walk_path := "res://assets/models/characters/body/animations/walking/Walking.fbx"
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
	var idle_path := "res://assets/models/characters/body/animations/idle/Idle.fbx"
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
	var path := "res://assets/models/characters/body/animations/sitting/Sitting.fbx"
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
