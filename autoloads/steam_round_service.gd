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

	var phase: String = snapshot.get("phase_name", "")
	var turn_seat: int = int(snapshot.get("current_turn_seat_index", GameManager.current_player_index))
	var draw_count: int = int(snapshot.get("draw_pile_count", -1))
	var discard_count: int = int(snapshot.get("discard_pile_count", -1))
	var top_discard: String = snapshot.get("top_discard_name", "")
	_log("Snapshot: phase=%s turn=%d draw=%d discard=%d" % [phase, turn_seat, draw_count, discard_count])

	# Update pile visuals on all peers
	var tbl = _round_controller.table
	if draw_count >= 0 and tbl.draw_pile_visual:
		tbl.draw_pile_visual.set_count(draw_count)
	if discard_count >= 0 and tbl.discard_pile_visual:
		tbl.discard_pile_visual.set_count(discard_count)
		if top_discard != "" and tbl.discard_label_3d:
			tbl.discard_label_3d.text = top_discard

	# Client-only: advance turn state when turn index changes
	if multiplayer.is_server():
		return
	if phase not in ["PLAYING", "KNOCKED"]:
		return
	var prev_turn: int = GameManager.current_player_index
	if turn_seat == prev_turn:
		return
	GameManager.current_player_index = turn_seat
	# Clean up any drawn card still visible from previous turn
	if tbl.drawn_card and is_instance_valid(tbl.drawn_card):
		tbl.drawn_card.queue_free()
	tbl.drawn_card = null
	tbl.is_drawing = false
	tbl.is_player_turn = false
	if tbl.discard_pile_visual:
		tbl.discard_pile_visual.set_interactive(false)
	_log("Turn advanced to seat %d — starting next turn on client" % turn_seat)
	tbl.turn_manager.start_next_turn()

@rpc("authority", "call_remote", "reliable")
func _client_apply_round_snapshot(snapshot: Dictionary) -> void:
	_apply_round_snapshot(snapshot)

# ---------------------------------------------------------------------------
# Step 3: Deal sync
# ---------------------------------------------------------------------------

func broadcast_deal_start(remaining_ids: Array[int]) -> void:
	_client_start_deal.rpc(remaining_ids)

func broadcast_private_hand(peer_id: int, seat_index: int, hand_ids: Array[int]) -> void:
	_client_receive_private_hand.rpc_id(peer_id, seat_index, hand_ids)

@rpc("authority", "call_local", "reliable")
func _client_start_deal(remaining_ids: Array[int]) -> void:
	if _round_controller == null:
		push_warning("SteamRoundService: _client_start_deal — no round controller")
		return
	# Apply remaining draw pile sequence on all peers (host updates its own pile too)
	_round_controller.table.deck_manager.apply_sequence(remaining_ids)
	# Only clients start the deal animation — host already dealt
	if not multiplayer.is_server():
		_round_controller.table.dealing_manager.deal_cards_to_all_players_client()

# ---------------------------------------------------------------------------
# Step 4: Viewing phase sync
# ---------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func client_request_viewing_ready() -> void:
	if not multiplayer.is_server():
		return
	var seat_idx := _get_seat_index_for_sender()
	if seat_idx < 0:
		return
	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		push_warning("SteamRoundService: viewing_ready from seat %d but state is not INITIAL_VIEWING" % seat_idx)
		return
	_round_controller.request_ready_state(seat_idx)
	var ready_count := GameManager.get_ready_count()
	_log("Viewing ready from seat %d — %d/%d ready" % [seat_idx, ready_count, _round_controller.table.num_players])
	if GameManager.are_all_players_ready():
		await get_tree().create_timer(0.5).timeout
		_client_begin_playing_phase.rpc()

@rpc("authority", "call_local", "reliable")
func _client_begin_playing_phase() -> void:
	if _round_controller == null:
		return
	_log("Begin playing phase on all peers")
	_round_controller.table.viewing_manager.end_viewing_phase()

@rpc("authority", "call_remote", "reliable")
func _client_receive_private_hand(seat_index: int, hand_ids: Array[int]) -> void:
	if _round_controller == null:
		push_warning("SteamRoundService: _client_receive_private_hand — no round controller")
		return
	var dm = _round_controller.table.dealing_manager
	if _round_controller.table.is_dealing:
		# Deal animation still running — buffer for after animation completes
		dm._pending_private_hand_seat = seat_index
		dm._pending_private_hand_ids = hand_ids
	else:
		dm.apply_private_hand(seat_index, hand_ids)

# ---------------------------------------------------------------------------
# Step 5: Turn loop — client-to-host action RPCs
# ---------------------------------------------------------------------------

## Called by host after draw animation completes; finds acting peer and sends drawn card privately.
func notify_client_draw(actor_seat_idx: int, card_id: int) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	# Find the peer_id for this seat
	var rs := SteamRoomService.get_room_state()
	for peer_id in multiplayer.get_peers():
		var steam_id := int(State.lobby_data.peer_members.get(peer_id, 0))
		if steam_id == 0:
			continue
		var member = rs.get_member(steam_id)
		if member != null and member.seat_index == actor_seat_idx:
			_client_set_drawn_card.rpc_id(peer_id, actor_seat_idx, card_id)
			return

@rpc("authority", "call_remote", "reliable")
func _client_set_drawn_card(seat_idx: int, card_id: int) -> void:
	## Client receives their private drawn card identity and animates it face-up.
	if _round_controller == null:
		return
	var tbl = _round_controller.table
	var card_data = tbl.deck_manager.find_card_data_by_id(card_id)
	if card_data == null:
		push_warning("SteamRoundService: _client_set_drawn_card — card_id %d not found" % card_id)
		return
	# Create the card node at the draw pile
	var card := tbl.card_scene.instantiate() as Card3D
	tbl.add_child(card)
	var top_offset := Vector3(0, tbl.draw_pile_visual.card_count * 0.01 if tbl.draw_pile_visual else 0.0, 0)
	card.global_position = tbl.draw_pile_marker.global_position + top_offset
	card.initialize(card_data, false)
	card.is_interactable = false
	card.card_clicked.connect(tbl._on_card_clicked)
	card.card_right_clicked.connect(tbl._on_card_right_clicked)
	# Animate to view position (same as host-side draw_card_from_pile)
	var view_pos: Vector3 = tbl.view_helper.get_card_view_position()
	var view_rot: float = tbl.view_helper.get_card_view_rotation()
	card.global_rotation = Vector3(0, view_rot, 0)
	card.move_to(view_pos, 0.6, false)
	await get_tree().create_timer(0.65).timeout
	card.flip(true, 0.35)
	await get_tree().create_timer(0.4).timeout
	tbl.view_helper.tilt_card_towards_viewer(card, false)
	await get_tree().create_timer(0.25).timeout
	# Register as drawn card and enable interactions
	tbl.drawn_card = card
	tbl.is_drawing = false
	if tbl.draw_pile_visual:
		tbl.draw_pile_visual.set_interactive(false)
	if tbl.discard_pile_visual:
		tbl.discard_pile_visual.set_interactive(true)
	var grid = tbl.player_grids[seat_idx]
	for i in range(4):
		var c = grid.get_card_at(i)
		if c:
			c.is_interactable = true
	for pc in grid.penalty_cards:
		pc.is_interactable = true
	tbl.turn_ui.update_action("Click your card to swap, OR click discard pile to use ability")
	tbl.turn_ui.show_card_info(card_data)
	_log("Drawn card set for client seat %d: %s" % [seat_idx, card_data.get_short_name()])

@rpc("any_peer", "reliable")
func client_request_draw() -> void:
	if not multiplayer.is_server():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	var seat_idx := _get_seat_index_for_sender()
	if seat_idx < 0 or _round_controller == null:
		return
	if GameManager.current_player_index != seat_idx:
		push_warning("SteamRoundService: draw from seat %d but it's seat %d's turn" % [seat_idx, GameManager.current_player_index])
		return
	if _round_controller.table.drawn_card or _round_controller.table.is_drawing:
		return
	_do_client_draw(seat_idx, sender_peer)

func _do_client_draw(seat_idx: int, _sender_peer: int) -> void:
	await _round_controller.request_draw(seat_idx)
	# notify_client_draw is called inside request_draw after the animation — nothing more to do

@rpc("any_peer", "reliable")
func client_request_swap(slot: int, is_penalty: bool) -> void:
	if not multiplayer.is_server():
		return
	var seat_idx := _get_seat_index_for_sender()
	if seat_idx < 0 or _round_controller == null:
		return
	if GameManager.current_player_index != seat_idx:
		return
	if _round_controller.table.drawn_card == null:
		return
	var grid = _round_controller.table.player_grids[seat_idx]
	var target_card: Card3D = null
	if is_penalty:
		if slot >= 0 and slot < grid.penalty_cards.size():
			target_card = grid.penalty_cards[slot]
	else:
		target_card = grid.get_card_at(slot)
	if target_card == null:
		push_warning("SteamRoundService: client_request_swap — no card at slot %d (penalty=%s) for seat %d" % [slot, is_penalty, seat_idx])
		return
	_do_client_swap(seat_idx, target_card)

func _do_client_swap(seat_idx: int, target_card: Card3D) -> void:
	await _round_controller.request_swap(seat_idx, target_card)

@rpc("any_peer", "reliable")
func client_request_discard_drawn() -> void:
	if not multiplayer.is_server():
		return
	var seat_idx := _get_seat_index_for_sender()
	if seat_idx < 0 or _round_controller == null:
		return
	if GameManager.current_player_index != seat_idx:
		return
	if _round_controller.table.drawn_card == null:
		return
	_do_client_discard(seat_idx)

func _do_client_discard(seat_idx: int) -> void:
	await _round_controller.request_discard_drawn(seat_idx)
