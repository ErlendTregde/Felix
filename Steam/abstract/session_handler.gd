@abstract class_name SessionHandler extends Node 


## these are host only:
@abstract func on_game_start(peers: Array) -> void
# this gets called whenever the game starts (the host only)

@abstract func on_player_join(peer: int) -> void
# this gets called whenever a player spawns in the world

@abstract func on_player_leave(peer: int) -> void
# this gets called whenever a player despawns or leaves the game


