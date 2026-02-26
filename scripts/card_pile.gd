extends Node3D
class_name CardPile
## Visual representation of a card pile (draw or discard)
## Shows a stack of cards

@export var pile_type: String = "draw"  # "draw" or "discard"
@export var show_count: bool = true
@export var max_visual_cards: int = 10

var card_count: int = 0
var top_card_data: CardData = null
var is_interactive: bool = false  # Can be clicked
var is_hovered: bool = false
var hover_timer: Timer = null  # Debounce timer

var card_mesh_scene = preload("res://scenes/cards/card_3d.tscn")
var visual_cards: Array[MeshInstance3D] = []
var interaction_area: Area3D = null
var base_position: Vector3 = Vector3.ZERO
var placeholder_mesh: Node3D = null  # Frame container

signal pile_clicked(pile: CardPile)

func _ready() -> void:
	base_position = global_position
	create_placeholder()
	setup_interaction()
	setup_hover_timer()
	update_visual()

func setup_hover_timer() -> void:
	"""Setup debounce timer for hover exit"""
	hover_timer = Timer.new()
	hover_timer.wait_time = 0.1  # 100ms debounce
	hover_timer.one_shot = true
	hover_timer.timeout.connect(_apply_hover_exit)
	add_child(hover_timer)

func create_placeholder() -> void:
	"""Creates a visible placeholder border when pile is empty"""
	var container = Node3D.new()

	var width = 0.75
	var height = 1.05
	var border = 0.03  # Border thickness

	# White material
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.5

	# Top border (full width)
	var top = MeshInstance3D.new()
	var top_mesh = QuadMesh.new()
	top_mesh.size = Vector2(width, border)
	top.mesh = top_mesh
	top.material_override = mat
	top.rotation_degrees = Vector3(-90, 0, 0)
	top.position = Vector3(0, 0.001, -height/2)
	container.add_child(top)

	# Bottom border (full width)
	var bottom = MeshInstance3D.new()
	var bottom_mesh = QuadMesh.new()
	bottom_mesh.size = Vector2(width, border)
	bottom.mesh = bottom_mesh
	bottom.material_override = mat
	bottom.rotation_degrees = Vector3(-90, 0, 0)
	bottom.position = Vector3(0, 0.001, height/2)
	container.add_child(bottom)

	# Left border (inner height)
	var left = MeshInstance3D.new()
	var left_mesh = QuadMesh.new()
	left_mesh.size = Vector2(border, height - 2 * border)
	left.mesh = left_mesh
	left.material_override = mat
	left.rotation_degrees = Vector3(-90, 0, 0)
	left.position = Vector3(-width/2, 0.001, 0)
	container.add_child(left)

	# Right border (inner height)
	var right = MeshInstance3D.new()
	var right_mesh = QuadMesh.new()
	right_mesh.size = Vector2(border, height - 2 * border)
	right.mesh = right_mesh
	right.material_override = mat
	right.rotation_degrees = Vector3(-90, 0, 0)
	right.position = Vector3(width/2, 0.001, 0)
	container.add_child(right)

	placeholder_mesh = container
	add_child(placeholder_mesh)

func setup_interaction() -> void:
	"""Setup Area3D for click detection (both draw and discard piles)"""
	interaction_area = Area3D.new()
	add_child(interaction_area)
	
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.8, 0.2, 1.0)  # Slightly larger than card
	collision.shape = box
	collision.position = Vector3(0, 0.1, 0)
	interaction_area.add_child(collision)
	
	# Connect signals
	interaction_area.input_event.connect(_on_input_event)
	interaction_area.mouse_entered.connect(_on_mouse_entered)
	interaction_area.mouse_exited.connect(_on_mouse_exited)

func _on_input_event(_camera: Camera3D, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	"""Handle mouse clicks on pile"""
	if not is_interactive:
		return
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("%s pile clicked!" % pile_type.capitalize())
		pile_clicked.emit(self)

func _on_mouse_entered() -> void:
	"""Handle mouse hover start - elevate immediately"""
	if not is_interactive:
		return
	# Stop any pending lower action
	if hover_timer:
		hover_timer.stop()
	is_hovered = true
	apply_hover_enter()

func _on_mouse_exited() -> void:
	"""Handle mouse hover end - lower after delay"""
	if not is_interactive:
		return
	# Only start timer if not already running
	if hover_timer and not hover_timer.time_left > 0:
		hover_timer.start()

func apply_hover_enter() -> void:
	"""Elevate only the visual cards (not placeholder)"""
	for card in visual_cards:
		if is_instance_valid(card):
			var base_y = card.position.y
			var tween = card.create_tween()
			tween.tween_property(card, "position:y", base_y + 0.15, 0.1)

func _apply_hover_exit() -> void:
	"""Lower the cards after debounce delay"""
	if is_hovered:
		is_hovered = false
		lower_cards()

func lower_cards() -> void:
	"""Lower only the visual cards back to base position"""
	for i in range(visual_cards.size()):
		var card = visual_cards[i]
		if is_instance_valid(card):
			var base_y = i * 0.01  # Original stacked position
			var tween = card.create_tween()
			tween.tween_property(card, "position:y", base_y, 0.1)


func set_interactive(interactive: bool) -> void:
	"""Enable/disable pile interaction"""
	is_interactive = interactive
	if not is_interactive:
		is_hovered = false
		lower_cards()

func set_count(count: int) -> void:
	"""Update the pile count"""
	card_count = count
	update_visual()

func set_top_card(card_data: CardData) -> void:
	"""Set the top card (for discard pile)"""
	top_card_data = card_data
	update_visual()

func update_visual() -> void:
	"""Update visual representation of the pile"""
	# Clear existing visual cards
	for card in visual_cards:
		if is_instance_valid(card):
			card.queue_free()
	visual_cards.clear()
	
	# Create stacked cards visual
	var cards_to_show = min(card_count, max_visual_cards)
	
	for i in range(cards_to_show):
		var card_mesh = MeshInstance3D.new()
		var quad = QuadMesh.new()
		quad.size = Vector2(0.64, 0.89)
		card_mesh.mesh = quad
		
		# For discard pile, show top card face-up. Otherwise show backs
		if pile_type == "discard" and i == cards_to_show - 1 and top_card_data != null:
			# Top card of discard - show face (white)
			var mat = load("res://resources/materials/card_front_material.tres")
			if mat:
				card_mesh.set_surface_override_material(0, mat)
		else:
			# Use card back material (blue)
			var mat = load("res://resources/materials/card_back_material.tres")
			if mat:
				card_mesh.set_surface_override_material(0, mat)
		
		# Stack with slight offset
		card_mesh.position = Vector3(0, i * 0.01, 0)
		card_mesh.rotation_degrees = Vector3(-90, 0, 0)
		
		add_child(card_mesh)
		visual_cards.append(card_mesh)

func get_top_position() -> Vector3:
	"""Get position for the top of the pile"""
	return global_position + Vector3(0, card_count * 0.01, 0)
