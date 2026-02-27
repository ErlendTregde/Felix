extends Node
class_name ScoringManager
## Calculates scores at round end and tracks multi-round totals

var table  # Reference to game_table

func init(game_table) -> void:
	table = game_table

# ======================================
# SCORE CALCULATION
# ======================================

func calculate_all_scores() -> Dictionary:
	"""Calculate scores for every player. Returns { player_id: score }.
	Scoring rules:
	  - Number cards (A–10) = face value (Ace = 1)
	  - Jack = 11, Queen = 12
	  - Black King (♣/♠) = −1
	  - Red King (♥/♦) = +25
	  - Joker = 1
	All cards in main grid AND penalty cards count."""
	var scores: Dictionary = {}
	
	for i in range(table.player_grids.size()):
		var grid = table.player_grids[i]
		var total: int = 0
		
		# Main grid (4 slots)
		for j in range(4):
			var card = grid.get_card_at(j)
			if card and card.card_data:
				total += card.card_data.get_score()
		
		# Penalty cards
		for card in grid.penalty_cards:
			if card and card.card_data:
				total += card.card_data.get_score()
		
		scores[i] = total
		print("Player %d score: %d" % [i + 1, total])
	
	return scores

func determine_winner(scores: Dictionary) -> int:
	"""Return player index with the LOWEST score. Ties go to first player in order."""
	var best_id: int = 0
	var best_score: int = 99999
	
	for player_id in scores:
		if scores[player_id] < best_score:
			best_score = scores[player_id]
			best_id = player_id
	
	return best_id

func apply_round_scores(scores: Dictionary) -> void:
	"""Add round scores to each player's total_score for multi-round tracking."""
	for player_id in scores:
		if player_id < table.players.size():
			var player = table.players[player_id]
			player.current_score = scores[player_id]
			player.total_score += scores[player_id]
			Events.score_updated.emit(player_id, player.total_score)

func get_score_summary() -> Array[Dictionary]:
	"""Return an array of { id, name, round_score, total_score } sorted by round score."""
	var summary: Array[Dictionary] = []
	for i in range(table.players.size()):
		summary.append({
			"id": i,
			"name": table.players[i].player_name,
			"round_score": table.players[i].current_score,
			"total_score": table.players[i].total_score,
			"knocked": table.players[i].has_knocked
		})
	summary.sort_custom(func(a, b): return a["round_score"] < b["round_score"])
	return summary

# ======================================
# FULL ROUND-END FLOW
# ======================================

func execute_round_end() -> void:
	"""Run the full round-end sequence: reveal → score → emit results."""
	# 1. Reveal all cards
	await table.knock_manager.reveal_all_cards()
	
	# 2. Brief pause for players to see the cards
	await get_tree().create_timer(1.5).timeout
	
	# 3. Calculate and apply scores
	var scores = calculate_all_scores()
	var winner_id = determine_winner(scores)
	apply_round_scores(scores)
	
	print("\n=== ROUND WINNER: %s (score %d) ===" % [
		table.players[winner_id].player_name, scores[winner_id]])
	
	# 4. Emit results
	Events.round_scores_calculated.emit(scores, winner_id)
	Events.round_ended.emit(winner_id, scores)
