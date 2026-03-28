extends Node3D

const TABLE_SURFACE_Y: float = 6.76
const SEAT_CAMERA_RADIUS: float = 9.5
const SEAT_CAMERA_HEIGHT_OFFSET: float = 3.2
const SEAT_CAMERA_LOOK_HEIGHT_OFFSET: float = 0.35
const LOCAL_FRONT_FILL_DISTANCE: float = 4.6
const LOCAL_BACK_FILL_DISTANCE: float = 7.2
const LOCAL_FILL_HEIGHT: float = 8.8

@onready var camera_controller = $Shell/CameraController
@onready var players_container = $Shell/Players
@onready var room_fill_light: OmniLight3D = $Shell/Room/FillLight
@onready var room_front_fill: OmniLight3D = $Shell/Room/FrontFill
@onready var room_back_fill: OmniLight3D = $Shell/Room/BackFill

@onready var title_label: Label = $RoomUI/TopLeft/TitleLabel
@onready var status_label: Label = $RoomUI/TopLeft/StatusLabel
@onready var seats_container: VBoxContainer = $RoomUI/TopLeft/SeatsContainer
@onready var invite_button: Button = $RoomUI/BottomBar/InviteButton
@onready var ready_button: Button = $RoomUI/BottomBar/ReadyButton
@onready var start_button: Button = $RoomUI/BottomBar/StartButton
@onready var leave_button: Button = $RoomUI/BottomBar/LeaveButton
@onready var lobby_code_label: Label = $RoomUI/TopLeft/LobbyCodeRow/LobbyCodeLabel
@onready var copy_button: Button = $RoomUI/TopLeft/LobbyCodeRow/CopyButton

var seat_visuals: Array[Node3D] = []
var _debug_overlay: CanvasLayer = null
var _debug_label: RichTextLabel = null
var _debug_visible: bool = false

# Movement system
var player_body_scene = preload("res://scenes/players/player_body.tscn")
var player_body: PlayerBody = null
var is_standing: bool = false
var leave_seat_container: Control = null
var interaction_label: Label = null

const CHAIR_POSITIONS: Array[Vector3] = [
	Vector3(0, 0, 5.5),    # South
	Vector3(0, 0, -5.5),   # North
	Vector3(-5.5, 0, 0),   # West
	Vector3(5.5, 0, 0),    # East
]
const CHAIR_FACE_DIRECTIONS: Array[Vector3] = [
	Vector3(0, 0, 1),
	Vector3(0, 0, -1),
	Vector3(-1, 0, 0),
	Vector3(1, 0, 0),
]

func _ready() -> void:
	_connect_room_service()
	invite_button.pressed.connect(_on_invite_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	SteamRoomService.ensure_room_flow_started()
	_refresh_view()
	_build_debug_overlay()
	_setup_movement_ui()
	_spawn_local_player_body()

func _connect_room_service() -> void:
	if not SteamRoomService.room_state_changed.is_connected(_on_room_state_changed):
		SteamRoomService.room_state_changed.connect(_on_room_state_changed)
		SteamRoomService.status_message_changed.connect(_on_status_message_changed)
		SteamRoomService.room_error.connect(_on_room_error)
		SteamRoomService.room_transition.connect(_on_room_transition)

func _on_room_state_changed() -> void:
	_refresh_view()

func _on_status_message_changed(message: String) -> void:
	status_label.text = message

func _on_room_error(message: String) -> void:
	status_label.text = message

func _on_room_transition(_phase_name: String) -> void:
	_refresh_view()

func _refresh_view() -> void:
	var room_state := SteamRoomService.get_room_state()
	title_label.text = room_state.room_name if not room_state.room_name.is_empty() else "Steam Room"
	status_label.text = SteamRoomService.get_status_message()
	_refresh_seat_labels(room_state)
	_refresh_buttons(room_state)
	_refresh_seat_visuals(room_state)
	_apply_local_view(room_state)

func _refresh_seat_labels(room_state: RoomState) -> void:
	for child in seats_container.get_children():
		child.queue_free()
	var scoreboard = room_state.session_scoreboard
	var has_scores := false
	if scoreboard != null:
		for v in scoreboard.scores_by_participant_id.values():
			if int(v) != 0:
				has_scores = true
				break
	for seat in room_state.seat_states:
		var seat_label := Label.new()
		if seat.is_occupied():
			seat_label.text = "%s: %s" % [seat.seat_label, seat.display_name]
			if seat.is_ready:
				seat_label.text += " (Ready)"
			if has_scores and scoreboard != null:
				var score: int = int(scoreboard.scores_by_participant_id.get(seat.occupant_participant_id, 0))
				seat_label.text += "  —  %d pts" % score
		else:
			seat_label.text = "%s: Empty" % seat.seat_label
		seat_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		seat_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		seat_label.add_theme_constant_override("outline_size", 3)
		seats_container.add_child(seat_label)

func _refresh_buttons(room_state: RoomState) -> void:
	var local_member := room_state.get_member(SteamPlatformService.get_local_steam_id())
	var is_host := SteamRoomService.is_local_host()
	ready_button.visible = not room_state.round_active and local_member != null
	if local_member != null and local_member.is_ready:
		ready_button.text = "Unready"
	else:
		ready_button.text = "I'm Ready"
	invite_button.visible = is_host and room_state.lobby_id != 0 and not room_state.round_active
	start_button.visible = is_host and not room_state.round_active
	start_button.disabled = not room_state.can_start_round()
	var show_code := is_host and room_state.lobby_id != 0
	lobby_code_label.visible = show_code
	copy_button.visible = show_code
	if show_code:
		lobby_code_label.text = "Lobby ID: %d" % room_state.lobby_id

func _refresh_seat_visuals(room_state: RoomState) -> void:
	for visual in seat_visuals:
		if is_instance_valid(visual):
			visual.queue_free()
	seat_visuals.clear()

	var card_y := TABLE_SURFACE_Y + 0.01
	var positions = [
		Vector3(0, card_y, 3.5),
		Vector3(0, card_y, -3.5),
		Vector3(-4, card_y, 0),
		Vector3(4, card_y, 0)
	]

	for seat in room_state.seat_states:
		if not seat.is_occupied() or seat.seat_index >= positions.size():
			continue
		var grid_pos: Vector3 = positions[seat.seat_index]
		var dir_away := Vector3(grid_pos.x, 0, grid_pos.z).normalized()
		var seat_pos := grid_pos + dir_away * 1.5
		var chair_pos := grid_pos + dir_away * 3.0
		chair_pos.y = seat_pos.y
		var color := _get_seat_color(room_state, seat)

		if seat.is_local:
			var dot := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.06
			sphere.height = 0.12
			dot.mesh = sphere
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color.lightened(0.1)
			mat.emission_enabled = true
			mat.emission = color.lightened(0.15)
			mat.emission_energy_multiplier = 1.3
			dot.material_override = mat
			add_child(dot)
			dot.global_position = Vector3(seat_pos.x, seat_pos.y + 0.3, seat_pos.z)
			seat_visuals.append(dot)
			continue

		var body_root := Node3D.new()
		add_child(body_root)
		body_root.global_position = Vector3(chair_pos.x, chair_pos.y - 0.6, chair_pos.z)
		var dir_to_center := Vector3(-chair_pos.x, 0, -chair_pos.z).normalized()
		if dir_to_center.length() > 0.01:
			body_root.rotation.y = atan2(dir_to_center.x, dir_to_center.z)

		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.55
		capsule.height = 2.2
		body.mesh = capsule
		var body_mat := StandardMaterial3D.new()
		body_mat.albedo_color = color
		body_mat.roughness = 0.8
		body.material_override = body_mat
		body.position = Vector3(0, 1.1, 0)
		body_root.add_child(body)

		var head := MeshInstance3D.new()
		var head_mesh := SphereMesh.new()
		head_mesh.radius = 0.42
		head_mesh.height = 0.84
		head.mesh = head_mesh
		var head_mat := StandardMaterial3D.new()
		head_mat.albedo_color = color.lightened(0.2)
		head_mat.roughness = 0.7
		head.material_override = head_mat
		head.position = Vector3(0, 2.55, 0)
		body_root.add_child(head)

		seat_visuals.append(body_root)

func _apply_local_view(room_state: RoomState) -> void:
	var seat_index := room_state.get_local_seat_index(SteamPlatformService.get_local_steam_id())
	if seat_index < 0:
		seat_index = 0
	var direction := _get_seat_direction(seat_index)
	var camera_pos := direction * SEAT_CAMERA_RADIUS
	camera_pos.y = TABLE_SURFACE_Y + SEAT_CAMERA_HEIGHT_OFFSET
	var look_target := Vector3(0, TABLE_SURFACE_Y + SEAT_CAMERA_LOOK_HEIGHT_OFFSET, 0)
	camera_controller.set_view(camera_pos, look_target)
	if room_fill_light:
		room_fill_light.global_position = Vector3(0, LOCAL_FILL_HEIGHT, 0)
	if room_front_fill:
		room_front_fill.global_position = Vector3(
			direction.x * LOCAL_FRONT_FILL_DISTANCE,
			LOCAL_FILL_HEIGHT,
			direction.z * LOCAL_FRONT_FILL_DISTANCE
		)
	if room_back_fill:
		room_back_fill.global_position = Vector3(
			direction.x * LOCAL_BACK_FILL_DISTANCE,
			LOCAL_FILL_HEIGHT,
			direction.z * LOCAL_BACK_FILL_DISTANCE
		)

func _get_seat_direction(seat_index: int) -> Vector3:
	var card_y := TABLE_SURFACE_Y + 0.01
	var positions = [
		Vector3(0, card_y, 3.5),
		Vector3(0, card_y, -3.5),
		Vector3(-4, card_y, 0),
		Vector3(4, card_y, 0)
	]
	if seat_index < 0 or seat_index >= positions.size():
		return Vector3(0, 0, 1)
	var seat_direction := Vector3(positions[seat_index].x, 0.0, positions[seat_index].z)
	if seat_direction.length() < 0.001:
		return Vector3(0, 0, 1)
	return seat_direction.normalized()

func _get_seat_color(room_state: RoomState, seat: SeatState) -> Color:
	var profile = room_state.participants_by_id.get(seat.occupant_participant_id, null)
	if profile != null:
		return profile.avatar_color
	return Color(0.8, 0.8, 0.8, 1.0)

func _input(event: InputEvent) -> void:
	# Leave seat: Q key
	var is_leave_seat := event.is_action_pressed("leave_seat")
	if not is_leave_seat and event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		is_leave_seat = true
	if is_leave_seat and not is_standing:
		_on_leave_seat_pressed()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_toggle_debug_overlay()

func _process(_delta: float) -> void:
	if _debug_visible:
		_update_debug_overlay()

func _build_debug_overlay() -> void:
	_debug_overlay = CanvasLayer.new()
	_debug_overlay.layer = 100
	add_child(_debug_overlay)
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size = Vector2(480, 320)
	_debug_overlay.add_child(panel)
	_debug_label = RichTextLabel.new()
	_debug_label.bbcode_enabled = true
	_debug_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_debug_label.add_theme_font_size_override("normal_font_size", 13)
	panel.add_child(_debug_label)
	_debug_overlay.visible = false

func _toggle_debug_overlay() -> void:
	_debug_visible = not _debug_visible
	_debug_overlay.visible = _debug_visible

func _update_debug_overlay() -> void:
	var rs := SteamRoomService.get_room_state()
	var lines: PackedStringArray = []
	lines.append("[b]== Steam Debug (F3 to hide) ==[/b]")
	lines.append("Phase: [b]%s[/b]  |  Round active: %s" % [rs.phase_name, rs.round_active])
	lines.append("Lobby ID: %d  |  Host SteamID: %d" % [rs.lobby_id, rs.host_steam_id])
	lines.append("Local SteamID: %d  |  Name: %s" % [
		SteamPlatformService.get_local_steam_id(),
		SteamPlatformService.get_local_display_name()
	])
	lines.append("MP unique_id: %d  |  is_server: %s  |  has_peer: %s" % [
		multiplayer.get_unique_id(),
		multiplayer.is_server(),
		multiplayer.has_multiplayer_peer()
	])
	lines.append("[b]--- Seats ---[/b]")
	for seat: SeatState in rs.seat_states:
		if seat.is_occupied():
			lines.append("[%s] %s  steamID:%d  peer:%d  ready:%s  local:%s" % [
				seat.seat_label, seat.display_name,
				seat.occupant_steam_id,
				rs.get_member(seat.occupant_steam_id).peer_id if rs.get_member(seat.occupant_steam_id) != null else 0,
				seat.is_ready, seat.is_local
			])
		else:
			lines.append("[%s] Empty" % seat.seat_label)
	_debug_label.text = "\n".join(lines)

## ── Movement system ──────────────────────────────────────────────────────

func _setup_movement_ui() -> void:
	# Leave seat button
	var leave_canvas := CanvasLayer.new()
	leave_canvas.layer = 10
	add_child(leave_canvas)
	leave_seat_container = Control.new()
	leave_seat_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	leave_seat_container.offset_left = -80
	leave_seat_container.offset_top = -80
	leave_seat_container.offset_right = 80
	leave_seat_container.offset_bottom = -20
	leave_canvas.add_child(leave_seat_container)
	var btn := Button.new()
	btn.text = "Leave Seat (Q)"
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(_on_leave_seat_pressed)
	leave_seat_container.add_child(btn)

	# Interaction prompt
	var prompt_canvas := CanvasLayer.new()
	prompt_canvas.layer = 10
	add_child(prompt_canvas)
	interaction_label = Label.new()
	interaction_label.text = "Press E to sit"
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.add_theme_font_size_override("font_size", 24)
	interaction_label.visible = false
	interaction_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	interaction_label.position = Vector2(-100, -200)
	interaction_label.size = Vector2(200, 40)
	prompt_canvas.add_child(interaction_label)

func _spawn_local_player_body() -> void:
	if player_body != null:
		return
	player_body = player_body_scene.instantiate()
	# Use a unique name per peer so MultiplayerSynchronizer paths don't collide
	var local_peer := multiplayer.get_unique_id()
	player_body.name = "LobbyBody_%d" % local_peer
	add_child(player_body)
	# Disable the MultiplayerSynchronizer — lobby movement is local only,
	# no need to sync walking position to other peers.
	var sync := player_body.get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.queue_free()
	player_body.setup(0, local_peer, SteamPlatformService.get_local_display_name(), Color(0.4, 0.6, 0.4), true)
	player_body.request_sit.connect(_on_body_request_sit)
	player_body.interaction_label = interaction_label

func _on_leave_seat_pressed() -> void:
	if is_standing or player_body == null:
		return
	var room_state := SteamRoomService.get_room_state()
	var seat_index := room_state.get_local_seat_index(SteamPlatformService.get_local_steam_id())
	if seat_index < 0:
		seat_index = 0

	is_standing = true
	var chair_pos := CHAIR_POSITIONS[seat_index] if seat_index < CHAIR_POSITIONS.size() else Vector3.ZERO
	var face_dir := CHAIR_FACE_DIRECTIONS[seat_index] if seat_index < CHAIR_FACE_DIRECTIONS.size() else Vector3(0, 0, 1)
	player_body.spawn_at_chair(chair_pos, face_dir)
	player_body.set_standing(true)

	# Switch camera: disable seated, then make FPS current
	camera_controller.set_process(false)
	camera_controller.set_process_input(false)
	player_body.activate_fps_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	leave_seat_container.visible = false

func _on_body_request_sit(_target_seat: int) -> void:
	if not is_standing or player_body == null:
		return
	is_standing = false
	player_body.set_standing(false)
	player_body.deactivate_fps_camera()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Restore seated camera
	camera_controller.set_process(true)
	camera_controller.set_process_input(true)
	camera_controller.camera.make_current()
	var room_state := SteamRoomService.get_room_state()
	_apply_local_view(room_state)
	leave_seat_container.visible = true

## ── Lobby actions ────────────────────────────────────────────────────────

func _on_invite_pressed() -> void:
	invite_button.disabled = true
	SteamPlatformService.open_invite_dialog()
	await get_tree().create_timer(2.0).timeout
	invite_button.disabled = false

func _on_copy_pressed() -> void:
	var rs := SteamRoomService.get_room_state()
	DisplayServer.clipboard_set(str(rs.lobby_id))
	copy_button.text = "Copied!"
	await get_tree().create_timer(2.0).timeout
	copy_button.text = "Copy"

func _on_ready_pressed() -> void:
	SteamRoomService.request_toggle_ready()

func _on_start_pressed() -> void:
	SteamRoomService.request_start_round()

func _on_leave_pressed() -> void:
	SteamRoomService.request_leave_room()
