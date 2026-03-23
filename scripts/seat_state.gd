extends RefCounted
class_name SeatState

var seat_index: int = -1
var seat_label: String = ""
var occupant_participant_id: int = -1
var occupant_steam_id: int = 0
var display_name: String = ""
var is_ready: bool = false
var control_type: SeatContext.SeatControlType = SeatContext.SeatControlType.REMOTE_HUMAN
var is_local: bool = false

func configure(new_seat_index: int, new_seat_label: String) -> SeatState:
	seat_index = new_seat_index
	seat_label = new_seat_label
	return self

func clear_occupant() -> void:
	occupant_participant_id = -1
	occupant_steam_id = 0
	display_name = ""
	is_ready = false
	control_type = SeatContext.SeatControlType.REMOTE_HUMAN
	is_local = false

func is_occupied() -> bool:
	return occupant_participant_id >= 0

func to_dict() -> Dictionary:
	return {
		"seat_index": seat_index,
		"seat_label": seat_label,
		"occupant_participant_id": occupant_participant_id,
		"occupant_steam_id": occupant_steam_id,
		"display_name": display_name,
		"is_ready": is_ready,
		"control_type": SeatContext.SeatControlType.keys()[control_type],
		"is_local": is_local,
	}

static func from_dict(data: Dictionary) -> SeatState:
	var state = load("res://scripts/seat_state.gd").new().configure(
		int(data.get("seat_index", -1)),
		String(data.get("seat_label", ""))
	)
	state.occupant_participant_id = int(data.get("occupant_participant_id", -1))
	state.occupant_steam_id = int(data.get("occupant_steam_id", 0))
	state.display_name = String(data.get("display_name", ""))
	state.is_ready = bool(data.get("is_ready", false))
	state.control_type = SeatContext.SeatControlType.get(String(data.get("control_type", "REMOTE_HUMAN")), SeatContext.SeatControlType.REMOTE_HUMAN)
	state.is_local = bool(data.get("is_local", false))
	return state
