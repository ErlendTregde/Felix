extends Node

const RoomStateScript = preload("res://scripts/room_state.gd")
const RoomMemberStateScript = preload("res://scripts/room_member_state.gd")
const SeatStateScript = preload("res://scripts/seat_state.gd")
const ParticipantProfileScript = preload("res://scripts/participant_profile.gd")

signal room_state_changed
signal status_message_changed(message: String)
signal room_error(message: String)
signal room_transition(phase_name: String)

var room_state: RoomState = null
var entry_mode: String = ""
var status_message: String = ""
var _next_participant_id: int = 0

func _ready() -> void:
	_reset_room_state()
	call_deferred("_connect_dependencies")

func _connect_dependencies() -> void:
	SteamPlatformService.steam_status_changed.connect(_on_steam_status_changed)
	SteamPlatformService.lobby_created.connect(_on_lobby_created)
	SteamPlatformService.lobby_joined.connect(_on_lobby_joined)
	SteamPlatformService.lobby_left.connect(_on_lobby_left)
	SteamPlatformService.lobby_join_failed.connect(_on_lobby_join_failed)
	SteamPlatformService.lobby_members_updated.connect(_on_lobby_members_updated)
	SteamPlatformService.lobby_data_updated.connect(_on_lobby_data_updated)
	SteamPlatformService.join_request_pending.connect(_on_join_request_pending)
	FelixNetworkSession.peer_registered.connect(_on_peer_registered)
	FelixNetworkSession.player_left.connect(_on_player_left)
	FelixNetworkSession.host_disconnected.connect(_on_host_disconnected)
	FelixNetworkSession.connection_failed.connect(_on_connection_failed)
	if State.pending_join_request.lobby_id > 0:
		_on_join_request_pending(
			int(State.pending_join_request.lobby_id),
			int(State.pending_join_request.friend_id),
			String(State.pending_join_request.source)
		)

func prepare_host_entry() -> void:
	_reset_room_state()
	entry_mode = "host"
	_set_phase("CONNECTING")
	_set_status("Creating Steam room...")

func prepare_join_entry() -> void:
	_reset_room_state()
	entry_mode = "join"
	_set_phase("CONNECTING")
	_set_status("Joining Steam room...")

func ensure_room_flow_started() -> void:
	_log("ensure_room_flow_started: entry_mode='%s'  lobby_id=%d" % [entry_mode, int(State.lobby_data.id)])
	if entry_mode == "host":
		if not SteamPlatformService.is_steam_available():
			_emit_room_error(SteamPlatformService.get_unavailable_reason())
			return
		if State.lobby_data.id == 0:
			_log("Creating new friends-only lobby (max 4)")
			SteamPlatformService.create_friends_lobby(4)
		else:
			_refresh_room_state_for_current_role()
	elif entry_mode == "join":
		if State.lobby_data.id != 0:
			_log("Joining lobby %d" % int(State.lobby_data.id))
			_set_status("Connecting to host...")
			_refresh_room_state_for_current_role()
		else:
			_set_status("Waiting for Steam lobby...")
	elif State.lobby_data.id != 0:
		_refresh_room_state_for_current_role()
	else:
		_set_phase("IDLE")

func _log(msg: String) -> void:
	print("[SteamRoomService] %s" % msg)

func get_room_state() -> RoomState:
	return room_state

func get_status_message() -> String:
	return status_message

func is_local_host() -> bool:
	return SteamPlatformService.is_local_lobby_owner()

func request_toggle_ready() -> void:
	var local_member = room_state.get_member(SteamPlatformService.get_local_steam_id())
	var next_ready := true
	if local_member != null:
		next_ready = not local_member.is_ready
	request_ready_state(next_ready)

func request_ready_state(is_ready: bool = true) -> void:
	if room_state.lobby_id == 0:
		return
	if is_local_host():
		_apply_ready_change_for_steam_id(SteamPlatformService.get_local_steam_id(), is_ready)
		_broadcast_room_snapshot()
		return
	_server_request_ready_state.rpc_id(1, is_ready)

func request_start_round() -> void:
	if room_state.lobby_id == 0:
		return
	if not is_local_host():
		_emit_room_error("Only the host can start the round.")
		return
	if not room_state.can_start_round():
		_emit_room_error("All seated players must be ready before the round can start.")
		return
	_log("Starting round — %d seated players" % room_state.get_seated_member_count())
	room_state.round_active = true
	_set_phase("IN_ROUND")
	_set_status("Round entered. Full networked gameplay sync lands in Phase 3.")
	FelixNetworkSession.start_session_for_all()
	_broadcast_room_snapshot()
	_client_room_transition.rpc("IN_ROUND", status_message)

func finish_active_round() -> void:
	if not is_local_host():
		return
	_log("Finishing active round")
	room_state.round_active = false
	room_state.clear_ready_states()
	_set_phase("WAITING")
	_set_status("Round ended. Ready up for the next round.")
	_broadcast_room_snapshot()
	_client_room_transition.rpc("WAITING", status_message)

func request_leave_room() -> void:
	if State.lobby_data.id == 0:
		AppFlow.open_launcher()
		return
	SteamPlatformService.leave_current_lobby()
	_reset_room_state()
	AppFlow.open_launcher("Left Steam room.")

func _reset_room_state() -> void:
	room_state = RoomStateScript.new()
	_next_participant_id = 0
	status_message = ""
	emit_signal("room_state_changed")
	emit_signal("status_message_changed", status_message)

func _set_status(message: String) -> void:
	status_message = message
	status_message_changed.emit(status_message)

func _set_phase(phase_name: String) -> void:
	_log("Phase: %s → %s" % [room_state.phase_name, phase_name])
	room_state.phase_name = phase_name
	room_transition.emit(phase_name)
	room_state_changed.emit()

func _emit_room_error(message: String) -> void:
	_set_status(message)
	room_error.emit(message)

func _refresh_room_state_for_current_role() -> void:
	room_state.lobby_id = int(State.lobby_data.id)
	room_state.room_name = String(State.lobby_data.name)
	room_state.host_steam_id = int(State.lobby_data.owner_id)
	if is_local_host():
		_rebuild_host_room_state()
	elif room_state.get_phase() == RoomState.RoomPhase.CONNECTING:
		_set_status("Waiting for room snapshot from host...")

func _rebuild_host_room_state() -> void:
	if not is_local_host():
		return

	_log("Rebuilding host room state — %d lobby members" % State.lobby_data.members.size())
	room_state.lobby_id = SteamPlatformService.get_lobby_id()
	room_state.room_name = SteamPlatformService.get_lobby_name()
	room_state.host_steam_id = int(State.lobby_data.owner_id)

	var current_member_ids: Array[int] = []
	for steam_id_variant in State.lobby_data.members.keys():
		current_member_ids.append(int(steam_id_variant))
	current_member_ids.sort()

	for existing_steam_id_variant in room_state.members_by_steam_id.keys().duplicate():
		var existing_steam_id := int(existing_steam_id_variant)
		if not current_member_ids.has(existing_steam_id):
			_remove_member(existing_steam_id)

	for steam_id in current_member_ids:
		var member_info: Dictionary = State.lobby_data.members.get(steam_id, {})
		var member_state = room_state.members_by_steam_id.get(steam_id, null)
		if member_state == null:
			member_state = _create_member_state(steam_id, member_info)
			room_state.members_by_steam_id[steam_id] = member_state
		else:
			_update_member_state(member_state, member_info)
		_apply_member_to_seat(member_state)

	if room_state.round_active:
		_set_phase("IN_ROUND")
	else:
		_set_phase("WAITING")
		_set_status("%d / %d ready" % [_count_ready_seats(), room_state.get_seated_member_count()])

	_broadcast_room_snapshot()

func _create_member_state(steam_id: int, member_info: Dictionary) -> RoomMemberState:
	_log("Creating member state: steam_id=%d  name='%s'" % [steam_id, String(member_info.get("steam_username", "?"))])
	var participant_id := _next_participant_id
	_next_participant_id += 1
	var seat_index := _assign_first_free_seat()
	_log("  → assigned seat_index=%d  participant_id=%d" % [seat_index, participant_id])
	var is_local := steam_id == SteamPlatformService.get_local_steam_id()
	var member_state = RoomMemberStateScript.new().configure(
		steam_id,
		_find_peer_id_for_steam_id(steam_id),
		participant_id,
		seat_index,
		String(member_info.get("steam_username", "Steam Player")),
		steam_id == int(State.lobby_data.owner_id),
		is_local
	)
	var profile = ParticipantProfileScript.new().configure(
		participant_id,
		member_state.display_name,
		_get_participant_color(participant_id),
		SeatContext.SeatControlType.LOCAL_HUMAN if is_local else SeatContext.SeatControlType.REMOTE_HUMAN,
		is_local
	)
	profile.steam_id = steam_id
	profile.peer_id = member_state.peer_id
	room_state.participants_by_id[participant_id] = profile
	room_state.session_scoreboard.ensure_participant(participant_id, profile.display_name)
	return member_state

func _update_member_state(member_state: RoomMemberState, member_info: Dictionary) -> void:
	member_state.display_name = String(member_info.get("steam_username", member_state.display_name))
	member_state.peer_id = _find_peer_id_for_steam_id(member_state.steam_id)
	member_state.is_host = member_state.steam_id == int(State.lobby_data.owner_id)
	member_state.is_local = member_state.steam_id == SteamPlatformService.get_local_steam_id()
	if room_state.participants_by_id.has(member_state.participant_id):
		var profile = room_state.participants_by_id[member_state.participant_id]
		profile.display_name = member_state.display_name
		profile.steam_id = member_state.steam_id
		profile.peer_id = member_state.peer_id
		profile.is_local = member_state.is_local
		profile.control_type = SeatContext.SeatControlType.LOCAL_HUMAN if member_state.is_local else SeatContext.SeatControlType.REMOTE_HUMAN
		room_state.session_scoreboard.ensure_participant(member_state.participant_id, profile.display_name)

func _apply_member_to_seat(member_state: RoomMemberState) -> void:
	var seat = room_state.get_seat(member_state.seat_index)
	if seat == null:
		return
	seat.occupant_participant_id = member_state.participant_id
	seat.occupant_steam_id = member_state.steam_id
	seat.display_name = member_state.display_name
	seat.is_ready = member_state.is_ready
	seat.is_local = member_state.is_local
	seat.control_type = SeatContext.SeatControlType.LOCAL_HUMAN if member_state.is_local else SeatContext.SeatControlType.REMOTE_HUMAN

func _remove_member(steam_id: int) -> void:
	_log("Removing member steam_id=%d" % steam_id)
	var member_state = room_state.members_by_steam_id.get(steam_id, null)
	if member_state == null:
		return
	var seat = room_state.get_seat(member_state.seat_index)
	if seat != null:
		seat.clear_occupant()
	room_state.session_scoreboard.remove_participant(member_state.participant_id)
	room_state.participants_by_id.erase(member_state.participant_id)
	room_state.members_by_steam_id.erase(steam_id)

func _assign_first_free_seat() -> int:
	for seat in room_state.seat_states:
		if not seat.is_occupied():
			return seat.seat_index
	return -1

func _find_peer_id_for_steam_id(steam_id: int) -> int:
	for peer_id_variant in State.lobby_data.peer_members.keys():
		if int(State.lobby_data.peer_members[peer_id_variant]) == steam_id:
			return int(peer_id_variant)
	return 1 if steam_id == SteamPlatformService.get_local_steam_id() and is_local_host() else 0

func _apply_ready_change_for_steam_id(steam_id: int, is_ready: bool) -> void:
	var member_state = room_state.members_by_steam_id.get(steam_id, null)
	if member_state == null:
		return
	member_state.is_ready = is_ready
	var seat = room_state.get_seat(member_state.seat_index)
	if seat != null:
		seat.is_ready = is_ready
	_set_status("%d / %d ready" % [_count_ready_seats(), room_state.get_seated_member_count()])

func _count_ready_seats() -> int:
	var count := 0
	for seat in room_state.seat_states:
		if seat.is_occupied() and seat.is_ready:
			count += 1
	return count

func _count_unready_seats() -> int:
	var count := 0
	for seat in room_state.seat_states:
		if seat.is_occupied() and not seat.is_ready:
			count += 1
	return count

func _broadcast_room_snapshot() -> void:
	var snapshot: Dictionary = room_state.to_dict()
	if not multiplayer.has_multiplayer_peer():
		_log("Broadcasting snapshot (local only, no peer)")
		_client_apply_room_snapshot(snapshot)
		return
	_log("Broadcasting snapshot via RPC  phase=%s  members=%d" % [room_state.phase_name, room_state.members_by_steam_id.size()])
	_client_apply_room_snapshot.rpc(snapshot)

func _is_steam_id_seated(steam_id: int) -> bool:
	var member = room_state.get_member(steam_id)
	if member == null:
		return false
	return room_state.get_seat(member.seat_index) != null

@rpc("any_peer", "reliable")
func _server_request_ready_state(is_ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	_log("RPC ready_state from peer=%d  is_ready=%s" % [sender_peer, is_ready])
	var steam_id := int(State.lobby_data.peer_members.get(sender_peer, 0))
	if steam_id == 0:
		push_warning("SteamRoomService: RPC from unregistered peer %d — ignored" % sender_peer)
		return
	if not _is_steam_id_seated(steam_id):
		push_warning("SteamRoomService: RPC from unseated player (steam_id %d) — ignored" % steam_id)
		return
	_apply_ready_change_for_steam_id(steam_id, is_ready)
	_broadcast_room_snapshot()

@rpc("authority", "call_local", "reliable")
func _client_apply_room_snapshot(snapshot: Dictionary) -> void:
	_log("Received room snapshot  phase=%s  members=%d" % [
		String(snapshot.get("phase_name", "?")),
		(snapshot.get("members_by_steam_id", {}) as Dictionary).size()
	])
	room_state = RoomStateScript.from_dict(snapshot)
	room_state_changed.emit()
	if not room_state.round_active and room_state.get_phase() != RoomState.RoomPhase.IDLE:
		_set_status("%d / %d ready" % [_count_ready_seats(), room_state.get_seated_member_count()])

@rpc("authority", "call_local", "reliable")
func _client_room_transition(phase_name: String, message: String = "") -> void:
	room_state.phase_name = phase_name
	room_state.round_active = phase_name == "IN_ROUND"
	if not message.is_empty():
		_set_status(message)
	room_transition.emit(phase_name)
	room_state_changed.emit()

func _get_participant_color(participant_id: int) -> Color:
	var colors: Array[Color] = [
		Color(0.2, 0.7, 0.2, 1.0),
		Color(0.7, 0.2, 0.2, 1.0),
		Color(0.2, 0.2, 0.7, 1.0),
		Color(0.7, 0.7, 0.2, 1.0),
	]
	if participant_id >= 0 and participant_id < colors.size():
		return colors[participant_id]
	return Color(0.8, 0.8, 0.8, 1.0)

func _on_steam_status_changed(is_available: bool, reason: String) -> void:
	if not is_available and entry_mode == "host":
		_emit_room_error(reason)

func _on_lobby_created(_lobby_id: int, _lobby_name: String) -> void:
	_refresh_room_state_for_current_role()

func _on_lobby_joined(_lobby_id: int, _lobby_name: String) -> void:
	_refresh_room_state_for_current_role()
	if entry_mode == "join":
		_set_status("Joined lobby. Waiting for room snapshot...")

func _on_lobby_left(_lobby_id: int) -> void:
	_reset_room_state()

func _on_lobby_join_failed(_lobby_id: int, _response: int) -> void:
	_emit_room_error("Failed to join the Steam lobby.")
	AppFlow.open_launcher("Failed to join Steam room.")

func _on_lobby_members_updated(_lobby_id: int, _members: Dictionary) -> void:
	if is_local_host():
		_rebuild_host_room_state()

func _on_lobby_data_updated(_lobby_id: int, _member_id: int) -> void:
	if is_local_host():
		_rebuild_host_room_state()

func _on_join_request_pending(_lobby_id: int, _friend_id: int, _source: String) -> void:
	prepare_join_entry()
	AppFlow.open_steam_room("Joining Steam room...")

func _on_peer_registered(_peer_id: int, _steam_id: int) -> void:
	if is_local_host():
		_rebuild_host_room_state()

func _on_player_left(_peer_id: int, _steam_id: int) -> void:
	if is_local_host():
		_rebuild_host_room_state()

func _on_host_disconnected() -> void:
	_reset_room_state()
	AppFlow.open_launcher("Host disconnected.")

func _on_connection_failed() -> void:
	_reset_room_state()
	AppFlow.open_launcher("Steam connection failed.")
