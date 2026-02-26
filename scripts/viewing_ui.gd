extends CanvasLayer
class_name ViewingUI
## UI overlay for initial card viewing phase

@onready var ready_button: Button = $Panel/VBoxContainer/ReadyButton
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var player_label: Label = $Panel/VBoxContainer/PlayerLabel

var current_player_id: int = 0

signal ready_pressed(player_id: int)

func _ready() -> void:
	ready_button.pressed.connect(_on_ready_pressed)
	hide()

func show_for_player(player_id: int, _player_count: int) -> void:
	"""Show the viewing UI for a specific player"""
	current_player_id = player_id
	player_label.text = "Player %d" % (player_id + 1)
	status_label.text = "Memorize your bottom 2 cards"
	ready_button.disabled = false
	ready_button.text = "I'm Ready"
	show()

func mark_player_ready(player_id: int) -> void:
	"""Update UI to show a player is ready"""
	if player_id == current_player_id:
		ready_button.disabled = true
		ready_button.text = "✓ Ready"
		status_label.text = "Waiting for other players..."

func update_waiting_count(ready_count: int, total_count: int) -> void:
	"""Update the waiting status"""
	if ready_count < total_count:
		status_label.text = "Waiting... (%d/%d ready)" % [ready_count, total_count]
	else:
		status_label.text = "All players ready! Starting game..."

func hide_ui() -> void:
	"""Hide the viewing UI"""
	hide()

func _on_ready_pressed() -> void:
	"""Handle ready button press"""
	ready_pressed.emit(current_player_id)
	mark_player_ready(current_player_id)
