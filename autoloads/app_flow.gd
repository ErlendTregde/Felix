extends Node

const LAUNCHER_SCENE := "res://scenes/ui/launcher.tscn"
const LOCAL_GAME_SCENE := "res://scenes/main/game_table.tscn"
const STEAM_ROOM_SCENE := "res://scenes/main/steam_room.tscn"

var _pending_status_message: String = ""

func consume_status_message() -> String:
	var message := _pending_status_message
	_pending_status_message = ""
	return message

func open_launcher(status_message: String = "") -> void:
	_pending_status_message = status_message
	_change_scene_if_needed(LAUNCHER_SCENE)

func start_local_game(status_message: String = "") -> void:
	_pending_status_message = status_message
	_change_scene_if_needed(LOCAL_GAME_SCENE)

func open_steam_room(status_message: String = "") -> void:
	_pending_status_message = status_message
	_change_scene_if_needed(STEAM_ROOM_SCENE)

func _change_scene_if_needed(scene_path: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var current_scene = tree.current_scene
	if current_scene and current_scene.scene_file_path == scene_path:
		return
	tree.change_scene_to_file(scene_path)
