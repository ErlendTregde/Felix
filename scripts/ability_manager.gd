extends Node
class_name AbilityManager
## Manages card abilities: look own, look opponent, blind swap, and look and swap (Queen)

var table  # Reference to game_table

func init(game_table) -> void:
	table = game_table

func handle_ability_target_selection(card: Card3D) -> void:
	"""Handle selecting a target card for an ability"""
	var grid = table.player_grids[GameManager.current_player_index]
	var current_player = GameManager.get_current_player()
	
	# Special handling for BLIND_SWAP (two-step selection)
	if table.current_ability == CardData.AbilityType.BLIND_SWAP:
		handle_blind_swap_selection(card)
		return
	
	# Special handling for LOOK_AND_SWAP (two-step selection)
	if table.current_ability == CardData.AbilityType.LOOK_AND_SWAP:
		handle_look_and_swap_selection(card)
		return
	
	# Check if the selected card is valid for the current ability
	if table.current_ability == CardData.AbilityType.LOOK_OWN:
		# For look_own, card must belong to current player
		if card.owner_player != current_player:
			print("Select one of YOUR cards!")
			return
	elif table.current_ability == CardData.AbilityType.LOOK_OPPONENT:
		# For look_opponent, card must belong to a NEIGHBOR (not own, not across)
		var current_player_idx = GameManager.current_player_index
		var neighbors = table.view_helper.get_neighbors(current_player_idx)
		# Search both main slots AND penalty cards
		var card_owner_idx = table._find_card_owner_idx(card)
		if card_owner_idx == current_player_idx:
			print("Select a NEIGHBOR's card, not your own!")
			return
		if not neighbors.has(card_owner_idx):
			print("That player is not your neighbor! Select a neighbor's card.")
			return
	
	# Found valid target
	table.ability_target_card = card
	card.is_interactable = false  # Prevent re-clicking the selected card
	
	# Switch selected card to darker "confirmed" cyan and lock all others
	card.set_highlighted(true, true)
	for g in table.player_grids:
		for i in range(4):
			var c = g.get_card_at(i)
			if c and c != card:
				c.set_highlighted(false)
				c.is_interactable = false
		for c in g.penalty_cards:
			if c != card:
				c.set_highlighted(false)
				c.is_interactable = false
	
	# Remove highlight before viewing so card face appears clean
	card.set_highlighted(false)

	# Calculate view position (same as draw card)
	var view_position = table.view_helper.get_card_view_position()
	
	# Animate card to view position
	card.move_to(view_position, 0.4, false)
	
	# Set global rotation to face current player
	var view_rotation = table.view_helper.get_card_view_rotation()
	card.global_rotation = Vector3(0, view_rotation, 0)
	
	# Wait for movement
	await get_tree().create_timer(0.45).timeout
	
	# Flip face-up
	if not card.is_face_up:
		card.flip(true, 0.3)
		# Wait for flip animation
		await get_tree().create_timer(0.35).timeout
	else:
		# Card already face-up, wait same time for consistency
		await get_tree().create_timer(0.35).timeout
	
	# Tilt towards player (using helper function)
	table.view_helper.tilt_card_towards_viewer(card)
	await get_tree().create_timer(0.25).timeout
	
	# Update UI
	table.turn_ui.update_action("Press SPACE to confirm")
	table.awaiting_ability_confirmation = true
	
	print("Viewing: %s" % card.card_data.get_short_name())

func handle_blind_swap_selection(card: Card3D) -> void:
	"""Handle two-step selection for blind swap ability - supports re-selection at both steps"""
	var current_player_idx = GameManager.current_player_index
	var neighbors = table.view_helper.get_neighbors(current_player_idx)

	# Find who owns this card
	var card_owner_idx = table._find_card_owner_idx(card)
	var is_own_card = (card_owner_idx == current_player_idx)
	var is_neighbor_card = neighbors.has(card_owner_idx)

	if not is_own_card and not is_neighbor_card:
		print("Select your card or a neighbor's card!")
		return

	# STEP 1 - No first card selected yet
	if table.blind_swap_first_card == null:
		table.blind_swap_first_card = card
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if table.blind_swap_first_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("First card selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			if is_own_card:
				table.turn_ui.update_action("Now select NEIGHBOR's card")
			else:
				table.turn_ui.update_action("Now select YOUR card")
		return

	# Clicking the already-selected first card - ignore
	if card == table.blind_swap_first_card:
		return

	# Find ownership of the currently selected first card
	var first_owner_idx = table._find_card_owner_idx(table.blind_swap_first_card)
	var first_is_own = (first_owner_idx == current_player_idx)

	# RE-SELECT FIRST CARD: same ownership type as current first card - switch to new card
	if is_own_card == first_is_own:
		# If second was also picked, deselect it too and reset step 2
		if table.blind_swap_second_card != null:
			_blind_swap_deselect_card(table.blind_swap_second_card)
			table.blind_swap_second_card = null
			table.awaiting_ability_confirmation = false
		# Deselect old first card, select new one
		_blind_swap_deselect_card(table.blind_swap_first_card)
		table.blind_swap_first_card = card
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if table.blind_swap_first_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("First card re-selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			if is_own_card:
				table.turn_ui.update_action("Now select NEIGHBOR's card")
			else:
				table.turn_ui.update_action("Now select YOUR card")
		return

	# STEP 2 - No second card selected yet (clicked card has opposite ownership = valid second pick)
	if table.blind_swap_second_card == null:
		table.blind_swap_second_card = card
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if table.blind_swap_second_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("Second card selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			table.turn_ui.update_action("Press SPACE to swap cards")
			table.awaiting_ability_confirmation = true
		return

	# Clicking the already-selected second card - ignore
	if card == table.blind_swap_second_card:
		return

	# RE-SELECT SECOND CARD: same ownership type as current second card - switch to new card
	var second_owner_idx = table._find_card_owner_idx(table.blind_swap_second_card)
	var second_is_own = (second_owner_idx == current_player_idx)
	if is_own_card == second_is_own:
		_blind_swap_deselect_card(table.blind_swap_second_card)
		table.blind_swap_second_card = card
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if table.blind_swap_second_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("Second card re-selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			table.turn_ui.update_action("Press SPACE to swap cards")

func _blind_swap_deselect_card(card: Card3D) -> void:
	"""Return a Jack-ability-selected card to its available (bright cyan) state"""
	card.is_elevation_locked = false
	card.elevate(0.0, 0.15)
	card.set_highlighted(true, false)  # bright cyan = still selectable

func _look_and_swap_deselect_card(card: Card3D) -> void:
	"""Return a Queen-ability-selected card to its available (bright cyan) state"""
	card.is_elevation_locked = false
	card.elevate(0.0, 0.15)
	card.set_highlighted(true, false)  # bright cyan = still selectable

func handle_look_and_swap_selection(card: Card3D) -> void:
	"""Handle two-step selection for look and swap ability (Queen) - supports re-selection at both steps"""
	var current_player_idx = GameManager.current_player_index
	var neighbors = table.view_helper.get_neighbors(current_player_idx)

	# Find who owns this card
	var card_owner_idx = table._find_card_owner_idx(card)
	var is_own_card = (card_owner_idx == current_player_idx)
	var is_neighbor_card = neighbors.has(card_owner_idx)

	if not is_own_card and not is_neighbor_card:
		print("Select your card or a neighbor's card!")
		return

	# STEP 1 - No first card selected yet
	if table.look_and_swap_first_card == null:
		table.look_and_swap_first_card = card
		table.look_and_swap_first_original_pos = card.base_position
		_queen_store_card_slot(card, true)
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if table.look_and_swap_first_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("First card selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			if is_own_card:
				table.turn_ui.update_action("Now select NEIGHBOR's card")
			else:
				table.turn_ui.update_action("Now select YOUR card")
		return

	# Clicking the already-selected first card - ignore
	if card == table.look_and_swap_first_card:
		return

	# Find ownership of the currently selected first card
	var first_owner_idx = table._find_card_owner_idx(table.look_and_swap_first_card)
	var first_is_own = (first_owner_idx == current_player_idx)

	# RE-SELECT FIRST CARD: same ownership type as current first card - switch to new card
	if is_own_card == first_is_own:
		# If second was also picked, deselect it too and reset step 2
		if table.look_and_swap_second_card != null:
			_look_and_swap_deselect_card(table.look_and_swap_second_card)
			table.look_and_swap_second_card = null
			table.awaiting_ability_confirmation = false
		# Deselect old first card, select new one
		_look_and_swap_deselect_card(table.look_and_swap_first_card)
		table.look_and_swap_first_card = card
		table.look_and_swap_first_original_pos = card.base_position
		_queen_store_card_slot(card, true)
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if table.look_and_swap_first_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("First card re-selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			if is_own_card:
				table.turn_ui.update_action("Now select NEIGHBOR's card")
			else:
				table.turn_ui.update_action("Now select YOUR card")
		return

	# STEP 2 - No second card selected yet (clicked card has opposite ownership = valid second pick)
	if table.look_and_swap_second_card == null:
		table.look_and_swap_second_card = card
		table.look_and_swap_second_original_pos = card.base_position
		_queen_store_card_slot(card, false)
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if table.look_and_swap_second_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("Second card selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			table.turn_ui.update_action("Press SPACE to view cards")
			table.awaiting_ability_confirmation = true
		return

	# Clicking the already-selected second card - ignore
	if card == table.look_and_swap_second_card:
		return

	# RE-SELECT SECOND CARD: same ownership type as current second card - switch to new card
	var second_owner_idx = table._find_card_owner_idx(table.look_and_swap_second_card)
	var second_is_own = (second_owner_idx == current_player_idx)
	if is_own_card == second_is_own:
		_look_and_swap_deselect_card(table.look_and_swap_second_card)
		table.look_and_swap_second_card = card
		table.look_and_swap_second_original_pos = card.base_position
		_queen_store_card_slot(card, false)
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if table.look_and_swap_second_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("Second card re-selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			table.turn_ui.update_action("Press SPACE to view cards")

func _queen_store_card_slot(card: Card3D, is_first: bool) -> void:
	"""Capture the grid reference and slot index for a Queen-selected card at the moment
	of selection. This avoids having to re-search later (cards may be at a viewing position).
	Handles both main-grid slots and penalty slots."""
	for i in range(table.player_grids.size()):
		var grid = table.player_grids[i]
		# Search main grid slots first
		for j in range(4):
			if grid.get_card_at(j) == card:
				if is_first:
					table.look_and_swap_first_grid = grid
					table.look_and_swap_first_slot = j
					table.look_and_swap_first_penalty_slot = -1
				else:
					table.look_and_swap_second_grid = grid
					table.look_and_swap_second_slot = j
					table.look_and_swap_second_penalty_slot = -1
				return
		# Search penalty slots
		for j in range(grid.penalty_cards.size()):
			if grid.penalty_cards[j] == card:
				if is_first:
					table.look_and_swap_first_grid = grid
					table.look_and_swap_first_slot = -1
					table.look_and_swap_first_penalty_slot = j
				else:
					table.look_and_swap_second_grid = grid
					table.look_and_swap_second_slot = -1
					table.look_and_swap_second_penalty_slot = j
				return

func _clear_queen_state() -> void:
	"""Reset all Queen look-and-swap state variables."""
	table.look_and_swap_first_card = null
	table.look_and_swap_second_card = null
	table.look_and_swap_first_original_pos = Vector3.ZERO
	table.look_and_swap_second_original_pos = Vector3.ZERO
	table.look_and_swap_first_grid = null
	table.look_and_swap_first_slot = -1
	table.look_and_swap_first_penalty_slot = -1
	table.look_and_swap_second_grid = null
	table.look_and_swap_second_slot = -1
	table.look_and_swap_second_penalty_slot = -1
	table.is_executing_ability = false
	table.current_ability = CardData.AbilityType.NONE

func _unlock_queen_ability() -> void:
	"""Emergency exit from the Queen ability — clean up state and end turn."""
	_clear_queen_state()
	table.turn_manager.end_current_turn()

func display_cards_for_choice() -> void:
	"""Display both selected cards side-by-side and show swap choice UI"""
	table.turn_ui.update_action("Viewing cards...")
	
	var card1 = table.look_and_swap_first_card
	var card2 = table.look_and_swap_second_card
	
	# Unlock elevation so we can move them
	card1.is_elevation_locked = false
	card2.is_elevation_locked = false
	
	# Calculate viewing positions (side-by-side, perpendicular to player's view direction)
	var view_center = table.view_helper.get_card_view_position()
	var sideways = table.view_helper.get_card_view_sideways()
	var card1_view_pos = view_center - sideways * 1.0
	var card2_view_pos = view_center + sideways * 1.0
	
	# Set global rotation to face current player
	var view_rotation = table.view_helper.get_card_view_rotation()
	card1.global_rotation = Vector3(0, view_rotation, 0)
	card2.global_rotation = Vector3(0, view_rotation, 0)
	
	# Remove highlight before viewing so card faces appear clean
	card1.set_highlighted(false)
	card2.set_highlighted(false)

	# Move cards to viewing positions
	card1.move_to(card1_view_pos, 0.4, false)
	card2.move_to(card2_view_pos, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Flip both cards face-up
	if not card1.is_face_up:
		card1.flip(true, 0.3)
	if not card2.is_face_up:
		card2.flip(true, 0.3)
	await get_tree().create_timer(0.35).timeout
	
	# Tilt both cards towards viewer
	table.view_helper.tilt_card_towards_viewer(card1)
	table.view_helper.tilt_card_towards_viewer(card2)
	await get_tree().create_timer(0.25).timeout
	
	# Show swap choice UI
	table.turn_ui.update_action("Choose whether to swap")
	table.swap_choice_ui.show_choice()
	print("Viewing: %s and %s" % [card1.card_data.get_short_name(), card2.card_data.get_short_name()])

func confirm_look_and_swap() -> void:
	"""Confirm Queen card selection and proceed to side-by-side viewing"""
	table.awaiting_ability_confirmation = false
	await display_cards_for_choice()

func confirm_blind_swap() -> void:
	"""Execute the blind swap between two selected cards (supports main grid and penalty slots)"""
	if not table.blind_swap_first_card or not table.blind_swap_second_card:
		print("Error: Both cards must be selected!")
		return
	
	print("\n=== Executing Blind Swap ===")
	
	var card1 = table.blind_swap_first_card
	var card2 = table.blind_swap_second_card
	
	# Find grid, main slot index, and penalty slot index for both cards.
	# Exactly one of main_slot / penalty_slot will be >= 0 for each card.
	var card1_grid: PlayerGrid = null
	var card1_main_slot: int = -1
	var card1_penalty_slot: int = -1
	var card2_grid: PlayerGrid = null
	var card2_main_slot: int = -1
	var card2_penalty_slot: int = -1
	
	for grid in table.player_grids:
		for i in range(4):
			if grid.get_card_at(i) == card1:
				card1_grid = grid; card1_main_slot = i
			if grid.get_card_at(i) == card2:
				card2_grid = grid; card2_main_slot = i
		for i in range(grid.penalty_cards.size()):
			if grid.penalty_cards[i] == card1:
				card1_grid = grid; card1_penalty_slot = i
			if grid.penalty_cards[i] == card2:
				card2_grid = grid; card2_penalty_slot = i
	
	if not card1_grid or not card2_grid:
		print("Error: Could not find card grids!")
		# Re-enable SPACE confirm so player can retry
		table.awaiting_ability_confirmation = true
		return
	
	print("Swapping: %s (Player %d) ↔ %s (Player %d)" % [
		card1.card_data.get_short_name(), card1_grid.player_id + 1,
		card2.card_data.get_short_name(), card2_grid.player_id + 1])
	
	# Compute the world-space target each card will move to (= where the OTHER card currently is)
	var card1_target := _grid_slot_global_pos(card2_grid, card2_main_slot, card2_penalty_slot)
	var card2_target := _grid_slot_global_pos(card1_grid, card1_main_slot, card1_penalty_slot)
	
	# --- Update data structures (swap entries in their respective arrays) ---
	if card1_main_slot != -1:
		card1_grid.cards[card1_main_slot] = card2
	else:
		card1_grid.penalty_cards[card1_penalty_slot] = card2
	
	if card2_main_slot != -1:
		card2_grid.cards[card2_main_slot] = card1
	else:
		card2_grid.penalty_cards[card2_penalty_slot] = card1
	
	# --- Update owner_player references ---
	var temp_owner = card1.owner_player
	card1.owner_player = card2.owner_player
	card2.owner_player = temp_owner
	
	# --- Animate both cards to new positions (while still elevated) ---
	card1.move_to(card1_target, 0.4, false)
	card2.move_to(card2_target, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Lower elevation lock
	card1.is_elevation_locked = false
	card2.is_elevation_locked = false
	card1.lower(0.2)
	card2.lower(0.2)
	await get_tree().create_timer(0.25).timeout
	
	# --- Reparent cards to their new grids and set local position/rotation ---
	# card1 now belongs to card2_grid at card2's old slot
	if card1.get_parent() != card2_grid:
		card1.get_parent().remove_child(card1)
		card2_grid.add_child(card1)
	card1.rotation = Vector3.ZERO
	if card2_main_slot != -1:
		card1.position = card2_grid.card_positions[card2_main_slot]
		card1.base_position = card2_grid.to_global(card2_grid.card_positions[card2_main_slot])
	else:
		card1.position = card2_grid.penalty_positions[card2_penalty_slot]
		card1.base_position = card2_grid.to_global(card2_grid.penalty_positions[card2_penalty_slot])
	
	# card2 now belongs to card1_grid at card1's old slot
	if card2.get_parent() != card1_grid:
		card2.get_parent().remove_child(card2)
		card1_grid.add_child(card2)
	card2.rotation = Vector3.ZERO
	if card1_main_slot != -1:
		card2.position = card1_grid.card_positions[card1_main_slot]
		card2.base_position = card1_grid.to_global(card1_grid.card_positions[card1_main_slot])
	else:
		card2.position = card1_grid.penalty_positions[card1_penalty_slot]
		card2.base_position = card1_grid.to_global(card1_grid.penalty_positions[card1_penalty_slot])
	
	# --- Unhighlight all cards ---
	for grid in table.player_grids:
		for i in range(4):
			var c = grid.get_card_at(i)
			if c:
				c.set_highlighted(false)
				c.is_interactable = false
		for c in grid.penalty_cards:
			c.set_highlighted(false)
			c.is_interactable = false
	
	table.blind_swap_first_card = null
	table.blind_swap_second_card = null
	table.is_executing_ability = false
	table.current_ability = CardData.AbilityType.NONE
	
	table.turn_manager.end_current_turn()

func _grid_slot_global_pos(grid: PlayerGrid, main_slot: int, penalty_slot: int) -> Vector3:
	"""Return the world-space position of a main-grid or penalty slot (used by blind swap)."""
	if main_slot != -1:
		return grid.to_global(grid.card_positions[main_slot])
	if penalty_slot != -1 and penalty_slot < grid.penalty_positions.size():
		return grid.to_global(grid.penalty_positions[penalty_slot])
	return grid.global_position

func _queen_slot_global_pos(grid: PlayerGrid, main_slot: int, penalty_slot: int) -> Vector3:
	"""Return the world-space position of a Queen-ability slot (main or penalty)."""
	if main_slot != -1:
		return grid.to_global(grid.card_positions[main_slot])
	if penalty_slot != -1 and penalty_slot < grid.penalty_positions.size():
		return grid.to_global(grid.penalty_positions[penalty_slot])
	return grid.global_position

func _queen_local_pos(grid: PlayerGrid, main_slot: int, penalty_slot: int) -> Vector3:
	"""Return the local-space position of a Queen-ability slot (main or penalty)."""
	if main_slot != -1:
		return grid.card_positions[main_slot]
	if penalty_slot != -1 and penalty_slot < grid.penalty_positions.size():
		return grid.penalty_positions[penalty_slot]
	return Vector3.ZERO

func _queen_set_slot(grid: PlayerGrid, main_slot: int, penalty_slot: int, card: Card3D) -> void:
	"""Write `card` into the correct slot array on `grid` (main or penalty)."""
	if main_slot != -1:
		grid.cards[main_slot] = card
	elif penalty_slot != -1:
		grid.penalty_cards[penalty_slot] = card

func confirm_ability_viewing() -> void:
	"""Confirm that player has seen the ability target and flip it back"""
	if not table.awaiting_ability_confirmation:
		return
	# Clear immediately to prevent double-fire from a second SPACE press
	table.awaiting_ability_confirmation = false
	
	# Route to blind swap confirmation if that's the current ability
	if table.current_ability == CardData.AbilityType.BLIND_SWAP:
		confirm_blind_swap()
		return

	# Route to Queen viewing confirmation if that's the current ability
	if table.current_ability == CardData.AbilityType.LOOK_AND_SWAP:
		confirm_look_and_swap()
		return
	
	# For viewing abilities (LOOK_OWN, LOOK_OPPONENT)
	if not table.ability_target_card:
		return
	
	var card = table.ability_target_card
	
	# Find which grid and position the card is in (main slots AND penalty slots)
	var card_grid = null
	var card_position = -1      # main-grid slot index, or -1
	var card_penalty_pos = -1   # penalty slot index, or -1
	
	# Search all player grids
	for grid in table.player_grids:
		for i in range(4):
			if grid.get_card_at(i) == card:
				card_grid = grid
				card_position = i
				break
		if not card_grid:
			for i in range(grid.penalty_cards.size()):
				if grid.penalty_cards[i] == card:
					card_grid = grid
					card_penalty_pos = i
					break
		if card_grid:
			break
	
	if not card_grid:
		print("Error: Could not find card's grid!")
		return
	
	# Reset rotation to zero (grid provides orientation)
	card.rotation = Vector3.ZERO
	await get_tree().create_timer(0.25).timeout
	
	# Flip card back face-down
	if card.is_face_up:
		card.flip(true, 0.3)
		await get_tree().create_timer(0.35).timeout
	
	# Animate back to grid position (main or penalty)
	var target_pos: Vector3
	if card_position != -1:
		target_pos = card_grid.to_global(card_grid.card_positions[card_position])
	else:
		target_pos = card_grid.to_global(card_grid.penalty_positions[card_penalty_pos])
	
	card.move_to(target_pos, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Reparent back to the card's grid so it inherits the correct rotation
	if card.get_parent() != card_grid:
		card.get_parent().remove_child(card)
		card_grid.add_child(card)
	card.rotation = Vector3.ZERO
	if card_position != -1:
		card.position = card_grid.card_positions[card_position]
		card.base_position = card_grid.to_global(card_grid.card_positions[card_position])
	else:
		card.position = card_grid.penalty_positions[card_penalty_pos]
		card.base_position = card_grid.to_global(card_grid.penalty_positions[card_penalty_pos])
	
	# Unhighlight ALL grids (LOOK_OPPONENT highlights multiple neighbor grids)
	for grid in table.player_grids:
		for i in range(4):
			var c = grid.get_card_at(i)
			if c:
				c.set_highlighted(false)
				c.is_interactable = false
		for c in grid.penalty_cards:
			c.set_highlighted(false)
			c.is_interactable = false
	
	# Clean up
	table.awaiting_ability_confirmation = false
	table.ability_target_card = null
	table.is_executing_ability = false
	table.current_ability = CardData.AbilityType.NONE
	
	# End turn
	table.turn_manager.end_current_turn()

func execute_ability_look_own() -> void:
	"""Execute 7/8 ability: Look at one of your own cards"""
	print("\n=== Ability: Look at Own Card ===")
	table.turn_ui.update_action("Select which card to look at")
	
	table.is_executing_ability = true
	table.current_ability = CardData.AbilityType.LOOK_OWN
	var grid = table.player_grids[GameManager.current_player_index]
	
	# Highlight own cards + penalty cards (cyan = selectable)
	for i in range(4):
		var card = grid.get_card_at(i)
		if card:
			card.set_highlighted(true)
			card.is_interactable = true
	for card in grid.penalty_cards:
		card.set_highlighted(true)
		card.is_interactable = true
	
	# Wait for player to select a card (handled in handle_ability_target_selection)
	# The flow continues in confirm_ability_viewing() when SPACE is pressed

func execute_ability_look_opponent() -> void:
	"""Execute 9/10 ability: Look at one of opponent's cards"""
	print("\n=== Ability: Look at Opponent's Card ===")
	
	table.is_executing_ability = true
	table.current_ability = CardData.AbilityType.LOOK_OPPONENT
	
	table.turn_ui.update_action("Select opponent's card to look at")
	
	# Highlight only NEIGHBOR cards + penalty cards (cyan = targetable)
	var current_player = GameManager.current_player_index
	var neighbors = table.view_helper.get_neighbors(current_player)
	for neighbor_idx in neighbors:
		var opponent_grid = table.player_grids[neighbor_idx]
		for j in range(4):
			var card = opponent_grid.get_card_at(j)
			if card:
				card.set_highlighted(true)
				card.is_interactable = true
		for card in opponent_grid.penalty_cards:
			card.set_highlighted(true)
			card.is_interactable = true
	
	# Wait for player to select a card (handled in handle_ability_target_selection)
	# The flow continues in confirm_ability_viewing() when SPACE is pressed

func execute_ability_blind_swap() -> void:
	"""Execute Jack ability: Blind swap with neighbor"""
	print("\n=== Ability: Blind Swap ===")
	table.turn_ui.update_action("Select YOUR card to swap")
	
	table.is_executing_ability = true
	table.current_ability = CardData.AbilityType.BLIND_SWAP
	
	var current_player_idx = GameManager.current_player_index
	var neighbors = table.view_helper.get_neighbors(current_player_idx)
	
	# Highlight own cards + penalty cards (cyan = your cards to swap)
	var own_grid = table.player_grids[current_player_idx]
	for i in range(4):
		var card = own_grid.get_card_at(i)
		if card:
			card.set_highlighted(true)
			card.is_interactable = true
	for card in own_grid.penalty_cards:
		card.set_highlighted(true)
		card.is_interactable = true
	
	# Highlight neighbor cards + penalty cards (cyan = neighbor cards to swap with)
	for neighbor_idx in neighbors:
		var neighbor_grid = table.player_grids[neighbor_idx]
		for i in range(4):
			var card = neighbor_grid.get_card_at(i)
			if card:
				card.set_highlighted(true)
				card.is_interactable = true
		for card in neighbor_grid.penalty_cards:
			card.set_highlighted(true)
			card.is_interactable = true

func execute_ability_look_and_swap() -> void:
	"""Execute Queen ability: Look at own card and neighbor card, then choose to swap"""
	print("\n=== Ability: Look and Swap ===")
	table.turn_ui.update_action("Select YOUR card to look at")
	
	table.is_executing_ability = true
	table.current_ability = CardData.AbilityType.LOOK_AND_SWAP
	
	var current_player_idx = GameManager.current_player_index
	var neighbors = table.view_helper.get_neighbors(current_player_idx)
	
	# Highlight own cards + penalty cards (cyan = your card to view)
	var own_grid = table.player_grids[current_player_idx]
	for i in range(4):
		var card = own_grid.get_card_at(i)
		if card:
			card.set_highlighted(true)
			card.is_interactable = true
	for card in own_grid.penalty_cards:
		card.set_highlighted(true)
		card.is_interactable = true
	
	# Highlight neighbor cards + penalty cards (cyan = neighbor card to view)
	for neighbor_idx in neighbors:
		var neighbor_grid = table.player_grids[neighbor_idx]
		for i in range(4):
			var card = neighbor_grid.get_card_at(i)
			if card:
				card.set_highlighted(true)
				card.is_interactable = true
		for card in neighbor_grid.penalty_cards:
			card.set_highlighted(true)
			card.is_interactable = true

func _on_swap_chosen() -> void:
	"""Called when player chooses to swap cards in Queen ability."""
	print("\n=== Swapping Cards ===")
	
	var card1 = table.look_and_swap_first_card
	var card2 = table.look_and_swap_second_card
	
	# Use the grid/slot references captured at selection time — avoids a re-search
	# failure if cards have since been moved to the viewing position.
	var card1_grid = table.look_and_swap_first_grid
	var card1_position = table.look_and_swap_first_slot           # -1 if penalty card
	var card1_penalty = table.look_and_swap_first_penalty_slot    # -1 if main-grid card
	var card2_grid = table.look_and_swap_second_grid
	var card2_position = table.look_and_swap_second_slot          # -1 if penalty card
	var card2_penalty = table.look_and_swap_second_penalty_slot   # -1 if main-grid card
	
	if not card1_grid or not card2_grid \
			or (card1_position == -1 and card1_penalty == -1) \
			or (card2_position == -1 and card2_penalty == -1):
		push_error("[Queen] _on_swap_chosen: missing grid refs (first=%s slot=%d pen=%d  second=%s slot=%d pen=%d)" % [
			str(card1_grid), card1_position, card1_penalty,
			str(card2_grid), card2_position, card2_penalty])
		_unlock_queen_ability()
		return
	
	# Get target positions — card1 goes to card2's old slot, card2 goes to card1's old slot
	var card1_target: Vector3 = _queen_slot_global_pos(card2_grid, card2_position, card2_penalty)
	var card2_target: Vector3 = _queen_slot_global_pos(card1_grid, card1_position, card1_penalty)
	
	# Flip cards back face-down first
	if card1.is_face_up:
		card1.flip(false, 0.3)
	if card2.is_face_up:
		card2.flip(false, 0.3)
	await get_tree().create_timer(0.35).timeout
	
	# Swap in grid arrays (update the correct array for each card)
	_queen_set_slot(card1_grid, card1_position, card1_penalty, card2)
	_queen_set_slot(card2_grid, card2_position, card2_penalty, card1)
	
	# Update owner_player references
	var temp_owner2 = card1.owner_player
	card1.owner_player = card2.owner_player
	card2.owner_player = temp_owner2
	
	# Animate both cards to their new positions
	card1.move_to(card1_target, 0.4, false)
	card2.move_to(card2_target, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Reparent cards to their new grids so they inherit the correct rotation.
	if card1.get_parent() != card2_grid:
		card1.get_parent().remove_child(card1)
		card2_grid.add_child(card1)
	card1.rotation = Vector3.ZERO
	card1.position = _queen_local_pos(card2_grid, card2_position, card2_penalty)
	card1.base_position = card2_target
	
	if card2.get_parent() != card1_grid:
		card2.get_parent().remove_child(card2)
		card1_grid.add_child(card2)
	card2.rotation = Vector3.ZERO
	card2.position = _queen_local_pos(card1_grid, card1_position, card1_penalty)
	card2.base_position = _queen_slot_global_pos(card1_grid, card1_position, card1_penalty)
	
	# Unhighlight all cards
	for grid in table.player_grids:
		for i in range(4):
			var c = grid.get_card_at(i)
			if c:
				c.set_highlighted(false)
				c.is_interactable = false
		for c in grid.penalty_cards:
			c.set_highlighted(false)
			c.is_interactable = false
	
	# Clean up
	_clear_queen_state()
	
	print("Swap complete!")
	
	# End turn
	table.turn_manager.end_current_turn()

func _on_no_swap_chosen() -> void:
	"""Called when player chooses NOT to swap cards in Queen ability"""
	print("\n=== Not Swapping - Returning Cards ===")
	
	var card1 = table.look_and_swap_first_card
	var card2 = table.look_and_swap_second_card
	var grid1 = table.look_and_swap_first_grid
	var slot1 = table.look_and_swap_first_slot
	var pen1 = table.look_and_swap_first_penalty_slot
	var grid2 = table.look_and_swap_second_grid
	var slot2 = table.look_and_swap_second_slot
	var pen2 = table.look_and_swap_second_penalty_slot
	
	# Flip cards back face-down first
	if card1.is_face_up:
		card1.flip(false, 0.3)
	if card2.is_face_up:
		card2.flip(false, 0.3)
	await get_tree().create_timer(0.35).timeout
	
	# Slide back to original grid slot positions
	card1.move_to(table.look_and_swap_first_original_pos, 0.4, false)
	card2.move_to(table.look_and_swap_second_original_pos, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Reparent cards back to their original grids so rotation is inherited correctly
	if grid1 and (slot1 != -1 or pen1 != -1):
		if card1.get_parent() != grid1:
			card1.get_parent().remove_child(card1)
			grid1.add_child(card1)
		card1.rotation = Vector3.ZERO
		card1.position = _queen_local_pos(grid1, slot1, pen1)
		card1.base_position = _queen_slot_global_pos(grid1, slot1, pen1)
	if grid2 and (slot2 != -1 or pen2 != -1):
		if card2.get_parent() != grid2:
			card2.get_parent().remove_child(card2)
			grid2.add_child(card2)
		card2.rotation = Vector3.ZERO
		card2.position = _queen_local_pos(grid2, slot2, pen2)
		card2.base_position = _queen_slot_global_pos(grid2, slot2, pen2)
	
	# Unlock elevation and lower cards
	card1.is_elevation_locked = false
	card2.is_elevation_locked = false
	card1.lower(0.2)
	card2.lower(0.2)
	await get_tree().create_timer(0.25).timeout
	
	# Unhighlight all cards
	for grid in table.player_grids:
		for i in range(4):
			var c = grid.get_card_at(i)
			if c:
				c.set_highlighted(false)
				c.is_interactable = false
		for c in grid.penalty_cards:
			c.set_highlighted(false)
			c.is_interactable = false
	
	# Clean up
	_clear_queen_state()
	
	print("Cards returned to original positions")
	
	# End turn
	table.turn_manager.end_current_turn()
