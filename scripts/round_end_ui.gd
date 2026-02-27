extends CanvasLayer
class_name RoundEndUI
## Shows round-end scores, winner announcement, and a "Play Again" button.

signal play_again_pressed

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var scores_container: VBoxContainer = $Panel/VBoxContainer/ScoresContainer
@onready var play_again_button: Button = $Panel/VBoxContainer/PlayAgainButton

func _ready() -> void:
	play_again_button.pressed.connect(_on_play_again)
	hide_ui()

func show_results(summary: Array[Dictionary], winner_id: int, knocker_name: String) -> void:
	"""Display round-end results.
	summary: Array of { id, name, round_score, total_score, knocked }"""
	# Clear old score rows
	for child in scores_container.get_children():
		child.queue_free()
	
	title_label.text = "%s wins the round!" % summary[0]["name"]
	
	# Build a row per player, sorted by round score (summary is pre-sorted)
	for entry in summary:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var name_label = Label.new()
		name_label.text = entry["name"]
		if entry["knocked"]:
			name_label.text += "  (knocked)"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		
		var round_label = Label.new()
		round_label.text = "Round: %d" % entry["round_score"]
		round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		round_label.custom_minimum_size.x = 100
		row.add_child(round_label)
		
		var total_label = Label.new()
		total_label.text = "Total: %d" % entry["total_score"]
		total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		total_label.custom_minimum_size.x = 100
		row.add_child(total_label)
		
		scores_container.add_child(row)
	
	panel.show()

func hide_ui() -> void:
	panel.hide()

func _on_play_again() -> void:
	hide_ui()
	play_again_pressed.emit()
