extends RefCounted
## Construye un mazo "arreglado" para pruebas: cada jugador recibe exactamente las
## cartas indicadas, luego se abre el pozo y después se roba en el orden de `draws`.

const Cards := preload("res://tests/support/cards.gd")


## hands: una cadena por jugador en el orden de reparto (10 cartas cada una).
## discard_top: carta que abre el pozo. draws: cartas que saldrán del mazo, en orden.
static func build(hands: Array, discard_top: String, draws: String = "") -> Deck:
	var stack: Array[Card] = []
	var pending := Cards.parse(draws)
	pending.reverse()
	stack.append_array(pending)
	stack.append(Cards.one(discard_top))
	for i in range(hands.size() - 1, -1, -1):
		var hand := Cards.parse(hands[i])
		hand.reverse()
		stack.append_array(hand)
	return Deck.from_cards(stack)


## Relleno de 10 cartas sin combinaciones posibles entre sí.
static func junk(variant: int = 0) -> String:
	var options := [
		"2H 4D 6C 8S 10H QD AC 3S 5H 7D",
		"2D 4C 6S 8H 10D QC AS 3H 5D 7C",
		"2C 4S 6H 8D 10C QS AH 3D 5C 7S",
		"2S 4H 6D 8C 10S QH AD 3C 5S 7H",
	]
	return options[variant % options.size()]
