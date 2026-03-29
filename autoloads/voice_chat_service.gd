extends Node

## VoiceChatService - Manages proximity voice chat using Steam Voice API.
## Captures microphone audio via Steam, broadcasts compressed Opus data to peers,
## and routes received audio to per-player VoicePlayer3D nodes for 3D playback.

signal player_talking(seat_index: int, is_talking: bool)

const VOICE_POLL_INTERVAL: float = 0.02
const MAX_VOICE_POLLS_PER_FRAME: int = 3
const MAX_OUTGOING_VOICE_PACKETS_PER_POLL: int = 3

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
	if _steam != null:
		if _steam.has_method("getVoiceOptimalSampleRate"):
			var rate: int = _steam.getVoiceOptimalSampleRate()
			if rate > 0:
				_sample_rate = rate
	FelixNetworkSession.player_left.connect(_on_player_left)
	FelixNetworkSession.host_disconnected.connect(stop_voice)
	FelixNetworkSession.connection_failed.connect(stop_voice)

func _process(delta: float) -> void:
	if not _is_voice_capture_active():
		_reset_voice_poll_state()
		return

	_voice_poll_accumulator += delta
	var polls: int = 0
	while _voice_poll_accumulator >= VOICE_POLL_INTERVAL and polls < MAX_VOICE_POLLS_PER_FRAME:
		_voice_poll_accumulator -= VOICE_POLL_INTERVAL
		_poll_outgoing_voice()
		polls += 1

	# Avoid building an unbounded catch-up burst after a frame hitch.
	if polls == MAX_VOICE_POLLS_PER_FRAME and _voice_poll_accumulator > VOICE_POLL_INTERVAL:
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
	return _can_send_voice_to_room()

func _can_send_voice_to_room() -> bool:
	if _local_seat_index < 0 or _steam == null:
		return false
	if int(State.lobby_data.id) == 0:
		return false
	if not multiplayer.has_multiplayer_peer():
		return false
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	return not _get_voice_targets().is_empty()

func _poll_outgoing_voice() -> void:
	if not _can_send_voice_to_room():
		return

	var sent_packets := 0
	while sent_packets < MAX_OUTGOING_VOICE_PACKETS_PER_POLL:
		if not _steam.has_method("getAvailableVoice"):
			return

		var available_voice: Dictionary = _steam.getAvailableVoice()
		var available_bytes: int = int(available_voice.get("buffer", available_voice.get("written", 0)))
		if available_voice.get("result", -1) != 0 or available_bytes <= 0:
			break

		var voice_data: Dictionary = _steam.getVoice()
		var written: int = int(voice_data.get("written", 0))
		if voice_data.get("result", -1) != 0 or written <= 0:
			break

		var compressed_data: PackedByteArray = _trim_buffer_to_size(
			voice_data.get("buffer", PackedByteArray()),
			written
		)
		if compressed_data.is_empty():
			break

		_broadcast_voice.rpc(compressed_data, _local_seat_index)
		sent_packets += 1

func _get_voice_targets() -> Array[int]:
	var room_state = SteamRoomService.get_room_state()
	var targets: Array[int] = []
	if room_state == null:
		return targets

	var local_steam_id := SteamPlatformService.get_local_steam_id()
	for member in room_state.members_by_steam_id.values():
		if member == null:
			continue
		if member.steam_id == 0 or member.steam_id == local_steam_id:
			continue
		if member.seat_index < 0:
			continue
		targets.append(member.steam_id)
	return targets

func _get_seat_index_for_steam_id(steam_id: int) -> int:
	var room_state = SteamRoomService.get_room_state()
	if room_state == null:
		return -1
	var member = room_state.get_member(steam_id)
	if member == null:
		return -1
	return member.seat_index

func _trim_buffer_to_size(buffer: PackedByteArray, size: int) -> PackedByteArray:
	if size <= 0 or buffer.is_empty():
		return PackedByteArray()
	if buffer.size() <= size:
		return buffer
	var trimmed := buffer
	trimmed.resize(size)
	return trimmed

func _reset_voice_poll_state() -> void:
	_voice_poll_accumulator = 0.0

# ---------------------------------------------------------------------------
# RPC - voice data transport (unreliable_ordered on channel 2)
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _broadcast_voice(compressed_data: PackedByteArray, sender_seat: int) -> void:
	if _steam == null or sender_seat < 0:
		return

	var pcm: Dictionary = _steam.decompressVoice(compressed_data, _sample_rate)
	var pcm_size: int = int(pcm.get("size", 0))
	if pcm.get("result", -1) != 0 or pcm_size <= 0:
		return

	var uncompressed: PackedByteArray = _trim_buffer_to_size(
		pcm.get("uncompressed", PackedByteArray()),
		pcm_size
	)
	if uncompressed.is_empty():
		return

	var player = _voice_players.get(sender_seat)
	if player != null and is_instance_valid(player):
		player.push_audio(uncompressed)
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
