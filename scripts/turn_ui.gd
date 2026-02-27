extends CanvasLayer
class_name TurnUI
## UI overlay for turn-based gameplay

@onready var turn_panel: PanelContainer = $TurnPanel
@onready var player_label: Label = $TurnPanel/VBoxContainer/PlayerLabel
@onready var action_label: Label = $TurnPanel/VBoxContainer/ActionLabel
@onready var instruction_label: Label = $TurnPanel/VBoxContainer/InstructionLabel

func _ready() -> void:
	hide_ui()

func show_turn(player_id: int, player_name: String, is_player_turn: bool) -> void:
	"""Show whose turn it is"""
	var is_final_round = GameManager.is_final_round()
	var prefix = "[FINAL ROUND] " if is_final_round else ""
	
	player_label.text = "%s%s's Turn" % [prefix, player_name]
	
	if is_player_turn:
		action_label.text = "Your Turn!"
		if is_final_round:
			instruction_label.text = "Final turn — draw and swap!"
		else:
			instruction_label.text = "Click draw pile to draw a card"
	else:
		action_label.text = "Opponent Playing..."
		if is_final_round:
			instruction_label.text = "Final round in progress..."
		else:
			instruction_label.text = ""
	
	turn_panel.show()

func update_action(action_text: String) -> void:
	"""Update the action instruction"""
	instruction_label.text = action_text

func hide_ui() -> void:
	"""Hide the turn UI"""
	turn_panel.hide()

func show_ui() -> void:
	"""Show the turn UI"""
	turn_panel.show()
