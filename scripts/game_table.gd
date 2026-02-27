extends Node3D
## Main game table controller - orchestrates components for the game board

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
