extends Node
class_name CardViewHelper
## Calculates viewing positions, rotations, and directions for card displays.
## Also manages debug seat markers and neighbor lookups.

var table  # Reference to game_table

func init(game_table) -> void:
	table = game_table

func get_player_seat_position(player_index: int) -> Vector3:
	"""Calculate where a player is seated (for viewing animations).
	
	Production-ready: Works for any player count and table configuration.
	Players sit away from table center.
	"""
	if player_index >= table.player_grids.size():
		return Vector3.ZERO
	
	var grid = table.player_grids[player_index]
	var table_center = Vector3.ZERO
	
	# Direction from center to grid
	var center_to_grid = grid.global_position - table_center
	
	# Player sits 1.5 units away from grid, away from center
	var seat_direction = center_to_grid.normalized()
	var seat_position = grid.global_position + seat_direction * 1.5
	
	return seat_position

func get_card_view_position() -> Vector3:
	"""Calculate the viewing position for a card based on current player."""
	return get_card_view_position_for(GameManager.current_player_index)

func get_card_view_position_for(player_idx: int) -> Vector3:
	"""Calculate the viewing position for a card based on a specific player.
	
	Production-ready: Card appears in front of the player (between seat and grid).
	"""
	if player_idx >= table.player_grids.size():
		return Vector3.ZERO
	var seat_pos = get_player_seat_position(player_idx)
	var grid_pos = table.player_grids[player_idx].global_position
	var midpoint = (seat_pos + grid_pos) / 2.0
	midpoint.y += 2.0  # Elevate above table
	return midpoint

func get_card_view_rotation() -> float:
	"""Get the Y-axis rotation for viewing a card based on current player."""
	return get_card_view_rotation_for(GameManager.current_player_index)

func get_card_view_rotation_for(player_idx: int) -> float:
	"""Get the Y-axis rotation for viewing a card for a specific player.
	
	Production-ready: Card faces toward player's seat, showing BACK to others.
	The card face points TOWARD the player, back points AWAY.
	"""
	if player_idx >= table.player_grids.size():
		return 0.0
	var grid_pos = table.player_grids[player_idx].global_position
	var seat_pos = get_player_seat_position(player_idx)
	var direction = seat_pos - grid_pos
	return atan2(direction.x, direction.z)

func get_card_view_sideways() -> Vector3:
	"""Get the world-space sideways direction perpendicular to the current player's view."""
	return get_card_view_sideways_for(GameManager.current_player_index)

func get_card_view_sideways_for(player_idx: int) -> Vector3:
	"""Get the world-space sideways direction perpendicular to a specific player's view.
	
	Used to offset side-by-side cards correctly for all player orientations.
	"""
	if player_idx >= table.player_grids.size():
		return Vector3.RIGHT
	var grid_pos = table.player_grids[player_idx].global_position
	var seat_pos = get_player_seat_position(player_idx)
	var dir = (seat_pos - grid_pos).normalized()
	# Rotate 90° in XZ plane: (dx, 0, dz) -> (dz, 0, -dx)
	return Vector3(dir.z, 0.0, -dir.x)

func tilt_card_towards_viewer(card: Card3D, steep: bool = false) -> void:
	"""Tilt a card towards the current player's viewing angle.
	
	Production-ready: Uses local X-axis tilt, works for all player rotations.
	The card tilts "up" from the player's perspective.
	When steep=true the card tilts nearly vertical so the front is hidden from
	the overhead camera (used for bot-private viewing).
	"""
	var tilt_angle := -1.4 if steep else -0.6
	var tween = card.create_tween()
	tween.tween_property(card, "rotation:x", tilt_angle, 0.2)

func get_neighbors(player_index: int) -> Array[int]:
	"""Get the neighbor player indices for a given player based on physical seating"""
	var neighbors: Array[int] = []
	var total_players = GameManager.player_count
	
	if total_players == 2:
		# In 2-player game, the other player is the neighbor
		neighbors.append(1 if player_index == 0 else 0)
	elif total_players == 3:
		# In 3-player game, all other players are neighbors
		for i in range(total_players):
			if i != player_index:
				neighbors.append(i)
	elif total_players == 4:
		# In 4-player game, neighbors are physically adjacent players
		# Seating: 0=South, 1=North, 2=West, 3=East
		# South/North neighbors: West and East (2, 3)
		# West/East neighbors: South and North (0, 1)
		if player_index == 0 or player_index == 1:  # South or North
			neighbors.append(2)  # West
			neighbors.append(3)  # East
		else:  # West or East (2 or 3)
			neighbors.append(0)  # South
			neighbors.append(1)  # North
	
	return neighbors

func create_seat_markers() -> void:
	"""Create visual debug markers at each player's seating position.
	This helps visualize where bots are 'sitting' and verify card viewing works correctly.
	"""
	# Clear old markers
	for marker in table.seat_markers:
		marker.queue_free()
	table.seat_markers.clear()
	
	# Create a marker for each player
	for i in range(table.num_players):
		var seat_pos = get_player_seat_position(i)
		
		# Create a simple sphere mesh
		var mesh_instance = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 0.15
		sphere_mesh.height = 0.3
		mesh_instance.mesh = sphere_mesh
		
		# Create material (different color per player)
		var material = StandardMaterial3D.new()
		if i == 0:
			material.albedo_color = Color.GREEN  # Player 1 (human)
		elif i == 1:
			material.albedo_color = Color.RED  # Player 2 (north bot)
		elif i == 2:
			material.albedo_color = Color.BLUE  # Player 3 (west bot)
		elif i == 3:
			material.albedo_color = Color.YELLOW  # Player 4 (east bot)
		
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy = 0.5
		mesh_instance.material_override = material
		
		# Add to tree first, THEN set global_position (requires is_inside_tree())
		table.add_child(mesh_instance)
		mesh_instance.global_position = Vector3(seat_pos.x, 0.5, seat_pos.z)
		
		table.seat_markers.append(mesh_instance)
		
		print("Created seat marker for Player %d at %s (color: %s)" % [i + 1, mesh_instance.global_position, material.albedo_color])
