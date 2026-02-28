extends Node3D
class_name PlayerGrid
## Manages a player's 2x2 grid of cards
## Handles card placement, retrieval, and visual layout

@export var player_id: int = 0
@export var grid_spacing: float = 1.0

var cards: Array[Card3D] = [null, null, null, null]  # 4 card slots
var penalty_cards: Array[Card3D] = []  # Overflow penalty cards (Phase 6)
var penalty_placeholders: Array[Node3D] = []  # White outline borders for each penalty slot
var card_positions: Array[Vector3] = []
var penalty_positions: Array[Vector3] = []  # Positions around the 2×2 grid
var placeholder_meshes: Array[Node3D] = []  # Frame containers
var base_rotation_y: float = 0.0  # Y-axis rotation for cards in this grid

# Position markers for 2x2 grid
@onready var position_markers = $PositionMarkers

func _ready() -> void:
	setup_grid_positions()
	create_placeholders()
	print("PlayerGrid %d initialized" % player_id)

func create_placeholders() -> void:
	"""Create background placeholder borders for each card position"""
	var width = 0.75
	var height = 1.05
	var border = 0.03  # Border thickness

	# White material — raised Y offset eliminates Z-fighting flicker
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.5
	mat.render_priority = 1

	for i in range(4):
		var container = Node3D.new()

		# Top border (full width)
		var top = MeshInstance3D.new()
		var top_mesh = QuadMesh.new()
		top_mesh.size = Vector2(width, border)
		top.mesh = top_mesh
		top.material_override = mat
		top.rotation_degrees = Vector3(-90, 0, 0)
		top.position = Vector3(0, 0.02, -height/2)
		container.add_child(top)

		# Bottom border (full width)
		var bottom = MeshInstance3D.new()
		var bottom_mesh = QuadMesh.new()
		bottom_mesh.size = Vector2(width, border)
		bottom.mesh = bottom_mesh
		bottom.material_override = mat
		bottom.rotation_degrees = Vector3(-90, 0, 0)
		bottom.position = Vector3(0, 0.02, height/2)
		container.add_child(bottom)

		# Left border (inner height)
		var left = MeshInstance3D.new()
		var left_mesh = QuadMesh.new()
		left_mesh.size = Vector2(border, height - 2 * border)
		left.mesh = left_mesh
		left.material_override = mat
		left.rotation_degrees = Vector3(-90, 0, 0)
		left.position = Vector3(-width/2, 0.02, 0)
		container.add_child(left)

		# Right border (inner height)
		var right = MeshInstance3D.new()
		var right_mesh = QuadMesh.new()
		right_mesh.size = Vector2(border, height - 2 * border)
		right.mesh = right_mesh
		right.material_override = mat
		right.rotation_degrees = Vector3(-90, 0, 0)
		right.position = Vector3(width/2, 0.02, 0)
		container.add_child(right)

		# Position at card slot
		container.position = card_positions[i]

		add_child(container)
		placeholder_meshes.append(container)

func setup_grid_positions() -> void:
	"""Calculate positions for 2x2 card grid and surrounding penalty slots"""
	card_positions.clear()
	penalty_positions.clear()
	
	var offset = grid_spacing / 2.0
	
	# 2x2 grid layout (top-left, top-right, bottom-left, bottom-right)
	card_positions.append(Vector3(-offset, 0, -offset))  # 0: Top-left
	card_positions.append(Vector3(offset, 0, -offset))   # 1: Top-right
	card_positions.append(Vector3(-offset, 0, offset))   # 2: Bottom-left
	card_positions.append(Vector3(offset, 0, offset))    # 3: Bottom-right
	
	# Penalty positions surrounding the 2×2 grid (8 slots)
	# Left column, Right column, Top row, Bottom row extras
	var s = grid_spacing
	penalty_positions.append(Vector3(-offset - s, 0, -offset))  # P0: Far-left top
	penalty_positions.append(Vector3(-offset - s, 0,  offset))  # P1: Far-left bottom
	penalty_positions.append(Vector3( offset + s, 0, -offset))  # P2: Far-right top
	penalty_positions.append(Vector3( offset + s, 0,  offset))  # P3: Far-right bottom
	penalty_positions.append(Vector3(-offset,     0, -offset - s))  # P4: Top-left far
	penalty_positions.append(Vector3( offset,     0, -offset - s))  # P5: Top-right far
	penalty_positions.append(Vector3(-offset,     0,  offset + s))  # P6: Bottom-left far
	penalty_positions.append(Vector3( offset,     0,  offset + s))  # P7: Bottom-right far

func add_card(card: Card3D, position_index: int, animate: bool = true) -> void:
	"""Add a card to a specific grid position"""
	if position_index < 0 or position_index >= 4:
		print("Error: Invalid position index %d" % position_index)
		return
	
	# Remove existing card if any
	if cards[position_index] != null:
		remove_card(position_index)
	
	# Add new card
	cards[position_index] = card
	add_child(card)
	
	if card.owner_player == null and has_meta("owner_player"):
		card.owner_player = get_meta("owner_player")
	
	# Position the card (rotation inherited from grid)
	var target_pos = card_positions[position_index]
	if animate:
		card.move_to(to_global(target_pos), 0.5, false)
	else:
		card.global_position = to_global(target_pos)
		card.base_position = card.global_position
	
	# Reset rotation to zero (grid provides orientation)
	card.rotation = Vector3.ZERO
	
	print("Card added to Player %d grid position %d: %s" % [player_id, position_index, card.card_data.get_short_name()])

func get_card_at(index: int) -> Card3D:
	"""Get card at specific position (0-3)"""
	if index >= 0 and index < cards.size():
		return cards[index]
	return null

func remove_card(index: int) -> Card3D:
	"""Remove and return card at position"""
	if index < 0 or index >= cards.size():
		return null
	
	var card = cards[index]
	if card != null:
		cards[index] = null
		if card.get_parent() == self:
			remove_child(card)
	
	return card

func replace_card(index: int, new_card: Card3D) -> Card3D:
	"""Replace card at position and return the old card"""
	var old_card = remove_card(index)
	add_card(new_card, index, true)
	return old_card

func get_all_cards() -> Array[Card3D]:
	"""Get all cards in the grid (may contain nulls)"""
	return cards.duplicate()

func get_valid_cards() -> Array[Card3D]:
	"""Get only non-null cards"""
	var valid_cards: Array[Card3D] = []
	for card in cards:
		if card != null:
			valid_cards.append(card)
	return valid_cards

func clear_grid() -> void:
	"""Remove all cards from the grid"""
	for i in range(cards.size()):
		var card = remove_card(i)
		if card != null:
			card.queue_free()

func get_position_for_card(index: int) -> Vector3:
	"""Get global position for a card slot"""
	if index >= 0 and index < card_positions.size():
		return to_global(card_positions[index])
	return global_position

func highlight_all(selected: bool = false) -> void:
	"""Highlight all cards in the grid"""
	for card in cards:
		if card != null:
			card.highlight(selected)

func remove_highlights() -> void:
	"""Remove highlights from all cards"""
	for card in cards:
		if card != null:
			card.remove_highlight()

func set_all_interactable(interactable: bool) -> void:
	"""Enable/disable interaction for all cards"""
	for card in cards:
		if card != null:
			card.is_interactable = interactable

# ======================================
# PHASE 6: PENALTY CARD MANAGEMENT
# ======================================

func add_penalty_card(card: Card3D, animate: bool = true) -> void:
	"""Add a penalty card to the next available penalty slot around the grid.
	When more than 8 penalty cards are added, extras stack with a Y-offset above the last slot."""
	var slot = penalty_cards.size()
	var stack_height: float = 0.0
	var is_overflow := false
	if slot >= penalty_positions.size():
		# All predefined slots full — stack with Y offset above the last slot
		stack_height = (slot - (penalty_positions.size() - 1)) * 0.025
		slot = penalty_positions.size() - 1
		is_overflow = true
	
	penalty_cards.append(card)
	add_child(card)
	
	# Ensure ownership is set (mirrors the pattern in add_card)
	if card.owner_player == null and has_meta("owner_player"):
		card.owner_player = get_meta("owner_player")
	
	var target_local = penalty_positions[slot] + Vector3(0, stack_height, 0)
	if animate:
		card.move_to(to_global(target_local), 0.4, false)
	else:
		card.global_position = to_global(target_local)
		card.base_position = card.global_position
	card.rotation = Vector3.ZERO
	
	# Only create a placeholder for new slots (not overflow stacked cards)
	if not is_overflow:
		_create_penalty_placeholder(penalty_positions[slot])
	
	print("Player %d received penalty card at slot %d: %s" % [
		player_id, slot, card.card_data.get_short_name()])

func remove_penalty_card(card: Card3D) -> void:
	"""Remove a penalty card and its placeholder. Caller is responsible for freeing the card node."""
	var idx = penalty_cards.find(card)
	if idx == -1:
		return
	penalty_cards.remove_at(idx)
	# Free the corresponding placeholder
	if idx < penalty_placeholders.size():
		var ph = penalty_placeholders[idx]
		penalty_placeholders.remove_at(idx)
		if is_instance_valid(ph):
			ph.queue_free()
	# Detach card from grid so the calling code can manage it
	if card.get_parent() == self:
		remove_child(card)

func _build_penalty_placeholder(local_pos: Vector3) -> Node3D:
	"""Build a white outline border Node3D for a penalty slot. Does NOT add to tracking array."""
	var width := 0.75
	var height := 1.05
	var border := 0.03

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.5
	mat.render_priority = 1

	var container := Node3D.new()

	for edge in [[Vector2(width, border), Vector3(0, 0.02, -height/2)],
				 [Vector2(width, border), Vector3(0, 0.02, height/2)],
				 [Vector2(border, height - 2*border), Vector3(-width/2, 0.02, 0)],
				 [Vector2(border, height - 2*border), Vector3(width/2, 0.02, 0)]]:

		var bar := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = edge[0]
		bar.mesh = quad
		bar.material_override = mat
		bar.rotation_degrees = Vector3(-90, 0, 0)
		bar.position = edge[1]
		container.add_child(bar)

	container.position = local_pos
	add_child(container)
	return container

func _create_penalty_placeholder(local_pos: Vector3) -> void:
	"""Create a white outline border at a penalty card slot and append it to the tracking array."""
	penalty_placeholders.append(_build_penalty_placeholder(local_pos))

func insert_penalty_card_at(card: Card3D, slot: int, animate: bool = true) -> void:
	"""Insert a card at a specific penalty slot index, preserving the positions of other penalty cards.
	Use this instead of add_penalty_card when swapping so the card lands at the exact slot."""
	slot = clampi(slot, 0, penalty_positions.size() - 1)

	penalty_cards.insert(slot, card)
	add_child(card)
	
	# Ensure ownership is set (mirrors the pattern in add_card)
	if card.owner_player == null and has_meta("owner_player"):
		card.owner_player = get_meta("owner_player")

	var target_local := penalty_positions[slot]
	if animate:
		card.move_to(to_global(target_local), 0.4, false)
	else:
		card.global_position = to_global(target_local)
		card.base_position = card.global_position
	card.rotation = Vector3.ZERO

	# Build the placeholder and insert it at the matching index so penalty_placeholders
	# stays in sync with penalty_cards.
	var ph := _build_penalty_placeholder(target_local)
	penalty_placeholders.insert(slot, ph)

	print("Player %d received penalty card at slot %d: %s" % [
		player_id, slot, card.card_data.get_short_name()])

func get_penalty_count() -> int:
	"""Return number of penalty cards this player has"""
	return penalty_cards.size()

func get_next_penalty_position() -> Vector3:
	"""Return the global position of the next penalty slot"""
	var slot = mini(penalty_cards.size(), penalty_positions.size() - 1)
	return to_global(penalty_positions[slot])
