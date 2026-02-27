extends Node
class_name KnockManager
## Handles the knock action, final round tracking, round-end card reveal,
## and the 3D knock buttons placed on the table near each player grid.

var table  # Reference to game_table

# 3D knock buttons — one per player, indexed by player_id
var knock_buttons: Array[KnockButton3D] = []

# Global offsets from each player-grid origin to place the button "in front"
# (between the grid and the nearest table edge, past all penalty card slots).
const BUTTON_OFFSETS = [
	Vector3(0, 0, 2.2),     # Player 0 (South): +z toward south edge
	Vector3(0, 0, -2.2),    # Player 1 (North): -z toward north edge
	Vector3(-1.8, 0, 0),    # Player 2 (West): -x toward west edge
	Vector3(1.8, 0, 0),     # Player 3 (East): +x toward east edge
]

# Y-rotation for each button so "KNOCK" text faces the player
const BUTTON_ROTATIONS = [
	0.0,         # Player 0: no rotation (text readable from south)
	PI,          # Player 1: 180° (readable from north)
	PI / 2.0,    # Player 2: 90° (readable from west)
	-PI / 2.0,   # Player 3: -90° (readable from east)
]

func init(game_table) -> void:
	table = game_table


# ======================================
# BUTTON CREATION & LIFECYCLE
# ======================================

func create_buttons() -> void:
	"""Create one KnockButton3D per player and add it to the table.
	Call this once after player grids are set up."""
	# Clean up any existing buttons
	for btn in knock_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	knock_buttons.clear()

	for i in range(table.player_grids.size()):
		var btn = KnockButton3D.new()
		btn.player_id = i

		btn.button_pressed.connect(_on_button_pressed)
		table.add_child(btn)

		# Position in global space (must be in tree first)
		var grid_pos: Vector3 = table.player_grids[i].global_position
		var offset: Vector3 = BUTTON_OFFSETS[i] if i < BUTTON_OFFSETS.size() else Vector3.ZERO
		btn.global_position = grid_pos + offset

		# Rotation so label faces the player
		btn.rotation.y = BUTTON_ROTATIONS[i] if i < BUTTON_ROTATIONS.size() else 0.0

		knock_buttons.append(btn)

	print("KnockManager: Created %d 3D knock buttons" % knock_buttons.size())


func show_button_for(player_id: int) -> void:
	"""Show only the button belonging to *player_id*, hide all others."""
	for btn in knock_buttons:
		if is_instance_valid(btn):
			if btn.player_id == player_id:
				btn.show_button()
			else:
				btn.hide_button()


func hide_all_buttons() -> void:
	"""Hide every knock button."""
	for btn in knock_buttons:
		if is_instance_valid(btn):
			btn.hide_button()


func get_button(player_id: int) -> KnockButton3D:
	"""Return the button for a specific player (or null)."""
	for btn in knock_buttons:
		if btn.player_id == player_id:
			return btn
	return null


func _on_button_pressed(player_id: int) -> void:
	"""A knock button was pressed (by human click or bot simulate_press)."""
	hide_all_buttons()
	perform_knock(player_id)


# ======================================
# KNOCK ACTION
# ======================================

func perform_knock(player_id: int) -> void:
	"""Execute a knock for the given player. This IS their entire turn."""
	var player = table.players[player_id]
	print("\n=== %s KNOCKS! ===" % player.player_name)
	player.has_knocked = true
	
	# Announce knock via GameManager (sets state to KNOCKED, builds final-turn list)
	GameManager.player_knock(player_id)
	
	# Update UI
	table.turn_ui.update_action("%s knocked! Final round begins." % player.player_name)
	
	# Brief pause so the announcement is visible
	await get_tree().create_timer(1.5).timeout
	
	# Advance to next player's turn (final round)
	table.turn_manager.end_current_turn()

# ======================================
# ROUND END — REVEAL ALL CARDS
# ======================================

func reveal_all_cards() -> void:
	"""Flip every card on the table face-up with a staggered animation."""
	print("\n=== ROUND END — Revealing All Cards ===")
	
	# Disable all interaction
	table.is_player_turn = false
	if table.draw_pile_visual:
		table.draw_pile_visual.set_interactive(false)
	if table.discard_pile_visual:
		table.discard_pile_visual.set_interactive(false)
	
	for grid in table.player_grids:
		for i in range(4):
			var card = grid.get_card_at(i)
			if card:
				card.is_interactable = false
		for c in grid.penalty_cards:
			c.is_interactable = false
	
	# Build reveal order starting from the knocker
	var total_players = table.player_grids.size()
	var start_idx = GameManager.knocker_id if GameManager.knocker_id >= 0 else 0
	var reveal_order: Array[int] = []
	for i in range(total_players):
		reveal_order.append((start_idx + i) % total_players)
	
	# Staggered reveal per player, per card
	for grid_idx in reveal_order:
		var grid = table.player_grids[grid_idx]
		# Main grid cards
		for i in range(4):
			var card = grid.get_card_at(i)
			if card and not card.is_face_up:
				card.flip(true, 0.3)
				_spawn_score_label(card)
				await get_tree().create_timer(0.15).timeout
		# Penalty cards
		for card in grid.penalty_cards:
			if card and not card.is_face_up:
				card.flip(true, 0.3)
				_spawn_score_label(card)
				await get_tree().create_timer(0.15).timeout
		# Short gap between players
		await get_tree().create_timer(0.3).timeout
	
	Events.all_cards_revealed.emit()
	print("All cards revealed!")


# ======================================
# SCORE LABELS — floating "+N" / "−N" per card
# ======================================

func _spawn_score_label(card: Card3D) -> void:
	"""Create a floating Label3D above the card showing its point value.
	The label drifts upward and fades out, then self-destructs."""
	if not card or not card.card_data:
		return

	var score: int = card.card_data.get_score()

	# Build text with explicit sign
	var text: String
	if score < 0:
		text = "%d" % score          # already has minus sign
	else:
		text = "+%d" % score

	# Pick colour — green for low/negative, white for neutral, red for high
	var color: Color
	if score <= 0:
		color = Color(0.2, 1.0, 0.3)   # Green
	elif score <= 5:
		color = Color(1.0, 1.0, 1.0)   # White
	elif score <= 12:
		color = Color(1.0, 0.7, 0.2)   # Orange
	else:
		color = Color(1.0, 0.2, 0.2)   # Red (Kings +25)

	var lbl = Label3D.new()
	lbl.text = text
	lbl.font_size = 64
	lbl.pixel_size = 0.004
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # Always face camera
	lbl.no_depth_test = true          # Render on top
	lbl.modulate = Color(color.r, color.g, color.b, 1.0)
	lbl.outline_size = 12
	lbl.outline_modulate = Color(0, 0, 0, 0.8)

	# Add to tree first, then set global position
	table.add_child(lbl)
	lbl.global_position = card.global_position + Vector3(0, 0.6, 0)

	# Animate: float up + fade out, then remove
	var tween = table.create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "global_position:y", lbl.global_position.y + 0.8, 1.2)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.2)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(false)
	tween.tween_callback(lbl.queue_free)
