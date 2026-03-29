extends AudioStreamPlayer3D
class_name VoicePlayer3D

## Per-player 3D voice playback. Pushes decompressed PCM directly into an
## AudioStreamGenerator with short fade-in/out to prevent clicks.

const SAMPLE_RATE: int = 48000
const FADE_FRAMES: int = 240              # 5 ms fade to prevent clicks
const SILENCE_TIMEOUT: float = 0.30

# Generator / playback
var _playback: AudioStreamGeneratorPlayback = null
var _generator: AudioStreamGenerator = null

# Reusable buffer
var _frame_buffer: PackedVector2Array = PackedVector2Array()

# Fade state
var _is_active: bool = false              # currently receiving voice data
var _fade_in_remaining: int = 0           # frames left in fade-in
var _last_sample: float = 0.0            # for fade-out

# Talking indicator
var _is_talking: bool = false
var _silence_timer: float = 0.0

# Occlusion
var _occlusion_enabled: bool = true
var _occlusion_ray: RayCast3D = null
var _is_occluded: bool = false
const OCCLUDED_VOLUME_REDUCTION: float = 12.0
const OCCLUDED_FILTER_CUTOFF: float = 2000.0
const NORMAL_FILTER_CUTOFF: float = 20500.0
const LERP_SPEED: float = 8.0
var _base_volume_db: float = 0.0

func _ready() -> void:
	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = float(SAMPLE_RATE)
	_generator.buffer_length = 0.2  # 200 ms headroom
	stream = _generator

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

func _process(delta: float) -> void:
	_silence_timer += delta
	if _is_talking and _silence_timer > SILENCE_TIMEOUT:
		_set_talking(false)
		# Fade out to avoid click when voice stops
		if _is_active:
			_push_fade_out()
			_is_active = false

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

## Push decompressed 16-bit mono PCM directly into the generator.
func push_audio(pcm_data: PackedByteArray) -> void:
	if _playback == null:
		return

	var frame_count: int = pcm_data.size() / 2
	if frame_count == 0:
		return

	var available: int = _playback.get_frames_available()
	if available <= 0:
		return
	if frame_count > available:
		frame_count = available

	# Start fade-in if this is a new voice burst
	if not _is_active:
		_is_active = true
		_fade_in_remaining = FADE_FRAMES

	# Build stereo frame buffer
	_frame_buffer.resize(frame_count)
	for i in frame_count:
		var s: float = pcm_data.decode_s16(i * 2) / 32768.0
		_frame_buffer[i] = Vector2(s, s)

	# Apply fade-in to prevent click at start
	if _fade_in_remaining > 0:
		var fade_count: int = mini(_fade_in_remaining, frame_count)
		var fade_start: int = FADE_FRAMES - _fade_in_remaining
		for i in fade_count:
			var t: float = float(fade_start + i + 1) / float(FADE_FRAMES)
			_frame_buffer[i] *= t
		_fade_in_remaining -= fade_count

	_playback.push_buffer(_frame_buffer)
	_last_sample = _frame_buffer[frame_count - 1].x

	_silence_timer = 0.0
	if not _is_talking:
		_set_talking(true)

## Short fade from last sample to zero — prevents click when voice stops.
func _push_fade_out() -> void:
	if _playback == null:
		return
	if absf(_last_sample) < 0.001:
		_last_sample = 0.0
		return
	var available: int = _playback.get_frames_available()
	var n: int = mini(FADE_FRAMES, available)
	if n <= 0:
		return

	_frame_buffer.resize(n)
	for i in n:
		var t: float = 1.0 - float(i + 1) / float(n)
		_frame_buffer[i] = Vector2(_last_sample * t, _last_sample * t)
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

func reset() -> void:
	_is_active = false
	_fade_in_remaining = 0
	_last_sample = 0.0
	_set_talking(false)
