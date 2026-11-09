class_name MoveRecord
extends RefCounted
## Movimiento de un jugador (value object): carga útil de la señal move_performed.
## El emisor (turn) define el evento y MatchHistory solo lo consume (H2).

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
		return _card_id
var timestamp_ms: int:
	get:
		return _timestamp_ms

var _sequence: int
var _round_number: int
var _player_id: StringName
var _action: int
var _card_id: int
var _timestamp_ms: int


## `p_timestamp_ms` negativo = ahora (solo la recuperación de partidas lo fija).
func _init(p_sequence: int, p_round: int, p_player: StringName, p_action: int, p_card_id: int,
		p_timestamp_ms: int = -1) -> void:
	_sequence = p_sequence
	_round_number = p_round
	_player_id = p_player
	_action = p_action
	_card_id = p_card_id
	_timestamp_ms = p_timestamp_ms if p_timestamp_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)


func to_data() -> Dictionary:
	return {
		"sequence": _sequence, "round_number": _round_number, "player_id": String(_player_id),
		"action": _action, "card_id": _card_id, "timestamp_ms": _timestamp_ms,
	}


static func from_data(data: Dictionary) -> MoveRecord:
	return MoveRecord.new(int(data["sequence"]), int(data["round_number"]), StringName(data["player_id"]),
		int(data["action"]), int(data["card_id"]), int(data["timestamp_ms"]))


func action_name() -> String:
	return Turn.Action.keys()[_action]
