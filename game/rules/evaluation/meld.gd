class_name Meld
extends RefCounted
## Combinación válida (value object): grupo del mismo valor o escalera, de 3 o más cartas.

var type: int:
	get:
		return _type
var cards: Array[Card]:
	get:
		return _cards.duplicate()

var _type: int
var _cards: Array[Card]


func _init(p_type: int, p_cards: Array[Card]) -> void:
	_type = p_type
	_cards = p_cards.duplicate()


func size() -> int:
	return _cards.size()


func _to_string() -> String:
	return "[%s]" % " ".join(_cards.map(func(c: Card) -> String: return str(c)))
