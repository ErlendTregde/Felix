extends RefCounted
class_name CardRef

var slot_ref: SlotRef = SlotRef.new()
var instance_id: int = -1
var short_name: String = ""
var rank: int = -1
var suit: int = -1
var is_face_up: bool = false

func configure(card: Card3D, owner_seat_id: int, slot_index: int, is_penalty: bool) -> CardRef:
	slot_ref = SlotRef.new().configure(owner_seat_id, slot_index, is_penalty)
	instance_id = card.get_instance_id()
	if card.card_data:
		short_name = card.card_data.get_short_name()
		rank = card.card_data.rank
		suit = card.card_data.suit
	is_face_up = card.is_face_up
	return self

func to_public_dict(viewer_seat_id: int = -1) -> Dictionary:
	var is_visible_to_viewer := is_face_up or viewer_seat_id == slot_ref.owner_seat_id
	return {
		"slot": slot_ref.to_dict(),
		"instance_id": instance_id,
		"is_face_up": is_face_up,
		"is_visible_to_viewer": is_visible_to_viewer,
		"short_name": short_name if is_visible_to_viewer else "UNKNOWN",
		"rank": rank if is_visible_to_viewer else -1,
		"suit": suit if is_visible_to_viewer else -1,
	}
