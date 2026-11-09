class_name Meld
extends RefCounted
## Combinación válida (value object): terna (3 cartas) o cuarta (4), por valor o escalera.

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
