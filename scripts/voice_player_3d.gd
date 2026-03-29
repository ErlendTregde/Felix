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
const SILENCE_THRESHOLD: float = 0.3  # seconds without data = not talking

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
	_generator.mix_rate = 48000.0
	_generator.buffer_length = 0.5  # 500ms buffer for jitter tolerance
	stream = _generator

	# 3D audio properties for proximity voice
	max_distance = 40.0
	unit_size = 5.0
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	max_db = 6.0
	attenuation_filter_cutoff_hz = NORMAL_FILTER_CUTOFF
	attenuation_filter_db = -24.0
	bus = &"Voice"

	_base_volume_db = volume_db

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
		VoiceChatService.player_talking.emit(-1, false)  # Generic "stopped talking"

func _physics_process(delta: float) -> void:
	if not _occlusion_enabled or _occlusion_ray == null:
		return

	# Point the raycast toward the active AudioListener3D (local player camera)
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return

	var listener_pos := camera.global_position
	var direction := listener_pos - global_position
	_occlusion_ray.target_position = _occlusion_ray.to_local(listener_pos)

	_occlusion_ray.force_raycast_update()
	var was_occluded := _is_occluded
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
	for i in range(frame_count):
		if not _playback.can_push_buffer(1):
			break  # Buffer full — drop remaining to avoid overrun
		var sample: float = pcm_data.decode_s16(i * 2) / 32768.0
		_playback.push_frame(Vector2(sample, sample))  # Mono → stereo

	_silence_timer = 0.0
	_is_talking = true

func _setup_occlusion_ray() -> void:
	_occlusion_ray = RayCast3D.new()
	_occlusion_ray.name = "OcclusionRay"
	_occlusion_ray.collision_mask = 1  # Layer 1 = walls/environment
	_occlusion_ray.enabled = true
	add_child(_occlusion_ray)
