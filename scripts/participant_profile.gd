extends RefCounted
class_name ParticipantProfile

var participant_id: int = -1
var display_name: String = ""
var avatar_color: Color = Color.WHITE
var control_type: SeatContext.SeatControlType = SeatContext.SeatControlType.BOT
var is_local: bool = false
var steam_id: int = 0
var peer_id: int = 0

func configure(
	new_participant_id: int,
	new_display_name: String,
	new_avatar_color: Color,
	new_control_type: SeatContext.SeatControlType,
	new_is_local: bool
) -> ParticipantProfile:
	participant_id = new_participant_id
	display_name = new_display_name
	avatar_color = new_avatar_color
	control_type = new_control_type
	is_local = new_is_local
	return self

func is_bot() -> bool:
	return control_type == SeatContext.SeatControlType.BOT

func is_local_human() -> bool:
	return control_type == SeatContext.SeatControlType.LOCAL_HUMAN

func is_remote_human() -> bool:
	return control_type == SeatContext.SeatControlType.REMOTE_HUMAN

func to_dict() -> Dictionary:
	return {
		"participant_id": participant_id,
		"display_name": display_name,
		"avatar_color": avatar_color.to_html(),
		"control_type": SeatContext.SeatControlType.keys()[control_type],
		"is_local": is_local,
		"steam_id": steam_id,
		"peer_id": peer_id,
	}

static func from_dict(data: Dictionary) -> ParticipantProfile:
	var profile = load("res://scripts/participant_profile.gd").new().configure(
		int(data.get("participant_id", -1)),
		String(data.get("display_name", "")),
		Color(data.get("avatar_color", "#ffffff")),
		SeatContext.SeatControlType.get(String(data.get("control_type", "BOT")), SeatContext.SeatControlType.BOT),
		bool(data.get("is_local", false))
	)
	profile.steam_id = int(data.get("steam_id", 0))
	profile.peer_id = int(data.get("peer_id", 0))
	return profile
