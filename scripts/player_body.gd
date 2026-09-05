extends CharacterBody3D
class_name PlayerBody

const MOVE_SPEED := 5.0
const MOUSE_SENSITIVITY := 0.002
const GRAVITY := 20.0

@export var seat_index: int = -1
@export var peer_id: int = 1

@onready var fps_camera: Camera3D = $FPSCamera
@onready var third_person_pivot: Node3D = $ThirdPersonPivot
@onready var third_person_arm: SpringArm3D = $ThirdPersonPivot/ThirdPersonArm
@onready var third_person_camera: Camera3D = $ThirdPersonPivot/ThirdPersonArm/ThirdPersonCamera
@onready var body_rig: BodyRig = $BodyRig
@onready var name_label: Label3D = $NameLabel
@onready var interaction_ray: RayCast3D = $FPSCamera/InteractionRay

const TP_MIN_ZOOM: float = 4.0
const TP_MAX_ZOOM: float = 30.0
const TP_PITCH_LIMIT: float = 1.05  # ~±60° pitch (positive = look up, negative = look down)

var is_standing: bool = false
var is_seated: bool = false   # True when sitting at a chair (body visible, no movement)
var is_local: bool = false  # Whether this body belongs to the local player
var mouse_rotation: Vector2 = Vector2.ZERO  # x = yaw, y = pitch
var avatar_color: Color = Color.WHITE  # Used by lobby for seated-visual placeholders
var _last_pos: Vector3 = Vector3.ZERO
var player_display_name: String = ""
var nearby_chair_seat_index: int = -1

# Voice indicator
var _talk_indicator: Label3D = null

# Seated placement for REMOTE full bodies — raise so the sitting pose rests on the chair
# instead of sinking below the table, and push back from the edge so it doesn't clip.
const SEATED_Y_OFFSET: float = 1.5
const SEATED_OUTWARD_OFFSET: float = 2.0
# Seated placement for the LOCAL player. Sitting keeps the SAME first-person camera as
# walking (same eye height), just dropped/positioned at the chair. Movement is locked.
const SEATED_LOCAL_Y: float = 0.0
const SEATED_LOCAL_BACK: float = 1.5

# Remote interpolation
var _remote_target_pos: Vector3 = Vector3.ZERO
var _remote_target_rot_y: float = 0.0
var _has_remote_target: bool = false
const REMOTE_LERP_SPEED: float = 12.0
# Head look (yaw/pitch) — synced so others see players turning their heads.
var _remote_head_yaw: float = 0.0
var _remote_head_pitch: float = 0.0
# Smoking emote: R toggles it (while standing); walking cancels. Synced so others see it.
var _smoking: bool = false
var _remote_smoking: bool = false
const SMOKE_WALK_CANCEL: float = 0.5  # moving faster than this cancels the smoke emote
# Card currently following this body's hand (the held/drawn card).
var _held_card: Node3D = null
# First-person arm-only viewmodel (local player only). Shown in first person instead of
# the full body so you see just your own hands walking/smoking. Built in setup().
var _fp_arms: FirstPersonArms = null
# Smoothed horizontal speed used to drive remote walk/idle (avoids flicker between
# 20Hz network packets, where the per-frame lerp delta momentarily drops to ~0).
var _remote_speed_smoothed: float = 0.0
const REMOTE_SPEED_SMOOTH: float = 8.0

# Interaction prompt (created by game_table/steam_room)
var interaction_label: Label = null

signal request_sit(seat_index: int)
signal request_stand()

func _ready() -> void:
	# Start hidden/inactive
	set_standing(false)
	# SpringArm should ignore our own collider so it doesn't collapse to zero.
	if third_person_arm:
		third_person_arm.add_excluded_object(get_rid())

func setup(p_seat_index: int, p_peer_id: int, p_display_name: String, p_color: Color, p_is_local: bool) -> void:
	seat_index = p_seat_index
	peer_id = p_peer_id
	player_display_name = p_display_name
	avatar_color = p_color
	is_local = p_is_local
	set_multiplayer_authority(peer_id)

	name_label.text = p_display_name

	# Voice talking indicator — positioned to the right of the name label
	_talk_indicator = Label3D.new()
	_talk_indicator.name = "TalkIndicator"
	_talk_indicator.text = ")))"
	_talk_indicator.font_size = 24
	_talk_indicator.outline_size = 6
	_talk_indicator.modulate = Color(0.3, 1.0, 0.3, 1.0)  # Green tint
	_talk_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_talk_indicator.no_depth_test = true
	_talk_indicator.position = Vector3(0, 12.3, 0)  # Above the name label
	_talk_indicator.visible = false
	add_child(_talk_indicator)

	# Set the model on the rig. T-Pose.fbx is the rigged character (skeleton, no real
	# motion); BodyRig merges in the walk/idle/seated clips from animations/. Everyone —
	# local and remote — uses the same full-body character.
	if body_rig:
		var model_path := "res://assets/models/characters/body/T-Pose.fbx"
		if ResourceLoader.exists(model_path):
			body_rig.model_scene = load(model_path)

	# Local player gets an arm-only overlay that sits exactly on top of the body (same
	# transform as BodyRig) and is shown only in first person. Parent it to the BODY (not
	# the camera) so the arms stay put as you look around — the head-height camera then sees
	# your own arms where they really are. Remote bodies never need it.
	if is_local and _fp_arms == null:
		_fp_arms = FirstPersonArms.new()
		_fp_arms.name = "FirstPersonArms"
		add_child(_fp_arms)

func set_standing(standing: bool) -> void:
	is_standing = standing
	if standing:
		is_seated = false
	# The local player only sees their OWN body in 3rd-person view. In first person
	# (standing or seated) their body is hidden — no head/back blocking the view, and no
	# hands when seated. Remote players are always visible so others see a whole character.
	_update_body_visibility()
	# Movement physics only while standing. Input (mouse-look) stays on while seated too,
	# so a seated player can still look around — they just can't walk.
	set_physics_process(standing and is_local)
	set_process_input(is_local and (standing or is_seated))

	if standing:
		name_label.visible = true
		# Reset locomotion tracking so the body doesn't spike to "walk" on frame 1.
		_last_pos = global_position
		_remote_speed_smoothed = 0.0
		if body_rig:
			body_rig.set_locomotion(0.0)
	else:
		nearby_chair_seat_index = -1
		if interaction_label:
			interaction_label.visible = false
		# Sitting/standing-down ends any smoking emote (the pose is standing-only).
		_smoking = false
		if body_rig:
			body_rig.stop_smoke()
		if is_seated and body_rig:
			body_rig.play_anim("seated_idle")

## Local player: own BODY MESH shows only in 3rd-person view; in first person it's hidden so
## the arm overlay can be seen instead. Remote players: whole body visible while in the room.
## CRITICAL: for the local player we must NOT hide the PlayerBody node itself — that would
## also hide the FPSCamera's first-person arms (a descendant). Hide only the BodyRig mesh.
func _update_body_visibility() -> void:
	var in_world := is_standing or is_seated
	if not is_local:
		visible = in_world
		return
	visible = true  # keep the node tree visible so the FP arms can render
	var show_full_body := in_world and is_instance_valid(third_person_camera) and third_person_camera.current
	if body_rig:
		body_rig.visible = show_full_body
	if name_label:
		name_label.visible = show_full_body  # no floating name tag over our own first-person view

## Drive the first-person arm viewmodel: visible only when the local player is in first
## person (FPS camera current) and in the world, playing walk/smoke to match the body.
## Idle (neither walking nor smoking) hides the arms — there's no idle_fp clip.
func _update_fp_arms() -> void:
	if not is_local or not is_instance_valid(_fp_arms):
		return
	var first_person := is_instance_valid(fps_camera) and fps_camera.current
	var in_world := is_standing or is_seated
	if not first_person or not in_world:
		_fp_arms.visible = false
		_fp_arms.set_state("")
		return
	# Mirror whatever the body is doing so the overlay arms match the real pose — except
	# when seated: the sitting pose looks wrong up close in first person, so the local FP
	# arms fall back to idle. (Remote bodies still show the real sitting anim to others.)
	var state := "idle"
	if is_standing:
		if _smoking:
			state = "smoke"
		elif Vector2(velocity.x, velocity.z).length() > BodyRig.WALK_ENTER:
			state = "walk"
	_fp_arms.set_state(state)
	_fp_arms.visible = true

## Position the body at a chair and play the sitting idle animation.
## Call this BEFORE set_standing(false) so is_seated is already true.
func seat_at(chair_position: Vector3, face_direction: Vector3) -> void:
	is_seated = true
	if is_local:
		# First-person seated: sit at the chair (pushed back a touch from the edge) at
		# standing eye height, so the FPS camera gives a natural seated view of the table.
		var back := face_direction.normalized() * SEATED_LOCAL_BACK
		global_position = Vector3(chair_position.x + back.x, SEATED_LOCAL_Y, chair_position.z + back.z)
	else:
		# Remote full body: raised so the sitting pose rests on the chair, and pushed
		# outward (face_direction points away from the table) so it doesn't clip.
		var outward := face_direction.normalized() * SEATED_OUTWARD_OFFSET
		global_position = Vector3(chair_position.x + outward.x, SEATED_Y_OFFSET, chair_position.z + outward.z)
	# Body forward (−Z, which the FPS camera looks along) points toward the table center.
	if face_direction.length() > 0.001:
		rotation.y = atan2(face_direction.x, face_direction.z)
	# Keep mouse-look continuous from the seated facing so the view doesn't snap.
	if is_local:
		mouse_rotation.x = rotation.y
	set_standing(false)

func apply_remote_state(pos: Vector3, rot_y: float, head_yaw: float = 0.0, head_pitch: float = 0.0, smoking: bool = false) -> void:
	_remote_target_pos = pos
	_remote_target_rot_y = rot_y
	_remote_head_yaw = head_yaw
	_remote_head_pitch = head_pitch
	_remote_smoking = smoking
	_has_remote_target = true

## Local player's vertical look angle (head pitch), for syncing while standing.
func get_head_pitch() -> float:
	return fps_camera.rotation.x if fps_camera else 0.0

## Whether this body is currently playing the smoking emote (used for multiplayer sync).
func is_smoking_emote() -> bool:
	return _smoking

## Reach to the draw pile, then move the hand to where the drawn card is held
## and keep it there until release_card() is called.
func reach_and_hold(pile_pos: Vector3, hold_pos: Vector3) -> void:
	if not body_rig:
		return
	body_rig.begin_reach(pile_pos)
	await get_tree().create_timer(0.45).timeout
	if is_instance_valid(body_rig):
		body_rig.move_reach(hold_pos, 0.3)

## Make a card follow this body's right hand each frame (the held card).
func hold_card_visual(card: Node3D) -> void:
	if body_rig and body_rig.has_hand_tracking():
		_held_card = card

## Stop holding — the hand returns to the seated pose and the card is released.
func release_card() -> void:
	_held_card = null
	if body_rig:
		body_rig.end_reach()

func _process(delta: float) -> void:
	# Keep visibility in sync with the active camera (local body shows only in 3rd person).
	_update_body_visibility()
	# First-person arm viewmodel mirrors what the body is doing (walk/smoke), shown only
	# when the local player is actually in first person.
	_update_fp_arms()

	# Smoothly interpolate remote bodies toward their latest synced position
	if not is_local and _has_remote_target and is_standing:
		global_position = global_position.lerp(_remote_target_pos, clampf(REMOTE_LERP_SPEED * delta, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _remote_target_rot_y, clampf(REMOTE_LERP_SPEED * delta, 0.0, 1.0))

	# Keep seated bodies locked on the sitting idle (overrides any stray anim).
	if body_rig and is_seated and not is_standing:
		body_rig.set_seated()

	# Drive walk/idle blend on the body rig (same rig for local and remote). Smoking
	# overrides locomotion; for the local player, starting to move cancels the emote.
	if body_rig and is_standing:
		var speed: float
		if is_local:
			speed = Vector2(velocity.x, velocity.z).length()
		else:
			# Horizontal distance only — ignore Y so gravity/height changes don't
			# read as movement. Smooth it so 20Hz packet gaps don't flicker idle/walk.
			var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
			var inst_speed := moved / maxf(delta, 0.001)
			_remote_speed_smoothed = lerpf(_remote_speed_smoothed, inst_speed, clampf(REMOTE_SPEED_SMOOTH * delta, 0.0, 1.0))
			speed = _remote_speed_smoothed
		if is_local and _smoking and speed > SMOKE_WALK_CANCEL:
			_smoking = false  # walking cancels the smoke emote
		var want_smoke: bool = _smoking if is_local else _remote_smoking
		if want_smoke:
			body_rig.start_smoke()    # idempotent: smoke pose + particles on
		else:
			body_rig.stop_smoke()     # idempotent: particles off
			body_rig.set_locomotion(speed)
	_last_pos = global_position

	# Drive the head-look on remote bodies so others see them turning their head.
	if body_rig and not is_local and (is_standing or is_seated):
		body_rig.set_head_look(_remote_head_yaw, _remote_head_pitch)

	# Keep the held card glued to the hand (position only — its readable rotation is preserved).
	if _held_card != null and is_instance_valid(_held_card) and body_rig:
		_held_card.global_position = body_rig.get_hand_position()

	# Keep the 3rd-person camera pointed at the player head every frame.
	if third_person_camera and third_person_camera.current:
		var target := third_person_pivot.global_position
		if third_person_camera.global_position.distance_squared_to(target) > 0.01:
			third_person_camera.look_at(target, Vector3.UP)

func activate_fps_camera() -> void:
	"""Make this body's FPS camera the active viewport camera. Only call for local player."""
	if not is_local:
		push_warning("BUG: activate_fps_camera called on remote body (seat %d, peer %d)" % [seat_index, peer_id])
		return
	if fps_camera:
		fps_camera.make_current()

func deactivate_fps_camera() -> void:
	"""Release this body's FPS camera. Does NOT pick a replacement — caller must do that."""
	if fps_camera:
		fps_camera.current = false

func spawn_at_chair(chair_position: Vector3, face_direction: Vector3) -> void:
	# Position at floor level, offset outward from the chair
	var spawn_offset := face_direction.normalized() * 1.5
	global_position = Vector3(chair_position.x + spawn_offset.x, 0.0, chair_position.z + spawn_offset.z)

	# Face away from table (toward the wall)
	if face_direction.length() > 0.001:
		var yaw := atan2(face_direction.x, face_direction.z)
		rotation.y = yaw
		mouse_rotation.x = yaw

	if is_local:
		fps_camera.rotation.x = 0.0
		mouse_rotation.y = 0.0

func _input(event: InputEvent) -> void:
	# Local player can look around while standing OR seated (seated just can't walk).
	if not is_local or not (is_standing or is_seated):
		return

	# V toggles between FPS and 3rd-person debug view
	if event is InputEventKey and event.pressed and event.keycode == KEY_V:
		_toggle_third_person()
		return

	# R toggles the smoking emote (only while standing; walking cancels it).
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if is_standing:
			_smoking = not _smoking
		return

	# Escape toggles mouse capture
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	# Mouse-wheel zooms the 3rd-person camera (when active).
	if event is InputEventMouseButton and event.pressed and third_person_camera.current:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			third_person_arm.spring_length = clampf(third_person_arm.spring_length - 1.5, TP_MIN_ZOOM, TP_MAX_ZOOM)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			third_person_arm.spring_length = clampf(third_person_arm.spring_length + 1.5, TP_MIN_ZOOM, TP_MAX_ZOOM)
			return

	# Re-capture mouse on click when visible
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_rotation.x -= event.relative.x * MOUSE_SENSITIVITY
		mouse_rotation.y -= event.relative.y * MOUSE_SENSITIVITY
		mouse_rotation.y = clampf(mouse_rotation.y, deg_to_rad(-80), deg_to_rad(80))

		rotation.y = mouse_rotation.x
		fps_camera.rotation.x = mouse_rotation.y
		# Drive 3rd-person pitch on the pivot. Positive pitch = camera below player (looks up).
		third_person_pivot.rotation.x = clampf(mouse_rotation.y, -TP_PITCH_LIMIT, TP_PITCH_LIMIT)

	if event.is_action_pressed("interact") and nearby_chair_seat_index >= 0:
		request_sit.emit(nearby_chair_seat_index)

func _physics_process(delta: float) -> void:
	if not is_standing or not is_local:
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	# Movement input
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir.y -= 1
	if Input.is_action_pressed("move_back"):
		input_dir.y += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction.length() > 0:
		velocity.x = direction.x * MOVE_SPEED
		velocity.z = direction.z * MOVE_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, MOVE_SPEED * 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0, MOVE_SPEED * 10.0 * delta)

	move_and_slide()

	# Clamp to room bounds
	position.x = clampf(position.x, -19.0, 19.0)
	position.z = clampf(position.z, -19.0, 19.0)

	# Check for nearby chairs
	_update_chair_detection()

func _update_chair_detection() -> void:
	var prev_nearby := nearby_chair_seat_index
	nearby_chair_seat_index = -1

	# Check overlapping areas
	for area in get_tree().get_nodes_in_group("chair_zones"):
		if area is Area3D:
			var dist := global_position.distance_to(area.global_position)
			if dist < 2.5:
				nearby_chair_seat_index = area.get_meta("seat_index", -1)
				break

	# Update prompt visibility
	if interaction_label:
		if nearby_chair_seat_index >= 0 and prev_nearby < 0:
			interaction_label.text = "Press E to sit"
			interaction_label.visible = true
		elif nearby_chair_seat_index < 0 and prev_nearby >= 0:
			interaction_label.visible = false

func play_anim(anim_id: String) -> void:
	if body_rig:
		body_rig.play_anim(anim_id)

func _toggle_third_person() -> void:
	if third_person_camera.current:
		fps_camera.make_current()
	else:
		third_person_camera.make_current()

func set_talking_indicator(talking: bool) -> void:
	if _talk_indicator != null:
		_talk_indicator.visible = talking
