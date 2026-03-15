extends Node

const APP_ID: int = 480
const PRIVATE_LOBBY = 0
const FRIENDS_ONLY_LOBBY = 1
const PUBLIC_LOBBY = 2
const INVISIBLE_LOBBY = 3
const MAX_LOBBY_PLAYERS := 4

const CLOSE_DISTANCE = 0
const DEFAULT_DISTANCE = 1
const FAR_DISTANCE = 2
const WORLDWIDE_DISTANCE = 3

var _handlers: Array[LobbyHandler] = []

func _ready() -> void:
	initialize_steam()
	
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_message.connect(_on_lobby_send_msg)
	Steam.join_requested.connect(_on_lobby_join_requested)
	
	check_command_line()

func initialize_steam() -> void:
	var init: Dictionary = Steam.steamInitEx(APP_ID, true)
	if init["status"] > Steam.STEAM_API_INIT_RESULT_OK:
		print("Failed to initialize steam: ", init)
		return
	
	var steam_id = Steam.getSteamID()
	var steam_username = Steam.getPersonaName()
	var owned: bool = Steam.isSubscribed()
	
	State.user_data.steam_id = steam_id
	State.user_data.steam_username = steam_username
	
	if not owned:
		print("the user does not own this game")
		return
	
	State.steam_initialized = true

func register_handler(_handler) -> void:
	if _handler is LobbyHandler and not _handlers.has(_handler):
		_handlers.append(_handler)
	
	if _handler is SessionHandler:
		p2p.register_handler(_handler)

func unregister_handler(_handler) -> void:
	if _handler is LobbyHandler and _handlers.has(_handler):
		_handlers.erase(_handler)
	
	if _handler is SessionHandler:
		p2p.unregister_handler(_handler)

func notify_handlers(_method: StringName, ...args: Array) -> void:
	for handler in _handlers:
		if is_instance_valid(handler) and handler.has_method(_method):
			handler.callv(_method, args)

func create_lobby(_lobby_name: String = "", _max_players: int = MAX_LOBBY_PLAYERS) -> void:
	if State.lobby_data.id != 0:
		return
	
	if _lobby_name == "":
		_lobby_name = State.user_data.steam_username + "'s lobby:"
	
	var max_players := clampi(_max_players, 1, MAX_LOBBY_PLAYERS)
	State.lobby_data.name = _lobby_name
	State.lobby_data.lobby_size = max_players
	Steam.createLobby(FRIENDS_ONLY_LOBBY, max_players)

func join_lobby(_lobby_id: int) -> void:
	State.single_player = false
	State.lobby_data.id = _lobby_id
	State.lobby_data.started = false
	State.lobby_data.peer_members.clear()
	Steam.joinLobby(_lobby_id)

func leave_lobby(_lobby_id: int) -> void:
	if State.lobby_data.id == 0:
		return
	
	Steam.leaveLobby(_lobby_id)
	
	for member in State.lobby_data.members:
		Steam.closeP2PSessionWithUser(member)
	
	p2p.reset_transport_state()
	State.reset_lobby_state()
	State.clear_pending_join_request()
	print("left")
	notify_handlers("on_lobby_left", _lobby_id)

func leave_current_lobby() -> void:
	leave_lobby(State.lobby_data.id)

func search_available_lobbies() -> void:
	Steam.addRequestLobbyListDistanceFilter(CLOSE_DISTANCE)
	Steam.requestLobbyList()

func send_chat_message(_message: String) -> void:
	var lobby_id = State.lobby_data.id
	var username = State.user_data.steam_username
	Steam.sendLobbyChatMsg(lobby_id, _message)
	notify_handlers("on_chat_message", username, _message)

func get_lobby_members(_lobby_id: int = -1) -> Dictionary:
	if _lobby_id == -1:
		_lobby_id = State.lobby_data.id
	elif _lobby_id == 0:
		return {}
	
	var members_nr = Steam.getNumLobbyMembers(_lobby_id)
	var players := {}
	
	for member in range(0, members_nr):
		var member_steam_id: int = Steam.getLobbyMemberByIndex(_lobby_id, member)
		var member_steam_name: String = Steam.getFriendPersonaName(member_steam_id)
		players[member_steam_id] = {
			"steam_id": member_steam_id,
			"steam_username": member_steam_name
		}
	
	State.lobby_data.members.clear()
	State.lobby_data.members = players
	return players

func start_session_for_all() -> void:
	if State.lobby_data.id == 0:
		return
	
	State.current_state = State.GameState.IN_GAME
	State.lobby_data.started = true
	Steam.setLobbyData(State.lobby_data.id, "started", "1")
	p2p.start_session()

func load_scene_for_all(_scene: Resource = null) -> void:
	start_session_for_all()

func _on_lobby_created(_connect: int, _lobby_id: int) -> void:
	if _connect != 1:
		return
	
	State.lobby_data.id = _lobby_id
	State.lobby_data.owner_id = State.user_data.steam_id
	State.lobby_data.started = false
	Steam.setLobbyData(_lobby_id, "name", State.lobby_data.name)
	Steam.setLobbyData(_lobby_id, "started", "0")
	p2p.create_socket()
	get_lobby_members(_lobby_id)
	notify_handlers("on_lobby_created", _lobby_id, State.lobby_data.name)

func _on_lobby_joined(_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		State.current_state = State.GameState.LOBBY
		State.reset_lobby_state()
		State.clear_pending_join_request()
		notify_handlers("on_lobby_join_failed", _lobby_id, response)
		return
	
	var started_raw = Steam.getLobbyData(_lobby_id, "started")
	var lobby_name = Steam.getLobbyData(_lobby_id, "name")
	var owner_id = Steam.getLobbyOwner(_lobby_id)
	
	State.lobby_data.name = lobby_name
	State.lobby_data.owner_id = owner_id
	State.lobby_data.started = (started_raw == "1")
	get_lobby_members(_lobby_id)
	State.clear_pending_join_request()
	
	if State.lobby_data.started:
		State.current_state = State.GameState.IN_GAME
	
	if State.user_data.steam_id != owner_id:
		p2p.connect_socket(owner_id)
	
	notify_handlers("on_lobby_joined", _lobby_id, lobby_name)

func _on_lobby_chat_update(_lobby_id: int, _change_id: int, _making_change_id: int, _chat_state: int) -> void:
	var changer_name: String = Steam.getFriendPersonaName(_change_id)
	var message := ""
	
	match _chat_state:
		Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
			message = "%s has joined the lobby." % changer_name
		Steam.CHAT_MEMBER_STATE_CHANGE_LEFT:
			message = "%s has left the lobby." % changer_name
		Steam.CHAT_MEMBER_STATE_CHANGE_KICKED:
			message = "%s has been kicked from the lobby." % changer_name
		Steam.CHAT_MEMBER_STATE_CHANGE_BANNED:
			message = "%s has been banned from the lobby." % changer_name
		_:
			message = "%s did... something." % changer_name
	
	notify_handlers("on_system_message", message)

func _on_lobby_data_update(_success: bool, _lobby_id: int, _member_id: int) -> void:
	if not _success or _lobby_id != State.lobby_data.id:
		return
	
	State.lobby_data.started = (Steam.getLobbyData(_lobby_id, "started") == "1")
	get_lobby_members(_lobby_id)
	notify_handlers("on_lobby_data_updated", _lobby_id, _member_id)

func _on_lobby_match_list(_lobbies: Array) -> void:
	notify_handlers("on_lobbies_found", _lobbies)

func _on_lobby_send_msg(_result: int, _user: int, _message: String, _type: int) -> void:
	if _user == State.user_data.steam_id:
		return
	
	var sender = Steam.getFriendPersonaName(_user)
	notify_handlers("on_chat_message", sender, _message)

func _on_lobby_join_requested(_lobby_id: int, _friend_id: int) -> void:
	State.single_player = false
	State.set_pending_join_request(_lobby_id, "steam_invite", _friend_id)
	var steam_name = Steam.getFriendPersonaName(_friend_id)
	print("joining..." + steam_name)
	notify_handlers("on_join_request_pending", _lobby_id, _friend_id, "steam_invite")
	join_lobby(_lobby_id)

func check_command_line() -> void:
	var these_arguments: Array = OS.get_cmdline_args()
	if these_arguments.size() < 2:
		return
	
	if these_arguments[0] == "+connect_lobby":
		var lobby_id := int(these_arguments[1])
		if lobby_id <= 0:
			return
		
		print("Command line lobby ID: %s" % these_arguments[1])
		State.single_player = false
		State.set_pending_join_request(lobby_id, "command_line")
		notify_handlers("on_join_request_pending", lobby_id, 0, "command_line")
		join_lobby(lobby_id)
