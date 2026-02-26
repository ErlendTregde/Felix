extends Node
## Main game state machine and round controller
## Handles game flow, state transitions, and orchestrates gameplay

enum GameState {
	SETUP,           # Player count selection
	DEALING,         # Cards being dealt
	INITIAL_VIEWING, # Players memorizing bottom 2 cards
	PLAYING,         # Normal gameplay
	ABILITY_ACTIVE,  # Waiting for ability target selection
	KNOCKED,         # Final turns after knock
	ROUND_END        # Scoring and results
}

# Game state
var current_state: GameState = GameState.SETUP
var current_round: int = 0
var current_player_index: int = 0
var player_count: int = 2
var knocker_id: int = -1

# Players
var players: Array = []  # Array of Player nodes

# Deck management
var deck_manager: Node = null

func _ready() -> void:
	print("Felix Card Game - GameManager initialized")

func start_game(num_players: int) -> void:
	"""Initialize a new game with specified number of players"""
	player_count = clampi(num_players, 2, 4)
	current_round = 0
	knocker_id = -1
	
	print("Starting game with %d players" % player_count)
	Events.game_started.emit()
	change_state(GameState.DEALING)

func start_round() -> void:
	"""Start a new round"""
	current_round += 1
	knocker_id = -1
	current_player_index = 0
	
	print("Starting round %d" % current_round)
	Events.round_started.emit(current_round)
	change_state(GameState.DEALING)

func change_state(new_state: GameState) -> void:
	"""Transition to a new game state"""
	if current_state == new_state:
		return
	
	exit_state(current_state)
	current_state = new_state
	enter_state(current_state)
	
	var state_name = GameState.keys()[new_state]
	print("Game state changed to: %s" % state_name)
	Events.game_state_changed.emit(state_name)

func enter_state(state: GameState) -> void:
	"""Called when entering a new state"""
	match state:
		GameState.SETUP:
			pass
		GameState.DEALING:
			# Will trigger dealing sequence
			pass
		GameState.INITIAL_VIEWING:
			# Will trigger viewing sequence
			pass
		GameState.PLAYING:
			start_turn()
		GameState.ABILITY_ACTIVE:
			Events.action_prompt_changed.emit("Select ability target...")
		GameState.KNOCKED:
			print("Player %d knocked! Final turns..." % knocker_id)
		GameState.ROUND_END:
			# Will trigger scoring
			pass

func exit_state(state: GameState) -> void:
	"""Called when exiting a state"""
	match state:
		GameState.PLAYING:
			pass
		GameState.ABILITY_ACTIVE:
			pass
		_:
			pass

func start_turn() -> void:
	"""Start the current player's turn"""
	if players.is_empty():
		return
	
	var player_id = players[current_player_index].player_id if players.size() > current_player_index else 0
	print("Turn started for player %d" % player_id)
	Events.turn_started.emit(player_id)
	Events.action_prompt_changed.emit("Draw a card from the deck")

func next_turn() -> void:
	"""Move to the next player's turn (clockwise)"""
	var player_id = players[current_player_index].player_id if players.size() > current_player_index else 0
	Events.turn_ended.emit(player_id)
	
	current_player_index = get_next_player_clockwise(current_player_index)
	
	# Check if we've completed final turns after knock
	if current_state == GameState.KNOCKED and current_player_index == (knocker_id % player_count):
		change_state(GameState.ROUND_END)
	else:
		start_turn()

func get_next_player_clockwise(current: int) -> int:
	"""Get the next player index in clockwise order"""
	# Clockwise turn order based on player positions:
	# P0 (South) → P2 (West) → P1 (North) → P3 (East) → P0
	# This matches physical seating when viewed from above
	
	match player_count:
		2:
			# 2 players: P0 → P1 → P0
			return (current + 1) % 2
		3:
			# 3 players: P0 → P2 → P1 → P0
			match current:
				0: return 2
				2: return 1
				1: return 0
				_: return 0
		4:
			# 4 players: P0 → P2 → P1 → P3 → P0
			match current:
				0: return 2  # South → West
				2: return 1  # West → North
				1: return 3  # North → East
				3: return 0  # East → South
				_: return 0
		_:
			return (current + 1) % player_count

func player_knock(player_id: int) -> void:
	"""Handle a player knocking"""
	if current_state != GameState.PLAYING:
		return
	
	knocker_id = player_id
	Events.player_knocked.emit(player_id)
	change_state(GameState.KNOCKED)
	next_turn()  # Move to next player for final turns

func get_current_player() -> Node:
	"""Get the current player node"""
	if players.is_empty() or current_player_index >= players.size():
		return null
	return players[current_player_index]

func set_player_ready(player_id: int, is_ready: bool = true) -> void:
	"""Mark a player as ready (for initial viewing phase)"""
	if player_id >= 0 and player_id < players.size():
		players[player_id].is_ready = is_ready
		print("Player %d ready state: %s" % [player_id + 1, is_ready])
		Events.player_ready_changed.emit(player_id, is_ready)

func are_all_players_ready() -> bool:
	
	"""Check if all players have marked themselves as ready"""
	for player in players:
		if not player.is_ready:
			return false
	return true

func get_ready_count() -> int:
	"""Get the number of players who are ready"""
	var count = 0
	for player in players:
		if player.is_ready:
			count += 1
	return count

func reset_all_ready_states() -> void:
	"""Reset all players' ready states to false"""
	for player in players:
		player.is_ready = false
