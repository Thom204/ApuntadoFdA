class_name Hand
extends RefCounted
## Mano privada de un jugador. Solo expone copias de sus cartas (Ley de Deméter, H4).

var owner_id: StringName:
	get:
		return _owner_id

var _owner_id: StringName
var _cards: Array[Card] = []


func _init(p_owner_id: StringName) -> void:
	_owner_id = p_owner_id


func add(card: Card) -> void:
	_cards.append(card)


func add_all(cards: Array[Card]) -> void:
	_cards.append_array(cards)


## Busca una carta por instance_id; null si no está.
func find(card_id: int) -> Card:
	for c in _cards:
		if c.instance_id == card_id:
			return c
	return null


## Retira una carta por instance_id; null si no está.
func take(card_id: int) -> Card:
	var card := find(card_id)
	if card != null:
		_cards.erase(card)
	return card


func cards() -> Array[Card]:
	return _cards.duplicate()


func size() -> int:
	return _cards.size()
