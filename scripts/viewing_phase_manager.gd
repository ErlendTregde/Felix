extends Node
class_name ViewingPhaseManager
## Manages the initial card viewing phase where players memorize their bottom 2 cards

var table  # Reference to game_table

func init(game_table) -> void:
	table = game_table

func get_bottom_card_positions(player_index: int) -> Array[int]:
	"""Get the bottom 2 card positions based on proximity to player's seating location.
	
	Production-ready approach: Players sit away from table center, regardless of rotation.
	Works for any table size, player count, or grid configuration.
	"""
	if player_index >= table.player_grids.size():
		return [2, 3]  # Fallback
	
	var grid = table.player_grids[player_index]
	
	# Table center (assumed at world origin)
	var table_center = Vector3.ZERO
	
	# Calculate direction from table center to grid
	var center_to_grid = grid.global_position - table_center
	
	# Player sits on the OPPOSITE side (away from center)
	# Normalize to get direction, multiply by distance to get seating position
	var player_seat_direction = center_to_grid.normalized()
	var player_seat_pos = grid.global_position + player_seat_direction * 1.5
	
	# Calculate distance from each card position to the player's seat
	var distances: Array = []
	for i in range(4):
		var card_world_pos = grid.to_global(grid.card_positions[i])
		var distance = player_seat_pos.distance_to(card_world_pos)
		distances.append({"index": i, "distance": distance})
	
	# Sort by distance (closest first)
	distances.sort_custom(func(a, b): return a.distance < b.distance)
	
	# Return the 2 closest card indices
	return [distances[0].index, distances[1].index]

func lift_bottom_cards_for_viewing(player_idx: int) -> void:
	"""Animate a player's 2 bottom cards to a side-by-side viewing position above the table.
	For the human player this is their private view; bots animate so they visually appear to look.
	"""
	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		return

	var grid = table.player_grids[player_idx]
	var bottom_positions = get_bottom_card_positions(player_idx)
	var card1 = grid.get_card_at(bottom_positions[0])
	var card2 = grid.get_card_at(bottom_positions[1])

	if not card1 or not card2:
		return

	print("Player %d picking up cards: %s, %s" % [
		player_idx + 1,
		card1.card_data.get_short_name(),
		card2.card_data.get_short_name()])

	# Save original grid positions NOW (before move_to overwrites base_position)
	var orig_pos1 = grid.to_global(grid.card_positions[bottom_positions[0]])
	var orig_pos2 = grid.to_global(grid.card_positions[bottom_positions[1]])

	# Calculate side-by-side viewing positions for this player
	var view_center = table.view_helper.get_card_view_position_for(player_idx)
	var sideways = table.view_helper.get_card_view_sideways_for(player_idx)
	var view_rotation = table.view_helper.get_card_view_rotation_for(player_idx)

	# Rotate cards to face this player
	card1.global_rotation = Vector3(0, view_rotation, 0)
	card2.global_rotation = Vector3(0, view_rotation, 0)

	# Elevate and spread side-by-side
	card1.move_to(view_center - sideways * 1.0, 0.45, false)
	card2.move_to(view_center + sideways * 1.0, 0.45, false)
	await get_tree().create_timer(0.5).timeout

	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		return

	# Flip face-up so player can see card values
	if not card1.is_face_up:
		card1.flip(true, 0.3)
	if not card2.is_face_up:
		card2.flip(true, 0.3)
	await get_tree().create_timer(0.35).timeout

	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		return

	# Tilt toward viewer (steep for bots so human camera can't see the front)
	var is_bot: bool = (player_idx != 0)
	table.view_helper.tilt_card_towards_viewer(card1, is_bot)
	table.view_helper.tilt_card_towards_viewer(card2, is_bot)
	await get_tree().create_timer(0.25).timeout

	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		return

	# Store so we can return these cards later (include saved grid positions)
	table.initial_view_cards[player_idx] = [card1, card2, orig_pos1, orig_pos2]

func return_bottom_cards_for_player(player_idx: int) -> void:
	"""Animate a player's viewed bottom cards back to their grid positions."""
	if not table.initial_view_cards.has(player_idx):
		return

	var cards: Array = table.initial_view_cards[player_idx]
	table.initial_view_cards.erase(player_idx)

	var card1: Card3D = cards[0]
	var card2: Card3D = cards[1]
	var orig_pos1: Vector3 = cards[2]
	var orig_pos2: Vector3 = cards[3]

	# Untilt
	card1.rotation.x = 0.0
	card2.rotation.x = 0.0

	# Flip face-down
	if card1.is_face_up:
		card1.flip(false, 0.3)
	if card2.is_face_up:
		card2.flip(false, 0.3)
	await get_tree().create_timer(0.35).timeout

	# Reset rotation so grid orientation takes over
	card1.rotation = Vector3.ZERO
	card2.rotation = Vector3.ZERO

	# Animate back to original grid positions (use saved positions, NOT base_position
	# which was overwritten by move_to when lifting)
	card1.move_to(orig_pos1, 0.4, false)
	card2.move_to(orig_pos2, 0.4, false)
	await get_tree().create_timer(0.45).timeout

	print("Player %d cards returned to grid" % (player_idx + 1))

func _bot_auto_return_cards(player_idx: int) -> void:
	"""After a viewing delay, automatically return a bot's cards and mark them ready."""
	await get_tree().create_timer(2.5).timeout

	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		return  # Phase already ended (e.g. A-key debug)

	if table.initial_view_cards.has(player_idx):
		await return_bottom_cards_for_player(player_idx)

	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		return

	GameManager.set_player_ready(player_idx, true)
	var ready_count = GameManager.get_ready_count()
	table.viewing_ui.update_waiting_count(ready_count, table.num_players)
	print("Bot Player %d finished viewing (%d/%d ready)" % [player_idx + 1, ready_count, table.num_players])

	if GameManager.are_all_players_ready():
		await get_tree().create_timer(0.3).timeout
		end_viewing_phase()

func auto_ready_other_players() -> void:
	"""Debug function to auto-ready all bot players immediately"""
	print("\n=== Auto-Ready Debug Activated ===")
	for i in range(1, table.num_players):
		if i >= GameManager.players.size():
			continue
		# Snap cards back instantly (skip smooth return for debug speed)
		if table.initial_view_cards.has(i):
			var cards: Array = table.initial_view_cards[i]
			table.initial_view_cards.erase(i)
			# cards = [card1, card2, orig_pos1, orig_pos2]
			for ci in range(2):
				var c: Card3D = cards[ci]
				var orig_pos: Vector3 = cards[ci + 2]
				c.rotation = Vector3.ZERO
				if c.is_face_up:
					c.flip(false, 0.15)
				c.move_to(orig_pos, 0.2, false)
		GameManager.set_player_ready(i, true)

	var ready_count = GameManager.get_ready_count()
	table.viewing_ui.update_waiting_count(ready_count, table.num_players)
	print("All other players marked as ready (%d/%d)" % [ready_count, table.num_players])

	if GameManager.are_all_players_ready():
		await get_tree().create_timer(0.5).timeout
		end_viewing_phase()

func start_initial_viewing_phase() -> void:
	"""Start the initial card viewing phase.
	All players simultaneously lift their 2 bottom cards to a viewing position.
	Bots return automatically after a delay; human presses the Ready button.
	"""
	print("\n=== Starting Initial Viewing Phase ===")
	GameManager.change_state(GameManager.GameState.INITIAL_VIEWING)
	GameManager.reset_all_ready_states()
	table.initial_view_cards.clear()

	# Fire-and-forget: all players lift their cards simultaneously
	for i in range(table.num_players):
		lift_bottom_cards_for_viewing(i)  # async, runs independently

	# Wait for all lift animations to finish (0.5 + 0.35 + 0.25 + buffer)
	await get_tree().create_timer(1.3).timeout

	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		return

	# Bots auto-return after a short viewing delay
	for i in range(1, table.num_players):
		_bot_auto_return_cards(i)  # async, runs independently

	# Show Ready button for the human player
	table.viewing_ui.show_for_player(0, table.num_players)
	print("Memorize your bottom 2 cards. Press Ready when done.")
	print("(Press A to auto-ready bots for testing)")

func _on_player_ready_pressed(player_id: int) -> void:
	"""Handle when a player presses the ready button.
	Returns the human player's cards to the grid, then checks if all players are ready.
	"""
	# Return the human player's cards first so they animate back smoothly
	if table.initial_view_cards.has(player_id):
		await return_bottom_cards_for_player(player_id)

	GameManager.set_player_ready(player_id, true)

	var ready_count = GameManager.get_ready_count()
	table.viewing_ui.update_waiting_count(ready_count, table.num_players)
	print("Ready count: %d/%d" % [ready_count, table.num_players])

	if GameManager.are_all_players_ready():
		await get_tree().create_timer(0.5).timeout
		end_viewing_phase()

func end_viewing_phase() -> void:
	"""End the viewing phase and start the game.
	By this point all viewed cards should already be back in their grids.
	"""
	print("\n=== Ending Viewing Phase ===")
	print("All players ready! Starting game...")

	# Hide UI
	table.viewing_ui.hide_ui()

	# Safety: return any cards still in the air (e.g. race conditions)
	for player_idx in table.initial_view_cards.keys():
		await return_bottom_cards_for_player(player_idx)
	table.initial_view_cards.clear()

	# Start the game
	print("\n=== Game Starting ===")
	GameManager.change_state(GameManager.GameState.PLAYING)
	table.turn_manager.start_next_turn()
