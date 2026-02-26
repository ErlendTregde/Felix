extends Node
## Global event bus for decoupled communication across the game
## Emits signals that any node can connect to without tight coupling

# Game state signals
@warning_ignore("unused_signal")
signal game_started
@warning_ignore("unused_signal")
signal round_started(round_number: int)
@warning_ignore("unused_signal")
signal round_ended(winner_player_id: int, scores: Dictionary)
signal game_state_changed(new_state: String)

# Turn signals
@warning_ignore("unused_signal")
signal turn_started(player_id: int)
@warning_ignore("unused_signal")
signal turn_ended(player_id: int)
@warning_ignore("unused_signal")
signal player_knocked(player_id: int)
@warning_ignore("unused_signal")
signal player_ready_changed(player_id: int, is_ready: bool)

# Card signals
@warning_ignore("unused_signal")
signal card_dealt(card_data: Resource, player_id: int, position: int)
@warning_ignore("unused_signal")
signal card_flipped(card: Node, is_face_up: bool)
@warning_ignore("unused_signal")
signal card_drawn(card_data: Resource)
@warning_ignore("unused_signal")
signal card_played(card_data: Resource, player_id: int)
@warning_ignore("unused_signal")
signal card_discarded(card_data: Resource)
@warning_ignore("unused_signal")
signal card_revealed(card_data: Resource, player_id: int)

# Ability signals
@warning_ignore("unused_signal")
signal ability_activated(ability_type: String, player_id: int)
@warning_ignore("unused_signal")
signal ability_target_selected(target_card: Node)
@warning_ignore("unused_signal")
signal ability_completed(ability_type: String)

# Fast reaction signals
@warning_ignore("unused_signal")
signal match_attempted(player_id: int, target_card: Node)
@warning_ignore("unused_signal")
signal match_successful(player_id: int, matched_card: Node)
@warning_ignore("unused_signal")
signal match_failed(player_id: int)
@warning_ignore("unused_signal")
signal penalty_card_added(player_id: int)

# UI signals
@warning_ignore("unused_signal")
signal score_updated(player_id: int, new_score: int)
@warning_ignore("unused_signal")
signal action_prompt_changed(text: String)
@warning_ignore("unused_signal")
signal player_ready(player_id: int)

func _ready() -> void:
	print("Felix Card Game - Event Bus initialized")
