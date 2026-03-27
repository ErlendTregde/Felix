extends RefCounted
class_name SessionScoreboard

var scores_by_participant_id: Dictionary = {}
var display_names_by_participant_id: Dictionary = {}

func ensure_participant(participant_id: int, display_name: String) -> void:
	if not scores_by_participant_id.has(participant_id):
		scores_by_participant_id[participant_id] = 0
	display_names_by_participant_id[participant_id] = display_name

func remove_participant(participant_id: int) -> void:
	scores_by_participant_id.erase(participant_id)
	display_names_by_participant_id.erase(participant_id)

func add_score(participant_id: int, amount: int) -> void:
	if scores_by_participant_id.has(participant_id):
		scores_by_participant_id[participant_id] += amount

func clear() -> void:
	scores_by_participant_id.clear()
	display_names_by_participant_id.clear()

func to_dict() -> Dictionary:
	return {
		"scores_by_participant_id": scores_by_participant_id.duplicate(true),
		"display_names_by_participant_id": display_names_by_participant_id.duplicate(true),
	}

static func from_dict(data: Dictionary) -> SessionScoreboard:
	var scoreboard = load("res://scripts/session_scoreboard.gd").new()
	scoreboard.scores_by_participant_id = data.get("scores_by_participant_id", {}).duplicate(true)
	scoreboard.display_names_by_participant_id = data.get("display_names_by_participant_id", {}).duplicate(true)
	return scoreboard
