extends Node3D
## Main game table controller - orchestrates components for the game board

@export var local_seat_override: int = -1
@export var debug_view_seat_override: int = -1

@onready var camera_controller = $Shell/CameraController
@onready var players_container = $Shell/Players
@onready var draw_pile_marker = $Shell/PositionMarkers/DrawPile
@onready var discard_pile_marker = $Shell/PositionMarkers/DiscardPile
@onready var room_fill_light: OmniLight3D = $Shell/Room/FillLight
@onready var room_front_fill: OmniLight3D = $Shell/Room/FrontFill
@onready var room_back_fill: OmniLight3D = $Shell/Room/BackFill

var discard_label_3d: Label3D = null

## Table surface Y — must match the baked transform in game_table.tscn
## (GLB model scaled ×8.42, positioned so surface = 6.76, floor at Y=0)
@export_group("Table Layout")
@export var table_surface_y: float = 6.76
@export var seat_camera_radius: float = 9.5
@export var seat_camera_height_offset: float = 3.2
@export var seat_camera_look_height_offset: float = 0.35

@export_group("Lighting")
@export var local_front_fill_distance: float = 4.6
@export var local_back_fill_distance: float = 7.2
@export var local_fill_height: float = 8.8

@export_group("")
const SEAT_LABELS: Array[String] = ["South", "North", "West", "East"]
const PARTICIPANT_COLORS: Array[Color] = [
	Color(0.2, 0.7, 0.2, 1.0),
	Color(0.7, 0.2, 0.2, 1.0),
	Color(0.2, 0.2, 0.7, 1.0),
	Color(0.7, 0.7, 0.2, 1.0),
]

var deck_manager: DeckManager
var card_scene = preload("res://scenes/cards/card_3d.tscn")
var player_grid_scene = preload("res://scenes/players/player_grid.tscn")
var card_pile_scene = preload("res://scenes/cards/card_pile.tscn")
var viewing_ui_scene = preload("res://scenes/ui/viewing_ui.tscn")
var turn_ui_scene = preload("res://scenes/ui/turn_ui.tscn")
var swap_choice_ui_scene = preload("res://scenes/ui/swap_choice_ui.tscn")
var round_end_ui_scene = preload("res://scenes/ui/round_end_ui.tscn")
var player_body_scene = preload("res://scenes/players/player_body.tscn")
var leave_seat_ui_scene = preload("res://scenes/ui/leave_seat_ui.tscn")
const ParticipantProfileScript = preload("res://scripts/participant_profile.gd")

var player_grids: Array[PlayerGrid] = []
var players: Array[Player] = []
var player_bodies: Dictionary = {}  # seat_index -> PlayerBody
var participant_profiles: Array = []
var seat_contexts: Array[SeatContext] = []
var local_seat_index: int = 0
var num_players: int = 2
var is_dealing: bool = false
var is_local_player_standing: bool = false

var draw_pile_visual: CardPile = null
var discard_pile_visual: CardPile = null
var viewing_ui = null  # ViewingUI instance
var turn_ui = null  # TurnUI instance
var swap_choice_ui = null  # SwapChoiceUI instance
var round_end_ui = null  # RoundEndUI instance
var leave_seat_ui: CanvasLayer = null  # LeaveSeatUI CanvasLayer
var leave_seat_container: Control = null  # The actual Control inside the CanvasLayer
var interaction_label: Label = null  # "Press E to sit" prompt

# Turn system variables
var selected_card: Card3D = null
var drawn_card: Card3D = null
var is_player_turn: bool = false
var is_drawing: bool = false  # Prevent multiple draws per turn
var _optimistic_draw_start_time: float = 0.0  # Timestamp when optimistic draw animation began

# Initial viewing phase state
var initial_view_cards: Dictionary = {}  # player_idx -> [card1, card2]

# Debug: Visual markers for player seating positions
var seat_markers: Array[Node3D] = []

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
var round_controller: FelixRoundController = null

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

	round_controller = FelixRoundController.new()
	round_controller.init(self)
	add_child(round_controller)

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
	swap_choice_ui.swap_chosen.connect(_on_queen_swap_chosen)
	swap_choice_ui.no_swap_chosen.connect(_on_queen_no_swap_chosen)
	
	# Create round end UI
	round_end_ui = round_end_ui_scene.instantiate()
	add_child(round_end_ui)
	round_end_ui.play_again_pressed.connect(_on_play_again_pressed)
	
	# Create leave seat UI
	leave_seat_ui = leave_seat_ui_scene.instantiate()
	add_child(leave_seat_ui)
	leave_seat_container = leave_seat_ui.get_node("Container")
	leave_seat_container.visible = true
	var leave_btn = leave_seat_ui.get_node("Container/LeaveSeatButton")
	if leave_btn:
		leave_btn.pressed.connect(_on_leave_seat_pressed)

	# Create interaction prompt label (needs CanvasLayer to render over 3D)
	var interaction_canvas := CanvasLayer.new()
	interaction_canvas.layer = 10
	add_child(interaction_canvas)
	interaction_label = Label.new()
	interaction_label.text = "Press E to sit"
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interaction_label.add_theme_font_size_override("font_size", 24)
	interaction_label.visible = false
	interaction_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	interaction_label.position = Vector2(-100, -200)
	interaction_label.size = Vector2(200, 40)
	interaction_canvas.add_child(interaction_label)

	# Connect movement service signals
	SteamMovementService.player_stood.connect(_on_player_stood)
	SteamMovementService.player_sat.connect(_on_player_sat)
	SteamMovementService.position_updated.connect(_on_remote_position_updated)

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
	print("Press F1-F4 in setup to move the local participant to another seat")
	print("Press Shift+F1-F4 in setup to preview another seat without moving occupants")
	print("Debug local seat override: %s" % get_seat_label(local_seat_index))
	if debug_view_seat_override >= 0:
		print("Debug camera preview: %s" % get_seat_label(debug_view_seat_override))

func _input(event: InputEvent) -> void:
	# Leave seat: Q key or input action
	var is_leave_seat := event.is_action_pressed("leave_seat")
	if not is_leave_seat and event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		is_leave_seat = true
	if is_leave_seat and not is_local_player_standing:
		_on_leave_seat_pressed()
		get_viewport().set_input_as_handled()
		return

	# Block all card/game interactions while standing
	if is_local_player_standing:
		return

	if event is InputEventKey and event.pressed:
		# Deal cards — host can trigger in multiplayer; local mode uses same key
		if event.keycode == KEY_ENTER and not is_dealing:
			if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
				dealing_manager.deal_cards_to_all_players()

		# Change player count (local only)
		elif event.keycode == KEY_1 and not multiplayer.has_multiplayer_peer():
			change_player_count(1)
		elif event.keycode == KEY_2 and not multiplayer.has_multiplayer_peer():
			change_player_count(2)
		elif event.keycode == KEY_3 and not multiplayer.has_multiplayer_peer():
			change_player_count(3)
		elif event.keycode == KEY_4 and not multiplayer.has_multiplayer_peer():
			change_player_count(4)
		elif event.keycode == KEY_F1:
			if event.shift_pressed:
				_set_debug_view_seat_override(0)
			else:
				_set_debug_local_seat_override(0)
		elif event.keycode == KEY_F2:
			if event.shift_pressed:
				_set_debug_view_seat_override(1)
			else:
				_set_debug_local_seat_override(1)
		elif event.keycode == KEY_F3:
			if event.shift_pressed:
				_set_debug_view_seat_override(2)
			else:
				_set_debug_local_seat_override(2)
		elif event.keycode == KEY_F4:
			if event.shift_pressed:
				_set_debug_view_seat_override(3)
			else:
				_set_debug_local_seat_override(3)
		
		# Flip all cards / Confirm ability viewing
		elif event.keycode == KEY_SPACE:
			if ability_manager.awaiting_ability_confirmation:
				if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
					SteamRoundService.client_request_ability_confirm.rpc_id(1)
					_client_confirm_ability_local()
				else:
					round_controller.request_ability_confirm(local_seat_index)
			else:
				flip_all_cards()
		
		# Camera shake
		elif event.keycode == KEY_F:
			camera_controller.shake(0.2, 0.5)
			print("Camera shake!")
		
		# Debug: Auto-ready all other players (local only)
		elif event.keycode == KEY_A and not multiplayer.has_multiplayer_peer():
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
				if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
					SteamRoundService.client_request_draw.rpc_id(1)
				else:
					round_controller.request_draw(local_seat_index)

# ===========================================
# TABLE MODEL SETUP (GLB import)
# ===========================================

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

	if multiplayer.has_multiplayer_peer():
		var rs := SteamRoomService.get_room_state()
		num_players = rs.get_seated_member_count()
		if num_players < 1:
			num_players = 2
	else:
		num_players = clampi(count, 1, 4)
	local_seat_index = _resolve_local_seat_index(num_players)
	debug_view_seat_override = _sanitize_debug_view_seat_override(num_players)
	seat_contexts.clear()
	_rebuild_participant_profiles(num_players)
	var seat_assignments: Array[int]
	if multiplayer.has_multiplayer_peer():
		seat_assignments = _build_seat_assignments_from_room_state(num_players)
	else:
		seat_assignments = _build_local_participant_seat_assignment(num_players, local_seat_index)
	
	# Player positions around the round table (surface Y set dynamically)
	var card_y := table_surface_y + 0.01  # Cards sit slightly above table surface
	var positions = [
		Vector3(0, card_y, 3.5),
		Vector3(0, card_y, -3.5),
		Vector3(-4, card_y, 0),
		Vector3(4, card_y, 0)
	]
	
	var rotations = [
		0,          # Player 0 faces north
		PI,         # Player 1 faces south
		PI / 2,     # Player 2 faces east
		-PI / 2     # Player 3 faces west
	]
	
	for i in range(num_players):
		var participant_id := seat_assignments[i]
		var participant_profile = get_participant_profile(participant_id)
		var seat_control_type: SeatContext.SeatControlType = participant_profile.control_type if participant_profile != null else SeatContext.SeatControlType.BOT
		var seat_label := get_seat_label(i)
		var seat_context := SeatContext.new().configure(
			i,
			seat_label,
			participant_id,
			participant_profile.display_name if participant_profile != null else "Player %d" % (participant_id + 1),
			seat_control_type,
			participant_profile.is_local if participant_profile != null else i == local_seat_index
		)
		seat_contexts.append(seat_context)

		# Create Player object
		var player = Player.new()
		player.player_id = i
		player.participant_id = participant_id
		player.seat_index = i
		player.seat_label = seat_label
		player.player_name = participant_profile.display_name if participant_profile != null else "Player %d" % (participant_id + 1)
		player.player_color = participant_profile.avatar_color if participant_profile != null else _get_participant_color(participant_id)
		player.set_control_type(seat_control_type)
		players.append(player)
		players_container.add_child(player)
		
		# Create PlayerGrid
		var grid = player_grid_scene.instantiate()
		grid.player_id = i
		grid.owner_seat_id = i
		grid.position = positions[i]
		grid.rotation.y = rotations[i]
		grid.base_rotation_y = rotations[i]  # Store rotation for cards
		grid.set_meta("owner_player", player)
		grid.set_meta("owner_seat_id", i)
		grid.set_meta("occupant_participant_id", participant_id)
		player_grids.append(grid)
		players_container.add_child(grid)
		
		print("Setup %s in %s seat at position %s" % [player.player_name, seat_label, positions[i]])
	
	# Update GameManager
	GameManager.players = players
	GameManager.player_count = num_players
	GameManager.set_seat_contexts(seat_contexts, local_seat_index)
	round_controller.configure_seats(players, seat_contexts, local_seat_index)
	
	# Create debug seat markers
	view_helper.create_seat_markers()

	# Create 3D knock buttons (one per player grid)
	knock_manager.create_buttons()

	# Spawn PlayerBody for each human player
	_spawn_player_bodies()

	_apply_local_seat_camera_view()
	_apply_local_seat_lighting()
	
	if local_seat_index >= 0 and local_seat_index < players.size():
		print("Local participant %s is seated at %s" % [players[local_seat_index].player_name, get_seat_label(local_seat_index)])
	if debug_view_seat_override >= 0:
		print("Debug camera preview is following %s seat (occupants unchanged)" % get_seat_label(debug_view_seat_override))
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
	
	for body in player_bodies.values():
		if is_instance_valid(body):
			body.get_parent().remove_child(body)
			body.queue_free()
	player_bodies.clear()

	player_grids.clear()
	players.clear()
	seat_contexts.clear()

func flip_all_cards() -> void:
	"""Flip all cards on the table"""
	print("\n=== Flipping All Cards ===")
	for grid in player_grids:
		for card in grid.get_valid_cards():
			card.flip()

func _on_card_clicked(card: Card3D) -> void:
	"""Handle card click — dispatch to appropriate component"""
	if is_local_player_standing:
		return
	if GameManager.current_state == GameManager.GameState.PLAYING or GameManager.current_state == GameManager.GameState.KNOCKED:
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			# Give-card selection takes priority and can happen outside of the player's turn
			if match_manager.is_choosing_give_card and match_manager.give_card_actor_seat_idx == local_seat_index:
				var slot_info := _get_card_slot_info(card)
				if slot_info.slot >= 0:
					SteamRoundService.client_request_give_card.rpc_id(1, slot_info.slot, slot_info.is_penalty)
				return
			if not is_player_turn:
				return
			if ability_manager.is_executing_ability:
				# Client: route ability card selection to host
				var slot_info := _get_card_slot_info(card)
				if slot_info.slot >= 0:
					SteamRoundService.client_request_ability_select.rpc_id(1, card.owner_seat_id, slot_info.slot, slot_info.is_penalty)
					var ab_type := ability_manager.current_ability
					if ab_type == CardData.AbilityType.BLIND_SWAP or ab_type == CardData.AbilityType.LOOK_AND_SWAP:
						# Multi-step: full local animation (elevation + highlight)
						ability_manager.handle_ability_target_selection(card)
					elif ab_type == CardData.AbilityType.LOOK_OWN or ab_type == CardData.AbilityType.LOOK_OPPONENT:
						# Single-target: instant highlight so the click feels responsive
						card.set_highlighted(true, true)
						card.elevate(0.15, 0.12)
				return
			# Client: route swap to host via RPC; do local visual swap immediately
			if drawn_card != null:
				var slot_info := _get_card_slot_info(card)
				if slot_info.slot >= 0:
					_apply_client_swap(card, slot_info.slot, slot_info.is_penalty)
					SteamRoundService.client_request_swap.rpc_id(1, slot_info.slot, slot_info.is_penalty)
		else:
			round_controller.request_card_click(local_seat_index, card)
		return
	
	# Debug/testing: flip card
	print("\n=== Card Clicked: %s ===" % card.card_data.get_short_name())
	print("  Score: %d" % card.card_data.get_score())
	print("  Ability: %s" % CardData.AbilityType.keys()[card.card_data.get_ability()])
	print("  Is face up: %s" % card.is_face_up)
	
	card.flip()

func _on_card_right_clicked(card: Card3D) -> void:
	"""Handle card right-click — dispatch to match manager"""
	if is_local_player_standing:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		var slot_info := _get_card_slot_info(card)
		if slot_info.slot >= 0:
			# Optimistic: lift card to signal intent; auto-lower if host rejects
			card.elevate(0.15, 0.12)
			_reset_match_elevation_after_timeout(card)
			SteamRoundService.client_request_match.rpc_id(1, card.owner_seat_id, slot_info.slot, slot_info.is_penalty)
		return
	round_controller.request_match(local_seat_index, card)

func _reset_match_elevation_after_timeout(card: Card3D) -> void:
	"""Lower an optimistically-elevated match card if the host never confirms."""
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(card) and not card.is_queued_for_deletion():
		card.elevate(0.0, 0.15)

func _on_discard_pile_clicked(_pile: CardPile) -> void:
	"""Handle discard pile click - play card to discard and use ability"""
	if is_local_player_standing:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		# Client: animate own drawn card to discard pile before host confirms
		if drawn_card and is_instance_valid(drawn_card):
			var discard_card := drawn_card
			drawn_card = null  # Detach from tracking — snapshot cleanup will skip it
			discard_card.is_interactable = false
			discard_card.rotation = Vector3.ZERO
			discard_card.move_to(discard_pile_marker.global_position, 0.35, false)
		if discard_pile_visual:
			discard_pile_visual.set_interactive(false)
		SteamRoundService.client_request_discard_drawn.rpc_id(1)
	else:
		await round_controller.request_discard_drawn(local_seat_index)

func _on_draw_pile_clicked(_pile: CardPile) -> void:
	if is_local_player_standing:
		return
	"""Handle draw pile click - draw a card"""
	knock_manager.hide_all_buttons()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		# Optimistic: immediately start face-down pick-up animation so the player
		# sees instant feedback. Card identity arrives from host mid-animation.
		if not is_drawing and drawn_card == null and is_player_turn:
			is_drawing = true
			var pending_data := CardData.new()
			pending_data.card_id = -999  # Sentinel: identity pending from host
			var card := card_scene.instantiate() as Card3D
			add_child(card)
			var top_offset := Vector3(0, draw_pile_visual.card_count * 0.01 if draw_pile_visual else 0.0, 0)
			card.global_position = draw_pile_marker.global_position + top_offset
			card.initialize(pending_data, false)
			card.is_interactable = false
			card.card_clicked.connect(_on_card_clicked)
			card.card_right_clicked.connect(_on_card_right_clicked)
			var view_pos := view_helper.get_card_view_position()
			var view_rot := view_helper.get_card_view_rotation()
			card.global_rotation = Vector3(0, view_rot, 0)
			card.move_to(view_pos, 0.6, false)
			drawn_card = card
			_optimistic_draw_start_time = Time.get_ticks_msec() * 0.001
			if draw_pile_visual:
				draw_pile_visual.set_interactive(false)
				draw_pile_visual.set_count(draw_pile_visual.card_count - 1)
			_start_optimistic_draw_timeout()
		SteamRoundService.client_request_draw.rpc_id(1)
	else:
		await round_controller.request_draw(local_seat_index)

func _start_optimistic_draw_timeout() -> void:
	"""Clean up the optimistic draw card if the host never responds within 2 s."""
	await get_tree().create_timer(2.0).timeout
	if drawn_card and is_instance_valid(drawn_card) and drawn_card.card_data.card_id == -999:
		drawn_card.queue_free()
		drawn_card = null
		is_drawing = false
		if draw_pile_visual:
			draw_pile_visual.set_interactive(true)
			draw_pile_visual.set_count(draw_pile_visual.card_count + 1)

func _on_queen_swap_chosen() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		SteamRoundService.client_request_queen_choice.rpc_id(1, true)
		ability_manager._clear_queen_state()
		swap_choice_ui.hide_choice()
		return
	await ability_manager._on_swap_chosen()

func _on_queen_no_swap_chosen() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		SteamRoundService.client_request_queen_choice.rpc_id(1, false)
		ability_manager._clear_queen_state()
		swap_choice_ui.hide_choice()
		return
	await ability_manager._on_no_swap_chosen()

func _client_confirm_ability_local() -> void:
	"""Client-side cleanup after pressing SPACE to confirm an ability — no turn end."""
	var ab := ability_manager
	if not ab.awaiting_ability_confirmation:
		return
	ab.awaiting_ability_confirmation = false
	match ab.current_ability:
		CardData.AbilityType.LOOK_OWN, CardData.AbilityType.LOOK_OPPONENT:
			if ab.ability_target_card and is_instance_valid(ab.ability_target_card):
				var card := ab.ability_target_card
				card.rotation = Vector3.ZERO
				card.flip(false, 0.3)
				# Find the card's actual grid slot to compute the correct return position
				# (base_position was overwritten by move_to(view_pos) during reveal)
				var card_grid = null
				var card_position := -1
				var card_penalty_pos := -1
				for grid in player_grids:
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
				if card_grid:
					var target_pos: Vector3
					if card_position != -1:
						target_pos = card_grid.to_global(card_grid.card_positions[card_position])
					else:
						target_pos = card_grid.to_global(card_grid.penalty_positions[card_penalty_pos])
					card.move_to(target_pos, 0.4, false)
			ab.ability_target_card = null
			ab.is_executing_ability = false
			ab.current_ability = CardData.AbilityType.NONE
		CardData.AbilityType.BLIND_SWAP:
			if ab.blind_swap_first_card and is_instance_valid(ab.blind_swap_first_card):
				ab.blind_swap_first_card.is_elevation_locked = false
				ab.blind_swap_first_card.set_highlighted(false)
			if ab.blind_swap_second_card and is_instance_valid(ab.blind_swap_second_card):
				ab.blind_swap_second_card.is_elevation_locked = false
				ab.blind_swap_second_card.set_highlighted(false)
			ab.blind_swap_first_card = null
			ab.blind_swap_second_card = null
			ab.is_executing_ability = false
			ab.current_ability = CardData.AbilityType.NONE
		CardData.AbilityType.LOOK_AND_SWAP:
			# Keep state until _client_queen_display arrives from host
			pass

func _resolve_local_seat_index(player_count: int) -> int:
	if local_seat_override >= 0:
		return clampi(local_seat_override, 0, max(player_count - 1, 0))
	# In multiplayer, use the seat assigned by SteamRoomService
	if multiplayer.has_multiplayer_peer():
		var rs := SteamRoomService.get_room_state()
		var seat_idx := rs.get_local_seat_index(SteamPlatformService.get_local_steam_id())
		if seat_idx >= 0 and seat_idx < player_count:
			return seat_idx
	return 0

func _sanitize_debug_view_seat_override(player_count: int) -> int:
	if debug_view_seat_override < 0:
		return -1
	if debug_view_seat_override >= player_count:
		return -1
	return debug_view_seat_override

func _rebuild_participant_profiles(player_count: int) -> void:
	participant_profiles.clear()
	if multiplayer.has_multiplayer_peer():
		# Build profiles from SteamRoomService — is_local and control_type already stamped
		var rs := SteamRoomService.get_room_state()
		participant_profiles.resize(player_count)
		for pid_variant in rs.participants_by_id.keys():
			var pid := int(pid_variant)
			if pid < player_count:
				participant_profiles[pid] = rs.participants_by_id[pid_variant]
		return
	for participant_id in range(player_count):
		var control_type := SeatContext.SeatControlType.LOCAL_HUMAN if participant_id == 0 else SeatContext.SeatControlType.BOT
		var participant_profile = ParticipantProfileScript.new().configure(
			participant_id,
			"Player %d" % (participant_id + 1),
			_get_participant_color(participant_id),
			control_type,
			participant_id == 0
		)
		participant_profiles.append(participant_profile)

func _build_seat_assignments_from_room_state(player_count: int) -> Array[int]:
	var seat_assignments: Array[int] = []
	seat_assignments.resize(player_count)
	var rs := SteamRoomService.get_room_state()
	for seat in rs.seat_states:
		if seat.is_occupied() and seat.seat_index < player_count:
			seat_assignments[seat.seat_index] = seat.occupant_participant_id
	return seat_assignments

func _build_local_participant_seat_assignment(player_count: int, desired_local_seat: int) -> Array[int]:
	var seat_assignments: Array[int] = []
	seat_assignments.resize(player_count)
	if player_count <= 0:
		return seat_assignments

	var local_participant_id := 0
	var clamped_local_seat := clampi(desired_local_seat, 0, max(player_count - 1, 0))
	seat_assignments[clamped_local_seat] = local_participant_id

	var available_seats: Array[int] = []
	for seat_id in range(player_count):
		if seat_id != clamped_local_seat:
			available_seats.append(seat_id)

	for participant_id in range(1, player_count):
		seat_assignments[available_seats[participant_id - 1]] = participant_id

	return seat_assignments

func get_participant_profile(participant_id: int):
	return participant_profiles[participant_id] if participant_id >= 0 and participant_id < participant_profiles.size() else null

func get_participant_profile_for_seat(seat_id: int):
	var context := get_seat_context(seat_id)
	if context == null:
		return null
	return get_participant_profile(context.occupant_participant_id)

func get_seat_label(seat_id: int) -> String:
	if seat_id >= 0 and seat_id < SEAT_LABELS.size():
		return SEAT_LABELS[seat_id]
	return "Seat %d" % (seat_id + 1)

func _get_participant_color(participant_id: int) -> Color:
	if participant_id >= 0 and participant_id < PARTICIPANT_COLORS.size():
		return PARTICIPANT_COLORS[participant_id]
	return Color(0.8, 0.8, 0.8, 1.0)

func get_seat_context(seat_id: int) -> SeatContext:
	return seat_contexts[seat_id] if seat_id >= 0 and seat_id < seat_contexts.size() else null

func get_player_grid(idx: int) -> PlayerGrid:
	"""Bounds-checked accessor for player_grids. Returns null and logs an error on invalid index."""
	if idx < 0 or idx >= player_grids.size():
		push_error("GameTable: invalid player_grid index %d (size=%d)" % [idx, player_grids.size()])
		return null
	return player_grids[idx]

func is_local_seat(seat_id: int) -> bool:
	return seat_id == local_seat_index

func is_bot_seat(seat_id: int) -> bool:
	var context := get_seat_context(seat_id)
	return context != null and context.is_bot()

func can_local_seat_act(seat_id: int) -> bool:
	return is_local_seat(seat_id) and seat_id == GameManager.current_player_index

func _set_debug_local_seat_override(seat_id: int) -> void:
	if is_dealing or GameManager.current_state != GameManager.GameState.SETUP:
		print("Debug local seat override can only be changed before dealing.")
		return
	local_seat_override = seat_id
	print("Debug local seat override set to %s seat" % get_seat_label(seat_id))
	setup_players(num_players)

func _set_debug_view_seat_override(seat_id: int) -> void:
	if is_dealing or GameManager.current_state != GameManager.GameState.SETUP:
		print("Debug camera preview can only be changed before dealing.")
		return

	var clamped_seat_id := clampi(seat_id, 0, max(num_players - 1, 0))
	if debug_view_seat_override == clamped_seat_id:
		debug_view_seat_override = -1
		print("Debug camera preview cleared. Following local seat %s." % get_seat_label(local_seat_index))
	else:
		debug_view_seat_override = clamped_seat_id
		print("Debug camera preview set to %s seat. Occupants unchanged." % get_seat_label(clamped_seat_id))

	_apply_local_seat_camera_view()
	_apply_local_seat_lighting()

func _apply_local_seat_camera_view() -> void:
	var active_view_seat := get_active_view_seat_index()
	if not camera_controller or active_view_seat < 0 or active_view_seat >= player_grids.size():
		return
	var seat_direction := _get_seat_direction(active_view_seat)
	var camera_pos := seat_direction * seat_camera_radius
	camera_pos.y = table_surface_y + seat_camera_height_offset
	var look_target := Vector3(0, table_surface_y + seat_camera_look_height_offset, 0)
	camera_controller.set_view(camera_pos, look_target)

func _apply_local_seat_lighting() -> void:
	var seat_direction := _get_seat_direction(get_active_view_seat_index())
	if room_fill_light:
		room_fill_light.global_position = Vector3(0, local_fill_height, 0)
	if room_front_fill:
		room_front_fill.global_position = Vector3(
			seat_direction.x * local_front_fill_distance,
			local_fill_height,
			seat_direction.z * local_front_fill_distance
		)
	if room_back_fill:
		room_back_fill.global_position = Vector3(
			seat_direction.x * local_back_fill_distance,
			local_fill_height,
			seat_direction.z * local_back_fill_distance
		)

func get_active_view_seat_index() -> int:
	if debug_view_seat_override >= 0 and debug_view_seat_override < player_grids.size():
		return debug_view_seat_override
	return local_seat_index

func _get_seat_direction(seat_id: int) -> Vector3:
	if seat_id < 0 or seat_id >= player_grids.size():
		return Vector3(0, 0, 1)
	var grid_pos := player_grids[seat_id].global_position
	var seat_direction := Vector3(grid_pos.x, 0.0, grid_pos.z)
	if seat_direction.length() < 0.001:
		return Vector3(0, 0, 1)
	return seat_direction.normalized()

func _find_card_owner_idx(card: Card3D) -> int:
	"""Return the player index who owns this card, or -1 if not found"""
	for i in range(player_grids.size()):
		for j in range(4):
			if player_grids[i].get_card_at(j) == card:
				return i
		for pc in player_grids[i].penalty_cards:
			if pc == card:
				return i
	if card and card.owner_seat_id >= 0:
		return card.owner_seat_id
	return -1

# ======================================
# PHASE 8: KNOCKING & SCORING
# ======================================

# _on_knock_pressed removed — 3D buttons go through knock_manager._on_button_pressed()

func _on_game_state_changed(state_name: String) -> void:
	"""React to game state changes — trigger round end flow."""
	if state_name == "ROUND_END":
		# Force all standing players back to seated
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			SteamMovementService.force_sit_all()
		elif not multiplayer.has_multiplayer_peer():
			if is_local_player_standing:
				SteamMovementService.local_sit(local_seat_index)
		if leave_seat_container:
			leave_seat_container.visible = false
		_handle_round_end()
	elif state_name == "DEALING" or state_name == "INITIAL_VIEWING" or state_name == "PLAYING" or state_name == "KNOCKED":
		_show_leave_seat_ui()

func _handle_round_end() -> void:
	"""Execute the full round-end sequence: reveal, score, show UI."""
	# In multiplayer, host broadcasts full card data to all clients first
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		SteamRoundService.broadcast_round_end_to_all(self)
	# Hide turn UI and knock buttons
	if turn_ui:
		turn_ui.hide_ui()
	knock_manager.hide_all_buttons()

	await scoring_manager.execute_round_end()

	# Host: push round scores into the session scoreboard so it survives between rounds
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var scoreboard = SteamRoomService.room_state.session_scoreboard
		if scoreboard != null:
			for player in players:
				scoreboard.add_score(player.participant_id, player.current_score)

	# Show round end UI
	var summary = scoring_manager.get_score_summary()
	var scores = scoring_manager.calculate_all_scores()
	var winner_id = scoring_manager.determine_winner(scores)
	var knocker_name = ""
	if GameManager.knocker_id >= 0 and GameManager.knocker_id < players.size():
		knocker_name = players[GameManager.knocker_id].player_name
	if round_end_ui:
		var is_mp := multiplayer.has_multiplayer_peer()
		round_end_ui.show_results(summary, winner_id, knocker_name, is_mp, is_mp and multiplayer.is_server())

func _on_play_again_pressed() -> void:
	"""Start a new round — or return to Steam room in multiplayer."""
	# Reset movement state
	SteamMovementService.reset()
	is_local_player_standing = false

	if multiplayer.has_multiplayer_peer():
		if SteamRoomService.is_local_host():
			SteamRoomService.finish_active_round()
		return
	print("\n=== Starting New Round ===")
	
	# Reset game state
	round_controller.prepare_new_round_metadata()
	
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
		player.cards.clear()
		player.has_knocked = false
		player.is_ready = false
		player.current_score = 0
	if round_controller:
		round_controller.sync_scores_from_players(players)
	
	# Reset deck
	deck_manager.reset_deck()
	
	# Reset bot knock counter
	if bot_ai_manager:
		bot_ai_manager.reset_turn_count()

	# Hide any lingering knock buttons
	knock_manager.hide_all_buttons()

	# Clear persistent rank labels from the previous round
	get_tree().call_group("round_end_rank_labels", "queue_free")
	
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
	ability_manager.reset_state()
	match_manager.reset_state()
	round_controller.sync_runtime_state()
	
	# Start dealing
	dealing_manager.deal_cards_to_all_players()

func _on_card_discarded_ui(card_data: Resource) -> void:
	"""Update the 3D discard label floating above the pile."""
	if discard_label_3d and card_data and card_data is CardData:
		var cd: CardData = card_data as CardData
		discard_label_3d.text = cd.get_rank_display()

func _get_card_slot_info(card: Card3D) -> Dictionary:
	"""Return {slot, is_penalty} for a card in any player grid, or slot=-1 if not found."""
	for grid in player_grids:
		for i in range(4):
			if grid.get_card_at(i) == card:
				return {"slot": i, "is_penalty": false}
		for i in range(grid.penalty_cards.size()):
			if grid.penalty_cards[i] == card:
				return {"slot": i, "is_penalty": true}
	return {"slot": -1, "is_penalty": false}

func _apply_client_swap(old_card: Card3D, slot: int, is_penalty: bool) -> void:
	"""Client-side visual swap: animate old card to discard, drawn card into grid slot."""
	if drawn_card == null:
		return
	var grid = player_grids[local_seat_index]
	# Disable all interactions immediately
	if discard_pile_visual:
		discard_pile_visual.set_interactive(false)
	for g in player_grids:
		for i in range(4):
			var c = g.get_card_at(i)
			if c:
				c.is_interactable = false
	# Compute target position for the new card
	var target_pos: Vector3
	if is_penalty:
		target_pos = grid.to_global(grid.penalty_positions[slot]) if slot < grid.penalty_positions.size() else grid.global_position
	else:
		target_pos = grid.to_global(grid.card_positions[slot])
	# Animate old card to discard pile
	var discard_pos: Vector3 = discard_pile_marker.global_position
	old_card.is_interactable = false
	old_card.rotation = Vector3.ZERO
	old_card.move_to(discard_pos, 0.35, false)
	# Animate drawn card to grid slot
	var new_card := drawn_card
	drawn_card = null
	new_card.is_interactable = false
	new_card.rotation = Vector3.ZERO
	if new_card.is_face_up:
		new_card.flip(false, 0.3)
	new_card.move_to(target_pos, 0.4, false)
	# Update data immediately (don't wait for animation)
	deck_manager.add_to_discard(old_card.card_data)
	if discard_pile_visual:
		discard_pile_visual.set_count(deck_manager.discard_pile.size())
		discard_pile_visual.set_top_card(old_card.card_data)
	# Clear old card from grid and place new card
	if is_penalty:
		if slot >= 0 and slot < grid.penalty_cards.size():
			grid.penalty_cards[slot] = new_card
	else:
		grid.cards[slot] = new_card
	# Reparent new card to grid after a short delay
	await get_tree().create_timer(0.45).timeout
	if is_instance_valid(old_card):
		old_card.queue_free()
	if is_instance_valid(new_card):
		if new_card.get_parent() != grid:
			new_card.get_parent().remove_child(new_card)
			grid.add_child(new_card)
		if is_penalty:
			new_card.position = grid.penalty_positions[slot] if slot < grid.penalty_positions.size() else Vector3.ZERO
		else:
			new_card.position = grid.card_positions[slot]
		new_card.base_position = new_card.global_position
		new_card.rotation = Vector3.ZERO

# ======================================
# PLAYER MOVEMENT / SIT-STAND SYSTEM
# ======================================

const CHAIR_POSITIONS: Array[Vector3] = [
	Vector3(0, 0, 5.5),    # South
	Vector3(0, 0, -5.5),   # North
	Vector3(-5.5, 0, 0),   # West
	Vector3(5.5, 0, 0),    # East
]

const CHAIR_FACE_DIRECTIONS: Array[Vector3] = [
	Vector3(0, 0, 1),    # South faces outward (+Z)
	Vector3(0, 0, -1),   # North faces outward (-Z)
	Vector3(-1, 0, 0),   # West faces outward (-X)
	Vector3(1, 0, 0),    # East faces outward (+X)
]

func _spawn_player_bodies() -> void:
	for body in player_bodies.values():
		if is_instance_valid(body):
			body.get_parent().remove_child(body)
			body.queue_free()
	player_bodies.clear()

	var init_seats: Array = []
	for i in range(num_players):
		var ctx := seat_contexts[i]
		if ctx.control_type == SeatContext.SeatControlType.BOT:
			continue

		var body: PlayerBody = player_body_scene.instantiate()
		body.name = "PlayerBody_Seat%d" % i
		# Remove MultiplayerSynchronizer — using RPC-based position sync instead
		var sync_node := body.get_node_or_null("MultiplayerSynchronizer")
		if sync_node:
			body.remove_child(sync_node)
			sync_node.queue_free()
		add_child(body)
		var body_peer_id := _get_peer_id_for_seat(i)
		var body_is_local := (i == local_seat_index)
		body.setup(i, body_peer_id, ctx.display_name, players[i].player_color, body_is_local)
		body.request_sit.connect(_on_body_request_sit)
		body.request_stand.connect(_on_body_request_stand)
		body.interaction_label = interaction_label
		player_bodies[i] = body
		init_seats.append(i)

	SteamMovementService.init_occupied_seats(init_seats)

func _get_peer_id_for_seat(seat_index: int) -> int:
	if not multiplayer.has_multiplayer_peer():
		return 1  # Local mode: authority is always 1
	var rs := SteamRoomService.get_room_state()
	for member in rs.members_by_steam_id.values():
		if member.seat_index == seat_index:
			return member.peer_id
	return 1

func _is_round_active() -> bool:
	var s := GameManager.current_state
	return s == GameManager.GameState.DEALING or s == GameManager.GameState.INITIAL_VIEWING \
		or s == GameManager.GameState.PLAYING or s == GameManager.GameState.ABILITY_ACTIVE \
		or s == GameManager.GameState.KNOCKED

func _on_leave_seat_pressed() -> void:
	if is_local_player_standing or _is_round_active():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		SteamMovementService.client_request_stand.rpc_id(1)
	elif multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		# Host stands directly
		SteamMovementService._standing_seats[local_seat_index] = true
		SteamMovementService._occupied_seats.erase(local_seat_index)
		SteamMovementService._client_player_stood.rpc(local_seat_index)
		SteamMovementService._client_player_stood(local_seat_index)
	else:
		# Local mode
		SteamMovementService.local_stand(local_seat_index)

func _on_body_request_sit(target_seat: int) -> void:
	if not is_local_player_standing:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		SteamMovementService.client_request_sit.rpc_id(1, target_seat)
	elif multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if SteamMovementService.is_seat_occupied(target_seat):
			return
		SteamMovementService._standing_seats[local_seat_index] = false
		SteamMovementService._occupied_seats[target_seat] = true
		var original := SteamMovementService._get_original_seat_for_current(local_seat_index)
		SteamMovementService._current_seat[original] = target_seat
		SteamMovementService._client_player_sat.rpc(local_seat_index, target_seat)
		SteamMovementService._client_player_sat(local_seat_index, target_seat)
	else:
		SteamMovementService.local_sit(local_seat_index, target_seat)

func _on_body_request_stand() -> void:
	_on_leave_seat_pressed()

func _find_body_at_seat(current_seat: int) -> PlayerBody:
	for body: PlayerBody in player_bodies.values():
		if is_instance_valid(body) and body.seat_index == current_seat:
			return body
	return null

func _on_player_stood(seat_index: int) -> void:
	var body := _find_body_at_seat(seat_index)
	if body == null:
		return

	var chair_pos := CHAIR_POSITIONS[seat_index] if seat_index < CHAIR_POSITIONS.size() else Vector3.ZERO
	var face_dir := CHAIR_FACE_DIRECTIONS[seat_index] if seat_index < CHAIR_FACE_DIRECTIONS.size() else Vector3(0, 0, 1)
	body.spawn_at_chair(chair_pos, face_dir)
	body.set_standing(true)

	# Only switch camera for the LOCAL player
	if seat_index == local_seat_index:
		is_local_player_standing = true
		# Disable seated camera processing (don't touch .current yet)
		camera_controller.set_process(false)
		camera_controller.set_process_input(false)
		# Make the FPS camera the active viewport camera
		body.activate_fps_camera()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if leave_seat_container:
			leave_seat_container.visible = false
		if turn_ui:
			turn_ui.hide_ui()

func _on_player_sat(seat_index: int, target_seat: int) -> void:
	var body := _find_body_at_seat(seat_index)
	if body:
		body.set_standing(false)
		body.seat_index = target_seat

	# Only switch camera for the LOCAL player
	var is_local: bool = (seat_index == local_seat_index)
	if is_local:
		is_local_player_standing = false
		if target_seat != local_seat_index:
			local_seat_index = target_seat
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if body:
			body.deactivate_fps_camera()
		# Restore seated camera
		camera_controller.set_process(true)
		camera_controller.set_process_input(true)
		camera_controller.camera.make_current()
		_apply_local_seat_camera_view()
		_apply_local_seat_lighting()
		if leave_seat_container:
			leave_seat_container.visible = true

func _show_leave_seat_ui() -> void:
	if leave_seat_container and not is_local_player_standing and not _is_round_active():
		leave_seat_container.visible = true

var _sync_timer: float = 0.0
const SYNC_INTERVAL: float = 0.05

func _process(delta: float) -> void:
	if is_local_player_standing and multiplayer.has_multiplayer_peer():
		var body := _find_body_at_seat(local_seat_index)
		if body:
			_sync_timer += delta
			if _sync_timer >= SYNC_INTERVAL:
				_sync_timer = 0.0
				var pos := body.global_position
				SteamMovementService.sync_body_position.rpc(
					local_seat_index, pos.x, pos.y, pos.z, body.rotation.y
				)

func _on_remote_position_updated(seat_index: int, pos: Vector3, rot_y: float) -> void:
	var body := _find_body_at_seat(seat_index)
	if body and not body.is_local:
		body.apply_remote_state(pos, rot_y)
