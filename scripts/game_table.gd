extends Node3D
## Main game table controller - orchestrates components for the game board

@onready var camera_controller = $CameraController
@onready var players_container = $Players
@onready var draw_pile_marker = $PositionMarkers/DrawPile
@onready var discard_pile_marker = $PositionMarkers/DiscardPile
@onready var table_model = $TableModel

var discard_label_3d: Label3D = null

# Table model configuration
const TARGET_TABLE_RADIUS := 6.0  # Must match the gameplay radius
const TARGET_SURFACE_Y := 0.76   # Table surface aligned with old gameplay height
var table_surface_y := 0.76  # Y height of the table surface after positioning

var deck_manager: DeckManager
var card_scene = preload("res://scenes/cards/card_3d.tscn")
var player_grid_scene = preload("res://scenes/players/player_grid.tscn")
var card_pile_scene = preload("res://scenes/cards/card_pile.tscn")
var viewing_ui_scene = preload("res://scenes/ui/viewing_ui.tscn")
var turn_ui_scene = preload("res://scenes/ui/turn_ui.tscn")
var swap_choice_ui_scene = preload("res://scenes/ui/swap_choice_ui.tscn")
var round_end_ui_scene = preload("res://scenes/ui/round_end_ui.tscn")

var player_grids: Array[PlayerGrid] = []
var players: Array[Player] = []
var num_players: int = 2
var is_dealing: bool = false

var draw_pile_visual: CardPile = null
var discard_pile_visual: CardPile = null
var viewing_ui = null  # ViewingUI instance
var turn_ui = null  # TurnUI instance
var swap_choice_ui = null  # SwapChoiceUI instance
var round_end_ui = null  # RoundEndUI instance

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
var look_and_swap_first_slot: int = -1        # main-grid slot (-1 if penalty card)
var look_and_swap_first_penalty_slot: int = -1  # penalty slot (-1 if main-grid card)
var look_and_swap_second_grid = null  # PlayerGrid
var look_and_swap_second_slot: int = -1       # main-grid slot (-1 if penalty card)
var look_and_swap_second_penalty_slot: int = -1 # penalty slot (-1 if main-grid card)

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
var give_card_needs_turn_start: bool = false  # True when start_next_turn returned early due to pending give-card
var match_claimed: bool = false  # True after a successful match; blocks further matches until a new card reaches the discard pile from the draw pile

# Component references
var view_helper: CardViewHelper = null
var dealing_manager: DealingManager = null
var viewing_manager: ViewingPhaseManager = null
var turn_manager: TurnManager = null
var ability_manager: AbilityManager = null
var bot_ai_manager: BotAIManager = null
var match_manager: MatchManager = null
var knock_manager: KnockManager = null
var scoring_manager: ScoringManager = null

func _ready() -> void:
	print("=== Felix Card Game - Game Table Ready ===")
	
	# Setup the 3D table model (measure, scale, position)
	_setup_table_model()
	
	# Initialize components
	view_helper = CardViewHelper.new()
	view_helper.init(self)
	add_child(view_helper)
	
	dealing_manager = DealingManager.new()
	dealing_manager.init(self)
	add_child(dealing_manager)
	
	viewing_manager = ViewingPhaseManager.new()
	viewing_manager.init(self)
	add_child(viewing_manager)
	
	turn_manager = TurnManager.new()
	turn_manager.init(self)
	add_child(turn_manager)
	
	ability_manager = AbilityManager.new()
	ability_manager.init(self)
	add_child(ability_manager)
	
	bot_ai_manager = BotAIManager.new()
	bot_ai_manager.init(self)
	add_child(bot_ai_manager)
	
	match_manager = MatchManager.new()
	match_manager.init(self)
	add_child(match_manager)
	
	knock_manager = KnockManager.new()
	knock_manager.init(self)
	add_child(knock_manager)
	
	scoring_manager = ScoringManager.new()
	scoring_manager.init(self)
	add_child(scoring_manager)
	
	# Initialize deck manager
	deck_manager = DeckManager.new()
	add_child(deck_manager)
	deck_manager.create_standard_deck()
	deck_manager.shuffle()
	deck_manager.pile_reshuffled.connect(turn_manager._on_pile_reshuffled)
	
	# Create card pile visuals
	setup_card_piles()
	
	# Create viewing UI
	viewing_ui = viewing_ui_scene.instantiate()
	add_child(viewing_ui)
	viewing_ui.ready_pressed.connect(viewing_manager._on_player_ready_pressed)
	
	# Create turn UI
	turn_ui = turn_ui_scene.instantiate()
	add_child(turn_ui)
	
	# Connect discard signal to update 3D discard label
	Events.card_discarded.connect(_on_card_discarded_ui)
	
	# Create swap choice UI (Queen ability)
	swap_choice_ui = swap_choice_ui_scene.instantiate()
	add_child(swap_choice_ui)
	swap_choice_ui.swap_chosen.connect(ability_manager._on_swap_chosen)
	swap_choice_ui.no_swap_chosen.connect(ability_manager._on_no_swap_chosen)
	
	# Create round end UI
	round_end_ui = round_end_ui_scene.instantiate()
	add_child(round_end_ui)
	round_end_ui.play_again_pressed.connect(_on_play_again_pressed)
	
	# Connect game state signals for round end
	Events.game_state_changed.connect(_on_game_state_changed)
	
	# Setup players
	setup_players(num_players)
	
	print("\nPress ENTER to deal cards")
	print("Press 1-4 to change player count")
	print("Press T to toggle test mode (ability cards: 7/8/9/10)")
	print("Press Y to toggle match test mode (only 7s and 8s)")
	print("Press SPACE to flip all cards")
	print("Press F to shake camera")
	print("Press A to auto-ready other players (debug)")
	print("Press D to draw card during your turn")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Deal cards
		if event.keycode == KEY_ENTER and not is_dealing:
			dealing_manager.deal_cards_to_all_players()
		
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
				ability_manager.confirm_ability_viewing()
			else:
				flip_all_cards()
		
		# Camera shake
		elif event.keycode == KEY_F:
			camera_controller.shake(0.2, 0.5)
			print("Camera shake!")
		
		# Debug: Auto-ready all other players (for testing)
		elif event.keycode == KEY_A:
			viewing_manager.auto_ready_other_players()
		
		# Toggle test mode (ability cards)
		elif event.keycode == KEY_T:
			if GameManager.current_state == GameManager.GameState.SETUP:
				deck_manager.toggle_test_mode()
				if draw_pile_visual:
					draw_pile_visual.set_count(deck_manager.get_draw_pile_count())
			else:
				print("Can only toggle test mode before dealing cards")
		
		# Toggle match test mode (7s and 8s only)
		elif event.keycode == KEY_Y:
			if GameManager.current_state == GameManager.GameState.SETUP:
				deck_manager.toggle_match_test_mode()
				if draw_pile_visual:
					draw_pile_visual.set_count(deck_manager.get_draw_pile_count())
			else:
				print("Can only toggle match test mode before dealing cards")
		
		# Draw card (Phase 4) — works in PLAYING and KNOCKED states
		elif event.keycode == KEY_D:
			if (GameManager.current_state == GameManager.GameState.PLAYING or GameManager.current_state == GameManager.GameState.KNOCKED) and is_player_turn and not drawn_card and not is_drawing:
				# Hide knock buttons once player starts drawing
				knock_manager.hide_all_buttons()
				turn_manager.handle_draw_card()

# ===========================================
# TABLE MODEL SETUP (GLB import)
# ===========================================

func _setup_table_model() -> void:
	"""Measure the imported GLB model using global transforms (handles FBX axis
	conversion, intermediate scales/rotations etc.), scale it so the TABLE mesh
	radius matches TARGET_TABLE_RADIUS, position it so the bottom rests on floor."""
	if not table_model:
		push_warning("TableModel node not found – falling back to no table.")
		return

	# Ensure identity transform for measurement
	table_model.transform = Transform3D.IDENTITY

	# --- Debug: print full node tree including scale ---
	print("\n=== Table Model Node Tree ===")
	_print_model_tree(table_model, 0)

	# --- Collect all mesh instances ---
	var all_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(table_model, all_meshes)
	if all_meshes.is_empty():
		push_warning("No meshes found in table model!")
		return

	# --- Find the table mesh by name (contains "table", case-insensitive) ---
	var table_mesh: MeshInstance3D = null
	for mi in all_meshes:
		if mi.name.to_lower().contains("table"):
			table_mesh = mi
			break

	# --- Get world-space AABBs using global_transform (accounts for all parent transforms) ---
	var table_world_aabb: AABB
	if table_mesh:
		table_world_aabb = _mesh_world_aabb(table_mesh)
		print("\n=== Table Mesh (world space, via global_transform) ===")
		print("  Node name    : ", table_mesh.name)
		print("  World AABB   : pos=%s  size=%s" % [table_world_aabb.position, table_world_aabb.size])
		print("  Global origin: ", table_mesh.global_position)
	else:
		push_warning("Could not find table mesh node – using full model AABB")
		table_world_aabb = _subtree_world_aabb(table_model)

	var full_world_aabb: AABB = _subtree_world_aabb(table_model)
	print("\n=== Full Model (world space) ===")
	print("  World AABB   : pos=%s  size=%s" % [full_world_aabb.position, full_world_aabb.size])

	# --- Compute table radius (XZ plane) ---
	var table_radius: float = maxf(table_world_aabb.size.x, table_world_aabb.size.z) / 2.0
	print("  Table world radius: ", table_radius)

	if table_radius < 0.001:
		push_warning("Table radius is zero – cannot scale. Check GLB import.")
		return

	# --- Scale uniformly so table radius = TARGET_TABLE_RADIUS ---
	var scale_factor: float = TARGET_TABLE_RADIUS / table_radius
	table_model.scale = Vector3.ONE * scale_factor
	print("  Scale factor : ", scale_factor)

	# --- Position: move model so the TABLE SURFACE is at TARGET_SURFACE_Y (0.76) ---
	# This keeps the table top at the same height as the original gameplay setup.
	# Legs/chairs extend below floor level — the room is expanded to accommodate.
	var table_top_before: float = table_world_aabb.position.y + table_world_aabb.size.y
	var scaled_table_top: float = table_top_before * scale_factor
	table_model.position = Vector3(0, TARGET_SURFACE_Y - scaled_table_top, 0)
	table_surface_y = TARGET_SURFACE_Y

	# --- Rotate 45° so chairs align with player cardinal positions (N/S/E/W) ---
	# The GLB model places chairs at diagonals; players sit at cardinal directions.
	table_model.rotation.y = deg_to_rad(45.0)

	# Print where the model bottom ends up (for room sizing)
	var model_bottom_world: float = full_world_aabb.position.y * scale_factor + table_model.position.y
	print("  Table surface Y: ", table_surface_y)
	print("  Model bottom Y : ", model_bottom_world)
	print("  Model offset Y : ", table_model.position.y)

	# --- Update draw/discard pile heights to match ---
	if draw_pile_marker:
		draw_pile_marker.position.y = table_surface_y + 0.01
	if discard_pile_marker:
		discard_pile_marker.position.y = table_surface_y + 0.01

	# --- Print chair world positions after scaling (for verification) ---
	print("\n=== Chair positions after scaling ===")
	for mi in all_meshes:
		if mi.name.to_lower().contains("chair"):
			print("  %s → world pos: %s" % [mi.name, mi.global_position])

	print("=== Table Model Setup Complete ===\n")

# --- Helpers: world-space AABB using global_transform ---

func _mesh_world_aabb(mi: MeshInstance3D) -> AABB:
	"""Get the world-space AABB of a single MeshInstance3D, properly accounting
	for ALL parent transforms (rotation, scale, position)."""
	var mesh_aabb: AABB = mi.mesh.get_aabb()
	return _transform_aabb(mi.global_transform, mesh_aabb)

func _transform_aabb(xform: Transform3D, aabb: AABB) -> AABB:
	"""Transform an AABB by a Transform3D by projecting all 8 corners."""
	var result := AABB(xform * aabb.get_endpoint(0), Vector3.ZERO)
	for i in range(1, 8):
		result = result.expand(xform * aabb.get_endpoint(i))
	return result

func _subtree_world_aabb(root: Node) -> AABB:
	"""Get the combined world-space AABB of all MeshInstance3D nodes under root."""
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, meshes)
	if meshes.is_empty():
		return AABB()
	var result: AABB = _mesh_world_aabb(meshes[0])
	for i in range(1, meshes.size()):
		result = result.merge(_mesh_world_aabb(meshes[i]))
	return result

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	"""Recursively collect all MeshInstance3D nodes with valid meshes."""
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			out.append(mi)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

func _print_model_tree(node: Node, depth: int) -> void:
	"""Debug utility — print the node tree including position, rotation, scale."""
	var indent := ""
	for i in range(depth):
		indent += "  "
	var info := indent + node.name + " (" + node.get_class() + ")"
	if node is Node3D:
		var n3d := node as Node3D
		info += " pos=" + str(n3d.position)
		if n3d.scale != Vector3.ONE:
			info += " scale=" + str(n3d.scale)
		if n3d.rotation != Vector3.ZERO:
			info += " rot=" + str(n3d.rotation)
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var aabb := (node as MeshInstance3D).mesh.get_aabb()
		info += " mesh_aabb=" + str(aabb)
	print(info)
	for child in node.get_children():
		_print_model_tree(child, depth + 1)

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

	# 3D label floating above discard pile
	discard_label_3d = Label3D.new()
	discard_label_3d.text = ""
	discard_label_3d.font_size = 48
	discard_label_3d.modulate = Color(1, 1, 1, 1)
	discard_label_3d.outline_modulate = Color(0, 0, 0, 1)
	discard_label_3d.outline_size = 8
	discard_label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	discard_label_3d.no_depth_test = true
	discard_label_3d.position = Vector3(0, 0.4, 0)
	discard_label_3d.pixel_size = 0.005
	discard_label_3d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	discard_label_3d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	discard_pile_marker.add_child(discard_label_3d)

func setup_players(count: int) -> void:
	"""Initialize player grids and player objects"""
	# Clear existing
	clear_all_players()
	
	num_players = clampi(count, 1, 4)
	
	# Player positions around the round table (surface Y set dynamically)
	var card_y := table_surface_y + 0.01  # Cards sit slightly above table surface
	var positions = [
		Vector3(0, card_y, 3.5),    # Player 0 (South) - Human
		Vector3(0, card_y, -3.5),   # Player 1 (North) - Bot
		Vector3(-4, card_y, 0),     # Player 2 (West) - Bot
		Vector3(4, card_y, 0)       # Player 3 (East) - Bot
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
	view_helper.create_seat_markers()

	# Create 3D knock buttons (one per player grid)
	knock_manager.create_buttons()
	
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

func flip_all_cards() -> void:
	"""Flip all cards on the table"""
	print("\n=== Flipping All Cards ===")
	for grid in player_grids:
		for card in grid.get_valid_cards():
			card.flip()

func _on_card_clicked(card: Card3D) -> void:
	"""Handle card click — dispatch to appropriate component"""
	# Phase 6: Handle give-card selection after a successful opponent match
	if is_choosing_give_card:
		match_manager.handle_give_card_selection(card)
		return
	
	# During gameplay (PLAYING or KNOCKED), handle card selection
	if GameManager.current_state == GameManager.GameState.PLAYING or GameManager.current_state == GameManager.GameState.KNOCKED:
		turn_manager.handle_card_selection(card)
		return
	
	# Debug/testing: flip card
	print("\n=== Card Clicked: %s ===" % card.card_data.get_short_name())
	print("  Score: %d" % card.card_data.get_score())
	print("  Ability: %s" % CardData.AbilityType.keys()[card.card_data.get_ability()])
	print("  Is face up: %s" % card.is_face_up)
	
	card.flip()

func _on_card_right_clicked(card: Card3D) -> void:
	"""Handle card right-click — dispatch to match manager"""
	match_manager.on_card_right_clicked(card)

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
	await turn_manager.play_card_to_discard(drawn_card)

func _on_draw_pile_clicked(_pile: CardPile) -> void:
	"""Handle draw pile click - draw a card"""
	if not is_player_turn:
		print("Not your turn!")
		return
	
	if drawn_card or is_drawing:
		print("Already drew a card!")
		return
	
	if GameManager.current_state != GameManager.GameState.PLAYING and GameManager.current_state != GameManager.GameState.KNOCKED:
		print("Cannot draw now!")
		return
	
	# Hide knock buttons once player starts drawing
	knock_manager.hide_all_buttons()
	
	# Disable draw pile interaction
	if draw_pile_visual:
		draw_pile_visual.set_interactive(false)
	
	# Start drawing
	turn_manager.handle_draw_card()

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

# ======================================
# PHASE 8: KNOCKING & SCORING
# ======================================

# _on_knock_pressed removed — 3D buttons go through knock_manager._on_button_pressed()

func _on_game_state_changed(state_name: String) -> void:
	"""React to game state changes — trigger round end flow."""
	if state_name == "ROUND_END":
		_handle_round_end()

func _handle_round_end() -> void:
	"""Execute the full round-end sequence: reveal, score, show UI."""
	# Hide turn UI and knock buttons
	if turn_ui:
		turn_ui.hide_ui()
	knock_manager.hide_all_buttons()
	
	await scoring_manager.execute_round_end()
	
	# Show round end UI
	var summary = scoring_manager.get_score_summary()
	var scores = scoring_manager.calculate_all_scores()
	var winner_id = scoring_manager.determine_winner(scores)
	var knocker_name = ""
	if GameManager.knocker_id >= 0 and GameManager.knocker_id < players.size():
		knocker_name = players[GameManager.knocker_id].player_name
	if round_end_ui:
		round_end_ui.show_results(summary, winner_id, knocker_name)

func _on_play_again_pressed() -> void:
	"""Start a new round — reset everything and re-deal."""
	print("\n=== Starting New Round ===")
	
	# Reset game state
	GameManager.knocker_id = -1
	GameManager.current_player_index = 0
	GameManager.change_state(GameManager.GameState.SETUP)
	
	# Clear cards from grids (main + penalty)
	for grid in player_grids:
		grid.clear_grid()
		# Also clear penalty cards
		for pc in grid.penalty_cards.duplicate():
			if is_instance_valid(pc):
				pc.queue_free()
		grid.penalty_cards.clear()
		# Clear penalty placeholders
		for ph in grid.penalty_placeholders:
			if is_instance_valid(ph):
				ph.queue_free()
		grid.penalty_placeholders.clear()
	
	# Reset player states (keep total_score)
	for player in players:
		player.has_knocked = false
		player.is_ready = false
		player.current_score = 0
	
	# Reset deck
	deck_manager.reset_deck()
	
	# Reset bot knock counter
	if bot_ai_manager:
		bot_ai_manager.reset_turn_count()

	# Hide any lingering knock buttons
	knock_manager.hide_all_buttons()
	
	# Update pile visuals
	if draw_pile_visual:
		draw_pile_visual.set_count(deck_manager.get_draw_pile_count())
	if discard_pile_visual:
		discard_pile_visual.set_count(0)
		discard_pile_visual.set_top_card(null)
	
	# Reset table state
	selected_card = null
	drawn_card = null
	is_player_turn = false
	is_drawing = false
	is_dealing = false
	is_executing_ability = false
	is_processing_match = false
	is_choosing_give_card = false
	match_claimed = false
	give_card_needs_turn_start = false
	
	# Start dealing
	dealing_manager.deal_cards_to_all_players()

func _on_card_discarded_ui(card_data: Resource) -> void:
	"""Update the 3D discard label floating above the pile."""
	if discard_label_3d and card_data and card_data is CardData:
		var cd: CardData = card_data as CardData
		discard_label_3d.text = cd.get_rank_display()
