extends Node

const PORT = 13154

signal session_started_signal
signal player_joined_signal(peer_id: int)
signal player_left_signal(peer_id: int, steam_id: int)
signal host_disconnected_signal
signal connection_failed_signal
signal peer_registered_signal(peer_id: int, steam_id: int)

var peer = null
var _handlers: Array[SessionHandler] = []
var _steam = null

func _ready() -> void:
	_steam = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	multiplayer.peer_connected.connect(_player_connected)
	multiplayer.peer_disconnected.connect(_player_disconnected)
	multiplayer.connected_to_server.connect(_connected_ok)
	multiplayer.connection_failed.connect(_connected_fail)
	multiplayer.server_disconnected.connect(_host_disconnected)

func _new_peer_instance():
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return null
	return ClassDB.instantiate("SteamMultiplayerPeer")

func register_handler(_handler) -> void:
	if _handler is SessionHandler and not _handlers.has(_handler):
		_handlers.append(_handler)

func unregister_handler(_handler) -> void:
	if _handler is SessionHandler and _handlers.has(_handler):
		_handlers.erase(_handler)

func notify_handlers(_method: StringName, ...args: Array) -> void:
	for handler in _handlers:
		if is_instance_valid(handler) and handler.has_method(_method):
			handler.callv(_method, args)

func reset_transport_state() -> void:
	multiplayer.set_multiplayer_peer(null)
	peer = null
	State.current_state = State.GameState.LOBBY
	State.lobby_data.started = false
	State.lobby_data.peer_members.clear()

func create_socket() -> void:
	reset_transport_state()
	peer = _new_peer_instance()
	if peer == null:
		connection_failed_signal.emit()
		notify_handlers("on_connection_failed")
		return
	peer.create_host(0)
	multiplayer.set_multiplayer_peer(peer)
	State.lobby_data.peer_members[1] = State.user_data.steam_id
	print("establishing connection (host)")

func connect_socket(_id: int) -> void:
	reset_transport_state()
	peer = _new_peer_instance()
	if peer == null:
		connection_failed_signal.emit()
		notify_handlers("on_connection_failed")
		return
	peer.create_client(_id, 0)
	multiplayer.set_multiplayer_peer(peer)
	print("establishing connection (client)")

func start_session() -> void:
	if not multiplayer.is_server():
		return
	
	_mark_session_started.rpc()
	notify_handlers("on_game_start", State.lobby_data.peer_members.keys())

func _host_disconnected() -> void:
	print("disconnected from host")
	reset_transport_state()
	notify_handlers("on_host_disconnected")
	host_disconnected_signal.emit()

func _connected_ok() -> void:
	print("connected_ok")

func _connected_fail() -> void:
	print("connected_fail")
	reset_transport_state()
	notify_handlers("on_connection_failed")
	connection_failed_signal.emit()

func _player_disconnected(_id: int) -> void:
	var steam_id := int(State.lobby_data.peer_members.get(_id, 0))
	State.lobby_data.peer_members.erase(_id)
	print("player with peer id: " + str(_id) + " left....")
	
	if multiplayer.is_server():
		notify_handlers("on_player_leave", _id)
	player_left_signal.emit(_id, steam_id)

func _player_connected(_id: int) -> void:
	print("player_connected")
	
	var my_steam_id = State.user_data.steam_id
	register_peer.rpc_id(_id, my_steam_id)
	
	if multiplayer.is_server():
		notify_handlers("on_player_join", _id)
	player_joined_signal.emit(_id)

@rpc("call_local", "reliable")
func _mark_session_started() -> void:
	State.current_state = State.GameState.IN_GAME
	State.lobby_data.started = true
	notify_handlers("on_session_started")
	session_started_signal.emit()

@rpc("any_peer")
func register_peer(_steam_id: int) -> void:
	var godot_id = multiplayer.get_remote_sender_id()
	State.lobby_data.peer_members[godot_id] = _steam_id
	print("Godot ID: ", godot_id, " | Steam ID: ", _steam_id)
	peer_registered_signal.emit(godot_id, _steam_id)
	notify_handlers("on_peer_registered", godot_id, _steam_id)
