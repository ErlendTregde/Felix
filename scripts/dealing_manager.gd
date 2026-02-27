extends Node
class_name DealingManager
## Handles dealing cards to players with animation

var table  # Reference to game_table

func init(game_table) -> void:
	table = game_table

func deal_cards_to_all_players() -> void:
	"""Deal 4 cards to each player with animation"""
	if table.is_dealing:
		return
	
	table.is_dealing = true
	print("\n=== Dealing Cards to %d Player(s) ===" % table.num_players)
	
	# Deal 4 cards per player
	for card_index in range(4):
		for player_index in range(table.num_players):
			await deal_single_card(player_index, card_index)
			
			# Update draw pile visual
			if table.draw_pile_visual:
				table.draw_pile_visual.set_count(table.deck_manager.get_draw_pile_count())
			
			await get_tree().create_timer(0.15).timeout  # Stagger between cards
	
	table.is_dealing = false
	print("\nDealing complete! All players have 4 cards.")
	Events.game_state_changed.emit("DEALING_COMPLETE")
	
	# Start viewing phase
	table.viewing_manager.start_initial_viewing_phase()

func deal_single_card(player_index: int, position_index: int) -> void:
	"""Deal one card to a specific player position"""
	if player_index >= table.player_grids.size():
		return
	
	var card_data = table.deck_manager.deal_card()
	if not card_data:
		print("Warning: Deck is empty!")
		return
	
	# Create card at draw pile position
	var card = table.card_scene.instantiate()
	table.add_child(card)
	card.global_position = table.draw_pile_marker.global_position
	card.initialize(card_data, false)
	
	# Connect signals
	card.card_clicked.connect(table._on_card_clicked)
	card.card_right_clicked.connect(table._on_card_right_clicked)
	
	# Add to player's grid (will animate there)
	var grid = table.player_grids[player_index]
	await reparent_card_to_grid(card, grid, position_index)
	
	# Update player data
	table.players[player_index].add_card(card)
	
	# Update draw pile visual
	if table.draw_pile_visual:
		table.draw_pile_visual.set_count(table.deck_manager.get_draw_pile_count())
	
	Events.card_dealt.emit(card_data, player_index, position_index)


func reparent_card_to_grid(card: Card3D, grid: PlayerGrid, card_position: int) -> void:
	"""Move card from table to player grid with animation"""
	var target_pos = grid.get_position_for_card(card_position)
	
	# Animate to position
	card.move_to(target_pos, 0.4, false)
	
	# Wait for animation, then reparent
	await get_tree().create_timer(0.4).timeout
	
	# Reparent to grid
	if card.get_parent():
		card.get_parent().remove_child(card)
	
	# Add to grid's cards array and as child
	grid.cards[card_position] = card
	grid.add_child(card)
	card.position = grid.card_positions[card_position]
	card.base_position = card.global_position
