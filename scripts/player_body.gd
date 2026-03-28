extends CharacterBody3D
class_name PlayerBody

const MOVE_SPEED := 5.0
const MOUSE_SENSITIVITY := 0.002
const GRAVITY := 20.0

@export var seat_index: int = -1
@export var peer_id: int = 1

@onready var fps_camera: Camera3D = $FPSCamera
@onready var avatar_mesh: MeshInstance3D = $AvatarMesh
@onready var name_label: Label3D = $NameLabel
@onready var interaction_ray: RayCast3D = $FPSCamera/InteractionRay

var is_standing: bool = false
var is_local: bool = false  # Whether this body belongs to the local player
var mouse_rotation: Vector2 = Vector2.ZERO  # x = yaw, y = pitch
var player_display_name: String = ""
var nearby_chair_seat_index: int = -1

# Remote interpolation
var _remote_target_pos: Vector3 = Vector3.ZERO
var _remote_target_rot_y: float = 0.0
var _has_remote_target: bool = false
const REMOTE_LERP_SPEED: float = 12.0

# Interaction prompt (created by game_table/steam_room)
var interaction_label: Label = null

signal request_sit(seat_index: int)
signal request_stand()

func _ready() -> void:
	# Start hidden/inactive
	set_standing(false)

func setup(p_seat_index: int, p_peer_id: int, p_display_name: String, p_color: Color, p_is_local: bool) -> void:
	seat_index = p_seat_index
	peer_id = p_peer_id
	player_display_name = p_display_name
	is_local = p_is_local
	set_multiplayer_authority(peer_id)

	name_label.text = p_display_name

	# Color the avatar
	var mat := StandardMaterial3D.new()
	mat.albedo_color = p_color
	avatar_mesh.material_override = mat

	# Local player: hide avatar mesh (first person view) but keep nametag visible
	if is_local:
		avatar_mesh.visible = false

func set_standing(standing: bool) -> void:
	is_standing = standing
	visible = standing
	# Only the local player processes input and physics
	set_physics_process(standing and is_local)
	set_process_input(standing and is_local)

	if standing:
		# Show avatar for remote players, nametag for everyone
		name_label.visible = true
		if not is_local:
			avatar_mesh.visible = true
	else:
		nearby_chair_seat_index = -1
		if interaction_label:
			interaction_label.visible = false

func apply_remote_state(pos: Vector3, rot_y: float) -> void:
	_remote_target_pos = pos
	_remote_target_rot_y = rot_y
	_has_remote_target = true

func _process(delta: float) -> void:
	# Smoothly interpolate remote bodies toward their latest synced position
	if not is_local and _has_remote_target and is_standing:
		global_position = global_position.lerp(_remote_target_pos, clampf(REMOTE_LERP_SPEED * delta, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _remote_target_rot_y, clampf(REMOTE_LERP_SPEED * delta, 0.0, 1.0))

func activate_fps_camera() -> void:
	"""Make this body's FPS camera the active viewport camera. Only call for local player."""
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

	# Escape toggles mouse capture
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
