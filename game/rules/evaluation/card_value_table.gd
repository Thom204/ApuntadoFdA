class_name CardValueTable
extends RefCounted
## Valor en puntos de cada carta (RD12). Es dato, no comportamiento: una variante
## puede usar otra tabla sin escribir una regla nueva.

var _values: Dictionary = {}
var _joker_value: int = 0


func _init(p_values: Dictionary = {}, p_joker_value: int = 0) -> void:
	_values = p_values.duplicate()
	_joker_value = p_joker_value


## Tabla estándar: 2-10 valen su número; A, J, Q y K valen 10; el comodín vale 0.
static func standard() -> CardValueTable:
	var values := {}
	for rank in range(Card.Rank.TWO, Card.Rank.TEN + 1):
		values[rank] = rank
	for rank in [Card.Rank.ACE, Card.Rank.JACK, Card.Rank.QUEEN, Card.Rank.KING]:
		values[rank] = 10
	return CardValueTable.new(values, 0)


func value_of(card: Card) -> int:
	if card.is_joker():
		return _joker_value
	return int(_values.get(card.rank, 0))
