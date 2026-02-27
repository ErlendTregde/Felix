extends Area3D
class_name KnockButton3D
## A 3D red cylinder "KNOCK" button that sits on the table surface.
## Uses Area3D for click detection (same pattern as Card3D).

signal button_pressed(player_id: int)

@export var player_id: int = 0

# Button dimensions
const BUTTON_RADIUS: float = 0.35
const BUTTON_HEIGHT: float = 0.1
const PRESS_DEPTH: float = 0.05
const PRESS_DURATION: float = 0.15

# Node references (built in _ready)
var cylinder_mesh: MeshInstance3D = null
var label: Label3D = null
var collision: CollisionShape3D = null

# State
var is_active: bool = false  # Whether the button can be clicked


func _ready() -> void:
	_build_visuals()
	_build_collision()

	# Connect Area3D signals for click detection
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# Start hidden
	visible = false
	is_active = false


# ======================================
# CONSTRUCTION
# ======================================

func _build_visuals() -> void:
	"""Create the red cylinder and KNOCK label."""
	# --- Cylinder body ---
	cylinder_mesh = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = BUTTON_RADIUS
	mesh.bottom_radius = BUTTON_RADIUS
	mesh.height = BUTTON_HEIGHT
	cylinder_mesh.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.12, 0.12)  # Red
	mat.roughness = 0.35
	mat.metallic = 0.1
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.05, 0.05)
	mat.emission_energy_multiplier = 0.3
	cylinder_mesh.material_override = mat

	# Position so bottom sits on the table (y = half height)
	cylinder_mesh.position = Vector3(0, BUTTON_HEIGHT / 2.0, 0)
	add_child(cylinder_mesh)

	# --- "KNOCK" text on top ---
	label = Label3D.new()
	label.text = "KNOCK"
	label.font_size = 48
	label.pixel_size = 0.003
	label.modulate = Color(1, 1, 1)
	label.outline_modulate = Color(0.1, 0.0, 0.0)
	label.outline_size = 8
	# Lay flat on top of cylinder (+Y up, text faces upward)
	label.position = Vector3(0, BUTTON_HEIGHT + 0.002, 0)
	label.rotation_degrees = Vector3(-90, 0, 0)  # Face upward
	add_child(label)


func _build_collision() -> void:
	"""Create a collision shape matching the cylinder."""
	collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = BUTTON_RADIUS
	shape.height = BUTTON_HEIGHT + 0.02  # Slightly taller for easier clicking
	collision.shape = shape
	collision.position = Vector3(0, BUTTON_HEIGHT / 2.0, 0)
	add_child(collision)


# ======================================
# SHOW / HIDE
# ======================================

func show_button() -> void:
	"""Make the button visible and clickable."""
	visible = true
	is_active = true
	# Reset cylinder to raised position
	if cylinder_mesh:
		cylinder_mesh.position.y = BUTTON_HEIGHT / 2.0
	if label:
		label.position.y = BUTTON_HEIGHT + 0.002


func hide_button() -> void:
	"""Make the button invisible and non-clickable."""
	visible = false
	is_active = false


# ======================================
# INTERACTION
# ======================================

func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	"""Handle mouse click — same pattern as Card3D."""
	if not is_active:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_animate_press()
			print("KNOCK button pressed by player %d" % player_id)


func _on_mouse_entered() -> void:
	"""Subtle hover feedback — brighten the button."""
	if not is_active:
		return
	if cylinder_mesh and cylinder_mesh.material_override:
		var mat: StandardMaterial3D = cylinder_mesh.material_override
		mat.emission_energy_multiplier = 0.8


func _on_mouse_exited() -> void:
	"""Remove hover feedback."""
	if cylinder_mesh and cylinder_mesh.material_override:
		var mat: StandardMaterial3D = cylinder_mesh.material_override
		mat.emission_energy_multiplier = 0.3


func _animate_press() -> void:
	"""Press the button down then emit after a short delay."""
	is_active = false  # Prevent double-clicks

	var tween = create_tween()
	# Press down
	tween.tween_property(cylinder_mesh, "position:y", (BUTTON_HEIGHT - PRESS_DEPTH) / 2.0, PRESS_DURATION)
	tween.parallel().tween_property(label, "position:y", BUTTON_HEIGHT - PRESS_DEPTH + 0.002, PRESS_DURATION)
	# Hold briefly
	tween.tween_interval(0.1)
	# Release back up
	tween.tween_property(cylinder_mesh, "position:y", BUTTON_HEIGHT / 2.0, PRESS_DURATION)
	tween.parallel().tween_property(label, "position:y", BUTTON_HEIGHT + 0.002, PRESS_DURATION)
	# Emit signal after animation
	tween.tween_callback(_emit_pressed)


func simulate_press() -> void:
	"""Called by bot AI to trigger the button without a mouse click."""
	if not is_active:
		return
	_animate_press()


func _emit_pressed() -> void:
	"""Emit the button_pressed signal (called after press animation)."""
	button_pressed.emit(player_id)
