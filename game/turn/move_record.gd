class_name MoveRecord
extends RefCounted
## Movimiento de un jugador (value object): carga útil de la señal move_performed.
## El emisor (turn) define el evento y MatchHistory solo lo consume (H2).
## `card` es la carta que el movimiento deja a la vista de todos (descarte, toma del
## pozo, carta de cierre); null al robar del mazo, porque esa carta es secreta.

var sequence: int:
	get:
		return _sequence
var round_number: int:
	get:
		return _round_number
var player_id: StringName:
	get:
		return _player_id
var action: int:
	get:
		return _action
var card_id: int:
	get:
		return -1 if _card == null else _card.instance_id
var card: Card:
	get:
		return _card
var timestamp_ms: int:
	get:
		return _timestamp_ms

var _sequence: int
var _round_number: int
var _player_id: StringName
var _action: int
var _card: Card
var _timestamp_ms: int


## `p_timestamp_ms` negativo = ahora (solo la recuperación de partidas lo fija).
func _init(p_sequence: int, p_round: int, p_player: StringName, p_action: int, p_card: Card,
		p_timestamp_ms: int = -1) -> void:
	_sequence = p_sequence
	_round_number = p_round
	_player_id = p_player
	_action = p_action
	_card = p_card
	_timestamp_ms = p_timestamp_ms if p_timestamp_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)


func to_data() -> Dictionary:
	return {
		"sequence": _sequence, "round_number": _round_number, "player_id": String(_player_id),
		"action": _action, "card": null if _card == null else _card.to_data(), "timestamp_ms": _timestamp_ms,
	}


static func from_data(data: Dictionary) -> MoveRecord:
	var card_data: Variant = data.get("card")
	return MoveRecord.new(int(data["sequence"]), int(data["round_number"]), StringName(data["player_id"]),
		int(data["action"]), null if card_data == null else Card.from_data(card_data), int(data["timestamp_ms"]))


func action_name() -> String:
	return Turn.Action.keys()[_action]
