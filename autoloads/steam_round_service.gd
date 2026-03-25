extends Node

## SteamRoundService — Phase 3 gameplay RPC hub.
## All multiplayer gameplay RPCs live here so they survive scene transitions.
## FelixRoundController calls bind_round_controller() on init and
## release_round_controller() on _exit_tree().

var _round_controller: FelixRoundController = null
var _pending_snapshots: Array[Dictionary] = []

func _log(msg: String) -> void:
	print("[SteamRoundService] %s" % msg)

# ---------------------------------------------------------------------------
# Controller lifecycle
# ---------------------------------------------------------------------------

func bind_round_controller(rc: FelixRoundController) -> void:
	_round_controller = rc
	_log("Round controller bound")
	_drain_pending_snapshots()

func release_round_controller() -> void:
	_round_controller = null
	_log("Round controller released")

func _drain_pending_snapshots() -> void:
	if _pending_snapshots.is_empty():
		return
	_log("Draining %d pending round snapshot(s)" % _pending_snapshots.size())
	for snapshot in _pending_snapshots:
		_apply_round_snapshot(snapshot)
	_pending_snapshots.clear()

# ---------------------------------------------------------------------------
# RPC helpers
# ---------------------------------------------------------------------------

## Maps the RPC sender's peer_id → steam_id → seat_index via lobby data + room state.
## Returns -1 and warns if the sender is unknown or unseated.
func _get_seat_index_for_sender() -> int:
	var sender_peer := multiplayer.get_remote_sender_id()
	var steam_id := int(State.lobby_data.peer_members.get(sender_peer, 0))
	if steam_id == 0:
		push_warning("SteamRoundService: RPC from unregistered peer %d — ignored" % sender_peer)
		return -1
	var member = SteamRoomService.room_state.get_member(steam_id)
	if member == null:
		push_warning("SteamRoundService: No room member for steam_id %d (peer %d) — ignored" % [steam_id, sender_peer])
		return -1
	return member.seat_index

## Sends each connected peer their own private round snapshot, then applies the
## host's own snapshot locally.  Must only be called on the host.
func _broadcast_round_snapshot_to_all() -> void:
	if _round_controller == null:
		push_warning("SteamRoundService: _broadcast_round_snapshot_to_all called with no round controller")
		return
	if not multiplayer.has_multiplayer_peer():
		return
	for peer_id in multiplayer.get_peers():
		var steam_id := int(State.lobby_data.peer_members.get(peer_id, 0))
		if steam_id == 0:
			continue
		var member = SteamRoomService.room_state.get_member(steam_id)
		var seat_index: int = member.seat_index if member != null else -1
		var snapshot := _round_controller.get_private_snapshot_for(seat_index)
		_client_apply_round_snapshot.rpc_id(peer_id, snapshot)
	# Apply host's own snapshot locally (host does not RPC to itself)
	var local_seat := _round_controller.get_local_seat_index()
	var local_snapshot := _round_controller.get_private_snapshot_for(local_seat)
	_apply_round_snapshot(local_snapshot)

# ---------------------------------------------------------------------------
# Client-side snapshot application
# ---------------------------------------------------------------------------

func _apply_round_snapshot(snapshot: Dictionary) -> void:
	if _round_controller == null:
		_log("Buffering round snapshot (round controller not yet bound)")
		_pending_snapshots.append(snapshot)
		return
	# TODO Phase 3 Step 5+: apply snapshot fields to local game state
	_log("Round snapshot received (phase=%s)" % String(snapshot.get("phase_name", "?")))

@rpc("authority", "call_remote", "reliable")
func _client_apply_round_snapshot(snapshot: Dictionary) -> void:
	_apply_round_snapshot(snapshot)
