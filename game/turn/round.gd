class_name Round
extends RefCounted
## Ronda: dueña del mazo, el pozo y las manos (invariante de conservación: cada
## carta está en un único lugar). Valida cada acción con Turn.can() y delega la
## validación del cierre en la regla (GameRule); la liquidación es de RoundScoring.
## No expone Deck, DiscardPile ni Hand: solo copias y datos públicos (Ley de
## Deméter). Recibe card_id, nunca una Card del cliente.

signal move_performed(move: MoveRecord)

enum Error {
	OK,
	ROUND_CLOSED,
	NOT_PLAYER_TURN,
	ACTION_NOT_ALLOWED,
	CARD_NOT_IN_HAND,
	DISCARD_EMPTY,
	DECK_EMPTY,
	INVALID_CLOSING,
}

## Código del catálogo para cada error. Tabla explícita: renombrar un valor del enum
## no cambia el protocolo.
const _ERROR_CODES := {
	Error.ROUND_CLOSED: ErrorCatalog.ROUND_CLOSED,
	Error.NOT_PLAYER_TURN: ErrorCatalog.NOT_PLAYER_TURN,
	Error.ACTION_NOT_ALLOWED: ErrorCatalog.ACTION_NOT_ALLOWED,
	Error.CARD_NOT_IN_HAND: ErrorCatalog.CARD_NOT_IN_HAND,
	Error.DISCARD_EMPTY: ErrorCatalog.DISCARD_EMPTY,
	Error.DECK_EMPTY: ErrorCatalog.DECK_EMPTY,
	Error.INVALID_CLOSING: ErrorCatalog.INVALID_CLOSING,
}

var number: int:
	get:
		return _number

var _number: int
var _rule: GameRule
var _turn_order: Array[StringName]
var _rng: RandomNumberGenerator
var _deck: Deck
var _discard_pile := DiscardPile.new()
var _hands: Dictionary = {}
var _turn: Turn
var _turn_index := 0
var _turn_count := 0
var _move_sequence := 0
var _closer_id := &""


func _init(p_number: int, p_rule: GameRule, p_turn_order: Array[StringName], p_rng: RandomNumberGenerator) -> void:
	_number = p_number
	_rule = p_rule
	_turn_order = p_turn_order.duplicate()
	_rng = p_rng


## Reparte desde un mazo ya barajado. Quien empieza recibe una carta extra y abre la
## ronda descartando sin robar: su descarte inicia el pozo, que arranca vacío.
func start(deck: Deck) -> void:
	_deck = deck
	var amount := _rule.cards_to_deal(_context())
	for player_id in _turn_order:
		var hand := Hand.new(player_id)
		hand.add_all(_deck.deal(amount))
		_hands[player_id] = hand
	_hands[_turn_order[0]].add(_deck.draw())
	_turn_index = 0
	_turn_count = 1
	_turn = Turn.opening(_turn_order[0], _turn_count)


# ======================================================================= comandos
func draw_from_deck(player_id: StringName) -> RoundActionResult:
	var error := _check(player_id, Turn.Action.DRAW_FROM_DECK)
	if error != Error.OK:
		return RoundActionResult.new(error)
	if _deck.is_empty():
		_deck.refill_from(_discard_pile, _rng)
	if _deck.is_empty():
		return RoundActionResult.new(Error.DECK_EMPTY)
	var card := _deck.draw()
	_hands[player_id].add(card)
	_record(Turn.Action.DRAW_FROM_DECK, null)
	return RoundActionResult.new(Error.OK, card)


func draw_from_discard(player_id: StringName) -> RoundActionResult:
	var error := _check(player_id, Turn.Action.DRAW_FROM_DISCARD)
	if error != Error.OK:
		return RoundActionResult.new(error)
	if _discard_pile.is_empty():
		return RoundActionResult.new(Error.DISCARD_EMPTY)
	var card := _discard_pile.take_top()
	_hands[player_id].add(card)
	_record(Turn.Action.DRAW_FROM_DISCARD, card)
	return RoundActionResult.new(Error.OK, card)


func discard(player_id: StringName, card_id: int) -> RoundActionResult:
	var error := _check(player_id, Turn.Action.DISCARD)
	if error != Error.OK:
		return RoundActionResult.new(error)
	var card: Card = _hands[player_id].take(card_id)
	if card == null:
		return RoundActionResult.new(Error.CARD_NOT_IN_HAND)
	_discard_pile.push(card)
	_record(Turn.Action.DISCARD, card)
	_begin_turn((_turn_index + 1) % _turn_order.size())
	return RoundActionResult.new(Error.OK, card)


## Un cierre rechazado no cambia mano, turno ni ronda (RD16). Uno aceptado baja la
## carta de descarte al pozo y cierra la ronda de inmediato (RD17).
func declare_closing(player_id: StringName, card_id: int) -> RoundActionResult:
	var error := _check(player_id, Turn.Action.DECLARE_CLOSING)
	if error != Error.OK:
		return RoundActionResult.new(error)
	var hand: Hand = _hands[player_id]
	var result := _rule.validate_closing(hand.cards(), hand.find(card_id), _context())
	if not result.is_valid:
		var code := Error.CARD_NOT_IN_HAND if result.reason == ValidationResult.Reason.CARD_NOT_IN_HAND else Error.INVALID_CLOSING
		return RoundActionResult.new(code, null, result)
	var closing_card := hand.take(card_id)
	_discard_pile.push(closing_card)
	_closer_id = player_id
	_record(Turn.Action.DECLARE_CLOSING, closing_card)
	return RoundActionResult.new(Error.OK, null, result)


# ======================================================================= snapshot
## Estado completo en datos planos (JSON-compatibles): orden del mazo, pozo, manos y
## turno. Es lo que persiste el adaptador; no expone Deck, DiscardPile ni Hand.
func to_snapshot() -> Dictionary:
	var hands := {}
	for player_id in _turn_order:
		hands[String(player_id)] = Card.list_to_data(_hands[player_id].cards())
	return {
		"number": _number,
		"turn_order": _turn_order.map(func(p: StringName) -> String: return String(p)),
		"deck": Card.list_to_data(_deck.cards()),
		"discard": Card.list_to_data(_discard_pile.cards()),
		"hands": hands,
		"turn_index": _turn_index,
		"turn_count": _turn_count,
		"phase": String(_turn.phase_name()),
		"move_sequence": _move_sequence,
		"closer_id": String(_closer_id),
	}


static func from_snapshot(data: Dictionary, rule: GameRule, rng: RandomNumberGenerator) -> Round:
	var order: Array[StringName] = []
	for player_id in data["turn_order"]:
		order.append(StringName(player_id))
	var r := Round.new(int(data["number"]), rule, order, rng)
	r._deck = Deck.from_cards(Card.list_from_data(data["deck"]))
	r._discard_pile = DiscardPile.from_cards(Card.list_from_data(data["discard"]))
	for player_id in order:
		var hand := Hand.new(player_id)
		hand.add_all(Card.list_from_data(data["hands"][String(player_id)]))
		r._hands[player_id] = hand
	r._turn_index = int(data["turn_index"])
	r._turn_count = int(data["turn_count"])
	r._turn = Turn.resumed(order[r._turn_index], r._turn_count, StringName(data["phase"]))
	r._move_sequence = int(data["move_sequence"])
	r._closer_id = StringName(data["closer_id"])
	return r


# ======================================================================= consultas
## Código de ErrorCatalog de un Round.Error (vacío para OK).
static func error_code(error: int) -> StringName:
	return _ERROR_CODES.get(error, &"")


## Lo que todos pueden ver de la mesa: nunca las cartas de una mano (RNF 3).
func public_state() -> Dictionary:
	var hand_sizes := {}
	for player_id in _turn_order:
		hand_sizes[player_id] = _hands[player_id].size()
	return {
		"number": _number,
		"current_player": _turn.player_id,
		"phase": _turn.phase_name(),
		"top_discard": _discard_pile.peek_top(),
		"deck_size": _deck.size(),
		"discard_size": _discard_pile.size(),
		"closed": is_closed(),
		"hand_sizes": hand_sizes,
	}


func current_player_id() -> StringName:
	return _turn.player_id


func current_phase() -> StringName:
	return _turn.phase_name()


func cards_of(player_id: StringName) -> Array[Card]:
	if not _hands.has(player_id):
		return []
	return _hands[player_id].cards()


func hand_size_of(player_id: StringName) -> int:
	return _hands[player_id].size() if _hands.has(player_id) else 0


func top_discard() -> Card:
	return _discard_pile.peek_top()


func deck_size() -> int:
	return _deck.size()


func discard_size() -> int:
	return _discard_pile.size()


func is_closed() -> bool:
	return _closer_id != &""


func closer_id() -> StringName:
	return _closer_id


func turn_order() -> Array[StringName]:
	return _turn_order.duplicate()


# ======================================================================= internos
func _check(player_id: StringName, action: int) -> int:
	if is_closed():
		return Error.ROUND_CLOSED
	if player_id != _turn.player_id:
		return Error.NOT_PLAYER_TURN
	if not _turn.can(action):
		return Error.ACTION_NOT_ALLOWED
	return Error.OK


func _begin_turn(index: int) -> void:
	_turn_index = index
	_turn_count += 1
	_turn = Turn.new(_turn_order[index], _turn_count)


## `card`: la carta que el movimiento deja a la vista (null si es secreta).
func _record(action: int, card: Card) -> void:
	_turn.apply(action)
	_move_sequence += 1
	move_performed.emit(MoveRecord.new(_move_sequence, _number, _turn.player_id, action, card))


func _context() -> RoundContext:
	return RoundContext.new(_number, _turn_order)
