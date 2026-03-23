extends RefCounted
class_name SlotRef

var owner_seat_id: int = -1
var slot_index: int = -1
var is_penalty: bool = false

func configure(new_owner_seat_id: int, new_slot_index: int, new_is_penalty: bool) -> SlotRef:
	owner_seat_id = new_owner_seat_id
	slot_index = new_slot_index
	is_penalty = new_is_penalty
	return self

func to_dict() -> Dictionary:
	return {
		"owner_seat_id": owner_seat_id,
		"slot_index": slot_index,
		"is_penalty": is_penalty,
	}
