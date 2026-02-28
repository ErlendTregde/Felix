extends Node
## Loads and caches card meshes from the 3D card model GLB file.
## Autoload — access globally as CardMeshLibrary.

const CARD_MODEL_PATH = "res://assets/models/cards/52Cards.glb"

## Cached mesh data: key → { "mesh": Mesh, "materials": Array[Material] }
var _mesh_cache: Dictionary = {}
var _loaded: bool = false

## Suit enum → GLB folder/prefix name
const SUIT_NAMES: Dictionary = {
	CardData.Suit.CLUBS:    "clubs",
	CardData.Suit.DIAMONDS: "diamonds",
	CardData.Suit.HEARTS:   "hearts",
	CardData.Suit.SPADES:   "spades",
}

func _ready() -> void:
	_load_meshes()

# ------------------------------------------------------------------
# PUBLIC API
# ------------------------------------------------------------------

func get_card_mesh_data(card_data: CardData) -> Dictionary:
	"""Return { "mesh": Mesh, "materials": Array } for the given card.
	Returns empty dict if not found."""
	if not _loaded:
		_load_meshes()
	var key := _make_key(card_data)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	push_warning("CardMeshLibrary: No mesh found for key '%s'" % key)
	return {}

# ------------------------------------------------------------------
# LOADING
# ------------------------------------------------------------------

func _load_meshes() -> void:
	if _loaded:
		return

	var scene := load(CARD_MODEL_PATH) as PackedScene
	if not scene:
		push_error("CardMeshLibrary: Failed to load card model at %s" % CARD_MODEL_PATH)
		return

	var instance := scene.instantiate()

	# --- Standard cards (4 suits × 13 ranks) ---
	for suit_enum in SUIT_NAMES:
		var suit_name: String = SUIT_NAMES[suit_enum]
		for rank_num in range(1, 14):  # ACE=1 … KING=13
			var card_name := "%s%02d" % [suit_name, rank_num]
			var mesh_node := _find_mesh_in_subtree(instance, card_name)
			if mesh_node:
				_cache_mesh(suit_name + "_%d" % rank_num, mesh_node)
			else:
				push_warning("CardMeshLibrary: mesh not found for '%s'" % card_name)

	# --- Jokers ---
	for jname in ["blackJoker", "redJoker"]:
		var mesh_node := _find_mesh_in_subtree(instance, jname)
		if mesh_node:
			var key := "joker_black" if jname == "blackJoker" else "joker_red"
			_cache_mesh(key, mesh_node)
		else:
			push_warning("CardMeshLibrary: mesh not found for '%s'" % jname)

	instance.queue_free()
	_loaded = true
	print("CardMeshLibrary: Cached %d card meshes." % _mesh_cache.size())

# ------------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------------

func _cache_mesh(key: String, mesh_node: MeshInstance3D) -> void:
	var materials: Array = []
	if mesh_node.mesh:
		for i in range(mesh_node.mesh.get_surface_count()):
			var mat = mesh_node.get_surface_override_material(i)
			# Reduce shininess so cards are readable under bright spotlight
			if mat and mat is StandardMaterial3D:
				var m: StandardMaterial3D = mat.duplicate()
				m.roughness = maxf(m.roughness, 0.85)
				m.specular = 0.15
				m.metallic = 0.0
				materials.append(m)
			else:
				materials.append(mat)
	_mesh_cache[key] = {
		"mesh": mesh_node.mesh,
		"materials": materials,
	}

func _make_key(card_data: CardData) -> String:
	if card_data.rank == CardData.Rank.JOKER:
		return "joker_black" if card_data.joker_index == 0 else "joker_red"
	var suit_name: String = SUIT_NAMES.get(card_data.suit, "")
	return "%s_%d" % [suit_name, int(card_data.rank)]

func _find_mesh_in_subtree(root: Node, target_name: String) -> MeshInstance3D:
	"""Find a MeshInstance3D whose ancestor or self matches target_name.
	The GLB may nest the mesh under the named node, so we check children too."""
	var node := _find_node_by_name(root, target_name)
	if not node:
		return null
	if node is MeshInstance3D:
		return node
	# Check direct children (common GLB pattern: Node3D > MeshInstance3D)
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
	# Check grandchildren
	for child in node.get_children():
		for grandchild in child.get_children():
			if grandchild is MeshInstance3D:
				return grandchild
	return null

func _find_node_by_name(node: Node, target: String) -> Node:
	if node.name == target:
		return node
	for child in node.get_children():
		var found := _find_node_by_name(child, target)
		if found:
			return found
	return null
