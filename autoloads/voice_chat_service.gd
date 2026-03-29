extends Node

## VoiceChatService - Manages proximity voice chat using Steam Voice API.
## Captures microphone audio via Steam, broadcasts compressed Opus data to peers,
## and routes received audio to per-player VoicePlayer3D nodes for 3D playback.

signal player_talking(seat_index: int, is_talking: bool)

const VOICE_POLL_INTERVAL: float = 0.02
const MAX_VOICE_POLLS_PER_TICK: int = 3

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

# Sample rate - fetched from Steam at startup for best quality
var _sample_rate: int = 48000
var _voice_poll_accumulator: float = 0.0

func _ready() -> void:
	_steam = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	if _steam != null and _steam.has_method("getVoiceOptimalSampleRate"):
		var rate: int = _steam.getVoiceOptimalSampleRate()
		if rate > 0:
			_sample_rate = rate
	FelixNetworkSession.player_left.connect(_on_player_left)
	FelixNetworkSession.host_disconnected.connect(stop_voice)
	FelixNetworkSession.connection_failed.connect(stop_voice)

func _physics_process(delta: float) -> void:
	if not _is_voice_capture_active():
		_reset_voice_poll_state()
		return

	_voice_poll_accumulator += delta
	var polls: int = 0
	while _voice_poll_accumulator >= VOICE_POLL_INTERVAL and polls < MAX_VOICE_POLLS_PER_TICK:
		_voice_poll_accumulator -= VOICE_POLL_INTERVAL
		_poll_outgoing_voice()
		polls += 1

	# Avoid building an unbounded catch-up burst after a frame hitch.
	if polls == MAX_VOICE_POLLS_PER_TICK and _voice_poll_accumulator > VOICE_POLL_INTERVAL:
		_voice_poll_accumulator = VOICE_POLL_INTERVAL

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("voice_toggle_mute"):
		toggle_mute()
	if _push_to_talk:
		if event.is_action_pressed("voice_push_to_talk"):
			_ptt_held = true
			if not _is_muted and _steam != null:
				_steam.startVoiceRecording()
				_reset_voice_poll_state()
		elif event.is_action_released("voice_push_to_talk"):
			_ptt_held = false
			if _steam != null:
				_steam.stopVoiceRecording()
			_reset_voice_poll_state()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func start_voice() -> void:
	if _steam == null:
		return
	if not _push_to_talk:
		_steam.startVoiceRecording()
	_is_recording = true
	_reset_voice_poll_state()

func stop_voice() -> void:
	if _steam != null:
		_steam.stopVoiceRecording()
	_is_recording = false
	_voice_players.clear()
	_local_seat_index = -1
	_reset_voice_poll_state()

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
	_reset_voice_poll_state()

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
	_reset_voice_poll_state()

func is_push_to_talk() -> bool:
	return _push_to_talk

func get_sample_rate() -> int:
	return _sample_rate

func _is_voice_capture_active() -> bool:
	if not _is_recording or _steam == null:
		return false
	if _is_muted:
		return false
	if _push_to_talk and not _ptt_held:
		return false
	return _can_broadcast_voice()

func _can_broadcast_voice() -> bool:
	if _local_seat_index < 0:
		return false
	if not multiplayer.has_multiplayer_peer():
		return false
	var peer := multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _poll_outgoing_voice() -> void:
	if _steam.has_method("getAvailableVoice"):
		var available_voice: Dictionary = _steam.getAvailableVoice()
		var available_bytes: int = int(available_voice.get("buffer", available_voice.get("written", 0)))
		if available_voice.get("result", -1) != 0 or available_bytes <= 0:
			return

	var voice_data: Dictionary = _steam.getVoice()
	if voice_data.get("result", -1) != 0 or voice_data.get("written", 0) <= 0:
		return
	_broadcast_voice.rpc(voice_data["buffer"], _local_seat_index)

func _reset_voice_poll_state() -> void:
	_voice_poll_accumulator = 0.0

# ---------------------------------------------------------------------------
# RPC - voice data transport (unreliable_ordered on channel 2)
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _broadcast_voice(compressed_data: PackedByteArray, sender_seat: int) -> void:
	if _steam == null:
		return

	var pcm: Dictionary = _steam.decompressVoice(compressed_data, _sample_rate)
	if pcm.get("result", -1) != 0 or pcm.get("size", 0) <= 0:
		return

	var player = _voice_players.get(sender_seat)
	if player != null and is_instance_valid(player):
		player.push_audio(pcm["uncompressed"])
		player_talking.emit(sender_seat, true)

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

func _on_player_left(_peer_id: int, steam_id: int) -> void:
	var room_state = SteamRoomService.get_room_state()
	if room_state == null:
		return
	var member = room_state.get_member(steam_id)
	if member != null and member.seat_index >= 0:
		unregister_voice_player(member.seat_index)
