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

# Seated placement — raise the body so it sits on the chair instead of sinking
# below the table, and push it back from the table edge so it doesn't clip through.
const SEATED_Y_OFFSET: float = 1.5
const SEATED_OUTWARD_OFFSET: float = 2.0

# Remote interpolation
var _remote_target_pos: Vector3 = Vector3.ZERO
var _remote_target_rot_y: float = 0.0
var _has_remote_target: bool = false
const REMOTE_LERP_SPEED: float = 12.0
# Head look (yaw/pitch) — synced so others see players turning their heads.
var _remote_head_yaw: float = 0.0
var _remote_head_pitch: float = 0.0
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

	# Set the model on the rig (Walking.fbx is the character + walk animation).
	if body_rig:
		var model_path := "res://assets/models/characters/body/Walking.fbx"
		if ResourceLoader.exists(model_path):
			body_rig.model_scene = load(model_path)

func set_standing(standing: bool) -> void:
	if standing and not is_local:
		print("[PlayerBody] set_standing(TRUE) on REMOTE seat=%d peer=%d" % [seat_index, peer_id])
	is_standing = standing
	if standing:
		is_seated = false
	# Visible when standing, or when seated for REMOTE players (so others see the
	# sitting pose). The local player never renders their own seated body — they'd
	# only see the back of their own head in front of the seated table camera.
	visible = standing or (is_seated and not is_local)
	# Only the local player processes input and physics — never when seated.
	set_physics_process(standing and is_local)
	set_process_input(standing and is_local)

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
		if is_seated and body_rig:
			body_rig.play_anim("seated_idle")

## Position the body at a chair and play the sitting idle animation.
## Call this BEFORE set_standing(false) so is_seated is already true.
func seat_at(chair_position: Vector3, face_direction: Vector3) -> void:
	print("[PlayerBody] seat_at seat=%d local=%s" % [seat_index, is_local])
	is_seated = true
	# Place body at the chair, raised so the sitting pose rests on the chair, and
	# pushed outward (face_direction points away from the table) so it doesn't clip.
	var outward := face_direction.normalized() * SEATED_OUTWARD_OFFSET
	global_position = Vector3(chair_position.x + outward.x, SEATED_Y_OFFSET, chair_position.z + outward.z)
	# Same convention as spawn_at_chair: body forward (−Z) points toward the table.
	if face_direction.length() > 0.001:
		rotation.y = atan2(face_direction.x, face_direction.z)
	set_standing(false)

func apply_remote_state(pos: Vector3, rot_y: float, head_yaw: float = 0.0, head_pitch: float = 0.0) -> void:
	_remote_target_pos = pos
	_remote_target_rot_y = rot_y
	_remote_head_yaw = head_yaw
	_remote_head_pitch = head_pitch
	_has_remote_target = true

## Local player's vertical look angle (head pitch), for syncing while standing.
func get_head_pitch() -> float:
	return fps_camera.rotation.x if fps_camera else 0.0

var _dbg_frames: int = 0
func _process(delta: float) -> void:
	# Throttled diagnostic for remote bodies — what state + animation are they in?
	if not is_local:
		_dbg_frames += 1
		if _dbg_frames % 90 == 0 and body_rig:
			print("[PlayerBody] seat=%d standing=%s seated=%s anim='%s'" % [
				seat_index, is_standing, is_seated, body_rig.current_anim_name()])

	# Smoothly interpolate remote bodies toward their latest synced position
	if not is_local and _has_remote_target and is_standing:
		global_position = global_position.lerp(_remote_target_pos, clampf(REMOTE_LERP_SPEED * delta, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _remote_target_rot_y, clampf(REMOTE_LERP_SPEED * delta, 0.0, 1.0))

	# Keep seated bodies locked on the sitting idle (overrides any stray anim).
	if body_rig and is_seated and not is_standing:
		body_rig.set_seated()

	# Drive walk/idle blend on the body rig (same rig for local and remote).
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
		body_rig.set_locomotion(speed)
	_last_pos = global_position

	# Drive the head-look on remote bodies so others see them turning their head.
	if body_rig and not is_local and (is_standing or is_seated):
		body_rig.set_head_look(_remote_head_yaw, _remote_head_pitch)

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
	if not is_standing or not is_local:
		return

	# V toggles between FPS and 3rd-person debug view
	if event is InputEventKey and event.pressed and event.keycode == KEY_V:
		_toggle_third_person()
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
