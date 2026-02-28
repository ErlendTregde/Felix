extends Node3D
## Camera controller with smooth mouse-look (Liar's Bar style).
## The camera pivots around a look-at target based on mouse position,
## with clamped angles and smooth interpolation.

@onready var camera: Camera3D = $Camera3D

# ── Look-around settings ──
## How far the camera can rotate horizontally (degrees)
@export var max_yaw_deg: float = 25.0
## How far the camera can rotate vertically (degrees)
@export var max_pitch_deg: float = 15.0
## Smoothing speed (higher = snappier, 4-8 feels natural)
@export var smooth_speed: float = 5.0

# ── Internal state ──
var _base_transform: Transform3D   # The camera's resting transform (from scene)
var _target_yaw: float = 0.0       # Current target yaw offset in radians
var _target_pitch: float = 0.0     # Current target pitch offset in radians
var _current_yaw: float = 0.0      # Smoothed yaw
var _current_pitch: float = 0.0    # Smoothed pitch

# ── Shake ──
var is_shaking: bool = false
var shake_strength: float = 0.0
var original_position: Vector3

func _ready() -> void:
	if camera:
		_base_transform = camera.transform
		original_position = camera.position

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var viewport_size := get_viewport().get_visible_rect().size
		# Mouse position as -1..1 range (centered)
		var mouse_pos := get_viewport().get_mouse_position()
		var nx: float = (mouse_pos.x / viewport_size.x) * 2.0 - 1.0
		var ny: float = (mouse_pos.y / viewport_size.y) * 2.0 - 1.0
		# Map to target angles (clamped by max)
		_target_yaw = -nx * deg_to_rad(max_yaw_deg)
		_target_pitch = -ny * deg_to_rad(max_pitch_deg)

func _process(delta: float) -> void:
	if not camera:
		return

	# Smooth interpolation toward target angles
	_current_yaw = lerp(_current_yaw, _target_yaw, clampf(smooth_speed * delta, 0.0, 1.0))
	_current_pitch = lerp(_current_pitch, _target_pitch, clampf(smooth_speed * delta, 0.0, 1.0))

	# Build rotated transform from base
	var rotated := _base_transform
	# Apply yaw (rotate around local Y)
	rotated = rotated * Transform3D(Basis(Vector3.UP, _current_yaw), Vector3.ZERO)
	# Apply pitch (rotate around local X)
	rotated = rotated * Transform3D(Basis(Vector3.RIGHT, _current_pitch), Vector3.ZERO)

	camera.transform = rotated

	# Shake overlay
	if is_shaking:
		var offset = Vector3(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength),
			0
		)
		camera.position += offset

func shake(intensity: float = 0.1, duration: float = 0.3) -> void:
	"""Shake the camera for impactful events"""
	if is_shaking:
		return
	is_shaking = true
	shake_strength = intensity
	await get_tree().create_timer(duration).timeout
	is_shaking = false

func smooth_move_to(target_pos: Vector3, duration: float = 1.0) -> void:
	"""Smoothly move camera to new position and update base transform"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	if camera:
		tween.tween_property(camera, "position", target_pos, duration)
		# Update base transform so look-around works from the new position
		var new_base := _base_transform
		new_base.origin = target_pos
		_base_transform = new_base
		original_position = target_pos
