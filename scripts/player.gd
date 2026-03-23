extends Node
class_name Player
## Represents a player in the game
## Tracks player state, cards, and score

@export var player_id: int = 0
@export var participant_id: int = 0
@export var seat_index: int = 0
@export var seat_label: String = ""
@export var player_name: String = "Player"
@export var player_color: Color = Color.WHITE
var control_type: SeatContext.SeatControlType = SeatContext.SeatControlType.BOT

var cards: Array[Node] = []  # Array of Card3D nodes
var current_score: int = 0
var total_score: int = 0  # Across multiple rounds
var is_ready: bool = false
var has_knocked: bool = false

func _ready() -> void:
	if player_name.is_empty():
		player_name = "Player %d" % (participant_id + 1)
	var final_seat_label := seat_label if not seat_label.is_empty() else "Seat %d" % (seat_index + 1)
	print("%s initialized in %s" % [player_name, final_seat_label])

func set_control_type(new_control_type: SeatContext.SeatControlType) -> void:
	control_type = new_control_type

func add_card(card: Node) -> void:
	"""Add a card to this player's hand"""
	cards.append(card)
	card.owner_player = self
	if card is Card3D:
		card.owner_seat_id = seat_index

func remove_card(card: Node) -> void:
	"""Remove a card from this player's hand"""
	var index = cards.find(card)
	if index != -1:
		cards.remove_at(index)

func get_card_at(index: int) -> Node:
	"""Get card at specific position"""
	if index >= 0 and index < cards.size():
		return cards[index]
	return null

func calculate_score() -> int:
	"""Calculate current score from cards in hand"""
	current_score = 0
	for card in cards:
		if card and card.card_data:
			current_score += card.card_data.get_score()
	
	Events.score_updated.emit(player_id, current_score)
	return current_score

func clear_cards() -> void:
	"""Remove all cards (for new round)"""
	for card in cards:
		if is_instance_valid(card):
			card.queue_free()
	cards.clear()
	current_score = 0
	has_knocked = false
	is_ready = false

func reset_for_new_game() -> void:
	"""Reset player state for new game"""
	clear_cards()
	total_score = 0
