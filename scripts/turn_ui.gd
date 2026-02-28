extends CanvasLayer
class_name TurnUI
## Clean minimal UI — white text, no background panels.

@onready var bottom_center: VBoxContainer = $BottomCenter
@onready var player_label: Label = $BottomCenter/PlayerLabel
@onready var action_label: Label = $BottomCenter/ActionLabel
@onready var instruction_label: Label = $BottomCenter/InstructionLabel

func _ready() -> void:
	hide_ui()

func show_turn(player_id: int, player_name: String, is_player_turn: bool) -> void:
	"""Show whose turn it is."""
	var is_final_round: bool = GameManager.is_final_round()
	var prefix: String = "FINAL ROUND — " if is_final_round else ""

	if is_player_turn:
		player_label.text = "%sYOUR TURN" % prefix
		action_label.text = ""
		if is_final_round:
			instruction_label.text = "[D] Draw   |   Click card to swap"
		else:
			instruction_label.text = "[D] Draw   |   Click card to swap"
	else:
		player_label.text = "%s%s's Turn" % [prefix, player_name]
		action_label.text = ""
		instruction_label.text = "Waiting..."

	bottom_center.show()

func update_action(action_text: String) -> void:
	"""Update the instruction line."""
	instruction_label.text = action_text

func hide_ui() -> void:
	"""Hide all turn UI elements."""
	bottom_center.hide()

func show_ui() -> void:
	"""Show the turn UI."""
	bottom_center.show()
