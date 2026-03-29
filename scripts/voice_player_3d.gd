extends AudioStreamPlayer3D
class_name VoicePlayer3D

## Per-player 3D voice playback with jitter-buffered audio.
##
## Instead of pushing packets straight into the AudioStreamGenerator (which
## causes crackling when packets arrive unevenly), incoming PCM is queued in a
## jitter buffer.  _process() drains the queue into the generator at a steady
## rate, keeping a small pre-buffer to absorb network jitter.
##
## State machine:
##   IDLE  → first packet arrives      → BUFFERING
##   BUFFERING → queue reaches target  → PLAYING  (fade-in)
##   PLAYING → queue drains to zero    → DRAINING (fade-out, then IDLE)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const SAMPLE_RATE: int = 48000

# Jitter buffer — how much audio to accumulate before playback starts.
# Higher = more jitter tolerance, lower = less latency.
# 60 ms ≈ 3 Opus frames — good balance for Steam P2P.
const PREBUFFER_FRAMES: int = int(SAMPLE_RATE * 0.06)  # 2880

# Short fade applied when voice starts/stops to prevent clicks.
const FADE_FRAMES: int = int(SAMPLE_RATE * 0.005)  # 5 ms = 240 frames

# If queue grows past this many samples, skip ahead to reduce latency buildup.
const MAX_QUEUE_FRAMES: int = int(SAMPLE_RATE * 0.30)  # 300 ms

# Silence timeout — how long without data before we consider the player silent.
const SILENCE_TIMEOUT: float = 0.30

# Playback states
enum VoiceState { IDLE, BUFFERING, PLAYING, DRAINING }

# ---------------------------------------------------------------------------
# Jitter buffer
# ---------------------------------------------------------------------------
var _packet_queue: Array = []           # Array of PackedFloat32Array
var _current_packet: PackedFloat32Array = PackedFloat32Array()
var _current_offset: int = 0
var _queued_samples: int = 0
var _state: VoiceState = VoiceState.IDLE

# Fade tracking
var _fade_progress: int = 0            # frames into current fade
var _last_sample: float = 0.0          # last pushed sample (for fade-out)

# Reusable push buffer
var _frame_buffer: PackedVector2Array = PackedVector2Array()

# Generator / playback references
var _playback: AudioStreamGeneratorPlayback = null
var _generator: AudioStreamGenerator = null

# Talking indicator
var _is_talking: bool = false
var _silence_timer: float = 0.0

# ---------------------------------------------------------------------------
# Occlusion
# ---------------------------------------------------------------------------
var _occlusion_enabled: bool = true
var _occlusion_ray: RayCast3D = null
var _is_occluded: bool = false
const OCCLUDED_VOLUME_REDUCTION: float = 12.0  # dB
const OCCLUDED_FILTER_CUTOFF: float = 2000.0
const NORMAL_FILTER_CUTOFF: float = 20500.0
const LERP_SPEED: float = 8.0
var _base_volume_db: float = 0.0

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func _ready() -> void:
	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = float(SAMPLE_RATE)
	# 300 ms generator buffer — gives headroom. Actual latency is controlled
	# by the jitter buffer pre-fill (~60 ms), not this value.
	_generator.buffer_length = 0.3
	stream = _generator

	# 3D audio properties
	max_distance = 70.0
	unit_size = 8.0
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	max_db = 6.0
	attenuation_filter_cutoff_hz = NORMAL_FILTER_CUTOFF
	attenuation_filter_db = -24.0
	bus = &"Voice"
	_base_volume_db = volume_db

	play()
	_playback = get_stream_playback()

	if _occlusion_enabled:
		_setup_occlusion_ray()

# ---------------------------------------------------------------------------
# Per-frame: drain jitter buffer → generator
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	# Silence detection
	_silence_timer += delta
	if _is_talking and _silence_timer > SILENCE_TIMEOUT:
		_set_talking(false)

	if _playback == null:
		return

	match _state:
		VoiceState.IDLE:
			return

		VoiceState.BUFFERING:
			if _queued_samples >= PREBUFFER_FRAMES:
				_state = VoiceState.PLAYING
				_fade_progress = 0
			else:
				return

		VoiceState.DRAINING:
			# Push a short fade-out from the last sample to zero, then go idle
			_push_fade_out()
			_state = VoiceState.IDLE
			return

	# --- VoiceState.PLAYING ---

	# If queue overflowed (sender outpacing us or burst), trim to keep latency bounded
	while _queued_samples > MAX_QUEUE_FRAMES and not _packet_queue.is_empty():
		var dropped: PackedFloat32Array = _packet_queue.pop_front()
		_queued_samples -= dropped.size()

	var available: int = _playback.get_frames_available()
	if available <= 0:
		return

	# Drain up to `available` frames from the packet queue
	var to_push: int = mini(available, _queued_samples)
	if to_push <= 0:
		# Queue ran dry — start draining (fade-out)
		_state = VoiceState.DRAINING
		return

	_frame_buffer.resize(to_push)
	var written: int = 0

	while written < to_push:
		# Advance to next packet if current one is exhausted
		if _current_offset >= _current_packet.size():
			if _packet_queue.is_empty():
				break
			_current_packet = _packet_queue.pop_front()
			_current_offset = 0

		var chunk_remaining: int = _current_packet.size() - _current_offset
		var n: int = mini(chunk_remaining, to_push - written)

		for i in n:
			var s: float = _current_packet[_current_offset + i]
			_frame_buffer[written + i] = Vector2(s, s)

		_current_offset += n
		written += n

	_queued_samples -= written

	if written == 0:
		_state = VoiceState.DRAINING
		return

	# Trim if we wrote fewer frames than allocated
	if written < _frame_buffer.size():
		_frame_buffer.resize(written)

	# Apply fade-in at the start of a new voice burst
	if _fade_progress < FADE_FRAMES:
		var fade_end: int = mini(FADE_FRAMES - _fade_progress, written)
		for i in fade_end:
			var t: float = float(_fade_progress + i + 1) / float(FADE_FRAMES)
			_frame_buffer[i] *= t
		_fade_progress += fade_end

	_playback.push_buffer(_frame_buffer)
	_last_sample = _frame_buffer[written - 1].x

func _physics_process(delta: float) -> void:
	if not _occlusion_enabled or _occlusion_ray == null:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return

	_occlusion_ray.target_position = _occlusion_ray.to_local(camera.global_position)
	_occlusion_ray.force_raycast_update()
	_is_occluded = _occlusion_ray.is_colliding()

	var target_vol := _base_volume_db - (OCCLUDED_VOLUME_REDUCTION if _is_occluded else 0.0)
	var target_cutoff := OCCLUDED_FILTER_CUTOFF if _is_occluded else NORMAL_FILTER_CUTOFF
	volume_db = lerpf(volume_db, target_vol, delta * LERP_SPEED)
	attenuation_filter_cutoff_hz = lerpf(attenuation_filter_cutoff_hz, target_cutoff, delta * LERP_SPEED)

# ---------------------------------------------------------------------------
# Public: receive a decompressed PCM packet
# ---------------------------------------------------------------------------

## Queue decompressed 16-bit mono PCM for jitter-buffered playback.
func push_audio(pcm_data: PackedByteArray) -> void:
	var frame_count: int = pcm_data.size() / 2
	if frame_count == 0:
		return

	# Decode s16 → float32 in one pass
	var samples := PackedFloat32Array()
	samples.resize(frame_count)
	for i in frame_count:
		samples[i] = pcm_data.decode_s16(i * 2) / 32768.0

	_packet_queue.append(samples)
	_queued_samples += frame_count

	# Kick the state machine
	if _state == VoiceState.IDLE:
		_state = VoiceState.BUFFERING
		_fade_progress = 0

	_silence_timer = 0.0
	if not _is_talking:
		_set_talking(true)

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Push a short crossfade from _last_sample to zero so the cutoff doesn't click.
func _push_fade_out() -> void:
	if _playback == null:
		return
	var available: int = _playback.get_frames_available()
	var n: int = mini(FADE_FRAMES, available)
	if n <= 0 or absf(_last_sample) < 0.001:
		_last_sample = 0.0
		return

	_frame_buffer.resize(n)
	for i in n:
		var t: float = 1.0 - float(i + 1) / float(n)
		var s: float = _last_sample * t
		_frame_buffer[i] = Vector2(s, s)
	_playback.push_buffer(_frame_buffer)
	_last_sample = 0.0

func _set_talking(talking: bool) -> void:
	_is_talking = talking
	var body := get_parent()
	if body != null and body.has_method("set_talking_indicator"):
		body.set_talking_indicator(talking)

func _setup_occlusion_ray() -> void:
	_occlusion_ray = RayCast3D.new()
	_occlusion_ray.name = "OcclusionRay"
	_occlusion_ray.collision_mask = 1
	_occlusion_ray.enabled = true
	add_child(_occlusion_ray)

## Call when this player disconnects or the scene is changing.
func reset() -> void:
	_packet_queue.clear()
	_current_packet = PackedFloat32Array()
	_current_offset = 0
	_queued_samples = 0
	_state = VoiceState.IDLE
	_last_sample = 0.0
	_set_talking(false)
