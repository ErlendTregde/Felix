extends Node

## SteamMovementService — Handles sit/stand RPCs for player movement.
## Follows the same authority pattern as SteamRoundService.

signal player_stood(seat_index: int)
signal player_sat(seat_index: int, target_seat: int)

var _standing_seats: Dictionary = {}  # seat_index -> bool

func _log(msg: String) -> void:
	print("[SteamMovementService] %s" % msg)

func reset() -> void:
	_standing_seats.clear()

func is_seat_standing(seat_index: int) -> bool:
	return _standing_seats.get(seat_index, false)

# ---------------------------------------------------------------------------
# RPC helpers (same pattern as SteamRoundService)
# ---------------------------------------------------------------------------

func _get_seat_index_for_sender() -> int:
	var sender_peer := multiplayer.get_remote_sender_id()
	var steam_id := int(State.lobby_data.peer_members.get(sender_peer, 0))
	if steam_id == 0:
		push_warning("SteamMovementService: RPC from unregistered peer %d — ignored" % sender_peer)
		return -1
	var member = SteamRoomService.room_state.get_member(steam_id)
	if member == null:
		push_warning("SteamMovementService: No room member for steam_id %d (peer %d) — ignored" % [steam_id, sender_peer])
		return -1
	return member.seat_index

# ---------------------------------------------------------------------------
# Client -> Host RPCs
# ---------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func client_request_stand() -> void:
	if not multiplayer.is_server():
		return
	var seat_idx := _get_seat_index_for_sender()
	if seat_idx < 0:
		return
	if _standing_seats.get(seat_idx, false):
		return  # Already standing
	_log("Player at seat %d requests to stand" % seat_idx)
	_standing_seats[seat_idx] = true
	# Broadcast to all clients
	_client_player_stood.rpc(seat_idx)
	# Apply locally on host
	_client_player_stood(seat_idx)

@rpc("any_peer", "reliable")
func client_request_sit(target_seat: int) -> void:
	if not multiplayer.is_server():
		return
	var seat_idx := _get_seat_index_for_sender()
	if seat_idx < 0:
		return
	if not _standing_seats.get(seat_idx, false):
		return  # Already seated
	# Players can only sit in their own seat
	if target_seat != seat_idx:
		push_warning("SteamMovementService: Player %d tried to sit in seat %d (not their seat)" % [seat_idx, target_seat])
		return
	_log("Player at seat %d requests to sit at seat %d" % [seat_idx, target_seat])
	_standing_seats[seat_idx] = false
	# Broadcast to all clients
	_client_player_sat.rpc(seat_idx, target_seat)
	# Apply locally on host
	_client_player_sat(seat_idx, target_seat)

# ---------------------------------------------------------------------------
# Host -> Client RPCs
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _client_player_stood(seat_index: int) -> void:
	_standing_seats[seat_index] = true
	_log("Player at seat %d stood up" % seat_index)
	player_stood.emit(seat_index)

@rpc("authority", "call_remote", "reliable")
func _client_player_sat(seat_index: int, target_seat: int) -> void:
	_standing_seats[seat_index] = false
	_log("Player at seat %d sat down at seat %d" % [seat_index, target_seat])
	player_sat.emit(seat_index, target_seat)

@rpc("authority", "call_remote", "reliable")
func _client_force_sit_all() -> void:
	_log("Force-sitting all players")
	for seat_idx in _standing_seats.keys():
		if _standing_seats[seat_idx]:
			_standing_seats[seat_idx] = false
			player_sat.emit(seat_idx, seat_idx)

# ---------------------------------------------------------------------------
# Host-only: force everyone seated (e.g. on round end)
# ---------------------------------------------------------------------------

func force_sit_all() -> void:
	if not multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		return
	_log("Host forcing all players seated")
	for seat_idx in _standing_seats.keys():
		_standing_seats[seat_idx] = false
	_client_force_sit_all.rpc()
	_client_force_sit_all()

# ---------------------------------------------------------------------------
# Local mode (no multiplayer peer)
# ---------------------------------------------------------------------------

func local_stand(seat_index: int) -> void:
	_standing_seats[seat_index] = true
	player_stood.emit(seat_index)

func local_sit(seat_index: int) -> void:
	_standing_seats[seat_index] = false
	player_sat.emit(seat_index, seat_index)
