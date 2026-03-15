extends Node
## Shared Steam session state for the borrowed multiplayer layer.
## Phase 0 keeps this data-only so Steam code stops owning Felix scenes.

var steam_initialized: bool = false
var single_player: bool = true

var user_data: Dictionary = {
	"steam_id" : 0,
	"steam_username": ""
}

var lobby_data: Dictionary = {
	"owner_id": 0,
	"id": 0,
	"members": {}, # key: steam_id -> {"steam_id": member_steam_id, "steam_username": member_steam_name}
	"peer_members": {}, # key: peer_id -> steam_id
	"name": "",
	"lobby_size": 4,
	"started": false
}

var pending_join_request: Dictionary = {
	"lobby_id": 0,
	"friend_id": 0,
	"source": ""
}

enum GameState { LOBBY, IN_GAME }
var current_state: GameState = GameState.LOBBY

func set_pending_join_request(lobby_id: int, source: String, friend_id: int = 0) -> void:
	pending_join_request.lobby_id = lobby_id
	pending_join_request.friend_id = friend_id
	pending_join_request.source = source

func clear_pending_join_request() -> void:
	pending_join_request.lobby_id = 0
	pending_join_request.friend_id = 0
	pending_join_request.source = ""

func reset_lobby_state() -> void:
	lobby_data.owner_id = 0
	lobby_data.id = 0
	lobby_data.members.clear()
	lobby_data.peer_members.clear()
	lobby_data.name = ""
	lobby_data.started = false
