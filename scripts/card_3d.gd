extends Area3D
class_name Card3D
## 3D representation of a playing card with flip animation and interaction.
## Uses a single two-sided mesh from the GLB card model.

@export var card_data: CardData
@export var is_face_up: bool = false

var owner_player: Player = null
var is_highlighted: bool = false
var is_interactable: bool = true

## The single MeshInstance3D that shows the card (front + back baked in).
## Created at runtime, rotated on local X to flip between face-up / face-down.
var card_mesh: MeshInstance3D = null
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

## Rotation offset applied to card_mesh so that at rotation.x == 0 the FRONT faces +Y (face-up).
## Flip adds PI on X so the BACK faces +Y (face-down).
const FACE_DOWN_X := PI
const FACE_UP_X := 0.0

## Scale factor to shrink GLB card meshes to game-world size.
## Original game cards were 0.64 × 0.89 units. Adjust this if cards are too big/small.
const CARD_MESH_SCALE := Vector3(0.085, 0.085, 0.085)

signal card_clicked(card: Card3D)
signal flip_completed(card: Card3D, is_face_up: bool)
signal card_right_clicked(card: Card3D)

func _ready() -> void:
	add_to_group("cards")
	base_position = global_position

	# Create the MeshInstance3D that will hold the card model
	card_mesh = MeshInstance3D.new()
	card_mesh.name = "CardMesh"
	card_mesh.scale = CARD_MESH_SCALE
	add_child(card_mesh)

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

	# Apply initial face state
	_apply_face_state()

func initialize(data: CardData, face_up: bool = false) -> void:
	"""Initialize the card with data — loads the correct mesh from CardMeshLibrary."""
	card_data = data
	is_face_up = face_up

	# Fetch mesh + materials from the autoload library
	var mesh_data: Dictionary = CardMeshLibrary.get_card_mesh_data(card_data)
	if mesh_data.has("mesh") and mesh_data["mesh"]:
		card_mesh.mesh = mesh_data["mesh"]
		var materials: Array = mesh_data.get("materials", [])
		for i in range(materials.size()):
			if materials[i]:
				card_mesh.set_surface_override_material(i, materials[i])

	_apply_face_state()
	print("Card initialized: %s" % card_data.get_short_name())

func _apply_face_state() -> void:
	"""Instantly orient the card_mesh child so the correct side faces the camera."""
	if not card_mesh:
		return
	card_mesh.rotation.x = FACE_UP_X if is_face_up else FACE_DOWN_X

func flip(animate: bool = true, duration: float = 0.4) -> void:
	"""Flip the card over with animation (rotates card_mesh on its local X axis)."""
	is_face_up = not is_face_up

	if animate:
		is_animating = true
		var target_x: float = FACE_UP_X if is_face_up else FACE_DOWN_X

		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)

		# Overshoot then settle (juicy flip)
		var overshoot := 0.15
		var dir := 1.0 if is_face_up else -1.0
		tween.tween_property(card_mesh, "rotation:x", target_x + overshoot * dir, duration * 0.6)
		tween.tween_property(card_mesh, "rotation:x", target_x, duration * 0.4)
		tween.tween_callback(_on_flip_completed)
	else:
		_apply_face_state()
		_on_flip_completed()

func highlight(selected: bool = false) -> void:
	"""Apply a juicy glow directly to the card mesh materials.
	   Normal: pulsing bright emission + gentle scale bounce.
	   Selected: solid brighter emission, no pulse — clearly 'chosen'."""
	is_highlighted = true
	
	# Kill any previous highlight tween
	if highlight_tween:
		highlight_tween.kill()
		highlight_tween = null
	
	# Remove old overlay quad if leftover from previous implementation
	if highlight_mesh:
		highlight_mesh.queue_free()
		highlight_mesh = null
	
	# Store original materials on first highlight so we can restore later
	if not has_meta("original_materials"):
		var originals: Array = []
		if card_mesh and card_mesh.mesh:
			for i in range(card_mesh.mesh.get_surface_count()):
				var mat = card_mesh.get_active_material(i)
				originals.append(mat.duplicate() if mat else null)
		set_meta("original_materials", originals)
	
	# Apply subtle transparent amber-gold tint over the original card
	var glow_color: Color
	var emission_energy: float
	
	if selected:
		glow_color = Color(1.0, 0.85, 0.4)  # Bright warm gold
		emission_energy = 0.6
	else:
		glow_color = Color(0.95, 0.75, 0.35)  # Soft amber-gold
		emission_energy = 0.35
	
	if card_mesh and card_mesh.mesh:
		for i in range(card_mesh.mesh.get_surface_count()):
			var mat = card_mesh.get_active_material(i)
			if mat and mat is StandardMaterial3D:
				var glow_mat: StandardMaterial3D = mat.duplicate()
				glow_mat.emission_enabled = true
				glow_mat.emission = glow_color
				glow_mat.emission_energy_multiplier = emission_energy
				card_mesh.set_surface_override_material(i, glow_mat)

func remove_highlight() -> void:
	"""Remove glow, restore original materials, reset scale."""
	is_highlighted = false
	
	# Kill any highlight tween
	if highlight_tween:
		highlight_tween.kill()
		highlight_tween = null
	if has_meta("extra_highlight_tweens"):
		var extras: Array = get_meta("extra_highlight_tweens")
		for t in extras:
			if t is Tween and t.is_valid():
				t.kill()
		remove_meta("extra_highlight_tweens")
	
	# Remove overlay mesh if any
	if highlight_mesh:
		highlight_mesh.queue_free()
		highlight_mesh = null
	
	# Restore original materials
	if has_meta("original_materials") and card_mesh and card_mesh.mesh:
		var originals: Array = get_meta("original_materials")
		for i in range(mini(originals.size(), card_mesh.mesh.get_surface_count())):
			if originals[i]:
				card_mesh.set_surface_override_material(i, originals[i].duplicate())
			else:
				card_mesh.set_surface_override_material(i, null)
		remove_meta("original_materials")

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
	tween.tween_property(self, "global_position:y", base_position.y + height, duration)

func lower(duration: float = 0.15) -> void:
	"""Return card to base position"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "global_position:y", base_position.y, duration)

func move_to(target_position: Vector3, duration: float = 0.5, with_rotation: bool = false) -> void:
	"""Smoothly move card to target position with natural ease-out overshoot."""
	is_animating = true
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)  # Natural overshoot built into easing

	tween.tween_property(self, "global_position", target_position, duration)

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
	# Snap card_mesh to exact target to prevent drift from repeated flips
	_apply_face_state()
	Events.card_flipped.emit(self, is_face_up)
	flip_completed.emit(self, is_face_up)
	print("Card flipped: %s (face_up: %s)" % [card_data.get_short_name(), is_face_up])
