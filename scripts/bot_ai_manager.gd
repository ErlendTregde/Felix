extends Node
class_name BotAIManager
## Handles bot turn logic and ability decisions

var table  # Reference to game_table

# Knock probability: starts very low, increases each turn
var _turn_count: int = 0
const KNOCK_BASE_CHANCE: float = 0.01  # 1% base
const KNOCK_INCREMENT: float = 0.005   # +0.5% per turn (very slow ramp)

func init(game_table) -> void:
	table = game_table

func reset_turn_count() -> void:
	"""Reset the knock probability counter for a new round."""
	_turn_count = 0

# ======================================
# HELPERS
# ======================================

func _get_all_cards(grid: PlayerGrid) -> Array[Card3D]:
	"""Return every non-null card in the grid (main slots + penalty cards)."""
	var result: Array[Card3D] = []
	for i in range(4):
		var c = grid.get_card_at(i)
		if c:
			result.append(c)
	for c in grid.penalty_cards:
		result.append(c)
	return result

func _get_card_return_position(grid: PlayerGrid, card: Card3D) -> Vector3:
	"""Return the global rest position for a card that belongs to *grid*.
	Works for main-grid cards AND penalty cards."""
	for i in range(4):
		if grid.get_card_at(i) == card:
			return grid.to_global(grid.card_positions[i])
	var pidx = grid.penalty_cards.find(card)
	if pidx != -1:
		var slot = mini(pidx, grid.penalty_positions.size() - 1)
		var stack_height := 0.0
		if pidx >= grid.penalty_positions.size():
			stack_height = (pidx - (grid.penalty_positions.size() - 1)) * 0.025
		return grid.to_global(grid.penalty_positions[slot] + Vector3(0, stack_height, 0))
	# Fallback
	return grid.global_position

func _pick_random_card(grid: PlayerGrid) -> Card3D:
	"""Pick a random non-null card from main grid + penalty cards."""
	var all = _get_all_cards(grid)
	if all.is_empty():
		return null
	return all[randi() % all.size()]

# ======================================
# TURN EXECUTION
# ======================================

func execute_bot_turn(bot_id: int) -> void:
	"""Execute a bot turn with ability decision logic"""
	print("Bot %d executing turn..." % (bot_id + 1))
	_turn_count += 1
	
	# === KNOCK DECISION (only in PLAYING state, not during final round) ===
	if GameManager.current_state == GameManager.GameState.PLAYING:
		var knock_chance = KNOCK_BASE_CHANCE + (KNOCK_INCREMENT * _turn_count)
		if randf() < knock_chance:
			print("Bot %d decides to KNOCK! (chance was %.1f%%)" % [bot_id + 1, knock_chance * 100.0])
			# Show the bot's 3D knock button and simulate a press for visual effect
			var btn = table.knock_manager.get_button(bot_id)
			if btn:
				btn.show_button()
				await get_tree().create_timer(0.4).timeout
				btn.simulate_press()
			else:
				# Fallback: no button found, knock directly
				table.knock_manager.perform_knock(bot_id)
			return

	# Hide knock buttons once the bot starts drawing (if visible)
	table.knock_manager.hide_all_buttons()
	
	# Bot draws a card
	table.drawn_card = await table.turn_manager.draw_card_from_pile()
	if not table.drawn_card:
		table.turn_manager.end_current_turn()
		return
	
	await get_tree().create_timer(0.5).timeout
	
	# Check if drawn card has an ability
	var ability = table.drawn_card.card_data.get_ability()
	var has_ability = ability != CardData.AbilityType.NONE
	
	# Collect all swappable cards (main grid + penalty)
	var grid = table.player_grids[bot_id]
	var swappable = _get_all_cards(grid)
	
	# Random decision: 50% chance to use ability if available
	var use_ability = has_ability and (randf() < 0.5)
	
	if use_ability:
		print("Bot deciding to use ability!")
		await execute_bot_ability(bot_id, ability)
	else:
		# Bot picks a random card to swap (Option B) from ALL occupied slots
		if swappable.size() > 0:
			var target_card = swappable[randi() % swappable.size()]
			await table.turn_manager.swap_cards(target_card, table.drawn_card)
		elif has_ability:
			# No swappable cards at all — fall back to using the ability
			print("Bot has no cards to swap — falling back to ability!")
			await execute_bot_ability(bot_id, ability)
		else:
			# No cards AND no ability — discard and end turn
			print("Bot has no cards and no ability — discarding drawn card.")
			table.drawn_card.queue_free()
			table.drawn_card = null
			table.turn_manager.end_current_turn()

func execute_bot_ability(bot_id: int, ability: CardData.AbilityType) -> void:
	"""Execute ability logic for bot (Option A)"""
	# Discard the card to activate ability
	var card = table.drawn_card
	
	# Animate to discard pile
	var discard_pos = table.discard_pile_marker.global_position
	card.move_to(discard_pos + Vector3(0, 0.05 * table.deck_manager.discard_pile.size(), 0), 0.3, false)
	await get_tree().create_timer(0.35).timeout
	
	# Add to discard pile data
	table.deck_manager.add_to_discard(card.card_data)
	table.match_manager._unlock_matching()  # New card on discard — matching now allowed
	
	# Update visual
	if table.discard_pile_visual:
		table.discard_pile_visual.set_count(table.deck_manager.discard_pile.size())
		table.discard_pile_visual.set_top_card(card.card_data)
	
	# Clean up the card
	card.queue_free()
	table.drawn_card = null
	
	# Execute ability
	match ability:
		CardData.AbilityType.LOOK_OWN:
			await bot_execute_look_own(bot_id)
		CardData.AbilityType.LOOK_OPPONENT:
			await bot_execute_look_opponent(bot_id)
		CardData.AbilityType.BLIND_SWAP:
			await bot_execute_blind_swap(bot_id)
		CardData.AbilityType.LOOK_AND_SWAP:
			await bot_execute_look_and_swap(bot_id)
		_:
			print("Bot: No ability to execute")
			table.turn_manager.end_current_turn()

func bot_execute_look_own(bot_id: int) -> void:
	"""Bot looks at one of its own cards (7/8 ability) WITH VISUAL ANIMATION"""
	print("Bot executing: Look at own card")
	
	table.turn_ui.update_action("Bot is looking at own card...")
	
	var grid = table.player_grids[bot_id]
	var target_card = _pick_random_card(grid)
	
	if not target_card:
		table.turn_manager.end_current_turn()
		return
	
	print("Bot looking at: %s" % target_card.card_data.get_short_name())
	
	# Highlight the card so player can see what bot is looking at
	target_card.set_highlighted(true)
	await get_tree().create_timer(0.3).timeout
	
	# Calculate view position (same as player)
	var view_position = table.view_helper.get_card_view_position()
	
	# Animate card to view position
	target_card.move_to(view_position, 0.4, false)
	
	# Set global rotation to face current player (bot)
	var view_rotation = table.view_helper.get_card_view_rotation()
	target_card.global_rotation = Vector3(0, view_rotation, 0)
	
	await get_tree().create_timer(0.45).timeout
	
	# Flip face-up so player can see what bot is viewing
	if not target_card.is_face_up:
		target_card.flip(true, 0.3)
		await get_tree().create_timer(0.35).timeout
	
	# Tilt towards viewer (steep so human camera can't see the front)
	table.view_helper.tilt_card_towards_viewer(target_card, true)
	await get_tree().create_timer(0.25).timeout
	
	# Hold for a moment so player can see
	await get_tree().create_timer(1.0).timeout
	
	# Reset rotation to zero (grid provides orientation)
	target_card.rotation = Vector3.ZERO
	await get_tree().create_timer(0.25).timeout
	
	# Flip back face-down
	if target_card.is_face_up:
		target_card.flip(true, 0.3)
		await get_tree().create_timer(0.35).timeout
	
	# Return to grid position (works for main grid AND penalty cards)
	var target_pos = _get_card_return_position(grid, target_card)
	target_card.move_to(target_pos, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Unhighlight
	target_card.set_highlighted(false)
	
	table.turn_manager.end_current_turn()

func bot_execute_look_opponent(bot_id: int) -> void:
	"""Bot looks at one opponent's card (9/10 ability) WITH VISUAL ANIMATION"""
	print("Bot executing: Look at opponent card")
	
	table.turn_ui.update_action("Bot is looking at opponent card...")
	
	# Pick random NEIGHBOR (not just any opponent)
	var opponents = table.view_helper.get_neighbors(bot_id)
	
	if opponents.is_empty():
		table.turn_manager.end_current_turn()
		return
	
	var opponent_id = opponents[randi() % opponents.size()]
	var opponent_grid = table.player_grids[opponent_id]
	var target_card = _pick_random_card(opponent_grid)
	
	if not target_card:
		table.turn_manager.end_current_turn()
		return
	
	print("Bot looking at opponent %d's card: %s" % [opponent_id + 1, target_card.card_data.get_short_name()])
	
	# Highlight the card so everyone can see what bot is looking at
	target_card.set_highlighted(true)
	await get_tree().create_timer(0.3).timeout
	
	# Calculate view position
	var view_position = table.view_helper.get_card_view_position()
	
	# Animate card to view position
	target_card.move_to(view_position, 0.4, false)
	
	# Set global rotation to face current player (bot)
	var view_rotation = table.view_helper.get_card_view_rotation()
	target_card.global_rotation = Vector3(0, view_rotation, 0)
	
	await get_tree().create_timer(0.45).timeout
	
	# Flip face-up so everyone can see
	if not target_card.is_face_up:
		target_card.flip(true, 0.3)
		await get_tree().create_timer(0.35).timeout
	
	# Tilt towards viewer (steep so human camera can't see the front)
	table.view_helper.tilt_card_towards_viewer(target_card, true)
	await get_tree().create_timer(0.25).timeout
	
	# Hold for a moment
	await get_tree().create_timer(1.0).timeout
	
	# Reset rotation to zero (grid provides orientation)
	target_card.rotation = Vector3.ZERO
	await get_tree().create_timer(0.25).timeout
	
	# Flip back face-down
	if target_card.is_face_up:
		target_card.flip(true, 0.3)
		await get_tree().create_timer(0.35).timeout
	
	# Return to grid position (works for main grid AND penalty cards)
	var target_pos = _get_card_return_position(opponent_grid, target_card)
	target_card.move_to(target_pos, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Unhighlight
	target_card.set_highlighted(false)
	
	table.turn_manager.end_current_turn()

func bot_execute_blind_swap(bot_id: int) -> void:
	"""Bot executes blind swap with neighbor (Jack ability) WITH VISUAL ANIMATION"""
	print("Bot executing: Blind swap")
	
	table.turn_ui.update_action("Bot is doing blind swap...")
	
	var neighbors = table.view_helper.get_neighbors(bot_id)
	if neighbors.is_empty():
		print("Bot has no neighbors!")
		table.turn_manager.end_current_turn()
		return
	
	# Pick random neighbor
	var neighbor_id = neighbors[randi() % neighbors.size()]
	
	# Pick random own card (main grid + penalty)
	var own_grid = table.player_grids[bot_id]
	var own_card = _pick_random_card(own_grid)
	
	# Pick random neighbor card (main grid + penalty)
	var neighbor_grid = table.player_grids[neighbor_id]
	var neighbor_card = _pick_random_card(neighbor_grid)
	
	if not own_card or not neighbor_card:
		table.turn_manager.end_current_turn()
		return
	
	# Resolve grid positions for both cards
	var own_pos := -1
	var own_penalty_idx := -1
	for i in range(4):
		if own_grid.get_card_at(i) == own_card:
			own_pos = i
			break
	if own_pos == -1:
		own_penalty_idx = own_grid.penalty_cards.find(own_card)
	
	var neighbor_pos := -1
	var neighbor_penalty_idx := -1
	for i in range(4):
		if neighbor_grid.get_card_at(i) == neighbor_card:
			neighbor_pos = i
			break
	if neighbor_pos == -1:
		neighbor_penalty_idx = neighbor_grid.penalty_cards.find(neighbor_card)
	
	print("Bot swapping: own card with neighbor %d's card" % (neighbor_id + 1))
	
	# Highlight both cards so player can see what's being swapped
	own_card.set_highlighted(true)
	neighbor_card.set_highlighted(true)
	
	# Elevate both cards
	own_card.elevate(0.2, 0.15)
	neighbor_card.elevate(0.2, 0.15)
	await get_tree().create_timer(0.2).timeout
	
	# Lock elevation
	own_card.is_elevation_locked = true
	neighbor_card.is_elevation_locked = true
	
	# Wait a moment so player can see which cards are selected
	await get_tree().create_timer(0.5).timeout
	
	# Get target positions (where each card is going)
	var own_target = _get_card_return_position(neighbor_grid, neighbor_card)
	var neighbor_target = _get_card_return_position(own_grid, own_card)
	
	# Swap in grid arrays — main grid slots
	if own_pos != -1:
		own_grid.cards[own_pos] = neighbor_card
	if neighbor_pos != -1:
		neighbor_grid.cards[neighbor_pos] = own_card
	
	# Swap penalty card tracking
	if own_penalty_idx != -1:
		own_grid.penalty_cards[own_penalty_idx] = neighbor_card
	if neighbor_penalty_idx != -1:
		neighbor_grid.penalty_cards[neighbor_penalty_idx] = own_card
	
	# Update owner_player references
	var temp_owner = own_card.owner_player
	own_card.owner_player = neighbor_card.owner_player
	neighbor_card.owner_player = temp_owner
	
	# Animate both cards to new positions (while elevated)
	own_card.move_to(own_target, 0.4, false)
	neighbor_card.move_to(neighbor_target, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Unlock and lower
	own_card.is_elevation_locked = false
	neighbor_card.is_elevation_locked = false
	own_card.lower(0.2)
	neighbor_card.lower(0.2)
	await get_tree().create_timer(0.25).timeout
	
	# Reparent cards to their new grids so they inherit the correct rotation
	if own_card.get_parent() != neighbor_grid:
		own_card.get_parent().remove_child(own_card)
		neighbor_grid.add_child(own_card)
	own_card.rotation = Vector3.ZERO
	# Set local position based on where the card ended up
	if neighbor_pos != -1:
		own_card.position = neighbor_grid.card_positions[neighbor_pos]
		own_card.base_position = neighbor_grid.to_global(neighbor_grid.card_positions[neighbor_pos])
	elif neighbor_penalty_idx != -1:
		var slot = mini(neighbor_penalty_idx, neighbor_grid.penalty_positions.size() - 1)
		own_card.position = neighbor_grid.penalty_positions[slot]
		own_card.base_position = neighbor_grid.to_global(neighbor_grid.penalty_positions[slot])
	
	if neighbor_card.get_parent() != own_grid:
		neighbor_card.get_parent().remove_child(neighbor_card)
		own_grid.add_child(neighbor_card)
	neighbor_card.rotation = Vector3.ZERO
	if own_pos != -1:
		neighbor_card.position = own_grid.card_positions[own_pos]
		neighbor_card.base_position = own_grid.to_global(own_grid.card_positions[own_pos])
	elif own_penalty_idx != -1:
		var slot = mini(own_penalty_idx, own_grid.penalty_positions.size() - 1)
		neighbor_card.position = own_grid.penalty_positions[slot]
		neighbor_card.base_position = own_grid.to_global(own_grid.penalty_positions[slot])
	
	# Unhighlight
	own_card.set_highlighted(false)
	neighbor_card.set_highlighted(false)
	
	table.turn_manager.end_current_turn()

func bot_execute_look_and_swap(bot_id: int) -> void:
	"""Bot executes look and swap (Queen ability) WITH VISUAL ANIMATION"""
	print("Bot executing: Look and swap")
	
	table.turn_ui.update_action("Bot is using Queen ability...")
	
	var neighbors = table.view_helper.get_neighbors(bot_id)
	if neighbors.is_empty():
		print("Bot has no neighbors!")
		table.turn_manager.end_current_turn()
		return
	
	# Pick random neighbor
	var neighbor_id = neighbors[randi() % neighbors.size()]
	
	# Pick random own card (main grid + penalty)
	var own_grid = table.player_grids[bot_id]
	var own_card = _pick_random_card(own_grid)
	
	# Pick random neighbor card (main grid + penalty)
	var neighbor_grid = table.player_grids[neighbor_id]
	var neighbor_card = _pick_random_card(neighbor_grid)
	
	if not own_card or not neighbor_card:
		table.turn_manager.end_current_turn()
		return
	
	# Resolve grid positions for both cards
	var own_pos := -1
	var own_penalty_idx := -1
	for i in range(4):
		if own_grid.get_card_at(i) == own_card:
			own_pos = i
			break
	if own_pos == -1:
		own_penalty_idx = own_grid.penalty_cards.find(own_card)
	
	var neighbor_pos := -1
	var neighbor_penalty_idx := -1
	for i in range(4):
		if neighbor_grid.get_card_at(i) == neighbor_card:
			neighbor_pos = i
			break
	if neighbor_pos == -1:
		neighbor_penalty_idx = neighbor_grid.penalty_cards.find(neighbor_card)
	
	print("Bot viewing: own %s and neighbor's %s" % [own_card.card_data.get_short_name(), neighbor_card.card_data.get_short_name()])
	
	# Highlight both cards
	own_card.set_highlighted(true)
	neighbor_card.set_highlighted(true)
	
	# Elevate both cards
	own_card.elevate(0.2, 0.15)
	neighbor_card.elevate(0.2, 0.15)
	await get_tree().create_timer(0.2).timeout
	
	# Lock elevation
	own_card.is_elevation_locked = true
	neighbor_card.is_elevation_locked = true
	
	# Wait a moment so player can see selection
	await get_tree().create_timer(0.5).timeout
	
	# Move cards to side-by-side viewing positions relative to this bot's seat
	var view_center = table.view_helper.get_card_view_position()
	var sideways = table.view_helper.get_card_view_sideways()
	var left_pos = view_center - sideways * 1.0
	var right_pos = view_center + sideways * 1.0

	# Unlock elevation before moving to view position
	own_card.is_elevation_locked = false
	neighbor_card.is_elevation_locked = false

	# Set global rotation to face current player (bot)
	var view_rotation = table.view_helper.get_card_view_rotation()
	own_card.global_rotation = Vector3(0, view_rotation, 0)
	neighbor_card.global_rotation = Vector3(0, view_rotation, 0)
	
	# Remove highlight before viewing so card faces appear clean
	own_card.set_highlighted(false)
	neighbor_card.set_highlighted(false)

	own_card.move_to(left_pos, 0.4, false)
	neighbor_card.move_to(right_pos, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Flip both face-up so everyone can see
	if not own_card.is_face_up:
		own_card.flip(true, 0.3)
	if not neighbor_card.is_face_up:
		neighbor_card.flip(true, 0.3)
	await get_tree().create_timer(0.35).timeout
	
	# Tilt both towards viewer (steep so human camera can't see the front)
	table.view_helper.tilt_card_towards_viewer(own_card, true)
	table.view_helper.tilt_card_towards_viewer(neighbor_card, true)
	await get_tree().create_timer(0.25).timeout
	
	# Hold for viewing
	await get_tree().create_timer(1.5).timeout
	
	# Random decision: 50% chance to swap
	var should_swap = randf() < 0.5
	
	if should_swap:
		print("Bot deciding to SWAP")
		
		# Flip back face-down
		if own_card.is_face_up:
			own_card.flip(false, 0.3)
		if neighbor_card.is_face_up:
			neighbor_card.flip(false, 0.3)
		await get_tree().create_timer(0.35).timeout
		
		# Get target positions (where each card is going)
		var own_target = _get_card_return_position(neighbor_grid, neighbor_card)
		var neighbor_target = _get_card_return_position(own_grid, own_card)
		
		# Swap in grid arrays — main grid slots
		if own_pos != -1:
			own_grid.cards[own_pos] = neighbor_card
		if neighbor_pos != -1:
			neighbor_grid.cards[neighbor_pos] = own_card
		
		# Swap penalty card tracking
		if own_penalty_idx != -1:
			own_grid.penalty_cards[own_penalty_idx] = neighbor_card
		if neighbor_penalty_idx != -1:
			neighbor_grid.penalty_cards[neighbor_penalty_idx] = own_card
		
		# Update owner_player references
		var temp_owner = own_card.owner_player
		own_card.owner_player = neighbor_card.owner_player
		neighbor_card.owner_player = temp_owner
		
		# Animate to new positions
		own_card.move_to(own_target, 0.4, false)
		neighbor_card.move_to(neighbor_target, 0.4, false)
		await get_tree().create_timer(0.45).timeout
		
		# Reparent cards to their new grids so they inherit the correct rotation
		if own_card.get_parent() != neighbor_grid:
			own_card.get_parent().remove_child(own_card)
			neighbor_grid.add_child(own_card)
		own_card.rotation = Vector3.ZERO
		if neighbor_pos != -1:
			own_card.position = neighbor_grid.card_positions[neighbor_pos]
			own_card.base_position = neighbor_grid.to_global(neighbor_grid.card_positions[neighbor_pos])
		elif neighbor_penalty_idx != -1:
			var slot = mini(neighbor_penalty_idx, neighbor_grid.penalty_positions.size() - 1)
			own_card.position = neighbor_grid.penalty_positions[slot]
			own_card.base_position = neighbor_grid.to_global(neighbor_grid.penalty_positions[slot])
		
		if neighbor_card.get_parent() != own_grid:
			neighbor_card.get_parent().remove_child(neighbor_card)
			own_grid.add_child(neighbor_card)
		neighbor_card.rotation = Vector3.ZERO
		if own_pos != -1:
			neighbor_card.position = own_grid.card_positions[own_pos]
			neighbor_card.base_position = own_grid.to_global(own_grid.card_positions[own_pos])
		elif own_penalty_idx != -1:
			var slot = mini(own_penalty_idx, own_grid.penalty_positions.size() - 1)
			neighbor_card.position = own_grid.penalty_positions[slot]
			neighbor_card.base_position = own_grid.to_global(own_grid.penalty_positions[slot])
	else:
		print("Bot deciding NOT to swap")
		
		# Flip back face-down
		if own_card.is_face_up:
			own_card.flip(false, 0.3)
		if neighbor_card.is_face_up:
			neighbor_card.flip(false, 0.3)
		await get_tree().create_timer(0.35).timeout
		
		# Return to original positions (works for main grid AND penalty cards)
		var own_original = _get_card_return_position(own_grid, own_card)
		var neighbor_original = _get_card_return_position(neighbor_grid, neighbor_card)
		
		own_card.move_to(own_original, 0.4, false)
		neighbor_card.move_to(neighbor_original, 0.4, false)
		await get_tree().create_timer(0.45).timeout
		
		# Correct rotation and position (cards stay in their original grids)
		own_card.rotation = Vector3.ZERO
		neighbor_card.rotation = Vector3.ZERO
		if own_pos != -1:
			own_card.position = own_grid.card_positions[own_pos]
			own_card.base_position = own_grid.to_global(own_grid.card_positions[own_pos])
		elif own_penalty_idx != -1:
			var slot = mini(own_penalty_idx, own_grid.penalty_positions.size() - 1)
			own_card.position = own_grid.penalty_positions[slot]
			own_card.base_position = own_grid.to_global(own_grid.penalty_positions[slot])
		if neighbor_pos != -1:
			neighbor_card.position = neighbor_grid.card_positions[neighbor_pos]
			neighbor_card.base_position = neighbor_grid.to_global(neighbor_grid.card_positions[neighbor_pos])
		elif neighbor_penalty_idx != -1:
			var slot = mini(neighbor_penalty_idx, neighbor_grid.penalty_positions.size() - 1)
			neighbor_card.position = neighbor_grid.penalty_positions[slot]
			neighbor_card.base_position = neighbor_grid.to_global(neighbor_grid.penalty_positions[slot])
	
	# Unlock and lower
	own_card.is_elevation_locked = false
	neighbor_card.is_elevation_locked = false
	own_card.lower(0.2)
	neighbor_card.lower(0.2)
	await get_tree().create_timer(0.25).timeout
	
	# Unhighlight
	own_card.set_highlighted(false)
	neighbor_card.set_highlighted(false)
	
	table.turn_manager.end_current_turn()
