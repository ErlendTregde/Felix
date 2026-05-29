extends Node3D

const PLAYER_BODY_SCENE := preload("res://scenes/players/player_body.tscn")

@onready var player_spawn: Marker3D = $PlayerSpawn
@onready var back_button: Button = $UI/BackButton

func _ready() -> void:
	# Spawn a single local player body — no networking in the playground.
	var body: PlayerBody = PLAYER_BODY_SCENE.instantiate()
	# Drop the MultiplayerSynchronizer (it errors without an active peer).
	var sync_node := body.get_node_or_null("MultiplayerSynchronizer")
	if sync_node:
		body.remove_child(sync_node)
		sync_node.queue_free()
	add_child(body)
	body.setup(0, 1, "Player", Color(0.4, 0.6, 0.9), true)
	body.set_standing(true)
	body.global_position = player_spawn.global_position
	body.activate_fps_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AppFlow.open_launcher()
