extends Node
class_name TurnManager
## Manages turn flow, card drawing, swapping, discard, and pile reshuffling

var table  # Reference to game_table

func init(game_table) -> void:
	table = game_table

# ======================================
# PHASE 4: TURN SYSTEM
# ======================================

func start_next_turn() -> void:
	"""Start the next player's turn"""
	var current_player_id = GameManager.current_player_index
	var current_player = GameManager.get_current_player()
	
	if not current_player:
		print("Error: No current player!")
		return
	
	# If game state is ROUND_END, don't start a new turn
	if GameManager.current_state == GameManager.GameState.ROUND_END:
		return
	
	# Lock out all input immediately so nothing fires during the reshuffle animation
	table.is_player_turn = false
	if table.draw_pile_visual:
		table.draw_pile_visual.set_interactive(false)
	
	# Hide knock buttons by default (shown explicitly for human turns in PLAYING state)
	table.knock_manager.hide_all_buttons()
	
	# If draw pile is empty, perform the reshuffle WITH animation BEFORE the turn begins
	if table.deck_manager.can_reshuffle():
		await animate_pile_reshuffle()
	
	print("\n=== Turn %d: %s ===" % [current_player_id + 1, current_player.player_name])
	
	# Check if this is player 1 (human) or a bot
	table.is_player_turn = (current_player_id == 0)
	
	# Update turn UI
	table.turn_ui.show_turn(current_player_id, current_player.player_name, table.is_player_turn)
	
	# Reset turn variables
	table.selected_card = null
	table.drawn_card = null
	table.is_drawing = false
	table.is_executing_ability = false
	table.current_ability = CardData.AbilityType.NONE
	table.ability_target_card = null
	table.awaiting_ability_confirmation = false
	table.blind_swap_first_card = null
	table.blind_swap_second_card = null
	table.give_card_needs_turn_start = false
	
	# Disable discard pile interaction at turn start
	if table.discard_pile_visual:
		table.discard_pile_visual.set_interactive(false)
	
	# Disable left-click on all grid cards at turn start.
	# Hover and right-click matching work independently (gated in card_3d.gd by is_animating,
	# not by is_interactable), so this only prevents accidental swap/ability clicks.
	# Left-click is re-enabled after drawing in handle_draw_card().
	for grid in table.player_grids:
		for i in range(4):
			var card = grid.get_card_at(i)
			if card:
				card.is_interactable = false
		for c in grid.penalty_cards:
			c.is_interactable = false
	
	# If a give-card selection was started during a previous turn's match (e.g. the human
	# matched an opponent's card while it was the opponent's turn, and the turn then advanced
	# before the human selected which card to give), restore that selection now and skip
	# the normal turn-start flow until the human picks a card.
	if table.is_choosing_give_card:
		if table.draw_pile_visual:
			table.draw_pile_visual.set_interactive(false)
		if table.discard_pile_visual:
			table.discard_pile_visual.set_interactive(false)
		table.give_card_needs_turn_start = true
		table.match_manager._start_give_card_selection(table.give_card_target_player_idx)
		return
	
	if table.is_player_turn:
		# Human player's turn - wait for input
		print("Your turn! Press D to draw a card")
		
		# Show knock button only in PLAYING state (not during final round after someone knocked)
		if GameManager.current_state == GameManager.GameState.PLAYING:
			table.turn_ui.update_action("Press D to draw a card, click draw pile, or KNOCK")
			table.knock_manager.show_button_for(0)  # Player 0 = human
		else:
			table.turn_ui.update_action("Press D to draw a card or click draw pile")
		
		# Enable draw pile interaction for human player
		if table.draw_pile_visual:
			table.draw_pile_visual.set_interactive(true)
	else:
		# Bot turn - auto-play
		print("%s (Bot) is thinking..." % current_player.player_name)
		# Show knock button for the bot in PLAYING state (bot_ai will simulate_press if it decides to knock)
		if GameManager.current_state == GameManager.GameState.PLAYING:
			table.knock_manager.show_button_for(current_player_id)
		# Disable draw pile for bots
		if table.draw_pile_visual:
			table.draw_pile_visual.set_interactive(false)
		await get_tree().create_timer(1.0).timeout
		table.bot_ai_manager.execute_bot_turn(current_player_id)

func handle_card_selection(card: Card3D) -> void:
	"""Handle player selecting a card during their turn"""
	if not table.is_player_turn:
		print("Not your turn!")
		return
	
	# Handle ability target selection
	if table.is_executing_ability:
		table.ability_manager.handle_ability_target_selection(card)
		return
	
	# Must draw a card first
	if not table.drawn_card:
		print("Draw a card first! Press D")
		return
	
	# Can only select cards from your own grid (main grid or penalty cards)
	var current_grid = table.player_grids[GameManager.current_player_index]
	var is_own_card := false
	for i in range(4):
		if current_grid.get_card_at(i) == card:
			is_own_card = true
			break
	if not is_own_card:
		for pc in current_grid.penalty_cards:
			if pc == card:
				is_own_card = true
				break
	if not is_own_card:
		print("That's not your card!")
		return
	
	# Disable discard pile interaction
	if table.discard_pile_visual:
		table.discard_pile_visual.set_interactive(false)
	
	# Execute swap immediately
	await swap_cards(card, table.drawn_card)

func handle_draw_card() -> void:
	"""Handle drawing a card (async wrapper for input handler)"""
	table.is_drawing = true
	table.drawn_card = await draw_card_from_pile()
	table.is_drawing = false
	if table.drawn_card:
		# Disable draw pile interaction (already drew)
		if table.draw_pile_visual:
			table.draw_pile_visual.set_interactive(false)
		
		# Enable discard pile interaction
		if table.discard_pile_visual:
			table.discard_pile_visual.set_interactive(true)
		
		# Enable current player's cards for swapping (main grid + penalty cards)
		var current_player_id = GameManager.current_player_index
		if current_player_id < table.player_grids.size():
			var grid = table.player_grids[current_player_id]
			for i in range(4):
				var card = grid.get_card_at(i)
				if card and card != table.drawn_card:
					card.is_interactable = true
			for pc in grid.penalty_cards:
				if pc != table.drawn_card:
					pc.is_interactable = true
		
		table.turn_ui.update_action("Click your card to swap, OR click discard pile to use ability")

func draw_card_from_pile() -> Card3D:
	"""Draw a card from the draw pile"""
	var card_data = table.deck_manager.deal_card()
	if not card_data:
		print("Draw pile is empty!")
		return null
	
	# Create the card at the top of the draw pile stack
	var card = table.card_scene.instantiate()
	table.add_child(card)
	var top_offset = Vector3(0, table.draw_pile_visual.card_count * 0.01, 0) if table.draw_pile_visual else Vector3.ZERO
	card.global_position = table.draw_pile_marker.global_position + top_offset
	card.initialize(card_data, false)  # Start face down
	card.is_interactable = false  # Can't interact with drawn card directly
	
	print("Drew card: %s" % card_data.get_short_name())
	
	# Get the current player's grid position for positioning the card
	var current_player_id = GameManager.current_player_index
	var current_grid = table.player_grids[current_player_id] if current_player_id < table.player_grids.size() else null
	
	if not current_grid:
		return card
	
	# Calculate view position using helper function
	var view_position = table.view_helper.get_card_view_position()
	
	# Animate card to view position (smooth glide)
	card.move_to(view_position, 0.6, false)
	
	# Set global rotation to face current player
	var view_rotation = table.view_helper.get_card_view_rotation()
	card.global_rotation = Vector3(0, view_rotation, 0)
	
	# Wait for movement
	await get_tree().create_timer(0.65).timeout
	
	# Flip face-up
	if not card.is_face_up:
		card.flip(true, 0.35)
		# Wait for flip animation
		await get_tree().create_timer(0.4).timeout
	else:
		# Card already face-up, wait same time for consistency
		await get_tree().create_timer(0.35).timeout
	
	# Tilt the card towards the player (steep for bots to hide front from human camera)
	var is_bot_turn: bool = (current_player_id != 0)
	table.view_helper.tilt_card_towards_viewer(card, is_bot_turn)
	await get_tree().create_timer(0.25).timeout
	
	# Update pile visual
	if table.draw_pile_visual:
		table.draw_pile_visual.set_count(table.deck_manager.get_draw_pile_count())
	
	return card

# ======================================
# PHASE 5: ABILITIES (discard entry point)
# ======================================

func play_card_to_discard(card: Card3D) -> void:
	"""Play drawn card to discard pile and activate ability if present"""
	print("Playing %s to discard pile" % card.card_data.get_short_name())
	
	# Ensure card is face-up
	if not card.is_face_up:
		card.flip(true, 0.2)
		await get_tree().create_timer(0.25).timeout
	
	# Reset rotation
	card.rotation = Vector3.ZERO
	
	# Animate to discard pile
	card.move_to(table.discard_pile_marker.global_position, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Add to discard pile data
	table.deck_manager.add_to_discard(card.card_data)
	table.match_claimed = false  # New card from draw pile — open a fresh matching window
	table.match_manager._unlock_matching()
	
	# Update visual
	if table.discard_pile_visual:
		table.discard_pile_visual.set_count(table.deck_manager.discard_pile.size())
		table.discard_pile_visual.set_top_card(card.card_data)
	
	# Clean up the card
	card.queue_free()
	table.drawn_card = null
	
	# Check for ability
	var ability = card.card_data.get_ability()
	if ability == CardData.AbilityType.LOOK_OWN:  # 7 or 8
		await table.ability_manager.execute_ability_look_own()
	elif ability == CardData.AbilityType.LOOK_OPPONENT:  # 9 or 10
		await table.ability_manager.execute_ability_look_opponent()
	elif ability == CardData.AbilityType.BLIND_SWAP:  # Jack
		await table.ability_manager.execute_ability_blind_swap()
	elif ability == CardData.AbilityType.LOOK_AND_SWAP:  # Queen
		await table.ability_manager.execute_ability_look_and_swap()
	else:
		print("No ability on this card")
		end_current_turn()

func swap_cards(grid_card: Card3D, new_card: Card3D) -> void:
	"""Swap a card in the grid with the drawn card"""
	var grid = table.player_grids[GameManager.current_player_index]
	
	# === IMMEDIATELY LOCK OUT ALL INTERACTION ===
	# Null drawn_card so handle_card_selection cannot re-enter swap_cards
	# during any await below (it checks "if not table.drawn_card: return").
	table.drawn_card = null
	# Disable every card belonging to the current player (main grid + penalty)
	for i in range(4):
		var c = grid.get_card_at(i)
		if c:
			c.is_interactable = false
	for c in grid.penalty_cards:
		c.is_interactable = false
	# Disable pile interaction
	if table.discard_pile_visual:
		table.discard_pile_visual.set_interactive(false)
	
	# Check main grid slots first
	var card_position = -1
	for i in range(4):
		if grid.get_card_at(i) == grid_card:
			card_position = i
			break
	
	# If not in main grid, check penalty slots
	if card_position == -1:
		var penalty_idx = grid.penalty_cards.find(grid_card)
		if penalty_idx != -1:
			# === PENALTY CARD SWAP ===
			print("Swapping penalty card %s with %s" % [grid_card.card_data.get_short_name(), new_card.card_data.get_short_name()])
			var discarded_card_data = grid_card.card_data
			
			# Remember the exact slot so the drawn card goes back to the same position.
			var swap_slot: int = penalty_idx
			
			# Save global position before detaching from grid
			var saved_global_pos = grid_card.global_position
			
			# Remove penalty card from grid tracking (also detaches from grid node)
			grid.remove_penalty_card(grid_card)
			table.deck_manager.add_to_discard(grid_card.card_data)
			
			# Re-parent to table so it stays in the scene tree for animation
			table.add_child(grid_card)
			grid_card.global_position = saved_global_pos  # Restore position to prevent jump
			
			# Flip the penalty card face-up and slide to discard pile
			if not grid_card.is_face_up:
				grid_card.flip(true, 0.2)
				await get_tree().create_timer(0.25).timeout
			grid_card.move_to(table.discard_pile_marker.global_position, 0.3, false)
			await get_tree().create_timer(0.35).timeout
			grid_card.queue_free()
			
			# Insert drawn card back at the exact slot that was freed.
			new_card.owner_player = table.players[GameManager.current_player_index]
			new_card.is_interactable = true
			if not new_card.card_clicked.is_connected(table._on_card_clicked):
				new_card.card_clicked.connect(table._on_card_clicked)
			if not new_card.card_right_clicked.is_connected(table._on_card_right_clicked):
				new_card.card_right_clicked.connect(table._on_card_right_clicked)
			if new_card.get_parent():
				new_card.get_parent().remove_child(new_card)
			grid.insert_penalty_card_at(new_card, swap_slot, true)
			await get_tree().create_timer(0.45).timeout
			
			# Flip drawn card face-down in its new penalty slot
			if new_card.is_face_up:
				new_card.flip(true, 0.3)
			
			if table.discard_pile_visual:
				table.discard_pile_visual.set_count(table.deck_manager.discard_pile.size())
				table.discard_pile_visual.set_top_card(discarded_card_data)
			
			# Open matching window now that the swap is fully done
			table.match_claimed = false
			table.match_manager._unlock_matching()
			
			print("Penalty swap complete!")
			end_current_turn()
			return
		else:
			print("Error: Card not found in grid!")
			print("Card clicked: %s" % grid_card.card_data.get_short_name())
			return
	
	print("Swapping %s with %s" % [grid_card.card_data.get_short_name(), new_card.card_data.get_short_name()])
	
	# Save card data before freeing (needed for discard pile visual)
	var discarded_card_data = grid_card.card_data
	
	# Remove old card from grid
	grid.cards[card_position] = null
	table.deck_manager.add_to_discard(grid_card.card_data)
	
	# Flip card face-up if not already
	if not grid_card.is_face_up:
		grid_card.flip(true, 0.2)
		await get_tree().create_timer(0.25).timeout
	
	# Animate old card to discard pile
	grid_card.move_to(table.discard_pile_marker.global_position, 0.3, false)
	await get_tree().create_timer(0.3).timeout
	grid_card.queue_free()
	
	# Add new card to grid using proper method (sets owner_player correctly)
	new_card.is_interactable = true
	# Connect signals (avoid double-connect — check first)
	if not new_card.card_clicked.is_connected(table._on_card_clicked):
		new_card.card_clicked.connect(table._on_card_clicked)
	if not new_card.card_right_clicked.is_connected(table._on_card_right_clicked):
		new_card.card_right_clicked.connect(table._on_card_right_clicked)
	
	# Reparent new card first
	if new_card.get_parent():
		new_card.get_parent().remove_child(new_card)
	
	# Use grid.add_card() which properly sets owner_player and rotation
	grid.add_card(new_card, card_position, true)
	await get_tree().create_timer(0.35).timeout
	
	# Flip face down if needed
	if new_card.is_face_up:
		new_card.flip(true, 0.3)  # Flip to face down
	
	# Update discard pile visual (use saved card data)
	if table.discard_pile_visual:
		table.discard_pile_visual.set_count(table.deck_manager.discard_pile.size())
		table.discard_pile_visual.set_top_card(discarded_card_data)
	
	# Open matching window now that the swap is fully done
	table.match_claimed = false
	table.match_manager._unlock_matching()
	
	print("Swap complete!")
	
	# End turn
	end_current_turn()

# ======================================
# TURN END
# ======================================

func end_current_turn() -> void:
	"""End the current turn and move to next player"""
	print("Turn ended\n")
	
	# Clean up
	table.selected_card = null
	table.drawn_card = null
	table.is_drawing = false
	table.is_executing_ability = false
	table.current_ability = CardData.AbilityType.NONE
	table.ability_target_card = null
	table.awaiting_ability_confirmation = false
	
	# Disable discard pile interaction
	if table.discard_pile_visual:
		table.discard_pile_visual.set_interactive(false)
	
	# Hide knock buttons
	table.knock_manager.hide_all_buttons()
	
	# Move to next turn (GameManager.next_turn handles KNOCKED → ROUND_END transition)
	GameManager.next_turn()
	
	# If round ended, don't start a new turn (the state change callback handles it)
	if GameManager.current_state == GameManager.GameState.ROUND_END:
		return
	
	await get_tree().create_timer(0.5).timeout
	start_next_turn()

# ======================================
# PILE RESHUFFLE ANIMATION
# ======================================

func _on_pile_reshuffled(_card_count: int) -> void:
	pass  # Reshuffle is handled proactively by animate_pile_reshuffle() in start_next_turn()

func animate_pile_reshuffle() -> void:
	"""Perform + animate the discard→draw transfer with a dramatic arc effect.
	The newest top-of-discard card stays (unless it is the only card, in which case
	it also transfers and the discard becomes temporarily empty)."""
	var count = table.deck_manager.perform_reshuffle()
	if count == 0:
		return
	
	print("=== RESHUFFLE: %d cards arc from discard to draw pile ===" % count)
	
	var discard_pos = table.discard_pile_marker.global_position
	var draw_pos = table.draw_pile_marker.global_position
	var arc_peak = (discard_pos + draw_pos) / 2.0 + Vector3(0, 2.0, 0)
	
	# Update discard visual to reflect actual post-reshuffle state
	if table.discard_pile_visual:
		var remaining = table.deck_manager.get_discard_pile_count()
		table.discard_pile_visual.set_count(remaining)
		table.discard_pile_visual.set_top_card(table.deck_manager.peek_top_discard())
	
	# Spawn ghost cards that arc from discard to draw pile
	var visual_count = mini(count, 10)
	var stagger := 0.07
	
	for i in range(visual_count):
		var ghost := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.64, 0.025, 0.89)
		ghost.mesh = mesh
		
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.35, 0.95)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.65, 1.0)
		mat.emission_energy = 2.0
		ghost.material_override = mat
		table.add_child(ghost)
		
		var jitter := Vector3(randf_range(-0.06, 0.06), 0.0, randf_range(-0.06, 0.06))
		ghost.global_position = discard_pos + jitter + Vector3(0, 0.025 * (i + 1), 0)
		ghost.rotation = Vector3(0, randf_range(-0.3, 0.3), 0)
		
		# Two-leg tween: rise to arc peak, then drop to draw pile
		var tween := create_tween()
		tween.tween_interval(i * stagger)
		tween.tween_property(ghost, "global_position", arc_peak + jitter, 0.28) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(ghost, "global_position",
			draw_pos + jitter + Vector3(0, 0.025 * (i + 1), 0), 0.26) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(ghost.queue_free)
	
	# Wait for all card arcs to finish, plus a short settle pause
	var total_time: float = (visual_count * stagger) + 0.28 + 0.26 + 0.25
	await get_tree().create_timer(total_time).timeout
	
	# Update draw pile visual to final count
	if table.draw_pile_visual:
		table.draw_pile_visual.set_count(table.deck_manager.get_draw_pile_count())
	
	print("Reshuffle complete. Draw pile: %d  Discard: %d" % [
		table.deck_manager.get_draw_pile_count(),
		table.deck_manager.get_discard_pile_count()])
