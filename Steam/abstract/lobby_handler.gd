@abstract class_name LobbyHandler extends Control


@abstract func on_chat_message(sender: String, message: String) -> void
# this gets called after someone sends a message with SteamManager.send_chat_message
# and it gets through to the lobby_message callback from Steam


@abstract func on_system_message(message: String) -> void
# this get called whenever someone joins or leaves or gets kicked or banned
# and the lobby_chat_update is called from Steam 
# (repopulating the player list is recommended)


@abstract func on_lobby_created(lobby_id: int, lobby_name: String) -> void
# this gets called whenever the lobby is created successfully (the host only)
# happens after lobby_created is called from Steam 


@abstract func on_lobby_joined(lobby_id: int, lobby_name: String) -> void
# this gets called whenever a lobby is joined successfully (the client only)
# happens once on the client machien whenever they join a lobby
# gets called when lobby_joined is called from Steam


@abstract func on_lobbies_found(lobbies: Array) -> void
# this gets called after SteamManager.search_available_lobbies is called
# and the lobby_match_list is called from Steam
