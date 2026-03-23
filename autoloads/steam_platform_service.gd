extends Node

signal steam_status_changed(is_available: bool, reason: String)
signal lobby_created(lobby_id: int, lobby_name: String)
signal lobby_joined(lobby_id: int, lobby_name: String)
signal lobby_left(lobby_id: int)
signal lobby_join_failed(lobby_id: int, response: int)
signal lobby_members_updated(lobby_id: int, members: Dictionary)
signal lobby_data_updated(lobby_id: int, member_id: int)
signal join_request_pending(lobby_id: int, friend_id: int, source: String)
signal system_message(message: String)
signal chat_message(sender: String, message: String)
signal lobby_search_results(lobbies: Array)

func _ready() -> void:
	call_deferred("_connect_raw_signals")

func _connect_raw_signals() -> void:
	if SteamManager == null:
		return
	if not SteamManager.steam_availability_changed.is_connected(_on_steam_availability_changed):
		SteamManager.steam_availability_changed.connect(_on_steam_availability_changed)
		SteamManager.lobby_created_signal.connect(_on_lobby_created)
		SteamManager.lobby_joined_signal.connect(_on_lobby_joined)
		SteamManager.lobby_left_signal.connect(_on_lobby_left)
		SteamManager.lobby_join_failed_signal.connect(_on_lobby_join_failed)
		SteamManager.lobby_members_updated_signal.connect(_on_lobby_members_updated)
		SteamManager.lobby_data_updated_signal.connect(_on_lobby_data_updated)
		SteamManager.join_request_pending_signal.connect(_on_join_request_pending)
		SteamManager.system_message_signal.connect(_on_system_message)
		SteamManager.chat_message_signal.connect(_on_chat_message)
		SteamManager.lobby_search_results_signal.connect(_on_lobby_search_results)
	steam_status_changed.emit(is_steam_available(), get_unavailable_reason())
	if State.pending_join_request.lobby_id > 0:
		join_request_pending.emit(
			State.pending_join_request.lobby_id,
			State.pending_join_request.friend_id,
			String(State.pending_join_request.source)
		)

func is_steam_available() -> bool:
	return SteamManager != null and SteamManager.is_steam_available()

func get_unavailable_reason() -> String:
	if SteamManager == null:
		return "Steam manager not loaded."
	return SteamManager.last_init_error

func create_friends_lobby(max_players: int = 4) -> void:
	if not is_steam_available():
		steam_status_changed.emit(false, get_unavailable_reason())
		return
	SteamManager.create_lobby("", max_players)

func join_lobby(lobby_id: int) -> void:
	if not is_steam_available():
		steam_status_changed.emit(false, get_unavailable_reason())
		return
	SteamManager.join_lobby(lobby_id)

func leave_current_lobby() -> void:
	if SteamManager == null:
		return
	SteamManager.leave_current_lobby()

func get_local_steam_id() -> int:
	return int(State.user_data.steam_id)

func get_local_display_name() -> String:
	return String(State.user_data.steam_username)

func get_current_members() -> Dictionary:
	return State.lobby_data.members.duplicate(true)

func get_lobby_id() -> int:
	return int(State.lobby_data.id)

func get_lobby_name() -> String:
	return String(State.lobby_data.name)

func is_local_lobby_owner() -> bool:
	return int(State.user_data.steam_id) != 0 and int(State.user_data.steam_id) == int(State.lobby_data.owner_id)

func _on_steam_availability_changed(is_available: bool, reason: String) -> void:
	steam_status_changed.emit(is_available, reason)

func _on_lobby_created(lobby_id: int, lobby_name: String) -> void:
	lobby_created.emit(lobby_id, lobby_name)

func _on_lobby_joined(lobby_id: int, lobby_name: String) -> void:
	lobby_joined.emit(lobby_id, lobby_name)

func _on_lobby_left(lobby_id: int) -> void:
	lobby_left.emit(lobby_id)

func _on_lobby_join_failed(lobby_id: int, response: int) -> void:
	lobby_join_failed.emit(lobby_id, response)

func _on_lobby_members_updated(lobby_id: int, members: Dictionary) -> void:
	lobby_members_updated.emit(lobby_id, members)

func _on_lobby_data_updated(lobby_id: int, member_id: int) -> void:
	lobby_data_updated.emit(lobby_id, member_id)

func _on_join_request_pending(lobby_id: int, friend_id: int, source: String) -> void:
	join_request_pending.emit(lobby_id, friend_id, source)

func _on_system_message(message: String) -> void:
	system_message.emit(message)

func _on_chat_message(sender: String, message: String) -> void:
	chat_message.emit(sender, message)

func _on_lobby_search_results(lobbies: Array) -> void:
	lobby_search_results.emit(lobbies)
