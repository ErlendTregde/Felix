extends Area3D
class_name Card3D
## 3D representation of a playing card with flip animation and interaction

@export var card_data: CardData
@export var is_face_up: bool = false

var owner_player: Player = null
var is_highlighted: bool = false
var is_interactable: bool = true

@onready var front_mesh: MeshInstance3D = $FrontMesh
@onready var back_mesh: MeshInstance3D = $BackMesh
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Visual feedback
var highlight_mesh: MeshInstance3D = null
var highlight_tween: Tween = null
var base_position: Vector3 = Vector3.ZERO
var is_hovered: bool = false
var hover_timer: Timer = null
var is_elevation_locked: bool = false  # Prevents hover system from lowering card

# Matching (Phase 6) — right-click to attempt match
var is_animating: bool = false  # True while a tween is running — blocks right-click

signal card_clicked(card: Card3D)
signal flip_completed(card: Card3D, is_face_up: bool)
signal card_right_clicked(card: Card3D)

func _ready() -> void:
	add_to_group("cards")
	base_position = global_position
	
	# Create hover debounce timer
	hover_timer = Timer.new()
	hover_timer.one_shot = true
	hover_timer.wait_time = 0.1  # 100ms debounce for lowering
	hover_timer.timeout.connect(_apply_hover_state)
	add_child(hover_timer)
	
	# Connect input signals
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# Set initial visibility
	update_visibility()

func initialize(data: CardData, face_up: bool = false) -> void:
	"""Initialize the card with data"""
	card_data = data
	is_face_up = face_up
	update_visibility()
	print("Card initialized: %s" % card_data.get_short_name())

func flip(animate: bool = true, duration: float = 0.4) -> void:
	"""Flip the card over with animation"""
	is_face_up = not is_face_up
	
	if animate:
		is_animating = true
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		
		# Rotate 180 degrees on Y axis with slight overshoot
		var current_rotation = rotation.y
		var target_rotation = current_rotation + PI
		
		# Add overshoot for juice
		tween.tween_property(self, "rotation:y", target_rotation + 0.2, duration * 0.6)
		tween.tween_property(self, "rotation:y", target_rotation, duration * 0.4)
		
		# Update visibility halfway through flip
		tween.tween_callback(update_visibility).set_delay(duration * 0.5)
		tween.tween_callback(_on_flip_completed)
	else:
		rotation.y += PI
		update_visibility()
		_on_flip_completed()

func update_visibility() -> void:
	"""Update which side of the card is visible"""
	if not is_inside_tree():
		return
		
	if front_mesh and back_mesh:
		front_mesh.visible = is_face_up
		back_mesh.visible = not is_face_up

func highlight(selected: bool = false) -> void:
	"""Add a flat glow overlay on the card surface.
	   Normal: bright cyan pulse.  Selected: dark solid cyan (card has been chosen)."""
	is_highlighted = true
	
	# Fully recreate the mesh each time so colour/state is always fresh
	if highlight_mesh:
		if highlight_tween:
			highlight_tween.kill()
			highlight_tween = null
		highlight_mesh.queue_free()
		highlight_mesh = null
	
	highlight_mesh = MeshInstance3D.new()
	var quad_mesh = QuadMesh.new()
	quad_mesh.size = Vector2(0.64, 0.89)  # Exact card face size
	highlight_mesh.mesh = quad_mesh
	# Cards lie flat in XZ plane (face +Y). QuadMesh faces +Z (XY plane),
	# so rotate -90 on X to lie flat — same orientation as FrontMesh / BackMesh.
	highlight_mesh.rotation_degrees = Vector3(-90, 0, 0)
	highlight_mesh.position = Vector3(0, 0.006, 0)  # Float just above card face
	add_child(highlight_mesh)
	
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	if selected:
		# Darker, solid cyan — no pulse, clearly indicates "this card is chosen"
		var sel_color = Color(0.0, 0.55, 0.75)
		material.albedo_color = Color(sel_color.r, sel_color.g, sel_color.b, 0.55)
		material.emission_enabled = true
		material.emission = sel_color
		material.emission_energy_multiplier = 1.2
		highlight_mesh.material_override = material
		# No tween — solid state
	else:
		# Bright cyan with breathing pulse
		var glow_color = Color(0.0, 0.85, 1.0)
		var intensity: float = 0.8
		material.albedo_color = Color(glow_color.r, glow_color.g, glow_color.b, 0.32)
		material.emission_enabled = true
		material.emission = glow_color
		material.emission_energy_multiplier = intensity
		highlight_mesh.material_override = material
		
		highlight_tween = create_tween()
		highlight_tween.set_loops()
		highlight_tween.tween_property(highlight_mesh, "material_override:emission_energy_multiplier",
				intensity * 0.25, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		highlight_tween.tween_property(highlight_mesh, "material_override:emission_energy_multiplier",
				intensity, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func remove_highlight() -> void:
	"""Fully remove the glow highlight and free all resources"""
	is_highlighted = false
	if highlight_tween:
		highlight_tween.kill()
		highlight_tween = null
	if highlight_mesh:
		highlight_mesh.queue_free()
		highlight_mesh = null

func set_highlighted(highlighted: bool, selected: bool = false) -> void:
	"""Helper to set highlight state. Pass selected=true for the darker 'chosen' style."""
	if highlighted:
		highlight(selected)
	else:
		remove_highlight()

func elevate(height: float = 0.2, duration: float = 0.15) -> void:
	"""Elevate the card (for hover effect)"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "position:y", base_position.y + height, duration)

func lower(duration: float = 0.15) -> void:
	"""Return card to base position"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "position:y", base_position.y, duration)

func move_to(target_position: Vector3, duration: float = 0.5, with_rotation: bool = false) -> void:
	"""Smoothly move card to target position"""
	is_animating = true
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Add slight overshoot for juice
	var overshoot = (target_position - global_position).normalized() * 0.2
	tween.tween_property(self, "global_position", target_position + overshoot, duration * 0.7)
	tween.tween_property(self, "global_position", target_position, duration * 0.3)
	
	if with_rotation:
		# Add spin during movement
		tween.parallel().tween_property(self, "rotation:y", rotation.y + TAU, duration)
	
	base_position = target_position
	tween.tween_callback(func(): is_animating = false)

func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	"""Handle mouse input: left-click = select/use (gated by is_interactable), right-click = attempt match (always allowed when not animating)."""
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if is_interactable:
				card_clicked.emit(self)
				print("Card clicked: %s" % card_data.get_short_name())
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if not is_animating:
				card_right_clicked.emit(self)

func _on_mouse_entered() -> void:
	"""Handle mouse hover start - elevate immediately (always allowed when not animating)"""
	if not is_animating and not is_hovered:
		# Stop any pending lower action
		if hover_timer:
			hover_timer.stop()
		is_hovered = true
		elevate()

func _on_mouse_exited() -> void:
	"""Handle mouse hover end - lower after delay"""
	if not is_animating and is_hovered:
		# Only start timer if not already running (prevents restart spam)
		if hover_timer and not hover_timer.time_left > 0:
			hover_timer.start()

func _apply_hover_state() -> void:
	"""Lower the card after debounce delay"""
	if is_elevation_locked:
		return  # Don't lower if elevation is locked (e.g., during Jack ability)
	if is_hovered:
		is_hovered = false
		lower()

func _on_flip_completed() -> void:
	"""Called when flip animation completes"""
	is_animating = false
	Events.card_flipped.emit(self, is_face_up)
	flip_completed.emit(self, is_face_up)
	print("Card flipped: %s (face_up: %s)" % [card_data.get_short_name(), is_face_up])
