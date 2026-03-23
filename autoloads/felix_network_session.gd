extends Node

signal session_started
signal player_joined(peer_id: int)
signal player_left(peer_id: int, steam_id: int)
signal host_disconnected
signal connection_failed
signal peer_registered(peer_id: int, steam_id: int)

func _ready() -> void:
	call_deferred("_connect_raw_signals")

func _connect_raw_signals() -> void:
	if p2p == null:
		return
	if not p2p.session_started_signal.is_connected(_on_session_started):
		p2p.session_started_signal.connect(_on_session_started)
		p2p.player_joined_signal.connect(_on_player_joined)
		p2p.player_left_signal.connect(_on_player_left)
		p2p.host_disconnected_signal.connect(_on_host_disconnected)
		p2p.connection_failed_signal.connect(_on_connection_failed)
		p2p.peer_registered_signal.connect(_on_peer_registered)

func is_session_active() -> bool:
	return multiplayer.multiplayer_peer != null

func is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()

func start_session_for_all() -> void:
	if SteamManager == null:
		return
	SteamManager.start_session_for_all()

func reset_session() -> void:
	if p2p == null:
		return
	p2p.reset_transport_state()

func _on_session_started() -> void:
	session_started.emit()

func _on_player_joined(peer_id: int) -> void:
	player_joined.emit(peer_id)

func _on_player_left(peer_id: int, steam_id: int) -> void:
	player_left.emit(peer_id, steam_id)

func _on_host_disconnected() -> void:
	host_disconnected.emit()

func _on_connection_failed() -> void:
	connection_failed.emit()

func _on_peer_registered(peer_id: int, steam_id: int) -> void:
	peer_registered.emit(peer_id, steam_id)
