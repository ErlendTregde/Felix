extends CanvasLayer
class_name TurnUI
## Contextual HUD: top-right actions panel + top-left drawn-card info panel.
## All text is white with black outline; no background panels.

@onready var top_right: VBoxContainer   = $TopRight
@onready var player_label: Label        = $TopRight/PlayerLabel
@onready var actions_box: VBoxContainer = $TopRight/ActionsBox
@onready var step_label: Label          = $TopRight/StepLabel
@onready var top_left: VBoxContainer    = $TopLeft
@onready var card_name_label: Label     = $TopLeft/CardNameLabel
@onready var card_score_label: Label    = $TopLeft/CardScoreLabel
@onready var card_ability_label: Label  = $TopLeft/CardAbilityLabel

# All action rows: {id: [key_badge_text, description_text]}
const ACTION_DEFS: Dictionary = {
	"draw":    ["[D]",           "Draw card"],
	"knock":   ["[K]",           "Knock"],
	"swap":    ["[Click card]",  "Swap drawn card"],
	"ability": ["[Click pile]",  "Use ability"],
	"select":  ["[Click]",       "Select card"],
	"confirm": ["[Space]",       "Confirm"],
	"match":   ["[Right-click]", "Match card"],
}

var _rows: Dictionary = {}  # id -> HBoxContainer

func _ready() -> void:
	_build_rows()
	hide_card_info()
	hide_step()
	hide_ui()

func _build_rows() -> void:
	"""Dynamically create one action row per ACTION_DEFS entry."""
	for id in ACTION_DEFS:
		var entry: Array = ACTION_DEFS[id]
		var row := HBoxContainer.new()
		row.name = "Row_" + id
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var lbl_key := Label.new()
		lbl_key.text = entry[0]
		lbl_key.custom_minimum_size.x = 90
		lbl_key.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35, 1))
		lbl_key.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		lbl_key.add_theme_constant_override("outline_size", 3)
		lbl_key.add_theme_font_size_override("font_size", 13)
		lbl_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl_key)

		var lbl_desc := Label.new()
		lbl_desc.text = entry[1]
		lbl_desc.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lbl_desc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		lbl_desc.add_theme_constant_override("outline_size", 3)
		lbl_desc.add_theme_font_size_override("font_size", 13)
		lbl_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl_desc)

		actions_box.add_child(row)
		_rows[id] = row
		row.hide()

func _show_rows(ids: Array) -> void:
	"""Show the listed rows, hide all others."""
	for k in _rows:
		_rows[k].visible = ids.has(k)

# ─────────────────────────── Public API ────────────────────────────────────

func show_turn(_player_id: int, player_name: String, is_player_turn: bool) -> void:
	"""Show the HUD at the start of a player's turn with the correct initial actions."""
	var final_prefix: String = "[FINAL ROUND]\n" if GameManager.is_final_round() else ""

	if is_player_turn:
		player_label.text = final_prefix + "YOUR TURN"
		if GameManager.is_final_round():
			_show_rows(["draw", "match"])
		else:
			_show_rows(["draw", "knock", "match"])
	else:
		player_label.text = "%s%s's Turn" % [final_prefix, player_name]
		_show_rows(["match"])

	hide_step()
	top_right.show()

func update_action(text: String) -> void:
	"""Map legacy action-text strings to the correct visible action rows.
	Also updates the step counter for multi-step abilities."""
	match text:
		"Click your card to swap, OR click discard pile to use ability":
			_show_rows(["swap", "ability", "match"])
			hide_step()
		"Press D to draw a card, click draw pile, or KNOCK":
			_show_rows(["draw", "knock", "match"])
			hide_step()
		"Press D to draw a card or click draw pile":
			_show_rows(["draw", "match"])
			hide_step()
		"Select which card to look at", \
		"Select opponent's card to look at":
			_show_rows(["select", "match"])
			hide_step()
		"Select YOUR card to swap", \
		"Select YOUR card to look at":
			# Start of Jack / Queen ability — first card not yet selected
			_show_rows(["select", "match"])
			hide_step()
		"Now select NEIGHBOR's card", \
		"Now select YOUR card":
			# First card confirmed — now picking second
			_show_rows(["select", "match"])
			set_step(1, 2)
		"Press SPACE to swap cards":
			_show_rows(["confirm", "match"])
			set_step(2, 2)
		"Press SPACE to view cards":
			_show_rows(["confirm", "match"])
			set_step(2, 2)
		"Press SPACE to confirm":
			_show_rows(["confirm", "match"])
			hide_step()
		"Viewing cards...", "Waiting...":
			_show_rows(["match"])
			hide_step()
		_:
			# Dynamic strings (e.g. "Choose a card to give to Player 2!", bot status)
			if "give" in text.to_lower() or "choose" in text.to_lower():
				_show_rows(["select"])
				hide_step()
			elif "bot is" in text.to_lower() or "knocked" in text.to_lower():
				_show_rows(["match"])
				hide_step()

func show_card_info(data: CardData) -> void:
	"""Show the top-left panel with the drawn card's rank, score, and ability."""
	card_name_label.text = data.get_short_name()
	var score: int = data.get_score()
	card_score_label.text = "%d pt%s" % [score, "" if absf(score) == 1 else "s"]
	var ability: CardData.AbilityType = data.get_ability()
	if ability != CardData.AbilityType.NONE:
		card_ability_label.text = _ability_label(ability)
		card_ability_label.show()
	else:
		card_ability_label.hide()
	top_left.show()

func hide_card_info() -> void:
	"""Hide the drawn-card info panel."""
	top_left.hide()

func set_step(current: int, total: int) -> void:
	"""Show a step counter (e.g. 'Step 1 / 2') during multi-step abilities."""
	step_label.text = "Step %d / %d" % [current, total]
	step_label.show()

func hide_step() -> void:
	"""Hide the step counter."""
	step_label.hide()

func hide_ui() -> void:
	"""Hide the entire HUD."""
	top_right.hide()
	top_left.hide()

func show_ui() -> void:
	"""Restore top-right panel (e.g. after Queen swap-choice dialog closes)."""
	top_right.show()

# ─────────────────────────── Helpers ────────────────────────────────────────

func _ability_label(ability: CardData.AbilityType) -> String:
	match ability:
		CardData.AbilityType.LOOK_OWN:      return "Look at own card"
		CardData.AbilityType.LOOK_OPPONENT: return "Look at opponent"
		CardData.AbilityType.BLIND_SWAP:    return "Blind swap (Jack)"
		CardData.AbilityType.LOOK_AND_SWAP: return "Look & swap (Queen)"
		_:                                  return ""
