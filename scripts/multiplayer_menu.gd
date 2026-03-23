extends Control

@onready var status_label: Label = $CenterPanel/VBoxContainer/StatusLabel
@onready var host_button: Button = $CenterPanel/VBoxContainer/HostButton
@onready var back_button: Button = $CenterPanel/VBoxContainer/BackButton
@onready var join_code_edit: LineEdit = $CenterPanel/VBoxContainer/JoinRow/JoinCodeEdit
@onready var join_button: Button = $CenterPanel/VBoxContainer/JoinRow/JoinButton

func _ready() -> void:
	status_label.text = AppFlow.consume_status_message()
	_show_steam_status()
	host_button.pressed.connect(_on_host_pressed)
	back_button.pressed.connect(_on_back_pressed)
	join_button.pressed.connect(_on_join_pressed)
	join_code_edit.text_submitted.connect(_on_join_code_submitted)
	SteamPlatformService.join_request_pending.connect(_on_join_request_pending)
	if State.pending_join_request.lobby_id > 0:
		_handle_pending_invite()

func _show_steam_status() -> void:
	if SteamPlatformService.is_steam_available():
		status_label.text = "Signed in as: %s" % SteamPlatformService.get_local_display_name()
	else:
		status_label.text = SteamPlatformService.get_unavailable_reason()
		host_button.disabled = true

func _on_host_pressed() -> void:
	SteamRoomService.prepare_host_entry()
	AppFlow.open_steam_room("Creating Steam room...")

func _on_back_pressed() -> void:
	AppFlow.open_launcher()

func _on_join_request_pending(_lobby_id: int, _friend_id: int, _source: String) -> void:
	_handle_pending_invite()

func _handle_pending_invite() -> void:
	SteamRoomService.prepare_join_entry()
	AppFlow.open_steam_room("Joining Steam room...")

func _on_join_pressed() -> void:
	_on_join_code_submitted(join_code_edit.text.strip_edges())

func _on_join_code_submitted(code: String) -> void:
	var lobby_id := code.to_int()
	if lobby_id <= 0:
		status_label.text = "Invalid Lobby ID."
		return
	SteamRoomService.prepare_join_entry()
	SteamPlatformService.join_lobby(lobby_id)
	AppFlow.open_steam_room("Joining lobby %d..." % lobby_id)
