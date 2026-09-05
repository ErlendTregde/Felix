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

const WALK_PATH := "res://assets/models/characters/body/firstperson/walking/walking_fp_hands.fbx"
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

## Smoke puff + cigarette for the smoke emote. The FP arms carry their own copy (the body's
## own emitter/cigarette are hidden along with the body in first person), and the walking-hands
## FBX has no cigarette baked in, so we build a little one and stick it in the hand.
var _hand_bone_idx: int = -1
var _smoke_emitter: Node3D = null
var _smoke_particles: GPUParticles3D = null
var _cigarette: Node3D = null   # cigarette + ember; visible only while smoking

## Where the cigarette / smoke sits, as an offset from the right hand in YOUR OWN frame:
## +X = your right, −X = your left, +Y = up, −Z = forward (the way you look). World units.
## Placed each frame in _process, so the axes are intuitive (not the twisted bone frame).
## While smoking, nudge it live: J/L = left/right, I/K = forward/back, U/O = up/down —
## the new value prints to the Output log so it can be baked in as the default here.
@export var smoke_offset: Vector3 = Vector3(-1.1, -0.05, -0.85)
@export var cigarette_rotation_deg: Vector3 = Vector3(90.0, 0.0, 0.0)
@export var cigarette_length: float = 0.4
@export var cigarette_radius: float = 0.025
## Debug: set false to disable the live J/L/I/K/U/O nudge keys once placement is dialed in.
@export var cigarette_tuning_keys: bool = true

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
		# Mixamo right-hand bone — the smoke puff rides its world position each frame.
		for i in _skel.get_bone_count():
			if _skel.get_bone_name(i).to_lower().ends_with("righthand"):
				_hand_bone_idx = i
				break

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

	_setup_smoke_particles()
	_setup_cigarette()

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
	var smoking := (state == "smoke")
	if _smoke_particles:
		_smoke_particles.emitting = smoking
	if _cigarette:
		_cigarette.visible = smoking

func current_state() -> String:
	return _state

func _process(_delta: float) -> void:
	# While smoking, place the cigarette + smoke at the hand, offset in YOUR frame (intuitive
	# axes), not the twisted hand-bone frame. Driven every frame so it tracks the hand's pose.
	if _state != "smoke" or _cigarette == null or _skel == null or _hand_bone_idx < 0:
		return
	var hand_pos: Vector3 = (_skel.global_transform * _skel.get_bone_global_pose(_hand_bone_idx)).origin
	var b := global_transform.basis.orthonormalized()
	var anchor := hand_pos + b * smoke_offset
	var t := _cigarette.global_transform
	t.origin = anchor
	t.basis = b * Basis.from_euler(Vector3(
		deg_to_rad(cigarette_rotation_deg.x),
		deg_to_rad(cigarette_rotation_deg.y),
		deg_to_rad(cigarette_rotation_deg.z)))
	_cigarette.global_transform = t
	if _smoke_emitter:
		_smoke_emitter.global_position = anchor

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

## Own smoke puff (mirrors BodyRig._setup_smoke_particles). Lives under this node (unscaled),
## driven to the hand each frame in _process so sizes/velocities stay in world units.
func _setup_smoke_particles() -> void:
	var emitter := Node3D.new()
	emitter.name = "SmokeEmitter"
	add_child(emitter)

	var p := GPUParticles3D.new()
	p.name = "Smoke"
	p.amount = 10
	p.lifetime = 2.2
	p.emitting = false
	p.local_coords = false  # puffs drift in world space instead of snapping with the hand

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.03
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 8.0
	mat.initial_velocity_min = 0.12
	mat.initial_velocity_max = 0.3
	mat.gravity = Vector3(0, 0.3, 0)  # drifts gently upward
	mat.scale_min = 0.3
	mat.scale_max = 0.5
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.2))
	scale_curve.add_point(Vector2(1.0, 1.0))  # small → larger over life
	var sct := CurveTexture.new()
	sct.curve = scale_curve
	mat.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.85, 0.85, 0.4))
	grad.set_color(1, Color(0.85, 0.85, 0.85, 0.0))  # fade alpha to 0 over life
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	mat.color_ramp = gt
	p.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
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

## Build a cigarette (with a glowing ember at the tip) that rides the hand while smoking.
## It lives under THIS (unscaled) node and is placed each frame in _process in the player's
## frame, so the tuning offset is intuitive world units. Hidden until smoking. The ember and
## paper draw over the hand (no_depth_test) so they can never hide inside the mesh.
func _setup_cigarette() -> void:
	var root := Node3D.new()
	root.name = "Cigarette"
	root.visible = false
	add_child(root)

	# Paper body: a thin cylinder whose lit end sits at the root origin (the ember / emit point,
	# where the smoke rises); the paper extends the OTHER way, down toward the hand.
	var body := MeshInstance3D.new()
	body.name = "Paper"
	var cyl := CylinderMesh.new()
	cyl.top_radius = cigarette_radius
	cyl.bottom_radius = cigarette_radius
	cyl.height = cigarette_length
	cyl.radial_segments = 8
	body.mesh = cyl
	body.position = Vector3(0.0, cigarette_length * 0.5, 0.0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.95, 0.93, 0.88)  # off-white paper
	pmat.emission_enabled = true
	pmat.emission = Color(0.9, 0.88, 0.8)
	pmat.emission_energy_multiplier = 0.5
	pmat.no_depth_test = true   # draw over the hand so it can't hide inside the mesh
	body.material_override = pmat
	body.extra_cull_margin = 16384.0
	root.add_child(body)

	# Glowing ember at the tip — also the smoke emit point.
	var ember := MeshInstance3D.new()
	ember.name = "Ember"
	var sph := SphereMesh.new()
	sph.radius = cigarette_radius * 1.8
	sph.height = cigarette_radius * 3.6
	ember.mesh = sph
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(1.0, 0.35, 0.05)
	emat.emission_enabled = true
	emat.emission = Color(1.0, 0.4, 0.1)
	emat.emission_energy_multiplier = 4.0  # embers glow
	emat.no_depth_test = true
	ember.material_override = emat
	ember.extra_cull_margin = 16384.0
	root.add_child(ember)

	_cigarette = root

## Debug: nudge the cigarette/smoke into place at runtime in YOUR frame (see smoke_offset).
## Prints the new value so it can be pasted back as the default. Toggle off with
## cigarette_tuning_keys. _process re-applies smoke_offset every frame.
func _input(event: InputEvent) -> void:
	if not cigarette_tuning_keys or _cigarette == null:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var step := 0.05
	var moved := true
	match (event as InputEventKey).keycode:
		KEY_L: smoke_offset.x += step   # your right
		KEY_J: smoke_offset.x -= step   # your left
		KEY_K: smoke_offset.z += step   # back
		KEY_I: smoke_offset.z -= step   # forward
		KEY_U: smoke_offset.y += step   # up
		KEY_O: smoke_offset.y -= step   # down
		_: moved = false
	if moved:
		print("smoke_offset = Vector3(%.3f, %.3f, %.3f)" % [smoke_offset.x, smoke_offset.y, smoke_offset.z])
