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
	var grid_pos = grid.global_position
	
	# Direction from center to grid in XZ plane only (ignore Y)
	var dir_xz = Vector3(grid_pos.x, 0, grid_pos.z).normalized()
	
	# Player sits 1.5 units beyond their grid, away from center
	var seat_position = grid_pos + dir_xz * 1.5
	seat_position.y = grid_pos.y  # Keep at table surface height
	
	return seat_position

func get_card_view_position() -> Vector3:
	"""Calculate the viewing position for a card based on current player."""
	return get_card_view_position_for(GameManager.current_player_index)

func get_card_view_position_for(player_idx: int) -> Vector3:
	"""Calculate the viewing position for a card based on a specific player.
	
	Production-ready: Card appears close to the player's camera/seat,
	giving the feeling of holding it in hand, near table level.
	"""
	if player_idx >= table.player_grids.size():
		return Vector3.ZERO
	var seat_pos = get_player_seat_position(player_idx)
	var grid_pos = table.player_grids[player_idx].global_position
	var dir = (seat_pos - grid_pos).normalized()
	# Push card beyond seat toward the player
	var view_pos = seat_pos + dir * 1.5
	view_pos.y = seat_pos.y + 0.6  # Low, close to table
	return view_pos

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
	var tilt_angle := 1.4 if steep else 0.6
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
	"""Create bot character visuals at each bot player's seat (on the chairs).
	Human player (index 0) gets a small marker; bots get a full capsule body + sphere head.
	"""
	# Clear old markers
	for marker in table.seat_markers:
		marker.queue_free()
	table.seat_markers.clear()
	
	# Bot body dimensions (large — must visually sit on chairs)
	var body_radius := 0.55
	var body_height := 2.2
	var head_radius := 0.42
	
	for i in range(table.num_players):
		var seat_pos = get_player_seat_position(i)
		
		# Chair sitting position: push bot further out to land right on the chair.
		# Grid positions are ~3.5-4.0 from center; chairs are at ~5.5-6.0 from center.
		var grid_pos = table.player_grids[i].global_position
		var dir_away = Vector3(grid_pos.x, 0, grid_pos.z).normalized()
		var chair_sit_pos = grid_pos + dir_away * 3.0
		chair_sit_pos.y = seat_pos.y
		
		# Bot color per player slot
		var bot_color: Color
		if i == 0:
			bot_color = Color(0.2, 0.7, 0.2)   # Human: green (small marker only)
		elif i == 1:
			bot_color = Color(0.7, 0.2, 0.2)   # North bot: red
		elif i == 2:
			bot_color = Color(0.2, 0.2, 0.7)   # West bot: blue
		else:
			bot_color = Color(0.7, 0.7, 0.2)   # East bot: yellow
		
		if i == 0:
			# Human player — just a small marker dot
			var dot = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 0.06
			sphere.height = 0.12
			dot.mesh = sphere
			var mat = StandardMaterial3D.new()
			mat.albedo_color = bot_color
			dot.material_override = mat
			table.add_child(dot)
			dot.global_position = Vector3(seat_pos.x, seat_pos.y + 0.3, seat_pos.z)
			table.seat_markers.append(dot)
		else:
			# Bot character — capsule body + sphere head, sitting on chair
			var bot_root = Node3D.new()
			bot_root.name = "BotVisual_%d" % i
			table.add_child(bot_root)
			# Position at chair, lowered so it looks seated (lower body hidden in chair)
			bot_root.global_position = Vector3(chair_sit_pos.x, chair_sit_pos.y - 0.6, chair_sit_pos.z)
			
			# Make bot face toward center of table
			var dir_to_center = Vector3(-chair_sit_pos.x, 0, -chair_sit_pos.z).normalized()
			if dir_to_center.length() > 0.01:
				bot_root.rotation.y = atan2(dir_to_center.x, dir_to_center.z)
			
			# Body (capsule)
			var body = MeshInstance3D.new()
			var capsule = CapsuleMesh.new()
			capsule.radius = body_radius
			capsule.height = body_height
			body.mesh = capsule
			var body_mat = StandardMaterial3D.new()
			body_mat.albedo_color = bot_color
			body_mat.roughness = 0.8
			body.material_override = body_mat
			bot_root.add_child(body)
			body.position = Vector3(0, body_height * 0.5, 0)
			
			# Head (sphere)
			var head = MeshInstance3D.new()
			var head_mesh = SphereMesh.new()
			head_mesh.radius = head_radius
			head_mesh.height = head_radius * 2.0
			head.mesh = head_mesh
			var head_mat = StandardMaterial3D.new()
			head_mat.albedo_color = bot_color.lightened(0.2)
			head_mat.roughness = 0.7
			head.material_override = head_mat
			bot_root.add_child(head)
			head.position = Vector3(0, body_height + head_radius * 0.8, 0)
			
			table.seat_markers.append(bot_root)
			print("Created bot visual for Player %d at %s (color: %s)" % [i + 1, bot_root.global_position, bot_color])
