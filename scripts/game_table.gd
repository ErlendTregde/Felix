extends Node3D
## Main game table controller - manages the game board and card instances

@onready var camera_controller = $CameraController
@onready var players_container = $Players
@onready var draw_pile_marker = $PositionMarkers/DrawPile
@onready var discard_pile_marker = $PositionMarkers/DiscardPile

var deck_manager: DeckManager
var card_scene = preload("res://scenes/cards/card_3d.tscn")
var player_grid_scene = preload("res://scenes/players/player_grid.tscn")
var card_pile_scene = preload("res://scenes/cards/card_pile.tscn")
var viewing_ui_scene = preload("res://scenes/ui/viewing_ui.tscn")
var turn_ui_scene = preload("res://scenes/ui/turn_ui.tscn")
var swap_choice_ui_scene = preload("res://scenes/ui/swap_choice_ui.tscn")

var player_grids: Array[PlayerGrid] = []
var players: Array[Player] = []
var num_players: int = 2
var is_dealing: bool = false

var draw_pile_visual: CardPile = null
var discard_pile_visual: CardPile = null
var viewing_ui = null  # ViewingUI instance
var turn_ui = null  # TurnUI instance
var swap_choice_ui = null  # SwapChoiceUI instance

# Turn system variables
var selected_card: Card3D = null
var drawn_card: Card3D = null
var is_player_turn: bool = false
var is_drawing: bool = false  # Prevent multiple draws per turn

# Ability system variables (Phase 5)
var is_executing_ability: bool = false
var current_ability: CardData.AbilityType = CardData.AbilityType.NONE
var ability_target_card: Card3D = null
var awaiting_ability_confirmation: bool = false

# Blind swap state (Jack ability)
var blind_swap_first_card: Card3D = null
var blind_swap_second_card: Card3D = null

# Look and swap state (Queen ability)
var look_and_swap_first_card: Card3D = null
var look_and_swap_second_card: Card3D = null
var look_and_swap_first_original_pos: Vector3 = Vector3.ZERO
var look_and_swap_second_original_pos: Vector3 = Vector3.ZERO
# Grid references and slot indices captured at selection time.
# These are used in _on_swap_chosen / _on_no_swap_chosen so we never have to
# re-search the grid array after cards have been moved to a viewing position.
var look_and_swap_first_grid = null   # PlayerGrid
var look_and_swap_first_slot: int = -1
var look_and_swap_second_grid = null  # PlayerGrid
var look_and_swap_second_slot: int = -1

# Initial viewing phase state
var initial_view_cards: Dictionary = {}  # player_idx -> [card1, card2]

# Debug: Visual markers for player seating positions
var seat_markers: Array[MeshInstance3D] = []

# ======================================
# PHASE 6: FAST REACTION MATCHING STATE
# ======================================
var is_processing_match: bool = false  # True while a match attempt is being resolved
var is_choosing_give_card: bool = false  # True while picking which card to give to opponent
var give_card_target_player_idx: int = -1  # Opponent who receives the give card

func _ready() -> void:
	print("=== Felix Card Game - Game Table Ready ===")
	
	# Initialize deck manager
	deck_manager = DeckManager.new()
	add_child(deck_manager)
	deck_manager.create_standard_deck()
	deck_manager.shuffle()
	deck_manager.pile_reshuffled.connect(_on_pile_reshuffled)
	
	# Create card pile visuals
	setup_card_piles()
	
	# Create viewing UI
	viewing_ui = viewing_ui_scene.instantiate()
	add_child(viewing_ui)
	viewing_ui.ready_pressed.connect(_on_player_ready_pressed)
	
	# Create turn UI
	turn_ui = turn_ui_scene.instantiate()
	add_child(turn_ui)
	
	# Create swap choice UI (Queen ability)
	swap_choice_ui = swap_choice_ui_scene.instantiate()
	add_child(swap_choice_ui)
	swap_choice_ui.swap_chosen.connect(_on_swap_chosen)
	swap_choice_ui.no_swap_chosen.connect(_on_no_swap_chosen)
	
	# Setup players
	setup_players(num_players)
	
	print("\nPress ENTER to deal cards")
	print("Press 1-4 to change player count")
	print("Press T to toggle test mode (ability cards: 7/8/9/10)")
	print("Press SPACE to flip all cards")
	print("Press F to shake camera")
	print("Press A to auto-ready other players (debug)")
	print("Press D to draw card during your turn")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Deal cards
		if event.keycode == KEY_ENTER and not is_dealing:
			deal_cards_to_all_players()
		
		# Change player count
		elif event.keycode == KEY_1:
			change_player_count(1)
		elif event.keycode == KEY_2:
			change_player_count(2)
		elif event.keycode == KEY_3:
			change_player_count(3)
		elif event.keycode == KEY_4:
			change_player_count(4)
		
		# Flip all cards / Confirm ability viewing
		elif event.keycode == KEY_SPACE:
			if awaiting_ability_confirmation:
				confirm_ability_viewing()
			else:
				flip_all_cards()
		
		# Camera shake
		elif event.keycode == KEY_F:
			camera_controller.shake(0.2, 0.5)
			print("Camera shake!")
		
		# Debug: Auto-ready all other players (for testing)
		elif event.keycode == KEY_A:
			auto_ready_other_players()
		
		# Toggle test mode (7/8 cards only)
		elif event.keycode == KEY_T:
			if GameManager.current_state == GameManager.GameState.SETUP:
				deck_manager.toggle_test_mode()
				if draw_pile_visual:
					draw_pile_visual.set_count(deck_manager.get_draw_pile_count())
			else:
				print("Can only toggle test mode before dealing cards")
		
		# Draw card (Phase 4)
		elif event.keycode == KEY_D:
			if GameManager.current_state == GameManager.GameState.PLAYING and is_player_turn and not drawn_card and not is_drawing:
				handle_draw_card()

func setup_card_piles() -> void:
	"""Create visual representations of card piles"""
	# Draw pile
	draw_pile_visual = card_pile_scene.instantiate()
	draw_pile_visual.pile_type = "draw"
	draw_pile_marker.add_child(draw_pile_visual)
	draw_pile_visual.set_count(54)
	draw_pile_visual.pile_clicked.connect(_on_draw_pile_clicked)
	
	# Discard pile
	discard_pile_visual = card_pile_scene.instantiate()
	discard_pile_visual.pile_type = "discard"
	discard_pile_marker.add_child(discard_pile_visual)
	discard_pile_visual.set_count(0)
	discard_pile_visual.pile_clicked.connect(_on_discard_pile_clicked)

func setup_players(count: int) -> void:
	"""Initialize player grids and player objects"""
	# Clear existing
	clear_all_players()
	
	num_players = clampi(count, 1, 4)
	
	# Player positions around the table
	var positions = [
		Vector3(0, 0.05, 3.5),    # Player 0 (South - bottom)
		Vector3(0, 0.05, -3.5),   # Player 1 (North - top)
		Vector3(-4, 0.05, 0),     # Player 2 (West - left)
		Vector3(4, 0.05, 0)       # Player 3 (East - right)
	]
	
	var rotations = [
		0,          # Player 0 faces north
		PI,         # Player 1 faces south
		PI / 2,     # Player 2 faces east
		-PI / 2     # Player 3 faces west
	]
	
	for i in range(num_players):
		# Create Player object
		var player = Player.new()
		player.player_id = i
		player.player_name = "Player %d" % (i + 1)
		players.append(player)
		players_container.add_child(player)
		
		# Create PlayerGrid
		var grid = player_grid_scene.instantiate()
		grid.player_id = i
		grid.position = positions[i]
		grid.rotation.y = rotations[i]
		grid.base_rotation_y = rotations[i]  # Store rotation for cards
		grid.set_meta("owner_player", player)
		player_grids.append(grid)
		players_container.add_child(grid)
		
		print("Setup %s at position %s" % [player.player_name, positions[i]])
	
	# Update GameManager
	GameManager.players = players
	GameManager.player_count = num_players
	
	# Create debug seat markers
	create_seat_markers()
	
	print("\n%d player(s) ready!" % num_players)

func change_player_count(count: int) -> void:
	"""Change number of players and reset"""
	if is_dealing:
		return
	
	print("\n=== Changing to %d player(s) ===" % count)
	deck_manager.reset_deck()
	setup_players(count)

func clear_all_players() -> void:
	"""Remove all players and grids"""
	for grid in player_grids:
		if is_instance_valid(grid):
			grid.clear_grid()
			grid.queue_free()
	
	for player in players:
		if is_instance_valid(player):
			player.clear_cards()
			player.queue_free()
	
	player_grids.clear()
	players.clear()

func deal_cards_to_all_players() -> void:
	"""Deal 4 cards to each player with animation"""
	if is_dealing:
		return
	
	is_dealing = true
	print("\n=== Dealing Cards to %d Player(s) ===" % num_players)
	
	# Deal 4 cards per player
	for card_index in range(4):
		for player_index in range(num_players):
			await deal_single_card(player_index, card_index)
			
			# Update draw pile visual
			if draw_pile_visual:
				draw_pile_visual.set_count(deck_manager.get_draw_pile_count())
			
			await get_tree().create_timer(0.15).timeout  # Stagger between cards
	
	is_dealing = false
	print("\nDealing complete! All players have 4 cards.")
	Events.game_state_changed.emit("DEALING_COMPLETE")
	
	# Start viewing phase
	start_initial_viewing_phase()

func deal_single_card(player_index: int, position_index: int) -> void:
	"""Deal one card to a specific player position"""
	if player_index >= player_grids.size():
		return
	
	var card_data = deck_manager.deal_card()
	if not card_data:
		print("Warning: Deck is empty!")
		return
	
	# Create card at draw pile position
	var card = card_scene.instantiate()
	add_child(card)
	card.global_position = draw_pile_marker.global_position
	card.initialize(card_data, false)
	
	# Connect signals
	card.card_clicked.connect(_on_card_clicked)
	card.card_right_clicked.connect(_on_card_right_clicked)
	
	# Add to player's grid (will animate there)
	var grid = player_grids[player_index]
	await reparent_card_to_grid(card, grid, position_index)
	
	# Update player data
	players[player_index].add_card(card)
	
	# Update draw pile visual
	if draw_pile_visual:
		draw_pile_visual.set_count(deck_manager.get_draw_pile_count())
	
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
	card.position = grid.card_positions[card_position]
	card.base_position = card.global_position

func flip_all_cards() -> void:
	"""Flip all cards on the table"""
	print("\n=== Flipping All Cards ===")
	for grid in player_grids:
		for card in grid.get_valid_cards():
			card.flip()

func get_bottom_card_positions(player_index: int) -> Array[int]:
	"""Get the bottom 2 card positions based on proximity to player's seating location.
	
	Production-ready approach: Players sit away from table center, regardless of rotation.
	Works for any table size, player count, or grid configuration.
	"""
	if player_index >= player_grids.size():
		return [2, 3]  # Fallback
	
	var grid = player_grids[player_index]
	
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

func create_seat_markers() -> void:
	"""Create visual debug markers at each player's seating position.
	This helps visualize where bots are 'sitting' and verify card viewing works correctly.
	"""
	# Clear old markers
	for marker in seat_markers:
		marker.queue_free()
	seat_markers.clear()
	
	# Create a marker for each player
	for i in range(num_players):
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
		add_child(mesh_instance)
		mesh_instance.global_position = Vector3(seat_pos.x, 0.5, seat_pos.z)
		
		seat_markers.append(mesh_instance)
		
		print("Created seat marker for Player %d at %s (color: %s)" % [i + 1, mesh_instance.global_position, material.albedo_color])

func lift_bottom_cards_for_viewing(player_idx: int) -> void:
	"""Animate a player's 2 bottom cards to a side-by-side viewing position above the table.
	For the human player this is their private view; bots animate so they visually appear to look.
	"""
	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		return

	var grid = player_grids[player_idx]
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
	var view_center = get_card_view_position_for(player_idx)
	var sideways = get_card_view_sideways_for(player_idx)
	var view_rotation = get_card_view_rotation_for(player_idx)

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

	# Tilt toward viewer
	var tween1 = card1.create_tween()
	tween1.tween_property(card1, "rotation:x", -0.6, 0.2)
	var tween2 = card2.create_tween()
	tween2.tween_property(card2, "rotation:x", -0.6, 0.2)
	await get_tree().create_timer(0.25).timeout

	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		return

	# Store so we can return these cards later (include saved grid positions)
	initial_view_cards[player_idx] = [card1, card2, orig_pos1, orig_pos2]

func return_bottom_cards_for_player(player_idx: int) -> void:
	"""Animate a player's viewed bottom cards back to their grid positions."""
	if not initial_view_cards.has(player_idx):
		return

	var cards: Array = initial_view_cards[player_idx]
	initial_view_cards.erase(player_idx)

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

	if initial_view_cards.has(player_idx):
		await return_bottom_cards_for_player(player_idx)

	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		return

	GameManager.set_player_ready(player_idx, true)
	var ready_count = GameManager.get_ready_count()
	viewing_ui.update_waiting_count(ready_count, num_players)
	print("Bot Player %d finished viewing (%d/%d ready)" % [player_idx + 1, ready_count, num_players])

	if GameManager.are_all_players_ready():
		await get_tree().create_timer(0.3).timeout
		end_viewing_phase()

func auto_ready_other_players() -> void:
	"""Debug function to auto-ready all bot players immediately"""
	print("\n=== Auto-Ready Debug Activated ===")
	for i in range(1, num_players):
		if i >= GameManager.players.size():
			continue
		# Snap cards back instantly (skip smooth return for debug speed)
		if initial_view_cards.has(i):
			var cards: Array = initial_view_cards[i]
			initial_view_cards.erase(i)
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
	viewing_ui.update_waiting_count(ready_count, num_players)
	print("All other players marked as ready (%d/%d)" % [ready_count, num_players])

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
	initial_view_cards.clear()

	# Fire-and-forget: all players lift their cards simultaneously
	for i in range(num_players):
		lift_bottom_cards_for_viewing(i)  # async, runs independently

	# Wait for all lift animations to finish (0.5 + 0.35 + 0.25 + buffer)
	await get_tree().create_timer(1.3).timeout

	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		return

	# Bots auto-return after a short viewing delay
	for i in range(1, num_players):
		_bot_auto_return_cards(i)  # async, runs independently

	# Show Ready button for the human player
	viewing_ui.show_for_player(0, num_players)
	print("Memorize your bottom 2 cards. Press Ready when done.")
	print("(Press A to auto-ready bots for testing)")

func _on_player_ready_pressed(player_id: int) -> void:
	"""Handle when a player presses the ready button.
	Returns the human player's cards to the grid, then checks if all players are ready.
	"""
	# Return the human player's cards first so they animate back smoothly
	if initial_view_cards.has(player_id):
		await return_bottom_cards_for_player(player_id)

	GameManager.set_player_ready(player_id, true)

	var ready_count = GameManager.get_ready_count()
	viewing_ui.update_waiting_count(ready_count, num_players)
	print("Ready count: %d/%d" % [ready_count, num_players])

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
	viewing_ui.hide_ui()

	# Safety: return any cards still in the air (e.g. race conditions)
	for player_idx in initial_view_cards.keys():
		await return_bottom_cards_for_player(player_idx)
	initial_view_cards.clear()

	# Start the game
	print("\n=== Game Starting ===")
	GameManager.change_state(GameManager.GameState.PLAYING)
	start_next_turn()

func _on_card_clicked(card: Card3D) -> void:
	"""Handle card click"""
	# Phase 6: Handle give-card selection after a successful opponent match
	if is_choosing_give_card:
		_handle_give_card_selection(card)
		return
	
	# During gameplay, handle card selection
	if GameManager.current_state == GameManager.GameState.PLAYING:
		handle_card_selection(card)
		return
	
	# Debug/testing: flip card
	print("\n=== Card Clicked: %s ===" % card.card_data.get_short_name())
	print("  Score: %d" % card.card_data.get_score())
	print("  Ability: %s" % CardData.AbilityType.keys()[card.card_data.get_ability()])
	print("  Is face up: %s" % card.is_face_up)
	
	card.flip()

func _handle_give_card_selection(card: Card3D) -> void:
	"""Human selected one of their own cards to give to the opponent after a successful match."""
	# Verify the card belongs to the human player
	var owner_idx = _find_card_owner_idx(card)
	if owner_idx != 0:
		print("[Match] Choose one of YOUR OWN cards to give!")
		return
	
	is_choosing_give_card = false
	var target_idx = give_card_target_player_idx
	give_card_target_player_idx = -1
	
	# Remove highlights from all own cards (main grid + penalty)
	var own_grid = player_grids[0]
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
	card.owner_player = players[target_idx]
	
	# Move card to opponent's penalty position
	var target_grid = player_grids[target_idx]
	
	# Detach from current parent before adding to target grid
	if card.get_parent() != null:
		card.get_parent().remove_child(card)
	target_grid.add_penalty_card(card, true)
	await get_tree().create_timer(0.5).timeout
	
	print("[Match] Player %d gave card to Player %d. Match complete!" % [1, target_idx + 1])
	
	# Unlock matching for the next discard event
	_unlock_matching()

func _on_discard_pile_clicked(_pile: CardPile) -> void:
	"""Handle discard pile click - play card to discard and use ability"""
	if not is_player_turn:
		print("Not your turn!")
		return
	
	if not drawn_card:
		print("Draw a card first! Press D")
		return
	
	# Disable discard pile interaction
	if discard_pile_visual:
		discard_pile_visual.set_interactive(false)
	
	# Play card to discard pile
	await play_card_to_discard(drawn_card)

func _on_draw_pile_clicked(_pile: CardPile) -> void:
	"""Handle draw pile click - draw a card"""
	if not is_player_turn:
		print("Not your turn!")
		return
	
	if drawn_card or is_drawing:
		print("Already drew a card!")
		return
	
	if GameManager.current_state != GameManager.GameState.PLAYING:
		print("Cannot draw now!")
		return
	
	# Disable draw pile interaction
	if draw_pile_visual:
		draw_pile_visual.set_interactive(false)
	
	# Start drawing
	handle_draw_card()

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
	
	# Lock out all input immediately so nothing fires during the reshuffle animation
	is_player_turn = false
	if draw_pile_visual:
		draw_pile_visual.set_interactive(false)
	
	# If draw pile is empty, perform the reshuffle WITH animation BEFORE the turn begins
	if deck_manager.can_reshuffle():
		await animate_pile_reshuffle()
	
	print("\n=== Turn %d: %s ===" % [current_player_id + 1, current_player.player_name])
	
	# Check if this is player 1 (human) or a bot
	is_player_turn = (current_player_id == 0)
	
	# Update turn UI
	turn_ui.show_turn(current_player_id, current_player.player_name, is_player_turn)
	
	# Reset turn variables
	selected_card = null
	drawn_card = null
	is_drawing = false
	is_executing_ability = false
	current_ability = CardData.AbilityType.NONE
	ability_target_card = null
	awaiting_ability_confirmation = false
	blind_swap_first_card = null
	blind_swap_second_card = null
	
	# Disable discard pile interaction at turn start
	if discard_pile_visual:
		discard_pile_visual.set_interactive(false)
	
	# Disable left-click on all grid cards at turn start.
	# Hover and right-click matching work independently (gated in card_3d.gd by is_animating,
	# not by is_interactable), so this only prevents accidental swap/ability clicks.
	# Left-click is re-enabled after drawing in handle_draw_card().
	for grid in player_grids:
		for i in range(4):
			var card = grid.get_card_at(i)
			if card:
				card.is_interactable = false
		for c in grid.penalty_cards:
			c.is_interactable = false
	
	if is_player_turn:
		# Human player's turn - wait for input
		print("Your turn! Press D to draw a card")
		turn_ui.update_action("Press D to draw a card or click draw pile")
		# Enable draw pile interaction for human player
		if draw_pile_visual:
			draw_pile_visual.set_interactive(true)
	else:
		# Bot turn - auto-play
		print("%s (Bot) is thinking..." % current_player.player_name)
		# Disable draw pile for bots
		if draw_pile_visual:
			draw_pile_visual.set_interactive(false)
		await get_tree().create_timer(1.0).timeout
		execute_bot_turn(current_player_id)

func handle_card_selection(card: Card3D) -> void:
	"""Handle player selecting a card during their turn"""
	if not is_player_turn:
		print("Not your turn!")
		return
	
	# Handle ability target selection
	if is_executing_ability:
		handle_ability_target_selection(card)
		return
	
	# Must draw a card first
	if not drawn_card:
		print("Draw a card first! Press D")
		return
	
	# Can only select own cards
	if card.owner_player != GameManager.get_current_player():
		print("That's not your card!")
		return
	
	# Disable discard pile interaction
	if discard_pile_visual:
		discard_pile_visual.set_interactive(false)
	
	# Execute swap immediately
	await swap_cards(card, drawn_card)

func handle_ability_target_selection(card: Card3D) -> void:
	"""Handle selecting a target card for an ability"""
	var grid = player_grids[GameManager.current_player_index]
	var current_player = GameManager.get_current_player()
	
	# Special handling for BLIND_SWAP (two-step selection)
	if current_ability == CardData.AbilityType.BLIND_SWAP:
		handle_blind_swap_selection(card)
		return
	
	# Special handling for LOOK_AND_SWAP (two-step selection)
	if current_ability == CardData.AbilityType.LOOK_AND_SWAP:
		handle_look_and_swap_selection(card)
		return
	
	# Check if the selected card is valid for the current ability
	if current_ability == CardData.AbilityType.LOOK_OWN:
		# For look_own, card must belong to current player
		if card.owner_player != current_player:
			print("Select one of YOUR cards!")
			return
	elif current_ability == CardData.AbilityType.LOOK_OPPONENT:
		# For look_opponent, card must belong to a NEIGHBOR (not own, not across)
		var current_player_idx = GameManager.current_player_index
		var neighbors = get_neighbors(current_player_idx)
		# Search both main slots AND penalty cards
		var card_owner_idx = _find_card_owner_idx(card)
		if card_owner_idx == current_player_idx:
			print("Select a NEIGHBOR's card, not your own!")
			return
		if not neighbors.has(card_owner_idx):
			print("That player is not your neighbor! Select a neighbor's card.")
			return
	
	# Found valid target
	ability_target_card = card
	card.is_interactable = false  # Prevent re-clicking the selected card
	
	# Switch selected card to darker "confirmed" cyan and lock all others
	card.set_highlighted(true, true)
	for g in player_grids:
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
	var view_position = get_card_view_position()
	
	# Animate card to view position
	card.move_to(view_position, 0.4, false)
	
	# Set global rotation to face current player
	var view_rotation = get_card_view_rotation()
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
	tilt_card_towards_viewer(card)
	await get_tree().create_timer(0.25).timeout
	
	# Update UI
	turn_ui.update_action("Press SPACE to confirm")
	awaiting_ability_confirmation = true
	
	print("Viewing: %s" % card.card_data.get_short_name())

func handle_blind_swap_selection(card: Card3D) -> void:
	"""Handle two-step selection for blind swap ability - supports re-selection at both steps"""
	var current_player_idx = GameManager.current_player_index
	var neighbors = get_neighbors(current_player_idx)

	# Find who owns this card
	var card_owner_idx = _find_card_owner_idx(card)
	var is_own_card = (card_owner_idx == current_player_idx)
	var is_neighbor_card = neighbors.has(card_owner_idx)

	if not is_own_card and not is_neighbor_card:
		print("Select your card or a neighbor's card!")
		return

	# STEP 1 - No first card selected yet
	if blind_swap_first_card == null:
		blind_swap_first_card = card
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if blind_swap_first_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("First card selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			if is_own_card:
				turn_ui.update_action("Now select NEIGHBOR's card")
			else:
				turn_ui.update_action("Now select YOUR card")
		return

	# Clicking the already-selected first card - ignore
	if card == blind_swap_first_card:
		return

	# Find ownership of the currently selected first card
	var first_owner_idx = _find_card_owner_idx(blind_swap_first_card)
	var first_is_own = (first_owner_idx == current_player_idx)

	# RE-SELECT FIRST CARD: same ownership type as current first card - switch to new card
	if is_own_card == first_is_own:
		# If second was also picked, deselect it too and reset step 2
		if blind_swap_second_card != null:
			_blind_swap_deselect_card(blind_swap_second_card)
			blind_swap_second_card = null
			awaiting_ability_confirmation = false
		# Deselect old first card, select new one
		_blind_swap_deselect_card(blind_swap_first_card)
		blind_swap_first_card = card
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if blind_swap_first_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("First card re-selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			if is_own_card:
				turn_ui.update_action("Now select NEIGHBOR's card")
			else:
				turn_ui.update_action("Now select YOUR card")
		return

	# STEP 2 - No second card selected yet (clicked card has opposite ownership = valid second pick)
	if blind_swap_second_card == null:
		blind_swap_second_card = card
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if blind_swap_second_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("Second card selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			turn_ui.update_action("Press SPACE to swap cards")
			awaiting_ability_confirmation = true
		return

	# Clicking the already-selected second card - ignore
	if card == blind_swap_second_card:
		return

	# RE-SELECT SECOND CARD: same ownership type as current second card - switch to new card
	var second_owner_idx = _find_card_owner_idx(blind_swap_second_card)
	var second_is_own = (second_owner_idx == current_player_idx)
	if is_own_card == second_is_own:
		_blind_swap_deselect_card(blind_swap_second_card)
		blind_swap_second_card = card
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if blind_swap_second_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("Second card re-selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			turn_ui.update_action("Press SPACE to swap cards")

func _find_card_owner_idx(card: Card3D) -> int:
	"""Return the player index who owns this card, or -1 if not found"""
	for i in range(player_grids.size()):
		for j in range(4):
			if player_grids[i].get_card_at(j) == card:
				return i
		for pc in player_grids[i].penalty_cards:
			if pc == card:
				return i
	return -1

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
	var neighbors = get_neighbors(current_player_idx)

	# Find who owns this card
	var card_owner_idx = _find_card_owner_idx(card)
	var is_own_card = (card_owner_idx == current_player_idx)
	var is_neighbor_card = neighbors.has(card_owner_idx)

	if not is_own_card and not is_neighbor_card:
		print("Select your card or a neighbor's card!")
		return

	# STEP 1 - No first card selected yet
	if look_and_swap_first_card == null:
		look_and_swap_first_card = card
		look_and_swap_first_original_pos = card.base_position
		_queen_store_card_slot(card, true)
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if look_and_swap_first_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("First card selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			if is_own_card:
				turn_ui.update_action("Now select NEIGHBOR's card")
			else:
				turn_ui.update_action("Now select YOUR card")
		return

	# Clicking the already-selected first card - ignore
	if card == look_and_swap_first_card:
		return

	# Find ownership of the currently selected first card
	var first_owner_idx = _find_card_owner_idx(look_and_swap_first_card)
	var first_is_own = (first_owner_idx == current_player_idx)

	# RE-SELECT FIRST CARD: same ownership type as current first card - switch to new card
	if is_own_card == first_is_own:
		# If second was also picked, deselect it too and reset step 2
		if look_and_swap_second_card != null:
			_look_and_swap_deselect_card(look_and_swap_second_card)
			look_and_swap_second_card = null
			awaiting_ability_confirmation = false
		# Deselect old first card, select new one
		_look_and_swap_deselect_card(look_and_swap_first_card)
		look_and_swap_first_card = card
		look_and_swap_first_original_pos = card.base_position
		_queen_store_card_slot(card, true)
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if look_and_swap_first_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("First card re-selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			if is_own_card:
				turn_ui.update_action("Now select NEIGHBOR's card")
			else:
				turn_ui.update_action("Now select YOUR card")
		return

	# STEP 2 - No second card selected yet (clicked card has opposite ownership = valid second pick)
	if look_and_swap_second_card == null:
		look_and_swap_second_card = card
		look_and_swap_second_original_pos = card.base_position
		_queen_store_card_slot(card, false)
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if look_and_swap_second_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("Second card selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			turn_ui.update_action("Press SPACE to view cards")
			awaiting_ability_confirmation = true
		return

	# Clicking the already-selected second card - ignore
	if card == look_and_swap_second_card:
		return

	# RE-SELECT SECOND CARD: same ownership type as current second card - switch to new card
	var second_owner_idx = _find_card_owner_idx(look_and_swap_second_card)
	var second_is_own = (second_owner_idx == current_player_idx)
	if is_own_card == second_is_own:
		_look_and_swap_deselect_card(look_and_swap_second_card)
		look_and_swap_second_card = card
		look_and_swap_second_original_pos = card.base_position
		_queen_store_card_slot(card, false)
		card.set_highlighted(true, true)
		card.elevate(0.2, 0.15)
		await get_tree().create_timer(0.16).timeout
		if look_and_swap_second_card == card:  # Guard: may have been replaced by a faster click
			card.is_elevation_locked = true
			print("Second card re-selected: %s (Player %d)" % [card.card_data.get_short_name(), card_owner_idx + 1])
			turn_ui.update_action("Press SPACE to view cards")

func _queen_store_card_slot(card: Card3D, is_first: bool) -> void:
	"""Capture the grid reference and slot index for a Queen-selected card at the moment
	of selection. This avoids having to re-search later (cards may be at a viewing position)."""
	for i in range(player_grids.size()):
		var grid = player_grids[i]
		for j in range(4):
			if grid.get_card_at(j) == card:
				if is_first:
					look_and_swap_first_grid = grid
					look_and_swap_first_slot = j
				else:
					look_and_swap_second_grid = grid
					look_and_swap_second_slot = j
				return

func _clear_queen_state() -> void:
	"""Reset all Queen look-and-swap state variables."""
	look_and_swap_first_card = null
	look_and_swap_second_card = null
	look_and_swap_first_original_pos = Vector3.ZERO
	look_and_swap_second_original_pos = Vector3.ZERO
	look_and_swap_first_grid = null
	look_and_swap_first_slot = -1
	look_and_swap_second_grid = null
	look_and_swap_second_slot = -1
	is_executing_ability = false
	current_ability = CardData.AbilityType.NONE

func _unlock_queen_ability() -> void:
	"""Emergency exit from the Queen ability — clean up state and end turn."""
	_clear_queen_state()
	end_current_turn()

func display_cards_for_choice() -> void:
	"""Display both selected cards side-by-side and show swap choice UI"""
	turn_ui.update_action("Viewing cards...")
	
	var card1 = look_and_swap_first_card
	var card2 = look_and_swap_second_card
	
	# Unlock elevation so we can move them
	card1.is_elevation_locked = false
	card2.is_elevation_locked = false
	
	# Calculate viewing positions (side-by-side, perpendicular to player's view direction)
	var view_center = get_card_view_position()
	var sideways = get_card_view_sideways()
	var card1_view_pos = view_center - sideways * 1.0
	var card2_view_pos = view_center + sideways * 1.0
	
	# Set global rotation to face current player
	var view_rotation = get_card_view_rotation()
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
	tilt_card_towards_viewer(card1)
	tilt_card_towards_viewer(card2)
	await get_tree().create_timer(0.25).timeout
	
	# Show swap choice UI
	turn_ui.update_action("Choose whether to swap")
	swap_choice_ui.show_choice()
	print("Viewing: %s and %s" % [card1.card_data.get_short_name(), card2.card_data.get_short_name()])

func get_player_seat_position(player_index: int) -> Vector3:
	"""Calculate where a player is seated (for viewing animations).
	
	Production-ready: Works for any player count and table configuration.
	Players sit away from table center.
	"""
	if player_index >= player_grids.size():
		return Vector3.ZERO
	
	var grid = player_grids[player_index]
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
	if player_idx >= player_grids.size():
		return Vector3.ZERO
	var seat_pos = get_player_seat_position(player_idx)
	var grid_pos = player_grids[player_idx].global_position
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
	if player_idx >= player_grids.size():
		return 0.0
	var grid_pos = player_grids[player_idx].global_position
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
	if player_idx >= player_grids.size():
		return Vector3.RIGHT
	var grid_pos = player_grids[player_idx].global_position
	var seat_pos = get_player_seat_position(player_idx)
	var dir = (seat_pos - grid_pos).normalized()
	# Rotate 90° in XZ plane: (dx, 0, dz) -> (dz, 0, -dx)
	return Vector3(dir.z, 0.0, -dir.x)

func tilt_card_towards_viewer(card: Card3D) -> void:
	"""Tilt a card towards the current player's viewing angle.
	
	Production-ready: Uses local X-axis tilt, works for all player rotations.
	The card tilts "up" from the player's perspective.
	"""
	var tween = card.create_tween()
	
	# Tilt on local X-axis by ~35 degrees toward viewer
	# This works for all players because global_rotation already faces them
	tween.tween_property(card, "rotation:x", -0.6, 0.2)

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

func confirm_look_and_swap() -> void:
	"""Confirm Queen card selection and proceed to side-by-side viewing"""
	awaiting_ability_confirmation = false
	await display_cards_for_choice()

func confirm_blind_swap() -> void:
	"""Execute the blind swap between two selected cards (supports main grid and penalty slots)"""
	if not blind_swap_first_card or not blind_swap_second_card:
		print("Error: Both cards must be selected!")
		return
	
	print("\n=== Executing Blind Swap ===")
	
	var card1 = blind_swap_first_card
	var card2 = blind_swap_second_card
	
	# Find grid, main slot index, and penalty slot index for both cards.
	# Exactly one of main_slot / penalty_slot will be >= 0 for each card.
	var card1_grid: PlayerGrid = null
	var card1_main_slot: int = -1
	var card1_penalty_slot: int = -1
	var card2_grid: PlayerGrid = null
	var card2_main_slot: int = -1
	var card2_penalty_slot: int = -1
	
	for grid in player_grids:
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
		awaiting_ability_confirmation = true
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
	for grid in player_grids:
		for i in range(4):
			var c = grid.get_card_at(i)
			if c:
				c.set_highlighted(false)
				c.is_interactable = false
		for c in grid.penalty_cards:
			c.set_highlighted(false)
			c.is_interactable = false
	
	blind_swap_first_card = null
	blind_swap_second_card = null
	is_executing_ability = false
	current_ability = CardData.AbilityType.NONE
	
	end_current_turn()

func _grid_slot_global_pos(grid: PlayerGrid, main_slot: int, penalty_slot: int) -> Vector3:
	"""Return the world-space position of a main-grid or penalty slot."""
	if main_slot != -1:
		return grid.to_global(grid.card_positions[main_slot])
	if penalty_slot != -1 and penalty_slot < grid.penalty_positions.size():
		return grid.to_global(grid.penalty_positions[penalty_slot])
	return grid.global_position

func confirm_ability_viewing() -> void:
	"""Confirm that player has seen the ability target and flip it back"""
	if not awaiting_ability_confirmation:
		return
	# Clear immediately to prevent double-fire from a second SPACE press
	awaiting_ability_confirmation = false
	
	# Route to blind swap confirmation if that's the current ability
	if current_ability == CardData.AbilityType.BLIND_SWAP:
		confirm_blind_swap()
		return

	# Route to Queen viewing confirmation if that's the current ability
	if current_ability == CardData.AbilityType.LOOK_AND_SWAP:
		confirm_look_and_swap()
		return
	
	# For viewing abilities (LOOK_OWN, LOOK_OPPONENT)
	if not ability_target_card:
		return
	
	var card = ability_target_card
	
	# Find which grid and position the card is in
	var card_grid = null
	var card_position = -1
	
	# Search all player grids
	for grid in player_grids:
		for i in range(4):
			if grid.get_card_at(i) == card:
				card_grid = grid
				card_position = i
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
	
	# Animate back to grid position
	if card_position != -1:
		var target_pos = card_grid.to_global(card_grid.card_positions[card_position])
		card.move_to(target_pos, 0.4, false)
		await get_tree().create_timer(0.45).timeout
		
		# Reparent back to the card's grid so it inherits the correct rotation
		if card.get_parent() != card_grid:
			card.get_parent().remove_child(card)
			card_grid.add_child(card)
		card.rotation = Vector3.ZERO
		card.position = card_grid.card_positions[card_position]
		card.base_position = card_grid.to_global(card_grid.card_positions[card_position])
	
	# Unhighlight ALL grids (LOOK_OPPONENT highlights multiple neighbor grids)
	for grid in player_grids:
		for i in range(4):
			var c = grid.get_card_at(i)
			if c:
				c.set_highlighted(false)
				c.is_interactable = false
		for c in grid.penalty_cards:
			c.set_highlighted(false)
			c.is_interactable = false
	
	# Clean up
	awaiting_ability_confirmation = false
	ability_target_card = null
	is_executing_ability = false
	current_ability = CardData.AbilityType.NONE
	
	# End turn
	end_current_turn()

func handle_draw_card() -> void:
	"""Handle drawing a card (async wrapper for input handler)"""
	is_drawing = true
	drawn_card = await draw_card_from_pile()
	is_drawing = false
	if drawn_card:
		# Disable draw pile interaction (already drew)
		if draw_pile_visual:
			draw_pile_visual.set_interactive(false)
		
		# Enable discard pile interaction
		if discard_pile_visual:
			discard_pile_visual.set_interactive(true)
		
		# Enable current player's cards for swapping (main grid + penalty cards)
		var current_player_id = GameManager.current_player_index
		if current_player_id < player_grids.size():
			var grid = player_grids[current_player_id]
			for i in range(4):
				var card = grid.get_card_at(i)
				if card and card != drawn_card:
					card.is_interactable = true
			for pc in grid.penalty_cards:
				if pc != drawn_card:
					pc.is_interactable = true
		
		turn_ui.update_action("Click your card to swap, OR click discard pile to use ability")

func draw_card_from_pile() -> Card3D:
	"""Draw a card from the draw pile"""
	var card_data = deck_manager.deal_card()
	if not card_data:
		print("Draw pile is empty!")
		return null
	
	# Create the card at draw pile
	var card = card_scene.instantiate()
	add_child(card)
	card.global_position = draw_pile_marker.global_position
	card.initialize(card_data, false)  # Start face down
	card.is_interactable = false  # Can't interact with drawn card directly
	
	print("Drew card: %s" % card_data.get_short_name())
	
	# Get the current player's grid position for positioning the card
	var current_player_id = GameManager.current_player_index
	var current_grid = player_grids[current_player_id] if current_player_id < player_grids.size() else null
	
	if not current_grid:
		return card
	
	# Calculate view position using helper function
	var view_position = get_card_view_position()
	
	# Animate card to view position
	card.move_to(view_position, 0.4, false)
	
	# Set global rotation to face current player
	var view_rotation = get_card_view_rotation()
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
	
	# Tilt the card towards the player
	tilt_card_towards_viewer(card)
	await get_tree().create_timer(0.25).timeout
	
	# Update pile visual
	if draw_pile_visual:
		draw_pile_visual.set_count(deck_manager.get_draw_pile_count())
	
	return card

# ======================================
# PHASE 5: ABILITIES
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
	card.move_to(discard_pile_marker.global_position, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Add to discard pile data
	deck_manager.add_to_discard(card.card_data)
	_unlock_matching()  # New card on discard — matching now allowed
	
	# Update visual
	if discard_pile_visual:
		discard_pile_visual.set_count(deck_manager.discard_pile.size())
		discard_pile_visual.set_top_card(card.card_data)
	
	# Clean up the card
	card.queue_free()
	drawn_card = null
	
	# Check for ability
	var ability = card.card_data.get_ability()
	if ability == CardData.AbilityType.LOOK_OWN:  # 7 or 8
		await execute_ability_look_own()
	elif ability == CardData.AbilityType.LOOK_OPPONENT:  # 9 or 10
		await execute_ability_look_opponent()
	elif ability == CardData.AbilityType.BLIND_SWAP:  # Jack
		await execute_ability_blind_swap()
	elif ability == CardData.AbilityType.LOOK_AND_SWAP:  # Queen
		await execute_ability_look_and_swap()
	else:
		print("No ability on this card")
		end_current_turn()

func execute_ability_look_own() -> void:
	"""Execute 7/8 ability: Look at one of your own cards"""
	print("\n=== Ability: Look at Own Card ===")
	turn_ui.update_action("Select which card to look at")
	
	is_executing_ability = true
	current_ability = CardData.AbilityType.LOOK_OWN
	var grid = player_grids[GameManager.current_player_index]
	
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
	
	is_executing_ability = true
	current_ability = CardData.AbilityType.LOOK_OPPONENT
	
	turn_ui.update_action("Select opponent's card to look at")
	
	# Highlight only NEIGHBOR cards + penalty cards (cyan = targetable)
	var current_player = GameManager.current_player_index
	var neighbors = get_neighbors(current_player)
	for neighbor_idx in neighbors:
		var opponent_grid = player_grids[neighbor_idx]
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
	turn_ui.update_action("Select YOUR card to swap")
	
	is_executing_ability = true
	current_ability = CardData.AbilityType.BLIND_SWAP
	
	var current_player_idx = GameManager.current_player_index
	var neighbors = get_neighbors(current_player_idx)
	
	# Highlight own cards + penalty cards (cyan = your cards to swap)
	var own_grid = player_grids[current_player_idx]
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
		var neighbor_grid = player_grids[neighbor_idx]
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
	turn_ui.update_action("Select YOUR card to look at")
	
	is_executing_ability = true
	current_ability = CardData.AbilityType.LOOK_AND_SWAP
	
	var current_player_idx = GameManager.current_player_index
	var neighbors = get_neighbors(current_player_idx)
	
	# Highlight own cards + penalty cards (cyan = your card to view)
	var own_grid = player_grids[current_player_idx]
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
		var neighbor_grid = player_grids[neighbor_idx]
		for i in range(4):
			var card = neighbor_grid.get_card_at(i)
			if card:
				card.set_highlighted(true)
				card.is_interactable = true
		for card in neighbor_grid.penalty_cards:
			card.set_highlighted(true)
			card.is_interactable = true

func swap_cards(grid_card: Card3D, new_card: Card3D) -> void:
	"""Swap a card in the grid with the drawn card"""
	var grid = player_grids[GameManager.current_player_index]
	
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
			
			# Remove penalty card from grid tracking (also detaches from grid node)
			grid.remove_penalty_card(grid_card)
			deck_manager.add_to_discard(grid_card.card_data)
			_unlock_matching()
			
			# Re-parent to table so it stays in the scene tree for animation
			add_child(grid_card)
			
			# Flip the penalty card face-up and slide to discard pile
			if not grid_card.is_face_up:
				grid_card.flip(true, 0.2)
				await get_tree().create_timer(0.25).timeout
			grid_card.move_to(discard_pile_marker.global_position, 0.3, false)
			await get_tree().create_timer(0.35).timeout
			grid_card.queue_free()
			
			# Add drawn card to the penalty slot
			new_card.is_interactable = true
			if not new_card.card_clicked.is_connected(_on_card_clicked):
				new_card.card_clicked.connect(_on_card_clicked)
			if not new_card.card_right_clicked.is_connected(_on_card_right_clicked):
				new_card.card_right_clicked.connect(_on_card_right_clicked)
			if new_card.get_parent():
				new_card.get_parent().remove_child(new_card)
			grid.add_penalty_card(new_card, true)
			await get_tree().create_timer(0.45).timeout
			
			# Flip drawn card face-down in its new penalty slot
			if new_card.is_face_up:
				new_card.flip(true, 0.3)
			
			if discard_pile_visual:
				discard_pile_visual.set_count(deck_manager.discard_pile.size())
				discard_pile_visual.set_top_card(discarded_card_data)
			
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
	deck_manager.add_to_discard(grid_card.card_data)
	_unlock_matching()  # New card on discard — matching now allowed
	
	# Flip card face-up if not already
	if not grid_card.is_face_up:
		grid_card.flip(true, 0.2)
		await get_tree().create_timer(0.25).timeout
	
	# Animate old card to discard pile
	grid_card.move_to(discard_pile_marker.global_position, 0.3, false)
	await get_tree().create_timer(0.3).timeout
	grid_card.queue_free()
	
	# Add new card to grid using proper method (sets owner_player correctly)
	new_card.is_interactable = true
	# Connect signals (avoid double-connect — check first)
	if not new_card.card_clicked.is_connected(_on_card_clicked):
		new_card.card_clicked.connect(_on_card_clicked)
	if not new_card.card_right_clicked.is_connected(_on_card_right_clicked):
		new_card.card_right_clicked.connect(_on_card_right_clicked)
	
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
	if discard_pile_visual:
		discard_pile_visual.set_count(deck_manager.discard_pile.size())
		discard_pile_visual.set_top_card(discarded_card_data)
	
	print("Swap complete!")
	
	# End turn
	end_current_turn()

func execute_bot_turn(bot_id: int) -> void:
	"""Execute a bot turn with ability decision logic"""
	print("Bot %d executing turn..." % (bot_id + 1))
	
	# Bot draws a card
	drawn_card = await draw_card_from_pile()
	if not drawn_card:
		end_current_turn()
		return
	
	await get_tree().create_timer(0.5).timeout
	
	# Check if drawn card has an ability
	var ability = drawn_card.card_data.get_ability()
	var has_ability = ability != CardData.AbilityType.NONE
	
	# Random decision: 50% chance to use ability if available
	var use_ability = has_ability and (randf() < 0.5)
	
	if use_ability:
		print("Bot deciding to use ability!")
		await execute_bot_ability(bot_id, ability)
	else:
		# Bot randomly picks a card to swap (Option B)
		var grid = player_grids[bot_id]
		var random_position = randi() % 4
		var target_card = grid.get_card_at(random_position)
		
		if target_card:
			await swap_cards(target_card, drawn_card)
		else:
			drawn_card.queue_free()
			end_current_turn()

func execute_bot_ability(bot_id: int, ability: CardData.AbilityType) -> void:
	"""Execute ability logic for bot (Option A)"""
	# Discard the card to activate ability
	var card = drawn_card
	
	# Animate to discard pile
	var discard_pos = discard_pile_marker.global_position
	card.move_to(discard_pos + Vector3(0, 0.05 * deck_manager.discard_pile.size(), 0), 0.3, false)
	await get_tree().create_timer(0.35).timeout
	
	# Add to discard pile data
	deck_manager.add_to_discard(card.card_data)
	_unlock_matching()  # New card on discard — matching now allowed
	
	# Update visual
	if discard_pile_visual:
		discard_pile_visual.set_count(deck_manager.discard_pile.size())
		discard_pile_visual.set_top_card(card.card_data)
	
	# Clean up the card
	card.queue_free()
	drawn_card = null
	
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
			end_current_turn()

func bot_execute_look_own(bot_id: int) -> void:
	"""Bot looks at one of its own cards (7/8 ability) WITH VISUAL ANIMATION"""
	print("Bot executing: Look at own card")
	
	turn_ui.update_action("Bot is looking at own card...")
	
	var grid = player_grids[bot_id]
	var random_pos = randi() % 4
	var target_card = grid.get_card_at(random_pos)
	
	if not target_card:
		end_current_turn()
		return
	
	print("Bot looking at: %s" % target_card.card_data.get_short_name())
	
	# Highlight the card so player can see what bot is looking at
	target_card.set_highlighted(true)
	await get_tree().create_timer(0.3).timeout
	
	# Calculate view position (same as player)
	var view_position = get_card_view_position()
	
	# Animate card to view position
	target_card.move_to(view_position, 0.4, false)
	
	# Set global rotation to face current player (bot)
	var view_rotation = get_card_view_rotation()
	target_card.global_rotation = Vector3(0, view_rotation, 0)
	
	await get_tree().create_timer(0.45).timeout
	
	# Flip face-up so player can see what bot is viewing
	if not target_card.is_face_up:
		target_card.flip(true, 0.3)
		await get_tree().create_timer(0.35).timeout
	
	# Tilt towards viewer
	tilt_card_towards_viewer(target_card)
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
	
	# Return to grid position
	var target_pos = grid.to_global(grid.card_positions[random_pos])
	target_card.move_to(target_pos, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Unhighlight
	target_card.set_highlighted(false)
	
	end_current_turn()

func bot_execute_look_opponent(bot_id: int) -> void:
	"""Bot looks at one opponent's card (9/10 ability) WITH VISUAL ANIMATION"""
	print("Bot executing: Look at opponent card")
	
	turn_ui.update_action("Bot is looking at opponent card...")
	
	# Pick random NEIGHBOR (not just any opponent)
	var opponents = get_neighbors(bot_id)
	
	if opponents.is_empty():
		end_current_turn()
		return
	
	var opponent_id = opponents[randi() % opponents.size()]
	var opponent_grid = player_grids[opponent_id]
	var random_pos = randi() % 4
	var target_card = opponent_grid.get_card_at(random_pos)
	
	if not target_card:
		end_current_turn()
		return
	
	print("Bot looking at opponent %d's card: %s" % [opponent_id + 1, target_card.card_data.get_short_name()])
	
	# Highlight the card so everyone can see what bot is looking at
	target_card.set_highlighted(true)
	await get_tree().create_timer(0.3).timeout
	
	# Calculate view position
	var view_position = get_card_view_position()
	
	# Animate card to view position
	target_card.move_to(view_position, 0.4, false)
	
	# Set global rotation to face current player (bot)
	var view_rotation = get_card_view_rotation()
	target_card.global_rotation = Vector3(0, view_rotation, 0)
	
	await get_tree().create_timer(0.45).timeout
	
	# Flip face-up so everyone can see
	if not target_card.is_face_up:
		target_card.flip(true, 0.3)
		await get_tree().create_timer(0.35).timeout
	
	# Tilt towards viewer
	tilt_card_towards_viewer(target_card)
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
	
	# Return to grid position
	var target_pos = opponent_grid.to_global(opponent_grid.card_positions[random_pos])
	target_card.move_to(target_pos, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Unhighlight
	target_card.set_highlighted(false)
	
	end_current_turn()

func bot_execute_blind_swap(bot_id: int) -> void:
	"""Bot executes blind swap with neighbor (Jack ability) WITH VISUAL ANIMATION"""
	print("Bot executing: Blind swap")
	
	turn_ui.update_action("Bot is doing blind swap...")
	
	var neighbors = get_neighbors(bot_id)
	if neighbors.is_empty():
		print("Bot has no neighbors!")
		end_current_turn()
		return
	
	# Pick random neighbor
	var neighbor_id = neighbors[randi() % neighbors.size()]
	
	# Pick random own card
	var own_grid = player_grids[bot_id]
	var own_pos = randi() % 4
	var own_card = own_grid.get_card_at(own_pos)
	
	# Pick random neighbor card
	var neighbor_grid = player_grids[neighbor_id]
	var neighbor_pos = randi() % 4
	var neighbor_card = neighbor_grid.get_card_at(neighbor_pos)
	
	if not own_card or not neighbor_card:
		end_current_turn()
		return
	
	print("Bot swapping: own card at pos %d with neighbor %d card at pos %d" % [own_pos, neighbor_id + 1, neighbor_pos])
	
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
	
	# Get target positions
	var own_target = neighbor_grid.to_global(neighbor_grid.card_positions[neighbor_pos])
	var neighbor_target = own_grid.to_global(own_grid.card_positions[own_pos])
	
	# Swap in grid arrays
	own_grid.cards[own_pos] = neighbor_card
	neighbor_grid.cards[neighbor_pos] = own_card
	
	# Update owner_player references
	var temp_owner = own_card.owner_player
	own_card.owner_player = neighbor_card.owner_player
	neighbor_card.owner_player = temp_owner
	
	# Remove early rotation reset - will be corrected after reparenting
	
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
	own_card.position = neighbor_grid.card_positions[neighbor_pos]
	own_card.base_position = neighbor_grid.to_global(neighbor_grid.card_positions[neighbor_pos])
	
	if neighbor_card.get_parent() != own_grid:
		neighbor_card.get_parent().remove_child(neighbor_card)
		own_grid.add_child(neighbor_card)
	neighbor_card.rotation = Vector3.ZERO
	neighbor_card.position = own_grid.card_positions[own_pos]
	neighbor_card.base_position = own_grid.to_global(own_grid.card_positions[own_pos])
	
	# Unhighlight
	own_card.set_highlighted(false)
	neighbor_card.set_highlighted(false)
	
	end_current_turn()

func bot_execute_look_and_swap(bot_id: int) -> void:
	"""Bot executes look and swap (Queen ability) WITH VISUAL ANIMATION"""
	print("Bot executing: Look and swap")
	
	turn_ui.update_action("Bot is using Queen ability...")
	
	var neighbors = get_neighbors(bot_id)
	if neighbors.is_empty():
		print("Bot has no neighbors!")
		end_current_turn()
		return
	
	# Pick random neighbor
	var neighbor_id = neighbors[randi() % neighbors.size()]
	
	# Pick random own card
	var own_grid = player_grids[bot_id]
	var own_pos = randi() % 4
	var own_card = own_grid.get_card_at(own_pos)
	
	# Pick random neighbor card
	var neighbor_grid = player_grids[neighbor_id]
	var neighbor_pos = randi() % 4
	var neighbor_card = neighbor_grid.get_card_at(neighbor_pos)
	
	if not own_card or not neighbor_card:
		end_current_turn()
		return
	
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
	var view_center = get_card_view_position()
	var sideways = get_card_view_sideways()
	var left_pos = view_center - sideways * 1.0
	var right_pos = view_center + sideways * 1.0

	# Unlock elevation before moving to view position
	own_card.is_elevation_locked = false
	neighbor_card.is_elevation_locked = false

	# Set global rotation to face current player (bot)
	var view_rotation = get_card_view_rotation()
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
	
	# Tilt both towards viewer
	var own_tween = own_card.create_tween()
	own_tween.tween_property(own_card, "rotation:x", -0.5, 0.2)
	var neighbor_tween = neighbor_card.create_tween()
	neighbor_tween.tween_property(neighbor_card, "rotation:x", -0.5, 0.2)
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
		
		# Remove the early wrong rotation reset - reparenting handles it
		var own_target = neighbor_grid.to_global(neighbor_grid.card_positions[neighbor_pos])
		var neighbor_target = own_grid.to_global(own_grid.card_positions[own_pos])
		
		# Swap in grid arrays
		own_grid.cards[own_pos] = neighbor_card
		neighbor_grid.cards[neighbor_pos] = own_card
		
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
		own_card.position = neighbor_grid.card_positions[neighbor_pos]
		own_card.base_position = neighbor_grid.to_global(neighbor_grid.card_positions[neighbor_pos])
		
		if neighbor_card.get_parent() != own_grid:
			neighbor_card.get_parent().remove_child(neighbor_card)
			own_grid.add_child(neighbor_card)
		neighbor_card.rotation = Vector3.ZERO
		neighbor_card.position = own_grid.card_positions[own_pos]
		neighbor_card.base_position = own_grid.to_global(own_grid.card_positions[own_pos])
	else:
		print("Bot deciding NOT to swap")
		
		# Flip back face-down
		if own_card.is_face_up:
			own_card.flip(false, 0.3)
		if neighbor_card.is_face_up:
			neighbor_card.flip(false, 0.3)
		await get_tree().create_timer(0.35).timeout
		
		# Return to original positions (no reparenting needed - cards stay in original grids)
		var own_original = own_grid.to_global(own_grid.card_positions[own_pos])
		var neighbor_original = neighbor_grid.to_global(neighbor_grid.card_positions[neighbor_pos])
		
		own_card.move_to(own_original, 0.4, false)
		neighbor_card.move_to(neighbor_original, 0.4, false)
		await get_tree().create_timer(0.45).timeout
		
		# Correct rotation (cards are still children of their original grids)
		own_card.rotation = Vector3.ZERO
		neighbor_card.rotation = Vector3.ZERO
		own_card.position = own_grid.card_positions[own_pos]
		own_card.base_position = own_grid.to_global(own_grid.card_positions[own_pos])
		neighbor_card.position = neighbor_grid.card_positions[neighbor_pos]
		neighbor_card.base_position = neighbor_grid.to_global(neighbor_grid.card_positions[neighbor_pos])
	
	# Unlock and lower
	own_card.is_elevation_locked = false
	neighbor_card.is_elevation_locked = false
	own_card.lower(0.2)
	neighbor_card.lower(0.2)
	await get_tree().create_timer(0.25).timeout
	
	# Unhighlight
	own_card.set_highlighted(false)
	neighbor_card.set_highlighted(false)
	
	end_current_turn()


# ======================================
# PHASE 6: FAST REACTION MATCHING SYSTEM
# ======================================

func _unlock_matching() -> void:
	"""Called whenever a match attempt finishes (success or fail)."""
	is_processing_match = false
	is_choosing_give_card = false
	give_card_target_player_idx = -1
	print("[Match] Match processing complete")

func _on_card_right_clicked(card: Card3D) -> void:
	"""Right-click a card to attempt to match it against the current discard pile top card."""
	# Block during ability execution
	if is_executing_ability:
		return
	# Block while waiting for human to choose a give-card
	if is_choosing_give_card:
		return
	# Block before the game starts
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	# Block if currently resolving another match
	if is_processing_match:
		print("[Match] Already resolving a match")
		return
	# Need a card on the discard pile
	var top = deck_manager.peek_top_discard()
	if not top:
		print("[Match] No card on discard pile")
		return
	print("[Match] Right-click attempt: %s vs top discard %s" % [
		card.card_data.get_short_name(), top.get_short_name()])
	await _attempt_match(card)

func _attempt_match(card: Card3D) -> void:
	"""Attempt to match a right-clicked card against the top of the discard pile.
	The card always animates: lift → slide to discard → flip face-up (reveal).
	Outcome (success / fail) is determined after the reveal."""
	var top_discard = deck_manager.peek_top_discard()
	if not top_discard:
		return
	
	# Lock immediately so two simultaneous right-clicks can't both resolve
	is_processing_match = true
	
	# Determine outcome and owner BEFORE any animation (card still in grid)
	var matches = (card.card_data.rank == top_discard.rank)
	var owner_idx = _find_card_owner_idx(card)
	
	# Guard: card must belong to someone (not a floating drawn card)
	if owner_idx == -1:
		is_processing_match = false
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
	if card.get_parent() != self:
		card.get_parent().remove_child(card)
		add_child(card)
		card.global_position = mid_global
	
	# STEP 3: Slide toward discard pile (slightly above)
	var discard_above = discard_pile_marker.global_position + Vector3(0, 0.4, 0)
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
	
	# Clear the grid slot (card already reparented to game_table in _attempt_match)
	var grid = player_grids[owner_idx]
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
	card.move_to(discard_pile_marker.global_position, 0.2, false)
	await get_tree().create_timer(0.25).timeout
	
	# Register on discard and update visual
	deck_manager.add_to_discard(card.card_data)
	if discard_pile_visual:
		discard_pile_visual.set_count(deck_manager.discard_pile.size())
		discard_pile_visual.set_top_card(card.card_data)
	
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
	
	# Remove card from opponent's grid (card already reparented to game_table in _attempt_match)
	var opponent_grid = player_grids[card_owner_idx]
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
	card.move_to(discard_pile_marker.global_position, 0.2, false)
	await get_tree().create_timer(0.25).timeout
	
	deck_manager.add_to_discard(card.card_data)
	if discard_pile_visual:
		discard_pile_visual.set_count(deck_manager.discard_pile.size())
		discard_pile_visual.set_top_card(card.card_data)
	card.queue_free()
	
	# Human must now pick one of their own cards to give to the opponent
	give_card_target_player_idx = card_owner_idx
	is_choosing_give_card = true
	_start_give_card_selection(card_owner_idx)

func _start_give_card_selection(target_idx: int) -> void:
	"""Highlight human player's own cards so they can pick one to give to the opponent."""
	print("[Match] Choose one of YOUR cards to give to Player %d" % (target_idx + 1))
	if turn_ui:
		turn_ui.update_action("Choose a card to give to Player %d!" % (target_idx + 1))
	
	var own_grid = player_grids[0]  # Human is always player 0
	for i in range(4):
		var c = own_grid.get_card_at(i)
		if c:
			c.set_highlighted(true)
			c.is_interactable = true
	# Also allow giving a penalty card
	for c in own_grid.penalty_cards:
		c.set_highlighted(true)
		c.is_interactable = true

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
	
	# Reparent back to original grid (preserves global transform)
	card.reparent(original_parent, true)
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
	if deck_manager.can_reshuffle():
		await animate_pile_reshuffle()
	
	var penalty_data = deck_manager.deal_card()
	if not penalty_data:
		print("[Match] No cards left for penalty!")
		return
	
	# Create card at the draw pile (child of game_table for the flight animation)
	var penalty_card = card_scene.instantiate()
	add_child(penalty_card)
	penalty_card.global_position = draw_pile_marker.global_position
	penalty_card.initialize(penalty_data, false)
	penalty_card.card_clicked.connect(_on_card_clicked)
	penalty_card.card_right_clicked.connect(_on_card_right_clicked)
	penalty_card.owner_player = players[player_idx]
	
	# Update draw pile visual immediately
	if draw_pile_visual:
		draw_pile_visual.set_count(deck_manager.get_draw_pile_count())
	
	# Compute the target penalty slot position BEFORE adding to grid
	# (penalty_cards.size() tells us the next free slot index)
	var grid = player_grids[player_idx]
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

# ======================================
# PILE RESHUFFLE ANIMATION
# ======================================

func _on_pile_reshuffled(_card_count: int) -> void:
	pass  # Reshuffle is handled proactively by animate_pile_reshuffle() in start_next_turn()

func animate_pile_reshuffle() -> void:
	"""Perform + animate the discard→draw transfer with a dramatic arc effect.
	The newest top-of-discard card stays (unless it is the only card, in which case
	it also transfers and the discard becomes temporarily empty)."""
	var count = deck_manager.perform_reshuffle()
	if count == 0:
		return
	
	print("=== RESHUFFLE: %d cards arc from discard to draw pile ===" % count)
	
	var discard_pos = discard_pile_marker.global_position
	var draw_pos = draw_pile_marker.global_position
	var arc_peak = (discard_pos + draw_pos) / 2.0 + Vector3(0, 2.0, 0)
	
	# Update discard visual to reflect actual post-reshuffle state
	if discard_pile_visual:
		var remaining = deck_manager.get_discard_pile_count()
		discard_pile_visual.set_count(remaining)
		discard_pile_visual.set_top_card(deck_manager.peek_top_discard())
	
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
		add_child(ghost)
		
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
	if draw_pile_visual:
		draw_pile_visual.set_count(deck_manager.get_draw_pile_count())
	
	print("Reshuffle complete. Draw pile: %d  Discard: %d" % [
		deck_manager.get_draw_pile_count(),
		deck_manager.get_discard_pile_count()])

# ======================================
# TURN END
# ======================================

func end_current_turn() -> void:
	"""End the current turn and move to next player"""
	print("Turn ended\n")
	
	# Clean up
	selected_card = null
	drawn_card = null
	is_drawing = false
	is_executing_ability = false
	current_ability = CardData.AbilityType.NONE
	ability_target_card = null
	awaiting_ability_confirmation = false
	
	# Disable discard pile interaction
	if discard_pile_visual:
		discard_pile_visual.set_interactive(false)
	
	# Move to next turn
	GameManager.next_turn()
	
	await get_tree().create_timer(0.5).timeout
	start_next_turn()

func _on_swap_chosen() -> void:
	"""Called when player chooses to swap cards in Queen ability."""
	print("\n=== Swapping Cards ===")
	
	var card1 = look_and_swap_first_card
	var card2 = look_and_swap_second_card
	
	# Use the grid/slot references captured at selection time — avoids a re-search
	# failure if cards have since been moved to the viewing position.
	var card1_grid = look_and_swap_first_grid
	var card1_position = look_and_swap_first_slot
	var card2_grid = look_and_swap_second_grid
	var card2_position = look_and_swap_second_slot
	
	if not card1_grid or not card2_grid or card1_position == -1 or card2_position == -1:
		push_error("[Queen] _on_swap_chosen: missing grid refs (first=%s slot=%d  second=%s slot=%d)" % [
			str(card1_grid), card1_position, str(card2_grid), card2_position])
		_unlock_queen_ability()
		return
	
	# Get target positions for animation
	var card1_target = card2_grid.to_global(card2_grid.card_positions[card2_position])
	var card2_target = card1_grid.to_global(card1_grid.card_positions[card1_position])
	
	# Flip cards back face-down first
	if card1.is_face_up:
		card1.flip(false, 0.3)
	if card2.is_face_up:
		card2.flip(false, 0.3)
	await get_tree().create_timer(0.35).timeout
	
	# Swap in grid arrays (update ownership)
	card1_grid.cards[card1_position] = card2
	card2_grid.cards[card2_position] = card1
	
	# Update owner_player references
	var temp_owner2 = card1.owner_player
	card1.owner_player = card2.owner_player
	card2.owner_player = temp_owner2
	
	# Animate both cards to their new positions
	card1.move_to(card1_target, 0.4, false)
	card2.move_to(card2_target, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Reparent cards to their new grids so they inherit the correct rotation.
	# Without this, rotation = Vector3.ZERO inherits the OLD grid's Y rotation.
	if card1.get_parent() != card2_grid:
		card1.get_parent().remove_child(card1)
		card2_grid.add_child(card1)
	card1.rotation = Vector3.ZERO
	card1.position = card2_grid.card_positions[card2_position]
	card1.base_position = card2_grid.to_global(card2_grid.card_positions[card2_position])
	
	if card2.get_parent() != card1_grid:
		card2.get_parent().remove_child(card2)
		card1_grid.add_child(card2)
	card2.rotation = Vector3.ZERO
	card2.position = card1_grid.card_positions[card1_position]
	card2.base_position = card1_grid.to_global(card1_grid.card_positions[card1_position])
	
	# Unhighlight all cards
	for grid in player_grids:
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
	end_current_turn()

func _on_no_swap_chosen() -> void:
	"""Called when player chooses NOT to swap cards in Queen ability"""
	print("\n=== Not Swapping - Returning Cards ===")
	
	var card1 = look_and_swap_first_card
	var card2 = look_and_swap_second_card
	var grid1 = look_and_swap_first_grid
	var slot1 = look_and_swap_first_slot
	var grid2 = look_and_swap_second_grid
	var slot2 = look_and_swap_second_slot
	
	# Flip cards back face-down first
	if card1.is_face_up:
		card1.flip(false, 0.3)
	if card2.is_face_up:
		card2.flip(false, 0.3)
	await get_tree().create_timer(0.35).timeout
	
	# Slide back to original grid slot positions
	card1.move_to(look_and_swap_first_original_pos, 0.4, false)
	card2.move_to(look_and_swap_second_original_pos, 0.4, false)
	await get_tree().create_timer(0.45).timeout
	
	# Reparent cards back to their original grids so rotation is inherited correctly
	if grid1 and slot1 != -1:
		if card1.get_parent() != grid1:
			card1.get_parent().remove_child(card1)
			grid1.add_child(card1)
		card1.rotation = Vector3.ZERO
		card1.position = grid1.card_positions[slot1]
		card1.base_position = grid1.to_global(grid1.card_positions[slot1])
	if grid2 and slot2 != -1:
		if card2.get_parent() != grid2:
			card2.get_parent().remove_child(card2)
			grid2.add_child(card2)
		card2.rotation = Vector3.ZERO
		card2.position = grid2.card_positions[slot2]
		card2.base_position = grid2.to_global(grid2.card_positions[slot2])
	
	# Unlock elevation and lower cards
	card1.is_elevation_locked = false
	card2.is_elevation_locked = false
	card1.lower(0.2)
	card2.lower(0.2)
	await get_tree().create_timer(0.25).timeout
	
	# Unhighlight all cards
	for grid in player_grids:
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
	end_current_turn()
