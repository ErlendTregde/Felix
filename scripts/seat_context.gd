extends RefCounted
class_name SeatContext

enum SeatControlType {
	LOCAL_HUMAN,
	BOT,
	REMOTE_HUMAN,
}

var seat_index: int = -1
var seat_label: String = ""
var occupant_participant_id: int = -1
var display_name: String = ""
var control_type: SeatControlType = SeatControlType.BOT
var is_ready: bool = false
var has_knocked: bool = false
var is_local: bool = false
var current_score: int = 0
var total_score: int = 0

func configure(
	new_seat_index: int,
	new_seat_label: String,
	new_occupant_participant_id: int,
	new_display_name: String,
	new_control_type: SeatControlType,
	new_is_local: bool
) -> SeatContext:
	seat_index = new_seat_index
	seat_label = new_seat_label
	occupant_participant_id = new_occupant_participant_id
	display_name = new_display_name
	control_type = new_control_type
	is_local = new_is_local
	return self

func is_local_human() -> bool:
	return control_type == SeatControlType.LOCAL_HUMAN

func is_bot() -> bool:
	return control_type == SeatControlType.BOT

func is_remote_human() -> bool:
	return control_type == SeatControlType.REMOTE_HUMAN

func to_dict() -> Dictionary:
	return {
		"seat_index": seat_index,
		"seat_label": seat_label,
		"occupant_participant_id": occupant_participant_id,
		"display_name": display_name,
		"control_type": SeatControlType.keys()[control_type],
		"is_ready": is_ready,
		"has_knocked": has_knocked,
		"is_local": is_local,
		"current_score": current_score,
		"total_score": total_score,
	}
