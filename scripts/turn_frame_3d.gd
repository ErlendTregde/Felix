extends Node3D
class_name TurnFrame3D
## Amber-gold glowing rectangular frame that outlines the active player's grid.
## Expands automatically to cover penalty card slots when the player has any.
## All bars share one material so they pulse perfectly in sync.

# ── Base size: covers 2×2 main grid only ──────────────────────────────────────
# Grid outer extent: X ±0.875, Z ±1.025  (cards at ±0.5, card w=0.75 h=1.05)
const HALF_W_BASE: float   = 1.15
const HALF_D_BASE: float   = 1.35


const THICKNESS: float = 0.055
const BAR_H: float     = 0.008
const Y_LIFT: float    = 0.025
# ── Per-slot extent used when computing dynamic bounding box ─────────────────
# Card half-sizes (from mesh): width 0.75→0.375, depth 1.05→0.525; + padding.
const SLOT_EXTENT_X: float = 0.65   # 0.375 + 0.275 padding
const SLOT_EXTENT_Z: float = 0.85   # 0.525 + 0.325 padding
# ── Corner bracket indicator ─────────────────────────────────────────────────
# A ┘-shaped marker that rises from the bottom-right corner of the frame.
# Visible only on the human player's turn.
const IND_VERT_H: float  = 0.50   # height the vertical bar rises above the table
const IND_HORIZ_L: float = 1.60   # length of the horizontal bar going left
const IND_THICK: float   = 0.045  # square cross-section for both indicator bars

const COLOR_AMBER := Color(0.95, 0.75, 0.35)
const ENERGY_LOW: float  = 0.45
const ENERGY_HIGH: float = 1.6

var shared_mat: StandardMaterial3D = null
var pulse_tween: Tween = null

# Per-bar references so we can reposition / resize them at runtime
var bar_top:   MeshInstance3D = null
var bar_bot:   MeshInstance3D = null
var bar_left:  MeshInstance3D = null
var bar_right: MeshInstance3D = null
var mesh_top:  BoxMesh = null
var mesh_bot:  BoxMesh = null
var mesh_left: BoxMesh = null
var mesh_right: BoxMesh = null

# 3D corner bracket indicator (visible only on human turn)
var ind_vert:  MeshInstance3D = null
var ind_horiz: MeshInstance3D = null
var ind_label: Label3D        = null

func _ready() -> void:
	_build_bars()
	_start_pulse()
	hide()

# ──────────────────────────────────────────────────────────────────────────────

func _build_bars() -> void:
	shared_mat = StandardMaterial3D.new()
	shared_mat.albedo_color = COLOR_AMBER
	shared_mat.emission_enabled = true
	shared_mat.emission = COLOR_AMBER
	shared_mat.emission_energy_multiplier = ENERGY_LOW
	shared_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var top_pair  := _make_bar(); bar_top   = top_pair[0];   mesh_top   = top_pair[1]
	var bot_pair  := _make_bar(); bar_bot   = bot_pair[0];   mesh_bot   = bot_pair[1]
	var left_pair := _make_bar(); bar_left  = left_pair[0];  mesh_left  = left_pair[1]
	var rght_pair := _make_bar(); bar_right = rght_pair[0];  mesh_right = rght_pair[1]

	add_child(bar_top)
	add_child(bar_bot)
	add_child(bar_left)
	add_child(bar_right)

	# Build corner bracket indicator (bottom-right corner, visible on human turns)
	var ind_v_mesh := BoxMesh.new()
	ind_v_mesh.size = Vector3(IND_THICK, IND_VERT_H, IND_THICK)
	ind_vert = MeshInstance3D.new()
	ind_vert.mesh = ind_v_mesh
	ind_vert.material_override = shared_mat

	var ind_h_mesh := BoxMesh.new()
	ind_h_mesh.size = Vector3(IND_HORIZ_L, IND_THICK, IND_THICK)
	ind_horiz = MeshInstance3D.new()
	ind_horiz.mesh = ind_h_mesh
	ind_horiz.material_override = shared_mat

	ind_label = Label3D.new()
	ind_label.text = "Your Turn"
	ind_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ind_label.modulate = COLOR_AMBER
	ind_label.font_size = 48
	ind_label.pixel_size = 0.0035
	ind_label.outline_size = 8
	ind_label.outline_modulate = Color(0, 0, 0, 1)
	ind_label.no_depth_test = true

	add_child(ind_vert)
	add_child(ind_horiz)
	add_child(ind_label)

	ind_vert.visible  = false
	ind_horiz.visible = false
	ind_label.visible = false

	_apply_size(-HALF_W_BASE, HALF_W_BASE, -HALF_D_BASE, HALF_D_BASE, false)

func _make_bar() -> Array:
	"""Returns [MeshInstance3D, BoxMesh]."""
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	mi.mesh = bm
	mi.material_override = shared_mat
	return [mi, bm]

func _apply_size(min_x: float, max_x: float, min_z: float, max_z: float, animate: bool) -> void:
	"""Reposition bars to form a rectangle spanning [min_x..max_x] × [min_z..max_z]."""
	var cx: float    = (min_x + max_x) * 0.5
	var cz: float    = (min_z + max_z) * 0.5
	var width: float = max_x - min_x
	var depth: float = max_z - min_z

	# Resize meshes immediately (BoxMesh.size cannot be tweened)
	mesh_top.size   = Vector3(width,     BAR_H, THICKNESS)
	mesh_bot.size   = Vector3(width,     BAR_H, THICKNESS)
	mesh_left.size  = Vector3(THICKNESS, BAR_H, depth - THICKNESS * 2.0)
	mesh_right.size = Vector3(THICKNESS, BAR_H, depth - THICKNESS * 2.0)

	if animate:
		var t := create_tween()
		t.set_parallel(true)
		t.set_trans(Tween.TRANS_QUAD)
		t.set_ease(Tween.EASE_OUT)
		t.tween_property(bar_top,   "position", Vector3(cx,    Y_LIFT, min_z), 0.22)
		t.tween_property(bar_bot,   "position", Vector3(cx,    Y_LIFT, max_z), 0.22)
		t.tween_property(bar_left,  "position", Vector3(min_x, Y_LIFT, cz),   0.22)
		t.tween_property(bar_right, "position", Vector3(max_x, Y_LIFT, cz),   0.22)
	else:
		bar_top.position   = Vector3(cx,    Y_LIFT, min_z)
		bar_bot.position   = Vector3(cx,    Y_LIFT, max_z)
		bar_left.position  = Vector3(min_x, Y_LIFT, cz)
		bar_right.position = Vector3(max_x, Y_LIFT, cz)

	# Keep indicator anchored to bottom-right corner (max_x, max_z)
	# Vertical bar rises from the corner; horizontal bar and label extend to the RIGHT.
	if ind_vert:
		var ind_y_top: float = Y_LIFT + IND_VERT_H
		ind_vert.position  = Vector3(max_x,                      Y_LIFT + IND_VERT_H * 0.5, max_z)
		ind_horiz.position = Vector3(max_x + IND_HORIZ_L * 0.5, ind_y_top,                  max_z)
		ind_label.position = Vector3(max_x + IND_HORIZ_L * 0.5, ind_y_top - 0.13,           max_z + 0.06)

# ──────────────────────────────────────────────────────────────────────────────

func _start_pulse() -> void:
	if pulse_tween:
		pulse_tween.kill()
	pulse_tween = create_tween()
	pulse_tween.set_loops()
	pulse_tween.set_trans(Tween.TRANS_SINE)
	pulse_tween.set_ease(Tween.EASE_IN_OUT)
	pulse_tween.tween_property(shared_mat, "emission_energy_multiplier", ENERGY_HIGH, 0.9)
	pulse_tween.tween_interval(0.1)
	pulse_tween.tween_property(shared_mat, "emission_energy_multiplier", ENERGY_LOW, 0.9)
	pulse_tween.tween_interval(0.1)

# ──────────────────────────────────────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────────────────────────────────────

func move_to_grid(grid: Node3D, is_human_turn: bool = false) -> void:
	"""Slide the frame to the given player grid, expanding if penalty cards exist.
	Shows the 3D corner bracket indicator only when is_human_turn is true."""
	show()

	# Show / hide the 3D corner bracket indicator
	ind_vert.visible  = is_human_turn
	ind_horiz.visible = is_human_turn
	ind_label.visible = is_human_turn

	# Compute bounding box from actual occupied card slots (main grid + penalty cards)
	var min_x := -HALF_W_BASE
	var max_x :=  HALF_W_BASE
	var min_z := -HALF_D_BASE
	var max_z :=  HALF_D_BASE

	if grid is PlayerGrid:
		var pg := grid as PlayerGrid
		for i in range(pg.penalty_cards.size()):
			var slot_idx: int = i  # penalty_cards[i] was placed at penalty_positions[i]
			if slot_idx >= pg.penalty_positions.size():
				break
			var pc = pg.penalty_cards[i]
			if not is_instance_valid(pc):
				continue
			var p: Vector3 = pg.penalty_positions[slot_idx]
			min_x = min(min_x, p.x - SLOT_EXTENT_X)
			max_x = max(max_x, p.x + SLOT_EXTENT_X)
			min_z = min(min_z, p.z - SLOT_EXTENT_Z)
			max_z = max(max_z, p.z + SLOT_EXTENT_Z)

	_apply_size(min_x, max_x, min_z, max_z, true)

	# Slide to grid position / rotation
	var t := create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_QUAD)
	t.set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", grid.global_position, 0.22)
	t.tween_property(self, "global_rotation",  grid.global_rotation,  0.22)
