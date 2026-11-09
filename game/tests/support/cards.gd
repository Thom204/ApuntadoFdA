extends RefCounted
## Fábrica de cartas para pruebas con notación corta: "7H 10D QS AC JK".
## Palos: H corazones, D diamantes, C tréboles, S picas. JK = comodín.

const _RANKS := {"A": 1, "J": 11, "Q": 12, "K": 13}
const _SUITS := {"H": Card.Suit.HEARTS, "D": Card.Suit.DIAMONDS, "C": Card.Suit.CLUBS, "S": Card.Suit.SPADES}

static var _next_id := 1000


static func parse(text: String) -> Array[Card]:
	var out: Array[Card] = []
	for token in text.split(" ", false):
		out.append(one(token))
	return out


static func one(token: String) -> Card:
	_next_id += 1
	if token == "JK":
		return Card.new(_next_id, Card.Rank.JOKER, Card.Suit.NONE)
	var rank_text := token.substr(0, token.length() - 1)
	var rank: int = _RANKS.get(rank_text, rank_text.to_int())
	return Card.new(_next_id, rank, _SUITS[token.right(1)])
