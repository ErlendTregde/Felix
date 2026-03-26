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
const ParticipantProfileScript = preload("res://scripts/participant_profile.gd")

var player_grids: Array[PlayerGrid] = []
var players: Array[Player] = []
var participant_profiles: Array = []
var seat_contexts: Array[SeatContext] = []
var local_seat_index: int = 0
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
					# For multi-step abilities (BLIND_SWAP, LOOK_AND_SWAP): show local visual feedback
					var ab_type := ability_manager.current_ability
					if ab_type == CardData.AbilityType.BLIND_SWAP or ab_type == CardData.AbilityType.LOOK_AND_SWAP:
						ability_manager.handle_ability_target_selection(card)
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
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		var slot_info := _get_card_slot_info(card)
		if slot_info.slot >= 0:
			SteamRoundService.client_request_match.rpc_id(1, card.owner_seat_id, slot_info.slot, slot_info.is_penalty)
		return
	round_controller.request_match(local_seat_index, card)

func _on_discard_pile_clicked(_pile: CardPile) -> void:
	"""Handle discard pile click - play card to discard and use ability"""
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		# Client: clean up the drawn card locally and let host handle the discard
		if drawn_card and is_instance_valid(drawn_card):
			drawn_card.queue_free()
		drawn_card = null
		if discard_pile_visual:
			discard_pile_visual.set_interactive(false)
		SteamRoundService.client_request_discard_drawn.rpc_id(1)
	else:
		await round_controller.request_discard_drawn(local_seat_index)

func _on_draw_pile_clicked(_pile: CardPile) -> void:
	"""Handle draw pile click - draw a card"""
	# Hide knock buttons once player starts drawing
	knock_manager.hide_all_buttons()
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		SteamRoundService.client_request_draw.rpc_id(1)
	else:
		await round_controller.request_draw(local_seat_index)

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
				ab.ability_target_card.flip(false, 0.3)
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
		_handle_round_end()

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
	"""Start a new round — or return to Steam room in multiplayer."""
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
	"""Client-side visual swap: instantly place drawn_card into the grid slot."""
	if drawn_card == null:
		return
	var grid = player_grids[local_seat_index]
	# Discard the old card locally
	deck_manager.add_to_discard(old_card.card_data)
	if discard_pile_visual:
		discard_pile_visual.set_count(deck_manager.discard_pile.size())
		discard_pile_visual.set_top_card(old_card.card_data)
	old_card.queue_free()
	# Place drawn card into the slot
	var new_card := drawn_card
	drawn_card = null
	new_card.is_interactable = false
	if new_card.get_parent():
		new_card.get_parent().remove_child(new_card)
	if is_penalty:
		if slot >= 0 and slot < grid.penalty_cards.size():
			grid.penalty_cards[slot] = new_card
			grid.add_child(new_card)
			new_card.global_position = grid.to_global(grid.penalty_positions[slot]) if slot < grid.penalty_positions.size() else grid.global_position
	else:
		grid.cards[slot] = new_card
		grid.add_child(new_card)
		new_card.position = grid.card_positions[slot]
		new_card.base_position = new_card.global_position
	new_card.rotation = Vector3.ZERO
	if new_card.is_face_up:
		new_card.flip(false, 0.2)
	# Disable all interactions until next turn
	if discard_pile_visual:
		discard_pile_visual.set_interactive(false)
	for g in player_grids:
		for i in range(4):
			var c = g.get_card_at(i)
			if c:
				c.is_interactable = false
