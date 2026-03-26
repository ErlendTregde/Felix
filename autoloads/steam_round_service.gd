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
	# ROUND_END is handled by broadcast_round_end_to_all (separate RPC with card data)
	if phase == "ROUND_END":
		return
	# Sync KNOCKED state when a knock is broadcast via snapshot
	if phase == "KNOCKED" and GameManager.current_state != GameManager.GameState.KNOCKED:
		GameManager.knocker_id = int(snapshot.get("knocker_seat_index", -1))
		GameManager.change_state(GameManager.GameState.KNOCKED)
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
	# Clean up any lingering ability state when the turn changes
	if tbl.ability_manager.is_executing_ability:
		tbl.ability_manager.reset_state()
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
	var did_draw := await _round_controller.request_draw(seat_idx)
	if not did_draw:
		push_warning("SteamRoundService: draw request declined by round controller for seat %d" % seat_idx)
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
	var did_swap := await _round_controller.request_swap(seat_idx, target_card)
	if not did_swap:
		push_warning("SteamRoundService: swap request declined by round controller for seat %d" % seat_idx)

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
	var did_discard := await _round_controller.request_discard_drawn(seat_idx)
	if not did_discard:
		push_warning("SteamRoundService: discard request declined by round controller for seat %d" % seat_idx)

# ---------------------------------------------------------------------------
# Step 6: Ability RPCs
# ---------------------------------------------------------------------------

## Find the acting peer and tell them an ability is starting.
func notify_client_ability_start(actor_seat_idx: int, ability_type_int: int) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var rs := SteamRoomService.get_room_state()
	for peer_id in multiplayer.get_peers():
		var steam_id := int(State.lobby_data.peer_members.get(peer_id, 0))
		if steam_id == 0:
			continue
		var member = rs.get_member(steam_id)
		if member != null and member.seat_index == actor_seat_idx:
			_client_begin_ability.rpc_id(peer_id, ability_type_int)
			return

@rpc("authority", "call_remote", "reliable")
func _client_begin_ability(ability_type_int: int) -> void:
	if _round_controller == null:
		return
	var tbl = _round_controller.table
	_log("Ability started on client: %s" % CardData.AbilityType.keys()[ability_type_int])
	match ability_type_int:
		CardData.AbilityType.LOOK_OWN:
			tbl.ability_manager.execute_ability_look_own()
		CardData.AbilityType.LOOK_OPPONENT:
			tbl.ability_manager.execute_ability_look_opponent()
		CardData.AbilityType.BLIND_SWAP:
			tbl.ability_manager.execute_ability_blind_swap()
		CardData.AbilityType.LOOK_AND_SWAP:
			tbl.ability_manager.execute_ability_look_and_swap()

@rpc("any_peer", "reliable")
func client_request_ability_select(target_seat: int, slot: int, is_penalty: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	var actor_seat := _get_seat_index_for_sender()
	if actor_seat < 0 or _round_controller == null:
		return
	if GameManager.current_player_index != actor_seat:
		return
	var tbl = _round_controller.table
	# Ignore if already waiting for SPACE confirm (prevents double-reveal on rapid clicks)
	if tbl.ability_manager.awaiting_ability_confirmation:
		return
	var card: Card3D = null
	if is_penalty:
		if target_seat >= 0 and target_seat < tbl.player_grids.size():
			var grid = tbl.player_grids[target_seat]
			if slot >= 0 and slot < grid.penalty_cards.size():
				card = grid.penalty_cards[slot]
	else:
		if target_seat >= 0 and target_seat < tbl.player_grids.size():
			card = tbl.player_grids[target_seat].get_card_at(slot)
	if card == null:
		push_warning("SteamRoundService: ability_select — no card at seat=%d slot=%d penalty=%s" % [target_seat, slot, is_penalty])
		return
	var card_id: int = card.card_data.card_id
	var ability: int = tbl.ability_manager.current_ability as int
	await _round_controller.request_ability_select(actor_seat, card)
	# After selection: reveal card privately for look abilities, or signal confirm-ready for swap abilities
	match ability:
		CardData.AbilityType.LOOK_OWN, CardData.AbilityType.LOOK_OPPONENT:
			if tbl.ability_manager.awaiting_ability_confirmation:
				_client_ability_reveal.rpc_id(sender_peer, target_seat, slot, is_penalty, card_id)
		CardData.AbilityType.BLIND_SWAP, CardData.AbilityType.LOOK_AND_SWAP:
			if tbl.ability_manager.awaiting_ability_confirmation:
				_client_ability_await_confirm.rpc_id(sender_peer)

@rpc("authority", "call_remote", "reliable")
func _client_ability_reveal(target_seat: int, slot: int, is_penalty: bool, card_id: int) -> void:
	if _round_controller == null:
		return
	var tbl = _round_controller.table
	var card: Card3D = null
	if is_penalty:
		if target_seat >= 0 and target_seat < tbl.player_grids.size():
			var grid = tbl.player_grids[target_seat]
			if slot >= 0 and slot < grid.penalty_cards.size():
				card = grid.penalty_cards[slot]
	else:
		if target_seat >= 0 and target_seat < tbl.player_grids.size():
			card = tbl.player_grids[target_seat].get_card_at(slot)
	if card == null:
		push_warning("SteamRoundService: _client_ability_reveal — no card at seat=%d slot=%d" % [target_seat, slot])
		return
	var card_data = tbl.deck_manager.find_card_data_by_id(card_id)
	if card_data:
		card.initialize(card_data, card.is_face_up)
	tbl.ability_manager.ability_target_card = card
	var view_pos: Vector3 = tbl.view_helper.get_card_view_position()
	var view_rot: float = tbl.view_helper.get_card_view_rotation()
	card.global_rotation = Vector3(0, view_rot, 0)
	card.move_to(view_pos, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	card.flip(true, 0.35)
	await get_tree().create_timer(0.4).timeout
	tbl.view_helper.tilt_card_towards_viewer(card, false)
	await get_tree().create_timer(0.25).timeout
	tbl.ability_manager.awaiting_ability_confirmation = true
	tbl.turn_ui.update_action("Press SPACE to confirm")
	_log("Revealed card to client: %s" % (card_data.get_short_name() if card_data else "unknown"))

@rpc("authority", "call_remote", "reliable")
func _client_ability_await_confirm() -> void:
	if _round_controller == null:
		return
	_round_controller.table.ability_manager.awaiting_ability_confirmation = true
	_round_controller.table.turn_ui.update_action("Press SPACE to confirm")

@rpc("any_peer", "reliable")
func client_request_ability_confirm() -> void:
	if not multiplayer.is_server():
		return
	var actor_seat := _get_seat_index_for_sender()
	if actor_seat < 0 or _round_controller == null:
		return
	if GameManager.current_player_index != actor_seat:
		return
	await _round_controller.request_ability_confirm(actor_seat)

## Send both Queen-selected card IDs to the acting remote client for side-by-side display.
func notify_client_queen_display(actor_seat_idx: int, c1_seat: int, c1_slot: int, c1_pen: int, c1_id: int, c2_seat: int, c2_slot: int, c2_pen: int, c2_id: int) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var rs := SteamRoomService.get_room_state()
	for peer_id in multiplayer.get_peers():
		var steam_id := int(State.lobby_data.peer_members.get(peer_id, 0))
		if steam_id == 0:
			continue
		var member = rs.get_member(steam_id)
		if member != null and member.seat_index == actor_seat_idx:
			_client_queen_display.rpc_id(peer_id, c1_seat, c1_slot, c1_pen, c1_id, c2_seat, c2_slot, c2_pen, c2_id)
			return

@rpc("authority", "call_remote", "reliable")
func _client_queen_display(c1_seat: int, c1_slot: int, c1_pen: int, c1_id: int, c2_seat: int, c2_slot: int, c2_pen: int, c2_id: int) -> void:
	if _round_controller == null:
		return
	var tbl = _round_controller.table
	var ab = tbl.ability_manager
	var card1: Card3D = null
	var card2: Card3D = null
	if c1_pen >= 0 and c1_seat < tbl.player_grids.size():
		card1 = tbl.player_grids[c1_seat].penalty_cards[c1_pen] if c1_pen < tbl.player_grids[c1_seat].penalty_cards.size() else null
	elif c1_slot >= 0 and c1_seat < tbl.player_grids.size():
		card1 = tbl.player_grids[c1_seat].get_card_at(c1_slot)
	if c2_pen >= 0 and c2_seat < tbl.player_grids.size():
		card2 = tbl.player_grids[c2_seat].penalty_cards[c2_pen] if c2_pen < tbl.player_grids[c2_seat].penalty_cards.size() else null
	elif c2_slot >= 0 and c2_seat < tbl.player_grids.size():
		card2 = tbl.player_grids[c2_seat].get_card_at(c2_slot)
	if card1 == null or card2 == null:
		push_warning("SteamRoundService: _client_queen_display — could not find cards")
		return
	var cd1 = tbl.deck_manager.find_card_data_by_id(c1_id)
	var cd2 = tbl.deck_manager.find_card_data_by_id(c2_id)
	if cd1:
		card1.initialize(cd1, card1.is_face_up)
	if cd2:
		card2.initialize(cd2, card2.is_face_up)
	ab.look_and_swap_first_card = card1
	ab.look_and_swap_second_card = card2
	await ab.display_cards_for_choice()

@rpc("any_peer", "reliable")
func client_request_queen_choice(do_swap: bool) -> void:
	if not multiplayer.is_server():
		return
	var actor_seat := _get_seat_index_for_sender()
	if actor_seat < 0 or _round_controller == null:
		return
	if GameManager.current_player_index != actor_seat:
		return
	var tbl = _round_controller.table
	if do_swap:
		await tbl.ability_manager._on_swap_chosen()
	else:
		await tbl.ability_manager._on_no_swap_chosen()

# ---------------------------------------------------------------------------
# Step 7: Matching RPCs
# ---------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func client_request_match(target_seat: int, slot: int, is_penalty: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer := multiplayer.get_remote_sender_id()
	var actor_seat := _get_seat_index_for_sender()
	if actor_seat < 0 or _round_controller == null:
		return
	var tbl = _round_controller.table
	# Fast-reject if match window already locked on host
	if tbl.match_manager.is_processing_match or tbl.match_manager.match_claimed:
		return
	var card: Card3D = null
	if is_penalty:
		if target_seat >= 0 and target_seat < tbl.player_grids.size():
			var grid = tbl.player_grids[target_seat]
			if slot >= 0 and slot < grid.penalty_cards.size():
				card = grid.penalty_cards[slot]
	else:
		if target_seat >= 0 and target_seat < tbl.player_grids.size():
			card = tbl.player_grids[target_seat].get_card_at(slot)
	if card == null:
		return
	# Capture match info before await (card may be freed)
	var top_discard = tbl.deck_manager.peek_top_discard()
	var did_match: bool = top_discard != null and card.card_data.rank == top_discard.rank
	var is_own_card: bool = (target_seat == actor_seat)
	await _round_controller.request_match(actor_seat, card)
	_broadcast_round_snapshot_to_all()
	# Notify all clients about the card that was removed (successful match)
	if did_match:
		_client_match_card_removed.rpc(target_seat, slot, is_penalty)
	# If opponent match, actor must give a card
	if tbl.match_manager.is_choosing_give_card and tbl.match_manager.give_card_actor_seat_idx == actor_seat:
		_client_begin_give_card.rpc_id(sender_peer, tbl.match_manager.give_card_target_player_idx)

## Removes a matched card from all clients' grids (called after a successful match on host).
@rpc("authority", "call_remote", "reliable")
func _client_match_card_removed(card_seat: int, card_slot: int, card_is_penalty: bool) -> void:
	if _round_controller == null:
		return
	var tbl = _round_controller.table
	if card_seat < 0 or card_seat >= tbl.player_grids.size():
		return
	var grid = tbl.player_grids[card_seat]
	var card: Card3D = null
	if card_is_penalty:
		if card_slot >= 0 and card_slot < grid.penalty_cards.size():
			card = grid.penalty_cards[card_slot]
			grid.penalty_cards[card_slot] = null
	else:
		card = grid.get_card_at(card_slot)
		if card:
			grid.cards[card_slot] = null
	if card and is_instance_valid(card):
		card.queue_free()

@rpc("authority", "call_remote", "reliable")
func _client_begin_give_card(target_seat: int) -> void:
	if _round_controller == null:
		return
	var tbl = _round_controller.table
	var local_seat := _round_controller.get_local_seat_index()
	tbl.match_manager.is_choosing_give_card = true
	tbl.match_manager.give_card_target_player_idx = target_seat
	tbl.match_manager.give_card_actor_seat_idx = local_seat
	tbl.match_manager._start_give_card_selection(local_seat, target_seat)
	_log("Give-card mode started — client seat %d must give to seat %d" % [local_seat, target_seat])

@rpc("any_peer", "reliable")
func client_request_give_card(slot: int, is_penalty: bool) -> void:
	if not multiplayer.is_server():
		return
	var actor_seat := _get_seat_index_for_sender()
	if actor_seat < 0 or _round_controller == null:
		return
	var tbl = _round_controller.table
	if not tbl.match_manager.is_choosing_give_card:
		return
	if tbl.match_manager.give_card_actor_seat_idx != actor_seat:
		return
	var card: Card3D = null
	if is_penalty:
		if actor_seat < tbl.player_grids.size():
			var grid = tbl.player_grids[actor_seat]
			if slot >= 0 and slot < grid.penalty_cards.size():
				card = grid.penalty_cards[slot]
	else:
		if actor_seat < tbl.player_grids.size():
			card = tbl.player_grids[actor_seat].get_card_at(slot)
	if card == null:
		push_warning("SteamRoundService: give_card — no card at seat=%d slot=%d penalty=%s" % [actor_seat, slot, is_penalty])
		return
	var target_seat: int = tbl.match_manager.give_card_target_player_idx
	await _round_controller.request_give_card(actor_seat, card)
	_broadcast_round_snapshot_to_all()
	# Notify all clients: given card removed from actor, added as penalty to target
	_client_give_card_done.rpc(actor_seat, slot, is_penalty, target_seat)

## Updates all clients after give-card: removes card from giver's grid, adds as penalty to recipient.
@rpc("authority", "call_remote", "reliable")
func _client_give_card_done(actor_seat: int, actor_slot: int, actor_is_penalty: bool, target_seat: int) -> void:
	if _round_controller == null:
		return
	var tbl = _round_controller.table
	# Remove from actor's grid
	if actor_seat >= 0 and actor_seat < tbl.player_grids.size():
		var actor_grid = tbl.player_grids[actor_seat]
		var card: Card3D = null
		if actor_is_penalty:
			if actor_slot >= 0 and actor_slot < actor_grid.penalty_cards.size():
				card = actor_grid.penalty_cards[actor_slot]
				actor_grid.penalty_cards[actor_slot] = null
		else:
			card = actor_grid.get_card_at(actor_slot)
			if card:
				actor_grid.cards[actor_slot] = null
		if card and is_instance_valid(card):
			# Re-parent and place in target's penalty slot
			if card.get_parent():
				card.get_parent().remove_child(card)
			var target_grid = tbl.player_grids[target_seat]
			card.owner_seat_id = target_seat
			target_grid.add_penalty_card(card, false)
	tbl.match_manager.is_choosing_give_card = false
	tbl.match_manager.give_card_actor_seat_idx = -1
	tbl.match_manager.give_card_target_player_idx = -1

# ---------------------------------------------------------------------------
# Step 8: Knock RPCs
# ---------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func client_request_knock() -> void:
	if not multiplayer.is_server():
		return
	var actor_seat := _get_seat_index_for_sender()
	if actor_seat < 0 or _round_controller == null:
		return
	if GameManager.current_player_index != actor_seat:
		push_warning("SteamRoundService: knock from seat %d but it's seat %d's turn" % [actor_seat, GameManager.current_player_index])
		return
	await _round_controller.request_knock(actor_seat)
	# Snapshot broadcast happens inside complete_turn → but also broadcast here for the KNOCKED state change
	_broadcast_round_snapshot_to_all()

# ---------------------------------------------------------------------------
# Step 9: Round End RPCs
# ---------------------------------------------------------------------------

## Host collects all card IDs from all grids and sends to each peer, then triggers round end.
func broadcast_round_end_to_all(tbl) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	# Build: { seat_id: { slot: card_id, ... }, "penalty": { seat_id: { slot: card_id } } }
	var card_ids: Dictionary = {}
	var penalty_ids: Dictionary = {}
	for seat_id in range(tbl.player_grids.size()):
		var grid = tbl.player_grids[seat_id]
		var seat_map: Dictionary = {}
		for i in range(4):
			var c = grid.get_card_at(i)
			if c and c.card_data:
				seat_map[i] = c.card_data.card_id
		card_ids[seat_id] = seat_map
		var pen_map: Dictionary = {}
		for i in range(grid.penalty_cards.size()):
			var pc = grid.penalty_cards[i]
			if pc and pc.card_data:
				pen_map[i] = pc.card_data.card_id
		penalty_ids[seat_id] = pen_map
	_client_round_end_begin.rpc(card_ids, penalty_ids)

@rpc("authority", "call_remote", "reliable")
func _client_round_end_begin(card_ids: Dictionary, penalty_ids: Dictionary) -> void:
	if _round_controller == null:
		return
	var tbl = _round_controller.table
	# Stamp all card data onto client's Card3D objects
	for seat_id in card_ids.keys():
		if seat_id >= tbl.player_grids.size():
			continue
		var grid = tbl.player_grids[seat_id]
		var seat_map: Dictionary = card_ids[seat_id]
		for slot_str in seat_map.keys():
			var slot: int = int(slot_str)
			var card_id: int = int(seat_map[slot_str])
			var card = grid.get_card_at(slot)
			if card:
				var cd = tbl.deck_manager.find_card_data_by_id(card_id)
				if cd:
					card.initialize(cd, card.is_face_up)
	for seat_id in penalty_ids.keys():
		if seat_id >= tbl.player_grids.size():
			continue
		var grid = tbl.player_grids[seat_id]
		var pen_map: Dictionary = penalty_ids[seat_id]
		for slot_str in pen_map.keys():
			var slot: int = int(slot_str)
			var card_id: int = int(pen_map[slot_str])
			if slot < grid.penalty_cards.size():
				var card = grid.penalty_cards[slot]
				if card:
					var cd = tbl.deck_manager.find_card_data_by_id(card_id)
					if cd:
						card.initialize(cd, card.is_face_up)
	_log("Round end: stamped card data on client — triggering round end")
	# Now trigger round end locally (card data is correct)
	GameManager.change_state(GameManager.GameState.ROUND_END)
