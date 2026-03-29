extends Node

## VoiceChatService — Manages proximity voice chat using Steam Voice API.
## Captures microphone audio via Steam, broadcasts compressed Opus data to peers,
## and routes received audio to per-player VoicePlayer3D nodes for 3D playback.

signal player_talking(seat_index: int, is_talking: bool)

# Recording state
var _is_recording: bool = false
var _is_muted: bool = false
var _push_to_talk: bool = false
var _ptt_held: bool = false

# Voice player routing: seat_index -> VoicePlayer3D
var _voice_players: Dictionary = {}
var _local_seat_index: int = -1

# Steam API reference
var _steam = null

# Always decompress at 48 kHz — Steam's "optimal" rate is often 11025 or 24000
# which sounds tinny/robotic.  48 kHz matches the AudioStreamGenerator mix rate
# and the Opus codec's native output, giving the cleanest result.
const SAMPLE_RATE: int = 48000

func _ready() -> void:
	_steam = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	FelixNetworkSession.player_left.connect(_on_player_left)

func _process(_delta: float) -> void:
	if not _is_recording or _steam == null:
		return
	if _is_muted:
		return
	if _push_to_talk and not _ptt_held:
		return

	# Poll every frame — Steam internally buffers ~20ms Opus frames.
	# Calling getVoice() once per frame at 60fps drains them with minimal latency.
	var voice_data: Dictionary = _steam.getVoice()
	if voice_data.get("result", -1) == 0 and voice_data.get("written", 0) > 0:
		_broadcast_voice.rpc(voice_data["buffer"], _local_seat_index)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("voice_toggle_mute"):
		toggle_mute()
	if _push_to_talk:
		if event.is_action_pressed("voice_push_to_talk"):
			_ptt_held = true
			if not _is_muted and _steam != null:
				_steam.startVoiceRecording()
		elif event.is_action_released("voice_push_to_talk"):
			_ptt_held = false
			if _steam != null:
				_steam.stopVoiceRecording()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func start_voice() -> void:
	if _steam == null:
		return
	if not _push_to_talk:
		_steam.startVoiceRecording()
	_is_recording = true

func stop_voice() -> void:
	if _steam != null:
		_steam.stopVoiceRecording()
	_is_recording = false
	_voice_players.clear()
	_local_seat_index = -1

func set_local_seat(seat_index: int) -> void:
	_local_seat_index = seat_index

func register_voice_player(seat_index: int, player: Node) -> void:
	_voice_players[seat_index] = player

func unregister_voice_player(seat_index: int) -> void:
	_voice_players.erase(seat_index)

func set_muted(muted: bool) -> void:
	_is_muted = muted
	if _steam == null:
		return
	if muted:
		_steam.stopVoiceRecording()
	elif _is_recording and not _push_to_talk:
		_steam.startVoiceRecording()

func toggle_mute() -> void:
	set_muted(not _is_muted)

func is_muted() -> bool:
	return _is_muted

func set_push_to_talk(enabled: bool) -> void:
	_push_to_talk = enabled
	if _steam == null or not _is_recording:
		return
	if enabled:
		_steam.stopVoiceRecording()
		_ptt_held = false
	else:
		if not _is_muted:
			_steam.startVoiceRecording()

func is_push_to_talk() -> bool:
	return _push_to_talk

# ---------------------------------------------------------------------------
# RPC — voice data transport (unreliable_ordered on channel 2)
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _broadcast_voice(compressed_data: PackedByteArray, sender_seat: int) -> void:
	if _steam == null:
		return

	var pcm: Dictionary = _steam.decompressVoice(compressed_data, SAMPLE_RATE)
	if pcm.get("result", -1) != 0 or pcm.get("size", 0) <= 0:
		return

	var player = _voice_players.get(sender_seat)
	if player != null and is_instance_valid(player):
		player.push_audio(pcm["uncompressed"])
		player_talking.emit(sender_seat, true)

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

func _on_player_left(peer_id: int, steam_id: int) -> void:
	var room_state = SteamRoomService.get_room_state()
	if room_state == null:
		return
	var member = room_state.get_member(steam_id)
	if member != null and member.seat_index >= 0:
		unregister_voice_player(member.seat_index)
