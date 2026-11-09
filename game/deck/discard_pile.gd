class_name DiscardPile
extends RefCounted
## Pozo de descarte. El final del arreglo es el tope visible.

var _cards: Array[Card] = []


## Pozo con un contenido dado (el último elemento es el tope). Para recuperar partidas.
static func from_cards(cards: Array[Card]) -> DiscardPile:
	var pile := DiscardPile.new()
	pile._cards = cards.duplicate()
	return pile


func push(card: Card) -> void:
	_cards.append(card)


## Devuelve null si el pozo está vacío.
func peek_top() -> Card:
	if _cards.is_empty():
		return null
	return _cards.back()


func take_top() -> Card:
	if _cards.is_empty():
		return null
	return _cards.pop_back()


func take_all_but_top() -> Array[Card]:
	var out: Array[Card] = []
	if _cards.size() <= 1:
		return out
	var top: Card = _cards.pop_back()
	out = _cards.duplicate()
	_cards = [top]
	return out


func size() -> int:
	return _cards.size()


func is_empty() -> bool:
	return _cards.is_empty()


## Copia del contenido, de la base al tope (para persistencia).
func cards() -> Array[Card]:
	return _cards.duplicate()
