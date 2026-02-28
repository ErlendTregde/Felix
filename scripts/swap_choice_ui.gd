extends Control
class_name SwapChoiceUI
## Clean minimal Queen ability swap choice — white text, no background panels.

signal swap_chosen
signal no_swap_chosen

@onready var swap_button: Button = $BottomCenter/SwapButton
@onready var no_swap_button: Button = $BottomCenter/NoSwapButton

func _ready() -> void:
	hide()
	swap_button.pressed.connect(_on_swap_pressed)
	no_swap_button.pressed.connect(_on_no_swap_pressed)

func show_choice() -> void:
	"""Show the choice UI."""
	show()
	swap_button.grab_focus()

func hide_choice() -> void:
	"""Hide the choice UI."""
	hide()

func _on_swap_pressed() -> void:
	"""Called when Swap button is pressed."""
	print("Queen ability: Swap chosen")
	swap_chosen.emit()
	hide_choice()

func _on_no_swap_pressed() -> void:
	"""Called when Don't Swap button is pressed."""
	print("Queen ability: Don't swap chosen")
	no_swap_chosen.emit()
	hide_choice()
