extends AudioStreamPlayer3D
class_name VoicePlayer3D

## Per-player 3D voice playback node. Attached as a child of remote PlayerBody.
## Receives decompressed PCM audio and pushes it into an AudioStreamGenerator
## for spatialized playback. Includes optional raycast-based occlusion.

var _playback: AudioStreamGeneratorPlayback = null
var _generator: AudioStreamGenerator = null

# Silence / talking detection
var _silence_timer: float = 0.0
var _is_talking: bool = false
const SILENCE_THRESHOLD: float = 0.25  # seconds without data = not talking

# Reusable buffer to avoid per-call allocation
var _frame_buffer: PackedVector2Array = PackedVector2Array()

# Occlusion
var _occlusion_enabled: bool = true
var _occlusion_ray: RayCast3D = null
var _is_occluded: bool = false
const OCCLUDED_VOLUME_REDUCTION: float = 12.0  # dB
const OCCLUDED_FILTER_CUTOFF: float = 2000.0   # Hz (muffled)
const NORMAL_FILTER_CUTOFF: float = 20500.0     # Hz (full range)
const LERP_SPEED: float = 8.0

var _base_volume_db: float = 0.0

func _ready() -> void:
	# Configure AudioStreamGenerator
	_generator = AudioStreamGenerator.new()
	_generator.mix_rate = float(VoiceChatService.get_decompress_rate())
	_generator.buffer_length = 0.2  # 200ms — jitter tolerance below perceptible latency
	stream = _generator

	# 3D audio properties for proximity voice
	max_distance = 70.0
	unit_size = 8.0
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	max_db = 6.0
	attenuation_filter_cutoff_hz = NORMAL_FILTER_CUTOFF
	attenuation_filter_db = -24.0
	bus = &"Voice"

	_base_volume_db = volume_db

	# Pre-allocate frame buffer at max capacity to avoid per-call allocation
	var max_frames: int = int(_generator.buffer_length * _generator.mix_rate)
	_frame_buffer.resize(max_frames)

	# Start the stream so we can get the playback reference
	play()
	_playback = get_stream_playback()

	# Setup occlusion raycast
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

	# Lerp volume and filter for smooth transitions
	var target_vol := _base_volume_db - (OCCLUDED_VOLUME_REDUCTION if _is_occluded else 0.0)
	var target_cutoff := OCCLUDED_FILTER_CUTOFF if _is_occluded else NORMAL_FILTER_CUTOFF
	volume_db = lerpf(volume_db, target_vol, delta * LERP_SPEED)
	attenuation_filter_cutoff_hz = lerpf(attenuation_filter_cutoff_hz, target_cutoff, delta * LERP_SPEED)

## Push decompressed PCM audio data into the generator playback buffer.
## [param pcm_data] is a PackedByteArray of 16-bit signed mono PCM samples.
func push_audio(pcm_data: PackedByteArray) -> void:
	if _playback == null:
		return

	var frame_count: int = pcm_data.size() / 2  # 16-bit mono = 2 bytes per sample
	if frame_count == 0:
		return

	# Clamp to available buffer space to avoid overrun
	var available: int = _playback.get_frames_available()
	if available <= 0:
		return
	if frame_count > available:
		frame_count = available

	# Build the entire frame buffer at once, then push in one call.
	# This is dramatically faster than pushing one frame at a time in GDScript.
	if frame_count > _frame_buffer.size():
		_frame_buffer.resize(frame_count)
	for i in frame_count:
		var sample: float = pcm_data.decode_s16(i * 2) / 32768.0
		_frame_buffer[i] = Vector2(sample, sample)
	_playback.push_buffer(_frame_buffer.slice(0, frame_count))

	# Update talking state
	if not _is_talking:
		_is_talking = true
		var body := get_parent()
		if body != null and body.has_method("set_talking_indicator"):
			body.set_talking_indicator(true)
	_silence_timer = 0.0

func _setup_occlusion_ray() -> void:
	_occlusion_ray = RayCast3D.new()
	_occlusion_ray.name = "OcclusionRay"
	_occlusion_ray.collision_mask = 1  # Layer 1 = walls/environment
	_occlusion_ray.enabled = true
	add_child(_occlusion_ray)
