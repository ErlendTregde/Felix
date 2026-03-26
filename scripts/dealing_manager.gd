extends Node
class_name DealingManager
## Handles dealing cards to players with animation

var table  # Reference to game_table

# Pending private hand — may arrive from host before deal animation finishes
var _pending_private_hand_seat: int = -1
var _pending_private_hand_ids: Array[int] = []

func init(game_table) -> void:
	table = game_table

func deal_cards_to_all_players() -> void:
	"""Deal 4 cards to each player with animation."""
	if table.is_dealing:
		return
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		await _deal_multiplayer_host()
		return
	# Local mode
	table.is_dealing = true
	print("\n=== Dealing Cards to %d Player(s) ===" % table.num_players)
	for card_index in range(4):
		for player_index in range(table.num_players):
			await deal_single_card(player_index, card_index)
			if table.draw_pile_visual:
				table.draw_pile_visual.set_count(table.deck_manager.get_draw_pile_count())
			await get_tree().create_timer(0.15).timeout  # Stagger between cards
	table.is_dealing = false
	print("\nDealing complete! All players have 4 cards.")
	Events.game_state_changed.emit("DEALING_COMPLETE")
	table.viewing_manager.start_initial_viewing_phase()

func _deal_multiplayer_host() -> void:
	"""Host: deal with real card data, then broadcast sequence + private hands to peers."""
	table.is_dealing = true
	print("\n=== [HOST] Dealing Cards to %d Player(s) ===" % table.num_players)
	for card_index in range(4):
		for player_index in range(table.num_players):
			await deal_single_card(player_index, card_index)
			if table.draw_pile_visual:
				table.draw_pile_visual.set_count(table.deck_manager.get_draw_pile_count())
			await get_tree().create_timer(0.15).timeout
	table.is_dealing = false
	print("\n[HOST] Dealing complete!")
	Events.game_state_changed.emit("DEALING_COMPLETE")

	# Collect remaining draw pile IDs after deal
	var remaining_ids: Array[int] = []
	for card in table.deck_manager.draw_pile:
		remaining_ids.append(card.card_id)

	# Trigger client deal animation via sequence broadcast
	SteamRoundService.broadcast_deal_start(remaining_ids)

	# Send each non-host peer their own 4 card IDs
	var rs := SteamRoomService.get_room_state()
	for peer_id in multiplayer.get_peers():
		var steam_id := int(State.lobby_data.peer_members.get(peer_id, 0))
		if steam_id == 0:
			continue
		var member = rs.get_member(steam_id)
		if member == null:
			continue
		var seat_idx: int = member.seat_index
		if seat_idx < 0 or seat_idx >= table.player_grids.size():
			continue
		var grid = table.player_grids[seat_idx]
		var hand_ids: Array[int] = []
		for slot in range(4):
			var card = grid.get_card_at(slot)
			if card and card.card_data:
				hand_ids.append(card.card_data.card_id)
		SteamRoundService.broadcast_private_hand(peer_id, seat_idx, hand_ids)

	table.viewing_manager.start_initial_viewing_phase()

func deal_cards_to_all_players_client() -> void:
	"""Client: animate deal using face-down placeholder cards (real data arrives via private hand)."""
	if table.is_dealing:
		return
	table.is_dealing = true
	print("\n=== [CLIENT] Dealing Cards to %d Player(s) ===" % table.num_players)
	var pile_count := 54
	for card_index in range(4):
		for player_index in range(table.num_players):
			await _deal_single_card_client(player_index, card_index)
			pile_count -= 1
			if table.draw_pile_visual:
				table.draw_pile_visual.set_count(pile_count)
			await get_tree().create_timer(0.15).timeout
	table.is_dealing = false
	print("\n[CLIENT] Dealing complete!")
	Events.game_state_changed.emit("DEALING_COMPLETE")
	table.viewing_manager.start_initial_viewing_phase()
	# Stamp real card data if private hand already arrived during animation
	_apply_buffered_private_hand()

func _deal_single_card_client(player_index: int, position_index: int) -> void:
	"""Create a face-down placeholder card and animate it to the player grid."""
	if player_index >= table.player_grids.size():
		return
	var placeholder := CardData.new()
	placeholder.card_id = -1  # sentinel: identity unknown on this peer
	var card = table.card_scene.instantiate()
	table.add_child(card)
	card.global_position = table.draw_pile_marker.global_position
	card.initialize(placeholder, false)
	card.card_clicked.connect(table._on_card_clicked)
	card.card_right_clicked.connect(table._on_card_right_clicked)
	var grid = table.player_grids[player_index]
	await reparent_card_to_grid(card, grid, position_index)
	table.players[player_index].add_card(card)

func apply_private_hand(seat_index: int, hand_ids: Array[int]) -> void:
	"""Stamp real CardData onto the local seat's grid cards after deal."""
	if seat_index < 0 or seat_index >= table.player_grids.size():
		push_warning("DealingManager: apply_private_hand — invalid seat %d" % seat_index)
		return
	var grid = table.player_grids[seat_index]
	for slot in range(mini(hand_ids.size(), 4)):
		var card = grid.get_card_at(slot)
		if card:
			var card_data = table.deck_manager.find_card_data_by_id(hand_ids[slot])
			if card_data:
				card.initialize(card_data, card.is_face_up)
			else:
				push_warning("DealingManager: could not find card_id %d for private hand" % hand_ids[slot])
	print("[CLIENT] Private hand stamped for seat %d" % seat_index)

func _apply_buffered_private_hand() -> void:
	if _pending_private_hand_seat >= 0:
		apply_private_hand(_pending_private_hand_seat, _pending_private_hand_ids)
		_pending_private_hand_seat = -1
		_pending_private_hand_ids.clear()

func deal_single_card(player_index: int, position_index: int) -> void:
	"""Deal one card to a specific player position"""
	if player_index >= table.player_grids.size():
		return

	var card_data = table.deck_manager.deal_card()
	if not card_data:
		push_warning("DealingManager: deal_card() returned null — deck exhausted")
		return

	# Create card at draw pile position
	var card = table.card_scene.instantiate()
	table.add_child(card)
	card.global_position = table.draw_pile_marker.global_position
	card.initialize(card_data, false)

	# Connect signals
	card.card_clicked.connect(table._on_card_clicked)
	card.card_right_clicked.connect(table._on_card_right_clicked)

	# Add to player's grid (will animate there)
	var grid = table.player_grids[player_index]
	await reparent_card_to_grid(card, grid, position_index)

	# Update player data
	table.players[player_index].add_card(card)

	# Update draw pile visual
	if table.draw_pile_visual:
		table.draw_pile_visual.set_count(table.deck_manager.get_draw_pile_count())

	Events.card_dealt.emit(card_data, player_index, position_index)


func reparent_card_to_grid(card: Card3D, grid: PlayerGrid, card_position: int) -> void:
	"""Move card from table to player grid with animation"""
	var target_pos = grid.get_position_for_card(card_position)

	# Animate to position
	card.move_to(target_pos, 0.4, false)

	# Wait for animation, then reparent
	await get_tree().create_timer(0.4).timeout

	# Reparent to grid
	if card.get_parent():
		card.get_parent().remove_child(card)

	# Add to grid's cards array and as child
	grid.cards[card_position] = card
	grid.add_child(card)
	card.owner_player = grid.get_meta("owner_player") if grid.has_meta("owner_player") else null
	card.owner_seat_id = grid.owner_seat_id
	card.position = grid.card_positions[card_position]
	card.base_position = card.global_position
