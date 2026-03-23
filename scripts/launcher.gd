extends Control

@onready var status_label: Label = $CenterPanel/StatusLabel
@onready var play_vs_ai_button: Button = $CenterPanel/PlayVsAIButton
@onready var steam_multiplayer_button: Button = $CenterPanel/SteamMultiplayerButton

func _ready() -> void:
	play_vs_ai_button.pressed.connect(_on_play_vs_ai_pressed)
	steam_multiplayer_button.pressed.connect(_on_steam_multiplayer_pressed)
	status_label.text = AppFlow.consume_status_message()

func _on_play_vs_ai_pressed() -> void:
	AppFlow.start_local_game()

func _on_steam_multiplayer_pressed() -> void:
	if not SteamPlatformService.is_steam_available():
		status_label.text = SteamPlatformService.get_unavailable_reason()
		return
	SteamRoomService.prepare_host_entry()
	AppFlow.open_steam_room("Creating Steam room...")
