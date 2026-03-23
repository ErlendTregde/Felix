extends Node
class_name FelixRoundController

var table
var round_state: RoundState = RoundState.new()

func init(game_table) -> void:
	table = game_table
	GameManager.bind_round_controller(self)
	sync_runtime_state()

func configure_seats(players: Array[Player], seat_contexts: Array[SeatContext], new_local_seat_index: int) -> void:
	round_state.set_seat_contexts(seat_contexts, new_local_seat_index)
	GameManager.players = players
	GameManager.player_count = seat_contexts.size()
	GameManager.set_seat_contexts(seat_contexts, new_local_seat_index)
	sync_runtime_state()

func get_local_seat_index() -> int:
	return round_state.local_seat_index

func get_seat_context(seat_id: int) -> SeatContext:
	return round_state.get_seat_context(seat_id)

func is_local_seat(seat_id: int) -> bool:
	return round_state.is_local_seat(seat_id)

func is_bot_seat(seat_id: int) -> bool:
	var context := get_seat_context(seat_id)
	return context != null and context.is_bot()

func is_remote_human_seat(seat_id: int) -> bool:
	var context := get_seat_context(seat_id)
	return context != null and context.is_remote_human()

func can_local_seat_act(seat_id: int) -> bool:
	return is_local_seat(seat_id) and _is_actor_turn(seat_id)

func begin_initial_viewing_phase() -> void:
	GameManager.current_round += 1
	GameManager.change_state(GameManager.GameState.INITIAL_VIEWING)
	GameManager.reset_all_ready_states()
	sync_runtime_state()

func request_ready_state(seat_id: int) -> void:
	if GameManager.current_state != GameManager.GameState.INITIAL_VIEWING:
		return
	GameManager.set_player_ready(seat_id, true)
	sync_runtime_state()

func begin_playing_phase() -> void:
	GameManager.change_state(GameManager.GameState.PLAYING)
	sync_runtime_state()

func prepare_new_round_metadata() -> void:
	GameManager.knocker_id = -1
	GameManager.current_player_index = 0
	GameManager.change_state(GameManager.GameState.SETUP)
	GameManager.reset_all_ready_states()
	for context in round_state.seat_contexts:
		context.has_knocked = false
	round_state.match_claimed = false
	round_state.pending_give_card_actor_seat_index = -1
	round_state.pending_give_card_target_seat_index = -1
	sync_runtime_state()

func request_draw(actor_seat_id: int) -> bool:
	if not _can_actor_draw(actor_seat_id):
		return false
	await table.turn_manager.handle_draw_card()
	sync_runtime_state()
	return table.drawn_card != null

func request_swap(actor_seat_id: int, target_card: Card3D) -> void:
	if not _can_actor_take_turn_action(actor_seat_id):
		return
	if not table.drawn_card:
		print("Draw a card first! Press D")
		return
	if not _card_belongs_to_seat(target_card, actor_seat_id):
		print("That is not your card!")
		return
	await table.turn_manager.swap_cards(target_card, table.drawn_card)
	sync_runtime_state()

func request_discard_drawn(actor_seat_id: int) -> void:
	if not _can_actor_take_turn_action(actor_seat_id):
		return
	if not table.drawn_card:
		print("Draw a card first! Press D")
		return
	await table.turn_manager.play_card_to_discard(table.drawn_card)
	sync_runtime_state()

func request_ability_select(actor_seat_id: int, card: Card3D) -> void:
	if not _can_actor_take_turn_action(actor_seat_id):
		return
	await table.ability_manager.handle_ability_target_selection(card)
	sync_runtime_state()

func request_ability_confirm(actor_seat_id: int) -> void:
	if not _can_actor_take_turn_action(actor_seat_id):
		return
	await table.ability_manager.confirm_ability_viewing()
	sync_runtime_state()

func request_card_click(actor_seat_id: int, card: Card3D) -> void:
	if table.is_choosing_give_card:
		await request_give_card(actor_seat_id, card)
		return
	if table.is_executing_ability:
		await request_ability_select(actor_seat_id, card)
		return
	await request_swap(actor_seat_id, card)

func request_match(actor_seat_id: int, card: Card3D) -> void:
	if actor_seat_id < 0:
		return
	await table.match_manager.on_card_right_clicked(actor_seat_id, card)
	sync_runtime_state()

func request_give_card(actor_seat_id: int, card: Card3D) -> void:
	if table.give_card_actor_seat_idx != actor_seat_id:
		return
	await table.match_manager.handle_give_card_selection(actor_seat_id, card)
	sync_runtime_state()

func request_knock(actor_seat_id: int) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if not _is_actor_turn(actor_seat_id):
		return
	await table.knock_manager.perform_knock(actor_seat_id)
	sync_runtime_state()

func complete_turn() -> void:
	GameManager.next_turn()
	sync_runtime_state()

func get_public_snapshot() -> Dictionary:
	sync_runtime_state()
	return round_state.get_public_snapshot()

func get_private_snapshot_for(seat_id: int) -> Dictionary:
	sync_runtime_state()
	return round_state.get_private_snapshot_for(seat_id)

func sync_scores_from_players(players: Array[Player]) -> void:
	for context in round_state.seat_contexts:
		if context.seat_index >= 0 and context.seat_index < players.size():
			var player := players[context.seat_index]
			context.current_score = player.current_score
			context.total_score = player.total_score
	sync_runtime_state()

func sync_runtime_state() -> void:
	round_state.set_phase(GameManager.GameState.keys()[GameManager.current_state])
	round_state.round_number = GameManager.current_round
	round_state.current_turn_seat_index = GameManager.current_player_index
	round_state.knocker_seat_index = GameManager.knocker_id
	round_state.final_round_remaining = GameManager.get_final_round_remaining()
	round_state.match_claimed = table.match_claimed if table else false
	round_state.pending_give_card_actor_seat_index = table.give_card_actor_seat_idx if table else -1
	round_state.pending_give_card_target_seat_index = table.give_card_target_player_idx if table else -1
	if table and table.deck_manager:
		round_state.draw_pile_count = table.deck_manager.get_draw_pile_count()
		round_state.discard_pile_count = table.deck_manager.get_discard_pile_count()
		var top_discard = table.deck_manager.peek_top_discard()
		round_state.top_discard_name = top_discard.get_short_name() if top_discard else ""
	_rebuild_card_refs()
	GameManager.set_round_state(round_state)

func _rebuild_card_refs() -> void:
	if not table:
		return
	round_state.seat_card_refs.clear()
	for seat_id in range(table.player_grids.size()):
		var grid = table.player_grids[seat_id]
		var refs: Array[CardRef] = []
		for slot_index in range(4):
			var card = grid.get_card_at(slot_index)
			if card:
				refs.append(CardRef.new().configure(card, seat_id, slot_index, false))
		for slot_index in range(grid.penalty_cards.size()):
			var penalty_card = grid.penalty_cards[slot_index]
			if penalty_card:
				refs.append(CardRef.new().configure(penalty_card, seat_id, slot_index, true))
		round_state.set_card_refs_for_seat(seat_id, refs)

func _is_actor_turn(actor_seat_id: int) -> bool:
	return actor_seat_id == GameManager.current_player_index

func _can_actor_take_turn_action(actor_seat_id: int) -> bool:
	if actor_seat_id < 0:
		return false
	if is_remote_human_seat(actor_seat_id):
		return false
	if GameManager.current_state != GameManager.GameState.PLAYING and GameManager.current_state != GameManager.GameState.KNOCKED:
		return false
	return _is_actor_turn(actor_seat_id)

func _can_actor_draw(actor_seat_id: int) -> bool:
	if not _can_actor_take_turn_action(actor_seat_id):
		return false
	if table.drawn_card or table.is_drawing:
		print("Already drew a card!")
		return false
	return true

func _card_belongs_to_seat(card: Card3D, seat_id: int) -> bool:
	return table._find_card_owner_idx(card) == seat_id
