extends RefCounted
class_name RoundState

var seat_contexts: Array[SeatContext] = []
var local_seat_index: int = 0
var current_turn_seat_index: int = 0
var phase_name: String = "SETUP"
var round_number: int = 0
var knocker_seat_index: int = -1
var final_round_remaining: Array[int] = []
var draw_pile_count: int = 0
var discard_pile_count: int = 0
var top_discard_name: String = ""
var match_claimed: bool = false
var pending_give_card_actor_seat_index: int = -1
var pending_give_card_target_seat_index: int = -1
var seat_card_refs: Dictionary = {}

func set_seat_contexts(contexts: Array[SeatContext], new_local_seat_index: int) -> void:
	seat_contexts = contexts.duplicate()
	local_seat_index = new_local_seat_index

func get_seat_context(seat_id: int) -> SeatContext:
	if seat_id < 0 or seat_id >= seat_contexts.size():
		return null
	return seat_contexts[seat_id]

func is_local_seat(seat_id: int) -> bool:
	return seat_id == local_seat_index

func set_phase(new_phase_name: String) -> void:
	phase_name = new_phase_name

func set_card_refs_for_seat(seat_id: int, refs: Array[CardRef]) -> void:
	seat_card_refs[seat_id] = refs

func get_public_snapshot() -> Dictionary:
	var seats: Array[Dictionary] = []
	var cards_by_seat: Dictionary = {}
	for context in seat_contexts:
		seats.append(context.to_dict())
	for seat_id in seat_card_refs.keys():
		var refs: Array = seat_card_refs[seat_id]
		var public_refs: Array[Dictionary] = []
		for ref in refs:
			public_refs.append(ref.to_public_dict())
		cards_by_seat[seat_id] = public_refs
	return {
		"phase_name": phase_name,
		"round_number": round_number,
		"local_seat_index": local_seat_index,
		"current_turn_seat_index": current_turn_seat_index,
		"knocker_seat_index": knocker_seat_index,
		"final_round_remaining": final_round_remaining.duplicate(),
		"draw_pile_count": draw_pile_count,
		"discard_pile_count": discard_pile_count,
		"top_discard_name": top_discard_name,
		"match_claimed": match_claimed,
		"pending_give_card_actor_seat_index": pending_give_card_actor_seat_index,
		"pending_give_card_target_seat_index": pending_give_card_target_seat_index,
		"seats": seats,
		"cards_by_seat": cards_by_seat,
	}

func get_private_snapshot_for(seat_id: int) -> Dictionary:
	var snapshot := get_public_snapshot()
	var private_refs: Array[Dictionary] = []
	var refs: Array = seat_card_refs.get(seat_id, [])
	for ref in refs:
		private_refs.append(ref.to_public_dict(seat_id))
	snapshot["private_cards"] = private_refs
	return snapshot
