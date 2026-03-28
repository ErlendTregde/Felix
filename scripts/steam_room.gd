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
var player_bodies: Dictionary = {}  # seat_index -> PlayerBody
var local_body: PlayerBody = null
var local_seat_index: int = 0
var local_original_seat: int = 0  # Never changes — the seat assigned by room state
var is_standing: bool = false
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

# Wall spawn point — players start here standing, facing toward table
const WALL_SPAWN_POS := Vector3(0, 0, -16.0)  # Near north wall

func _ready() -> void:
	_connect_room_service()
	invite_button.pressed.connect(_on_invite_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	SteamRoomService.ensure_room_flow_started()
	_build_debug_overlay()
	_setup_movement_ui()
	SteamMovementService.player_stood.connect(_on_player_stood)
	SteamMovementService.player_sat.connect(_on_player_sat)
	SteamMovementService.position_updated.connect(_on_remote_position_updated)
	# Disable seated camera before spawning — players start standing with FPS camera
	camera_controller.set_active(false)
	if camera_controller.camera:
		camera_controller.camera.current = false
	_spawn_all_player_bodies()
	_refresh_view()

func _connect_room_service() -> void:
	if not SteamRoomService.room_state_changed.is_connected(_on_room_state_changed):
		SteamRoomService.room_state_changed.connect(_on_room_state_changed)
		SteamRoomService.status_message_changed.connect(_on_status_message_changed)
		SteamRoomService.room_error.connect(_on_room_error)
		SteamRoomService.room_transition.connect(_on_room_transition)

func _on_room_state_changed() -> void:
	_spawn_all_player_bodies()
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
	ready_button.visible = not room_state.round_active and local_member != null and not is_standing
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

func _refresh_seat_visuals(_room_state: RoomState) -> void:
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

	# Build visuals from player_bodies (tracks actual seat positions after switches)
	for seat_idx in player_bodies:
		var pb: PlayerBody = player_bodies[seat_idx]
		if not is_instance_valid(pb):
			continue
		# Skip standing players (their PlayerBody is visible instead)
		if pb.is_standing:
			continue
		# Skip local player (they see through the seated camera)
		if pb.is_local:
			continue
		# Use the body's current seat_index for positioning
		var actual_seat: int = pb.seat_index
		if actual_seat < 0 or actual_seat >= positions.size():
			continue

		var grid_pos: Vector3 = positions[actual_seat]
		var dir_away := Vector3(grid_pos.x, 0, grid_pos.z).normalized()
		var chair_pos := grid_pos + dir_away * 3.0
		chair_pos.y = grid_pos.y
		var color := Color(0.4, 0.6, 0.4)
		var mat_override = pb.avatar_mesh.material_override
		if mat_override is StandardMaterial3D:
			color = mat_override.albedo_color

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
	if is_standing:
		return
	# Use local_seat_index which tracks the chair we're actually sitting in
	var seat_index := local_seat_index
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

var _sync_timer: float = 0.0
const SYNC_INTERVAL: float = 0.05  # 20 updates/sec

func _process(delta: float) -> void:
	if _debug_visible:
		_update_debug_overlay()
	# Broadcast local body position to all peers
	if is_standing and local_body != null and multiplayer.has_multiplayer_peer():
		_sync_timer += delta
		if _sync_timer >= SYNC_INTERVAL:
			_sync_timer = 0.0
			var pos := local_body.global_position
			SteamMovementService.sync_body_position.rpc(
				local_seat_index, pos.x, pos.y, pos.z, local_body.rotation.y
			)

func _on_remote_position_updated(seat_index: int, pos: Vector3, rot_y: float) -> void:
	var body := _find_body_at_seat(seat_index)
	if body and not body.is_local:
		body.apply_remote_state(pos, rot_y)

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

func _spawn_all_player_bodies() -> void:
	var room_state := SteamRoomService.get_room_state()
	var orig_seat := room_state.get_local_seat_index(SteamPlatformService.get_local_steam_id())
	if orig_seat >= 0:
		local_original_seat = orig_seat
	# Only set local_seat_index from room state on first spawn.
	# After that, seat switches via SteamMovementService update it.
	if local_body == null:
		local_seat_index = SteamMovementService.get_current_seat(local_original_seat)

	# Build set of occupied seat indices with their current peer_id
	var occupied_seats: Dictionary = {}  # seat_index -> SeatState
	var seat_peer_ids: Dictionary = {}   # seat_index -> peer_id
	for seat in room_state.seat_states:
		if seat.is_occupied():
			occupied_seats[seat.seat_index] = seat
			var member = room_state.get_member(seat.occupant_steam_id)
			seat_peer_ids[seat.seat_index] = member.peer_id if member != null and member.peer_id > 0 else 1

	# Remove bodies for seats that are no longer occupied,
	# or re-create if peer_id changed (authority needs updating)
	for seat_idx in player_bodies.keys():
		var body: PlayerBody = player_bodies[seat_idx]
		if not occupied_seats.has(seat_idx):
			if is_instance_valid(body) and body.is_local:
				local_body = null
			if is_instance_valid(body):
				body.get_parent().remove_child(body)
				body.queue_free()
			player_bodies.erase(seat_idx)
		elif is_instance_valid(body) and body.peer_id != seat_peer_ids.get(seat_idx, 1):
			# Peer ID changed — remove so it gets re-created with correct authority
			if body.is_local:
				local_body = null
			body.get_parent().remove_child(body)
			body.queue_free()
			player_bodies.erase(seat_idx)

	# Add bodies for newly occupied seats
	var new_bodies: Array[PlayerBody] = []
	for seat_idx in occupied_seats:
		if player_bodies.has(seat_idx):
			continue  # Already spawned with correct peer_id
		var seat: SeatState = occupied_seats[seat_idx]
		var body_peer_id: int = seat_peer_ids[seat_idx]
		var body_is_local: bool = (seat_idx == local_original_seat)
		var color := _get_seat_color(room_state, seat)

		var body: PlayerBody = player_body_scene.instantiate()
		body.name = "LobbyBody_Seat%d" % seat_idx
		# Remove MultiplayerSynchronizer — lobby uses RPC-based position sync
		var sync_node := body.get_node_or_null("MultiplayerSynchronizer")
		if sync_node:
			body.remove_child(sync_node)
			sync_node.queue_free()
		add_child(body)
		body.setup(seat_idx, body_peer_id, seat.display_name, color, body_is_local)
		body.request_sit.connect(_on_body_request_sit)
		if body_is_local:
			body.interaction_label = interaction_label
			local_body = body
		player_bodies[seat_idx] = body
		new_bodies.append(body)

	# Spawn new bodies standing at wall (not seated), offset so they don't overlap
	for i in new_bodies.size():
		var body: PlayerBody = new_bodies[i]
		var spawn_pos := WALL_SPAWN_POS + Vector3(i * 2.0 - (new_bodies.size() - 1), 0, 0)
		body.global_position = Vector3(spawn_pos.x, 0.0, spawn_pos.z)
		# Face toward table center (+Z from north wall)
		var yaw := atan2(0.0, 1.0)  # facing +Z (south, toward table)
		body.rotation.y = yaw
		body.mouse_rotation.x = yaw
		if body.is_local and body.fps_camera:
			body.fps_camera.rotation.x = 0.0
			body.mouse_rotation.y = 0.0
		body.set_standing(true)
		SteamMovementService._standing_seats[body.seat_index] = true
		if body.is_local:
			is_standing = true
			camera_controller.set_process(false)
			camera_controller.set_process_input(false)
			body.activate_fps_camera()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_leave_seat_pressed() -> void:
	if is_standing or local_body == null:
		return
	# Leaving seat counts as unready
	SteamRoomService.request_ready_state(false)
	# Route through SteamMovementService RPCs
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		SteamMovementService.client_request_stand.rpc_id(1)
	elif multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		SteamMovementService._standing_seats[local_seat_index] = true
		SteamMovementService._occupied_seats.erase(local_seat_index)
		SteamMovementService._client_player_stood.rpc(local_seat_index)
		SteamMovementService._client_player_stood(local_seat_index)
	else:
		SteamMovementService.local_stand(local_seat_index)

func _on_body_request_sit(target_seat: int) -> void:
	if not is_standing or local_body == null:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		SteamMovementService.client_request_sit.rpc_id(1, target_seat)
	elif multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if SteamMovementService.is_seat_occupied(target_seat):
			return
		SteamMovementService._standing_seats[local_seat_index] = false
		SteamMovementService._occupied_seats[target_seat] = true
		SteamMovementService._current_seat[local_original_seat] = target_seat
		SteamMovementService._client_player_sat.rpc(local_seat_index, target_seat, local_original_seat)
		SteamMovementService._client_player_sat(local_seat_index, target_seat, local_original_seat)
	else:
		SteamMovementService.local_sit(local_seat_index, target_seat)

func _find_body_at_seat(current_seat: int) -> PlayerBody:
	"""Find the body currently at the given seat (checks body.seat_index, not dict key)."""
	for body: PlayerBody in player_bodies.values():
		if is_instance_valid(body) and body.seat_index == current_seat:
			return body
	return null

func _on_player_stood(seat_index: int) -> void:
	var body := _find_body_at_seat(seat_index)
	if body == null:
		return
	var chair_pos := CHAIR_POSITIONS[seat_index] if seat_index < CHAIR_POSITIONS.size() else Vector3.ZERO
	var face_dir := CHAIR_FACE_DIRECTIONS[seat_index] if seat_index < CHAIR_FACE_DIRECTIONS.size() else Vector3(0, 0, 1)
	body.spawn_at_chair(chair_pos, face_dir)
	body.set_standing(true)

	# Refresh seated visuals to hide this player's avatar
	_refresh_seat_visuals(SteamRoomService.get_room_state())

	if seat_index == local_seat_index:
		is_standing = true
		camera_controller.set_process(false)
		camera_controller.set_process_input(false)
		body.activate_fps_camera()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_refresh_buttons(SteamRoomService.get_room_state())

func _on_player_sat(seat_index: int, target_seat: int) -> void:
	var body := _find_body_at_seat(seat_index)
	if body:
		body.set_standing(false)
		# Update the body's seat_index for visual positioning (don't move dict key)
		body.seat_index = target_seat

	# Refresh seated visuals to show this player's avatar again
	_refresh_seat_visuals(SteamRoomService.get_room_state())

	var is_local_player: bool = (seat_index == local_seat_index)
	if is_local_player:
		is_standing = false
		# Update local seat index if we sat in a different chair
		if target_seat != local_seat_index:
			local_seat_index = target_seat
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if body:
			body.deactivate_fps_camera()
		camera_controller.set_process(true)
		camera_controller.set_process_input(true)
		camera_controller.camera.make_current()
		var room_state := SteamRoomService.get_room_state()
		_apply_local_view(room_state)
		_refresh_buttons(room_state)

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
