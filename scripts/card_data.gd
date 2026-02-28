extends Resource
class_name CardData
## Defines a playing card's properties
## Used as data container for each card in the deck

enum Suit {
	HEARTS,
	DIAMONDS,
	CLUBS,
	SPADES,
	JOKER
}

enum Rank {
	JOKER = 0,
	ACE = 1,
	TWO = 2,
	THREE = 3,
	FOUR = 4,
	FIVE = 5,
	SIX = 6,
	SEVEN = 7,
	EIGHT = 8,
	NINE = 9,
	TEN = 10,
	JACK = 11,
	QUEEN = 12,
	KING = 13
}

enum AbilityType {
	NONE,
	LOOK_OWN,       # 7 or 8: Look at own card
	LOOK_OPPONENT,  # 9 or 10: Look at opponent's card
	BLIND_SWAP,     # Jack: Blind swap with opponent
	LOOK_AND_SWAP   # Queen: Look at own + opponent, optionally swap
}

@export var suit: Suit = Suit.HEARTS
@export var rank: Rank = Rank.ACE
@export var is_red_king: bool = false  # Special flag for red kings (+25 points)
var joker_index: int = 0  # 0 = black joker, 1 = red joker (visual only)

## Get the score value of this card
func get_score() -> int:
	match rank:
		Rank.JOKER:
			return 1  # Joker is 0 during play, 1 at scoring
		Rank.KING:
			if is_red_king:
				return 25  # Red King
			else:
				return -1  # Black King
		Rank.JACK:
			return 11
		Rank.QUEEN:
			return 12
		_:
			return rank  # Number cards = face value

## Get the special ability of this card
func get_ability() -> AbilityType:
	match rank:
		Rank.SEVEN, Rank.EIGHT:
			return AbilityType.LOOK_OWN
		Rank.NINE, Rank.TEN:
			return AbilityType.LOOK_OPPONENT
		Rank.JACK:
			return AbilityType.BLIND_SWAP
		Rank.QUEEN:
			return AbilityType.LOOK_AND_SWAP
		_:
			return AbilityType.NONE

## Get display name for the card
func get_card_name() -> String:
	if rank == Rank.JOKER:
		return "Joker"
	
	var rank_name: String
	match rank:
		Rank.ACE:
			rank_name = "Ace"
		Rank.JACK:
			rank_name = "Jack"
		Rank.QUEEN:
			rank_name = "Queen"
		Rank.KING:
			rank_name = "King"
		_:
			rank_name = str(rank)
	
	var suit_name: String = Suit.keys()[suit].capitalize()
	return "%s of %s" % [rank_name, suit_name]

## Get clean rank display name (e.g., "King", "8", "Joker")
func get_rank_display() -> String:
	match rank:
		Rank.JOKER:
			return "Joker"
		Rank.ACE:
			return "Ace"
		Rank.JACK:
			return "Jack"
		Rank.QUEEN:
			return "Queen"
		Rank.KING:
			return "King"
		_:
			return str(rank)

## Get short display name (e.g., "7♥", "K♠", "Q♦")
func get_short_name() -> String:
	if rank == Rank.JOKER:
		return "🃏"
	
	var rank_symbol: String
	match rank:
		Rank.ACE:
			rank_symbol = "A"
		Rank.JACK:
			rank_symbol = "J"
		Rank.QUEEN:
			rank_symbol = "Q"
		Rank.KING:
			rank_symbol = "K"
		_:
			rank_symbol = str(rank)
	
	var suit_symbol: String
	match suit:
		Suit.HEARTS:
			suit_symbol = "♥"
		Suit.DIAMONDS:
			suit_symbol = "♦"
		Suit.CLUBS:
			suit_symbol = "♣"
		Suit.SPADES:
			suit_symbol = "♠"
		_:
			suit_symbol = ""
	
	return "%s%s" % [rank_symbol, suit_symbol]
