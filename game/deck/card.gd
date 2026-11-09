class_name Card
extends RefCounted
## Carta (value object inmutable). `instance_id` es único dentro de la baraja doble,
## de modo que dos cartas con el mismo rango y palo siguen siendo distinguibles.
## No guarda puntos: el valor lo define CardValueTable (rules/evaluation).

enum Suit { NONE = -1, HEARTS, DIAMONDS, CLUBS, SPADES }
enum Rank { JOKER = 0, ACE = 1, TWO, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT, NINE, TEN, JACK, QUEEN, KING }

const _SUIT_SYMBOLS := {Suit.HEARTS: "♥", Suit.DIAMONDS: "♦", Suit.CLUBS: "♣", Suit.SPADES: "♠"}
const _RANK_LABELS := {Rank.ACE: "A", Rank.JACK: "J", Rank.QUEEN: "Q", Rank.KING: "K"}

var instance_id: int:
	get:
		return _instance_id
var rank: int:
	get:
		return _rank
var suit: int:
	get:
		return _suit

var _instance_id: int
var _rank: int
var _suit: int


func _init(p_instance_id: int, p_rank: int, p_suit: int) -> void:
	_instance_id = p_instance_id
	_rank = p_rank
	_suit = p_suit


func is_joker() -> bool:
	return _rank == Rank.JOKER


func same_rank_as(other: Card) -> bool:
	return _rank == other.rank


func same_suit_as(other: Card) -> bool:
	return _suit == other.suit


## Verdadero si esta carta va justo después de `other` en una escalera del mismo palo.
func follows(other: Card) -> bool:
	return same_suit_as(other) and _rank == other.rank + 1


## Forma de datos planos [instance_id, rank, suit] (snapshot de la partida).
func to_data() -> Array:
	return [_instance_id, _rank, _suit]


static func from_data(data: Array) -> Card:
	return Card.new(int(data[0]), int(data[1]), int(data[2]))


static func list_to_data(cards: Array[Card]) -> Array:
	return cards.map(func(c: Card) -> Array: return c.to_data())


static func list_from_data(data: Array) -> Array[Card]:
	var out: Array[Card] = []
	for item: Array in data:
		out.append(Card.from_data(item))
	return out


func _to_string() -> String:
	if is_joker():
		return "JOKER"
	return str(_RANK_LABELS.get(_rank, _rank)) + _SUIT_SYMBOLS.get(_suit, "?")
