extends RefCounted
class_name RoomState

## Bumped whenever the dict schema changes so from_dict() can reject stale snapshots.
const SCHEMA_VERSION := 1

## Canonical phase values. Use get_phase() to compare instead of raw strings.
enum RoomPhase { IDLE, CONNECTING, WAITING, IN_ROUND }

const DEFAULT_SEAT_LABELS: Array[String] = ["South", "North", "West", "East"]
const ParticipantProfileScript = preload("res://scripts/participant_profile.gd")
const RoomMemberStateScript = preload("res://scripts/room_member_state.gd")
const SeatStateScript = preload("res://scripts/seat_state.gd")
const SessionScoreboardScript = preload("res://scripts/session_scoreboard.gd")

var lobby_id: int = 0
var room_name: String = ""
var host_steam_id: int = 0
var phase_name: String = "IDLE"
var round_active: bool = false
var members_by_steam_id: Dictionary = {}
var participants_by_id: Dictionary = {}
var seat_states: Array[SeatState] = []
var session_scoreboard = null

func _init() -> void:
	session_scoreboard = SessionScoreboardScript.new()
	ensure_default_seats()

func reset() -> void:
	lobby_id = 0
	room_name = ""
	host_steam_id = 0
	phase_name = "IDLE"
	round_active = false
	members_by_steam_id.clear()
	participants_by_id.clear()
	session_scoreboard = SessionScoreboardScript.new()
	ensure_default_seats()

func ensure_default_seats() -> void:
	seat_states.clear()
	for seat_index in range(DEFAULT_SEAT_LABELS.size()):
		seat_states.append(SeatStateScript.new().configure(seat_index, DEFAULT_SEAT_LABELS[seat_index]))

func get_phase() -> RoomPhase:
	"""Parse phase_name string into the RoomPhase enum. Falls back to IDLE on unknown values."""
	match phase_name:
		"CONNECTING": return RoomPhase.CONNECTING
		"WAITING": return RoomPhase.WAITING
		"IN_ROUND": return RoomPhase.IN_ROUND
		_: return RoomPhase.IDLE

func get_member(steam_id: int) -> RoomMemberState:
	return members_by_steam_id.get(steam_id, null)

func get_seat(seat_index: int) -> SeatState:
	if seat_index < 0 or seat_index >= seat_states.size():
		return null
	return seat_states[seat_index]

func get_local_seat_index(local_steam_id: int) -> int:
	for seat in seat_states:
		if seat.occupant_steam_id == local_steam_id:
			return seat.seat_index
	return -1

func get_seated_member_count() -> int:
	var count := 0
	for seat in seat_states:
		if seat.is_occupied():
			count += 1
	return count

func clear_ready_states() -> void:
	for member_state in members_by_steam_id.values():
		member_state.is_ready = false
	for seat in seat_states:
		seat.is_ready = false

func can_start_round() -> bool:
	var seated := get_seated_member_count()
	if seated < 2 or seated > DEFAULT_SEAT_LABELS.size():
		return false
	for seat in seat_states:
		if seat.is_occupied() and not seat.is_ready:
			return false
	return true

func to_dict() -> Dictionary:
	var members: Dictionary = {}
	var participants: Dictionary = {}
	var seats: Array[Dictionary] = []
	for steam_id in members_by_steam_id.keys():
		members[steam_id] = members_by_steam_id[steam_id].to_dict()
	for participant_id in participants_by_id.keys():
		participants[participant_id] = participants_by_id[participant_id].to_dict()
	for seat in seat_states:
		seats.append(seat.to_dict())
	return {
		"v": SCHEMA_VERSION,
		"lobby_id": lobby_id,
		"room_name": room_name,
		"host_steam_id": host_steam_id,
		"phase_name": phase_name,
		"round_active": round_active,
		"members_by_steam_id": members,
		"participants_by_id": participants,
		"seat_states": seats,
		"session_scoreboard": session_scoreboard.to_dict(),
	}

static func from_dict(data: Dictionary) -> RoomState:
	var incoming_version := int(data.get("v", 0))
	if incoming_version != SCHEMA_VERSION:
		push_warning("RoomState schema mismatch: got v%d, expected v%d — snapshot may be stale" % [incoming_version, SCHEMA_VERSION])
	var state = load("res://scripts/room_state.gd").new()
	state.lobby_id = int(data.get("lobby_id", 0))
	state.room_name = String(data.get("room_name", ""))
	state.host_steam_id = int(data.get("host_steam_id", 0))
	state.phase_name = String(data.get("phase_name", "IDLE"))
	state.round_active = bool(data.get("round_active", false))
	state.members_by_steam_id.clear()
	state.participants_by_id.clear()
	state.seat_states.clear()
	for steam_id in data.get("members_by_steam_id", {}).keys():
		state.members_by_steam_id[int(steam_id)] = RoomMemberStateScript.from_dict(data["members_by_steam_id"][steam_id])
	for participant_id in data.get("participants_by_id", {}).keys():
		state.participants_by_id[int(participant_id)] = ParticipantProfileScript.from_dict(data["participants_by_id"][participant_id])
	for seat_data in data.get("seat_states", []):
		state.seat_states.append(SeatStateScript.from_dict(seat_data))
	if state.seat_states.is_empty():
		state.ensure_default_seats()
	state.session_scoreboard = SessionScoreboardScript.from_dict(data.get("session_scoreboard", {}))
	return state
