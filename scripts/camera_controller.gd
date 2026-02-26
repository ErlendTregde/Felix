extends Node3D
## Camera controller for the game table view
## Fixed perspective with optional shake effects

@onready var camera: Camera3D = $Camera3D

var is_shaking: bool = false
var shake_strength: float = 0.0
var original_position: Vector3

func _ready() -> void:
	if camera:
		original_position = camera.position

func _process(_delta: float) -> void:
	if is_shaking and camera:
		# Apply random shake offset
		var offset = Vector3(
			randf_range(-shake_strength, shake_strength),
			randf_range(-shake_strength, shake_strength),
			0
		)
		camera.position = original_position + offset

func shake(intensity: float = 0.1, duration: float = 0.3) -> void:
	"""Shake the camera for impactful events"""
	if is_shaking:
		return
	
	is_shaking = true
	shake_strength = intensity
	
	# Auto-stop after duration
	await get_tree().create_timer(duration).timeout
	
	is_shaking = false
	if camera:
		camera.position = original_position

func smooth_move_to(target_pos: Vector3, duration: float = 1.0) -> void:
	"""Smoothly move camera to new position"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	if camera:
		tween.tween_property(camera, "position", target_pos, duration)
		original_position = target_pos
