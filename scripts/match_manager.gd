extends Node
class_name MatchManager
## Handles the fast reaction matching system (Phase 6)
## Right-click matching, give card, penalty, and visual feedback

var table  # Reference to game_table

func init(game_table) -> void:
	table = game_table

func _unlock_matching() -> void:
	"""Called whenever a match attempt finishes (success or fail).
	NOTE: Does NOT touch is_choosing_give_card / give_card_target_player_idx.
	Those are managed exclusively by _handle_opponent_card_match (set) and
	handle_give_card_selection (clear)."""
	table.is_processing_match = false
	print("[Match] Match processing complete")

func on_card_right_clicked(card: Card3D) -> void:
	"""Right-click a card to attempt to match it against the current discard pile top card."""
	# Block during ability execution
	if table.is_executing_ability:
		return
	# Block while waiting for human to choose a give-card
	if table.is_choosing_give_card:
		return
	# Block before the game starts
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	# Block if currently resolving another match
	if table.is_processing_match:
		print("[Match] Already resolving a match")
		return
	# Need a card on the discard pile
	var top = table.deck_manager.peek_top_discard()
	if not top:
		print("[Match] No card on discard pile")
		return
	# Block if this discard card has already been claimed this round (no penalty!)
	if table.match_claimed:
		print("[Match] Too late — this card was already matched this round")
		return
	print("[Match] Right-click attempt: %s vs top discard %s" % [
		card.card_data.get_short_name(), top.get_short_name()])
	await _attempt_match(card)

func _attempt_match(card: Card3D) -> void:
	"""Attempt to match a right-clicked card against the top of the discard pile.
	The card always animates: lift → slide to discard → flip face-up (reveal).
	Outcome (success / fail) is determined after the reveal."""
	var top_discard = table.deck_manager.peek_top_discard()
	if not top_discard:
		return
	
	# Lock immediately so two simultaneous right-clicks can't both resolve
	table.is_processing_match = true
	
	# Determine outcome and owner BEFORE any animation (card still in grid)
	var matches = (card.card_data.rank == top_discard.rank)
	var owner_idx = table._find_card_owner_idx(card)
	
	# Guard: card must belong to someone (not a floating drawn card)
	if owner_idx == -1:
		table.is_processing_match = false
		return
	
	print("[Match] %s vs %s — %s" % [
		card.card_data.get_short_name(),
		top_discard.get_short_name(),
		"MATCH!" if matches else "no match"])
	
	# Save original location for snap-back on failure
	var original_parent = card.get_parent()
	var original_base_pos = card.base_position  # global rest position
	
	# STEP 1: Lift
	var lift_tween = card.create_tween()
	lift_tween.set_ease(Tween.EASE_OUT)
	lift_tween.tween_property(card, "global_position:y", card.global_position.y + 0.5, 0.1)
	await get_tree().create_timer(0.12).timeout
	
	# STEP 2: Reparent to table so global slide works cleanly
	var mid_global = card.global_position
	if card.get_parent() != table:
		card.get_parent().remove_child(card)
		table.add_child(card)
		card.global_position = mid_global
	
	# STEP 3: Slide toward discard pile (slightly above)
	var discard_above = table.discard_pile_marker.global_position + Vector3(0, 0.4, 0)
	card.move_to(discard_above, 0.25, false)
	await get_tree().create_timer(0.28).timeout
	
	# STEP 4: Flip face-up to reveal the card
	if not card.is_face_up:
		card.flip(true, 0.2)
	await get_tree().create_timer(0.3).timeout
	
	# STEP 5: Brief pause so player can see the card
	await get_tree().create_timer(0.15).timeout
	
	# STEP 6: Route based on outcome
	var is_own_card = (owner_idx == 0)
	if matches:
		if is_own_card:
			await _handle_own_card_match(card, owner_idx)
		else:
			await _handle_opponent_card_match(card, owner_idx)
	else:
		await _handle_failed_match(card, original_parent, original_base_pos)

func _handle_own_card_match(card: Card3D, owner_idx: int) -> void:
	"""Human matched one of their own cards — card is already at the discard hover position and face-up."""
	print("[Match] Own card match! Removing %s from Player %d's grid" % [
		card.card_data.get_short_name(), owner_idx + 1])
	# Claim the matching window so no one else can match this card this round
	table.match_claimed = true
	
	# Clear the grid slot (card already reparented to game_table in _attempt_match)
	var grid = table.player_grids[owner_idx]
	var found_in_main = false
	for i in range(4):
		if grid.get_card_at(i) == card:
			grid.cards[i] = null
			found_in_main = true
			break
	if not found_in_main:
		grid.remove_penalty_card(card)
	
	# Flash green to signal success
	_flash_card_color(card, Color(0.0, 1.0, 0.3), 0.4)
	
	# Slide down to final discard pile position
	card.move_to(table.discard_pile_marker.global_position, 0.2, false)
	await get_tree().create_timer(0.25).timeout
	
	# Register on discard and update visual
	table.deck_manager.add_to_discard(card.card_data)
	if table.discard_pile_visual:
		table.discard_pile_visual.set_count(table.deck_manager.discard_pile.size())
		table.discard_pile_visual.set_top_card(card.card_data)
	
	card.queue_free()
	print("[Match] Card removed from deck. Player %d now has %d valid cards." % [
		owner_idx + 1, grid.get_valid_cards().size()])
	
	# Unlock for the next match
	_unlock_matching()

func _handle_opponent_card_match(card: Card3D, card_owner_idx: int) -> void:
	"""Human grabbed an opponent's card and it matches — card is already at the discard hover position and face-up.
	Opponent's card goes to discard; human must then give one of their own cards to opponent."""
	print("[Match] Opponent card match! %s removed from Player %d's grid" % [
		card.card_data.get_short_name(), card_owner_idx + 1])
	# Claim the matching window so no one else can match this card this round
	table.match_claimed = true
	
	# Remove card from opponent's grid (card already reparented to game_table in _attempt_match)
	var opponent_grid = table.player_grids[card_owner_idx]
	var found_in_main = false
	for i in range(4):
		if opponent_grid.get_card_at(i) == card:
			opponent_grid.cards[i] = null
			found_in_main = true
			break
	if not found_in_main:
		opponent_grid.remove_penalty_card(card)
	
	# Flash green
	_flash_card_color(card, Color(0.0, 1.0, 0.3), 0.4)
	
	# Slide down to final discard pile position
	card.move_to(table.discard_pile_marker.global_position, 0.2, false)
	await get_tree().create_timer(0.25).timeout
	
	table.deck_manager.add_to_discard(card.card_data)
	if table.discard_pile_visual:
		table.discard_pile_visual.set_count(table.deck_manager.discard_pile.size())
		table.discard_pile_visual.set_top_card(card.card_data)
	card.queue_free()
	
	# Human must now pick one of their own cards to give to the opponent
	table.give_card_target_player_idx = card_owner_idx
	table.is_choosing_give_card = true
	_start_give_card_selection(card_owner_idx)

func _start_give_card_selection(target_idx: int) -> void:
	"""Highlight human player's own cards so they can pick one to give to the opponent."""
	print("[Match] Choose one of YOUR cards to give to Player %d" % (target_idx + 1))
	if table.turn_ui:
		table.turn_ui.update_action("Choose a card to give to Player %d!" % (target_idx + 1))
	
	var own_grid = table.player_grids[0]  # Human is always player 0
	for i in range(4):
		var c = own_grid.get_card_at(i)
		if c:
			c.set_highlighted(true)
			c.is_interactable = true
	# Also allow giving a penalty card
	for c in own_grid.penalty_cards:
		c.set_highlighted(true)
		c.is_interactable = true

func handle_give_card_selection(card: Card3D) -> void:
	"""Human selected one of their own cards to give to the opponent after a successful match."""
	# Verify the card belongs to the human player
	var owner_idx = table._find_card_owner_idx(card)
	if owner_idx != 0:
		print("[Match] Choose one of YOUR OWN cards to give!")
		return
	
	table.is_choosing_give_card = false
	var target_idx = table.give_card_target_player_idx
	table.give_card_target_player_idx = -1
	
	# Remove highlights from all own cards (main grid + penalty)
	var own_grid = table.player_grids[0]
	for i in range(4):
		var c = own_grid.get_card_at(i)
		if c:
			c.set_highlighted(false)
			c.is_interactable = false
	for c in own_grid.penalty_cards.duplicate():
		c.set_highlighted(false)
		c.is_interactable = false
	
	print("[Match] Giving %s to Player %d" % [card.card_data.get_short_name(), target_idx + 1])
	
	# Remove card from human's grid (check main grid and penalty slots)
	var found_in_main = false
	for i in range(4):
		if own_grid.get_card_at(i) == card:
			own_grid.cards[i] = null
			found_in_main = true
			break
	if not found_in_main:
		own_grid.remove_penalty_card(card)
	
	# Change ownership
	card.owner_player = table.players[target_idx]
	
	# Move card to opponent's penalty position
	var target_grid = table.player_grids[target_idx]
	
	# Detach from current parent before adding to target grid
	if card.get_parent() != null:
		card.get_parent().remove_child(card)
	target_grid.add_penalty_card(card, true)
	await get_tree().create_timer(0.5).timeout
	
	print("[Match] Player %d gave card to Player %d. Match complete!" % [1, target_idx + 1])
	
	# Unlock matching for the next discard event
	_unlock_matching()
	
	# If the turn-start was deferred while waiting for this give-card selection,
	# now properly start the pending turn.
	if table.give_card_needs_turn_start:
		table.give_card_needs_turn_start = false
		await get_tree().create_timer(0.3).timeout
		table.turn_manager.start_next_turn()
	elif table.is_player_turn and table.turn_ui:
		# Give-card happened during the human's own turn — restore the correct UI message
		# and re-enable the appropriate interaction state.
		if table.drawn_card:
			# Human already drew — restore the swap-step state
			table.turn_ui.update_action("Click your card to swap, OR click discard pile to use ability")
			# Re-enable human grid cards for swapping (give-card cleanup disabled them all)
			var grid = table.player_grids[0]
			for i in range(4):
				var c = grid.get_card_at(i)
				if c and c != table.drawn_card:
					c.is_interactable = true
			for pc in grid.penalty_cards:
				if pc != table.drawn_card:
					pc.is_interactable = true
		else:
			# Human hasn't drawn yet — restore the draw-step state
			table.turn_ui.update_action("Press D to draw a card or click draw pile")

func _handle_failed_match(card: Card3D, original_parent: Node3D, original_base_pos: Vector3) -> void:
	"""Card didn't match — red flash + shake above the discard pile, THEN snap back face-down, then penalty.
	Card arrives here already at the discard hover position and face-up."""
	print("[Match] Failed match! %s; returning card and issuing penalty." % card.card_data.get_short_name())
	
	# Brief pause so player sees the revealed (wrong) card
	await get_tree().create_timer(0.2).timeout
	
	# Red flash + shake WHILE still above the discard pile (so the "punishment" is visible there)
	await _shake_card(card, 0.35)
	
	# Brief beat after shake before returning
	await get_tree().create_timer(0.1).timeout
	
	# Slide back toward original grid slot (slightly elevated)
	var return_above = original_base_pos + Vector3(0, 0.4, 0)
	card.move_to(return_above, 0.3, false)
	await get_tree().create_timer(0.33).timeout
	
	# Reparent back to original grid with explicit rotation reset
	if card.get_parent() != original_parent:
		card.get_parent().remove_child(card)
		original_parent.add_child(card)
	card.rotation = Vector3.ZERO
	card.position = original_parent.to_local(original_base_pos) + Vector3(0, 0.4, 0)  # keep elevated
	card.base_position = original_base_pos
	
	# Flip face-down again
	card.flip(true, 0.2)
	await get_tree().create_timer(0.12).timeout
	
	# Lower to resting position
	card.move_to(original_base_pos, 0.2, false)
	await get_tree().create_timer(0.25).timeout
	
	# Give human player a penalty card
	await _give_penalty_card(0)
	
	# Re-unlock matching
	_unlock_matching()

func _give_penalty_card(player_idx: int) -> void:
	"""Draw a card from the draw pile, animate it flying to the penalty slot, then add it."""
	print("[Match] Giving penalty card to Player %d" % (player_idx + 1))
	
	# Reshuffle if needed
	if table.deck_manager.can_reshuffle():
		await table.turn_manager.animate_pile_reshuffle()
	
	var penalty_data = table.deck_manager.deal_card()
	if not penalty_data:
		print("[Match] No cards left for penalty!")
		return
	
	# Create card at the draw pile (child of game_table for the flight animation)
	var penalty_card = table.card_scene.instantiate()
	table.add_child(penalty_card)
	penalty_card.global_position = table.draw_pile_marker.global_position
	penalty_card.initialize(penalty_data, false)
	penalty_card.card_clicked.connect(table._on_card_clicked)
	penalty_card.card_right_clicked.connect(table._on_card_right_clicked)
	penalty_card.owner_player = table.players[player_idx]
	
	# Update draw pile visual immediately
	if table.draw_pile_visual:
		table.draw_pile_visual.set_count(table.deck_manager.get_draw_pile_count())
	
	# Compute the target penalty slot position BEFORE adding to grid
	# (penalty_cards.size() tells us the next free slot index)
	var grid = table.player_grids[player_idx]
	var target_slot = mini(grid.penalty_cards.size(), grid.penalty_positions.size() - 1)
	var target_global = grid.to_global(grid.penalty_positions[target_slot])
	
	# Animate: fly from draw pile to penalty slot position
	penalty_card.move_to(target_global, 0.5, false)
	await get_tree().create_timer(0.55).timeout
	
	# Reparent from game_table to the player's grid
	# add_penalty_card with animate=false will snap to the correct local position
	if penalty_card.get_parent():
		penalty_card.get_parent().remove_child(penalty_card)
	grid.add_penalty_card(penalty_card, false)
	
	print("[Match] Player %d now has %d penalty cards" % [player_idx + 1, grid.get_penalty_count()])

func _flash_card_color(card: Card3D, color: Color, duration: float) -> void:
	"""Flash a card mesh with a given color overlay (visual feedback)."""
	var flash_mesh = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(0.64, 0.89)
	flash_mesh.mesh = quad
	flash_mesh.rotation_degrees = Vector3(-90, 0, 0)
	flash_mesh.position = Vector3(0, 0.008, 0)
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.6)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash_mesh.material_override = mat
	card.add_child(flash_mesh)
	
	var tween = create_tween()
	tween.tween_property(flash_mesh, "material_override:albedo_color:a", 0.0, duration)
	tween.tween_callback(flash_mesh.queue_free)

func _shake_card(card: Card3D, duration: float) -> void:
	"""Red flash + horizontal shake to signal a failed match."""
	_flash_card_color(card, Color(1.0, 0.1, 0.1), duration)
	
	var origin = card.global_position
	var tween = card.create_tween()
	var shake_amount := 0.12
	var steps := 6
	var step_time := duration / steps
	for i in range(steps):
		var dir = shake_amount if i % 2 == 0 else -shake_amount
		tween.tween_property(card, "global_position:x", origin.x + dir, step_time)
	tween.tween_property(card, "global_position:x", origin.x, step_time * 0.5)
	await get_tree().create_timer(duration + step_time * 0.5).timeout
