extends CanvasLayer
class_name RoundEndUI
## Clean minimal round-end scores — white text with outline, no background panels.

signal play_again_pressed

@onready var center_panel: VBoxContainer = $CenterPanel
@onready var title_label: Label = $CenterPanel/TitleLabel
@onready var scores_container: VBoxContainer = $CenterPanel/ScoresContainer
@onready var play_again_button: Button = $CenterPanel/PlayAgainButton

func _ready() -> void:
	play_again_button.pressed.connect(_on_play_again)
	hide_ui()

func show_results(summary: Array[Dictionary], winner_id: int, knocker_name: String) -> void:
	"""Display round-end results."""
	# Clear old score rows
	for child in scores_container.get_children():
		child.queue_free()

	title_label.text = "%s wins!" % summary[0]["name"]

	# Build a row per player
	for entry in summary:
		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label: Label = Label.new()
		name_label.text = entry["name"]
		if entry["knocked"]:
			name_label.text += "  (knocked)"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		name_label.add_theme_constant_override("outline_size", 3)
		row.add_child(name_label)

		var round_label: Label = Label.new()
		round_label.text = "Round: %d" % entry["round_score"]
		round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		round_label.custom_minimum_size.x = 100
		round_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
		round_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		round_label.add_theme_constant_override("outline_size", 3)
		row.add_child(round_label)

		var total_label: Label = Label.new()
		total_label.text = "Total: %d" % entry["total_score"]
		total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		total_label.custom_minimum_size.x = 100
		total_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
		total_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		total_label.add_theme_constant_override("outline_size", 3)
		row.add_child(total_label)

		scores_container.add_child(row)

	center_panel.show()

func hide_ui() -> void:
	center_panel.hide()

func _on_play_again() -> void:
	hide_ui()
	play_again_pressed.emit()
