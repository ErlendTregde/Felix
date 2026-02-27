extends Node
class_name DeckManager
## Manages the deck of cards: creation, shuffling, dealing
## Handles both draw pile and discard pile

signal pile_reshuffled(card_count: int)

var card_data_deck: Array[CardData] = []
var draw_pile: Array[CardData] = []
var discard_pile: Array[CardData] = []
var is_test_mode: bool = false  # Toggle for ability testing

func _ready() -> void:
	print("DeckManager initialized")

func create_standard_deck() -> void:
	"""Create a standard 54-card deck (52 cards + 2 jokers)"""
	card_data_deck.clear()
	
	# Create 52 standard cards
	for suit in [CardData.Suit.HEARTS, CardData.Suit.DIAMONDS, CardData.Suit.CLUBS, CardData.Suit.SPADES]:
		for rank in range(CardData.Rank.ACE, CardData.Rank.KING + 1):
			var card = CardData.new()
			card.suit = suit
			card.rank = rank
			
			# Mark red kings
			if rank == CardData.Rank.KING and (suit == CardData.Suit.HEARTS or suit == CardData.Suit.DIAMONDS):
				card.is_red_king = true
			
			card_data_deck.append(card)
	
	# Add 2 jokers
	for i in range(2):
		var joker = CardData.new()
		joker.suit = CardData.Suit.JOKER
		joker.rank = CardData.Rank.JOKER
		card_data_deck.append(joker)
	
	print("Created deck with %d cards" % card_data_deck.size())

func create_test_deck_7_8() -> void:
	"""Create test deck with 7s, 8s, 9s, 10s, Jacks, and Queens for ability testing"""
	card_data_deck.clear()
	
	# Create 3 of each rank for variety (7, 8, 9, 10, Jack, Queen) = 18 cards
	var ability_ranks = [CardData.Rank.SEVEN, CardData.Rank.EIGHT, CardData.Rank.NINE, CardData.Rank.TEN, CardData.Rank.JACK, CardData.Rank.QUEEN]
	
	for rank in ability_ranks:
		# 3 cards per rank
		for i in range(3):
			var card = CardData.new()
			card.rank = rank
			# Cycle through suits
			match i:
				0: card.suit = CardData.Suit.HEARTS
				1: card.suit = CardData.Suit.DIAMONDS
				2: card.suit = CardData.Suit.CLUBS
			card_data_deck.append(card)
	
	print("Created TEST deck with %d cards (7s, 8s, 9s, 10s, Jacks, Queens)" % card_data_deck.size())

func create_test_deck_matching() -> void:
	"""Create a 52-card deck of only 7s and 8s (26 each) for match testing"""
	card_data_deck.clear()
	
	var suits = [CardData.Suit.HEARTS, CardData.Suit.DIAMONDS, CardData.Suit.CLUBS, CardData.Suit.SPADES]
	for i in range(26):
		var card = CardData.new()
		card.rank = CardData.Rank.SEVEN
		card.suit = suits[i % 4]
		card_data_deck.append(card)
	for i in range(26):
		var card = CardData.new()
		card.rank = CardData.Rank.EIGHT
		card.suit = suits[i % 4]
		card_data_deck.append(card)
	
	print("Created MATCH TEST deck with %d cards (26×7, 26×8)" % card_data_deck.size())

var is_match_test_mode: bool = false  # Toggle for match testing (7s and 8s only)

func toggle_match_test_mode() -> void:
	"""Toggle between standard deck and match test deck (7s and 8s only)"""
	# Turn off the other test mode if it's on
	if is_test_mode:
		is_test_mode = false
	is_match_test_mode = not is_match_test_mode
	
	if is_match_test_mode:
		create_test_deck_matching()
	else:
		create_standard_deck()
	
	shuffle()
	print("Match test mode: %s" % ("ENABLED (7s and 8s only)" if is_match_test_mode else "DISABLED (standard deck)"))

func toggle_test_mode() -> void:
	"""Toggle between standard deck and test deck"""
	# Turn off the other test mode if it's on
	if is_match_test_mode:
		is_match_test_mode = false
	is_test_mode = not is_test_mode
	
	if is_test_mode:
		create_test_deck_7_8()
	else:
		create_standard_deck()
	
	shuffle()
	print("Test mode: %s" % ("ENABLED (7s/8s/9s/10s/Jacks/Queens)" if is_test_mode else "DISABLED (standard deck)"))

func shuffle() -> void:
	"""Shuffle the deck using Fisher-Yates algorithm"""
	draw_pile = card_data_deck.duplicate()
	
	var n = draw_pile.size()
	for i in range(n - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = draw_pile[i]
		draw_pile[i] = draw_pile[j]
		draw_pile[j] = temp
	
	print("Deck shuffled - %d cards in draw pile" % draw_pile.size())

func deal_card() -> CardData:
	"""Draw and return the top card from the draw pile.
	Reshuffle must be handled BEFORE calling this: check can_reshuffle() and call perform_reshuffle()."""
	if draw_pile.is_empty():
		print("Warning: Draw pile is empty! Call perform_reshuffle() first.")
		return null
	
	var card = draw_pile.pop_front()
	return card

func can_reshuffle() -> bool:
	"""Returns true when draw pile is empty and at least 1 discard card exists to transfer."""
	return draw_pile.is_empty() and not discard_pile.is_empty()

func perform_reshuffle() -> int:
	"""Transfer discard cards to the draw pile in FIFO order (oldest drawn first).
	The most-recently-played card (top of discard) always stays, UNLESS it is the
	only card on the discard pile - in that case it is moved to draw so the game
	can continue. Returns the number of cards transferred."""
	if discard_pile.is_empty():
		return 0
	
	if discard_pile.size() == 1:
		# Edge case: only 1 card remains - move it to draw so the turn can proceed.
		# Discard becomes temporarily empty; the next discard will repopulate it.
		draw_pile = discard_pile.duplicate()
		discard_pile.clear()
		print("Reshuffle: last discard card '%s' moved to draw (discard now empty)." % draw_pile[0].get_short_name())
		return 1
	
	# Keep the top card (index -1 = most recently discarded)
	var top_card = discard_pile[-1]
	
	# Move all other cards to draw pile; oldest (index 0) will be drawn first (FIFO)
	draw_pile = discard_pile.slice(0, discard_pile.size() - 1)
	discard_pile = [top_card]
	
	var count = draw_pile.size()
	print("Reshuffle: %d cards moved to draw pile. '%s' stays on discard." % [count, top_card.get_short_name()])
	pile_reshuffled.emit(count)
	return count

func add_to_discard(card_data: CardData) -> void:
	"""Add a card to the discard pile"""
	if card_data:
		discard_pile.append(card_data)
		Events.card_discarded.emit(card_data)

func peek_top_discard() -> CardData:
	"""Look at the top card of discard pile without removing it"""
	if discard_pile.is_empty():
		return null
	return discard_pile[-1]

func reset_deck() -> void:
	"""Reset for a new round"""
	draw_pile.clear()
	discard_pile.clear()
	create_standard_deck()
	shuffle()

func get_draw_pile_count() -> int:
	return draw_pile.size()

func get_discard_pile_count() -> int:
	return discard_pile.size()
