class_name Deck
extends RefCounted
## Mazo de robo. El final del arreglo es la parte superior del mazo.

const JOKERS_PER_DECK := 2

var _cards: Array[Card] = []


static func build(deck_count: int, with_jokers: bool) -> Deck:
	var deck := Deck.new()
	var next_id := 0
	for _d in deck_count:
		for suit in [Card.Suit.HEARTS, Card.Suit.DIAMONDS, Card.Suit.CLUBS, Card.Suit.SPADES]:
			for rank in range(Card.Rank.ACE, Card.Rank.KING + 1):
				deck._cards.append(Card.new(next_id, rank, suit))
				next_id += 1
		if with_jokers:
			for _j in JOKERS_PER_DECK:
				deck._cards.append(Card.new(next_id, Card.Rank.JOKER, Card.Suit.NONE))
				next_id += 1
	return deck


## Mazo con un orden dado (el último elemento es la parte superior).
## Lo usan la recuperación de partidas y las pruebas.
static func from_cards(cards: Array[Card]) -> Deck:
	var deck := Deck.new()
	deck._cards = cards.duplicate()
	return deck


## Fisher-Yates con el RNG recibido, para que una semilla reproduzca la partida.
func shuffle(rng: RandomNumberGenerator) -> void:
	for i in range(_cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := _cards[i]
		_cards[i] = _cards[j]
		_cards[j] = tmp


## Devuelve null si el mazo está vacío.
func draw() -> Card:
	if _cards.is_empty():
		return null
	return _cards.pop_back()


func deal(amount: int) -> Array[Card]:
	var out: Array[Card] = []
	for _i in mini(amount, _cards.size()):
		out.append(_cards.pop_back())
	return out


## Recupera todas las cartas del pozo salvo el tope y las baraja.
func refill_from(pile: DiscardPile, rng: RandomNumberGenerator) -> void:
	_cards.append_array(pile.take_all_but_top())
	shuffle(rng)


func size() -> int:
	return _cards.size()


func is_empty() -> bool:
	return _cards.is_empty()


## Copia del contenido, de la base a la parte superior (para persistencia).
func cards() -> Array[Card]:
	return _cards.duplicate()
