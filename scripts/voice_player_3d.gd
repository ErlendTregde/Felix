extends AudioStreamPlayer3D
class_name VoicePlayer3D

## Per-player 3D voice playback node. Attached as a child of remote PlayerBody.
## Receives decompressed PCM audio and pushes it into an AudioStreamGenerator
## for spatialized playback. Includes optional raycast-based occlusion.

const SILENCE_THRESHOLD: float = 0.25  # seconds without data = not talking
const GENERATOR_BUFFER_LENGTH_SECONDS: float = 0.25
const STARTUP_PREFILL_SECONDS: float = 0.06
const TARGET_PLAYBACK_BUFFER_SECONDS: float = 0.08
const TRIMMED_BUFFER_SECONDS: float = 0.10
const MAX_BUFFERED_AUDIO_SECONDS: float = 0.18
const MAX_CHUNKS_PER_DRAIN: int = 4

const OCCLUDED_VOLUME_REDUCTION: float = 12.0  # dB
const OCCLUDED_FILTER_CUTOFF: float = 2000.0   # Hz (muffled)
const NORMAL_FILTER_CUTOFF: float = 20500.0    # Hz (full range)
const LERP_SPEED: float = 8.0

var _playback: AudioStreamGeneratorPlayback = null
var _generator: AudioStreamGenerator = null
var _mix_rate: int = 48000

# Silence / talking detection
var _silence_timer: float = 0.0
var _is_talking: bool = false

# Jitter buffering
var _queued_pcm_chunks: Array[PackedByteArray] = []
var _queued_frames: int = 0
var _playback_primed: bool = false
var _last_skip_count: int = 0

# Reusable buffer to avoid per-call allocation
var _frame_buffer: PackedVector2Array = PackedVector2Array()

# Occlusion
var _occlusion_enabled: bool = true
var _occlusion_ray: RayCast3D = null
var _is_occluded: bool = false
var _base_volume_db: float = 0.0

func _ready() -> void:
	# Configure AudioStreamGenerator with extra headroom for network jitter.
	_generator = AudioStreamGenerator.new()
	_mix_rate = VoiceChatService.get_sample_rate()
	_generator.mix_rate = float(_mix_rate)
	_generator.buffer_length = GENERATOR_BUFFER_LENGTH_SECONDS
	stream = _generator

	# 3D audio properties for proximity voice.
	max_distance = 70.0
	unit_size = 8.0
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	max_db = 0.0
	attenuation_filter_cutoff_hz = NORMAL_FILTER_CUTOFF
	attenuation_filter_db = -24.0
	bus = &"Voice"

	_base_volume_db = volume_db

	# Start the stream so we can get the playback reference.
	play()
	_playback = get_stream_playback()
	if _playback != null:
		_last_skip_count = _playback.get_skips()

	if _occlusion_enabled:
		_setup_occlusion_ray()

func _process(delta: float) -> void:
	_silence_timer += delta
	if _is_talking and _silence_timer > SILENCE_THRESHOLD:
		_is_talking = false
		var body := get_parent()
		if body != null and body.has_method("set_talking_indicator"):
			body.set_talking_indicator(false)

func _physics_process(delta: float) -> void:
	_sync_playback_skip_state()
	_drain_queued_audio()

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

## Queue decompressed PCM audio so playback can smooth network jitter.
## [param pcm_data] is a PackedByteArray of 16-bit signed mono PCM samples.
func push_audio(pcm_data: PackedByteArray) -> void:
	var frame_count: int = pcm_data.size() / 2
	if frame_count <= 0:
		return

	_queued_pcm_chunks.append(pcm_data)
	_queued_frames += frame_count
	_trim_stale_audio()

	if not _is_talking:
		_is_talking = true
		var body := get_parent()
		if body != null and body.has_method("set_talking_indicator"):
			body.set_talking_indicator(true)
	_silence_timer = 0.0

func _sync_playback_skip_state() -> void:
	if _playback == null:
		return

	var skip_count: int = _playback.get_skips()
	if skip_count > _last_skip_count:
		# Re-prime after an underrun instead of immediately playing a single late packet.
		_playback_primed = false
	_last_skip_count = skip_count

func _drain_queued_audio() -> void:
	if _playback == null or _queued_pcm_chunks.is_empty():
		return

	if not _playback_primed and _get_total_buffered_frames() < _seconds_to_frames(STARTUP_PREFILL_SECONDS):
		return
	_playback_primed = true

	var target_frames := _seconds_to_frames(TARGET_PLAYBACK_BUFFER_SECONDS)
	var drained_chunks: int = 0
	while drained_chunks < MAX_CHUNKS_PER_DRAIN and not _queued_pcm_chunks.is_empty():
		if _get_playback_buffered_frames() >= target_frames:
			break

		var pcm_chunk: PackedByteArray = _queued_pcm_chunks[0]
		var frame_count: int = pcm_chunk.size() / 2
		if frame_count <= 0:
			_queued_pcm_chunks.remove_at(0)
			continue
		if not _playback.can_push_buffer(frame_count):
			break

		_playback.push_buffer(_pcm_to_stereo_frames(pcm_chunk, frame_count))
		_queued_pcm_chunks.remove_at(0)
		_queued_frames -= frame_count
		drained_chunks += 1

func _trim_stale_audio() -> void:
	var max_frames := _seconds_to_frames(MAX_BUFFERED_AUDIO_SECONDS)
	if _get_total_buffered_frames() <= max_frames:
		return

	var trimmed_frames := _seconds_to_frames(TRIMMED_BUFFER_SECONDS)
	while not _queued_pcm_chunks.is_empty() and _get_total_buffered_frames() > trimmed_frames:
		var dropped_chunk: PackedByteArray = _queued_pcm_chunks[0]
		_queued_pcm_chunks.remove_at(0)
		_queued_frames -= dropped_chunk.size() / 2

	# Prefer dropping stale queued speech over letting voice drift far behind real time.
	_playback_primed = false

func _pcm_to_stereo_frames(pcm_data: PackedByteArray, frame_count: int) -> PackedVector2Array:
	_frame_buffer.resize(frame_count)
	for i in frame_count:
		var sample: float = pcm_data.decode_s16(i * 2) / 32768.0
		_frame_buffer[i] = Vector2(sample, sample)
	return _frame_buffer

func _get_total_buffered_frames() -> int:
	return _get_playback_buffered_frames() + _queued_frames

func _get_playback_buffered_frames() -> int:
	if _playback == null:
		return 0
	return max(0, _buffer_capacity_frames() - _playback.get_frames_available())

func _buffer_capacity_frames() -> int:
	return _seconds_to_frames(GENERATOR_BUFFER_LENGTH_SECONDS)

func _seconds_to_frames(seconds: float) -> int:
	return max(1, int(seconds * float(_mix_rate)))

func _setup_occlusion_ray() -> void:
	_occlusion_ray = RayCast3D.new()
	_occlusion_ray.name = "OcclusionRay"
	_occlusion_ray.collision_mask = 1  # Layer 1 = walls/environment
	_occlusion_ray.enabled = true
	add_child(_occlusion_ray)
