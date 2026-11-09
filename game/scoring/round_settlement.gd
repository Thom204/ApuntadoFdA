class_name RoundSettlement
extends RefCounted
## Liquidación de una ronda (value object): variación de puntaje de cada jugador.
## Penalización positiva para los perdedores y closer_score_delta para quien cerró.

var round_number: int:
	get:
		return _round_number
var closer_id: StringName:
	get:
		return _closer_id
var deltas: Dictionary:
	get:
		return _deltas.duplicate()

var _round_number: int
var _closer_id: StringName
var _deltas: Dictionary


func _init(p_round_number: int, p_closer_id: StringName, p_deltas: Dictionary) -> void:
	_round_number = p_round_number
	_closer_id = p_closer_id
	_deltas = p_deltas.duplicate()


func delta_of(player_id: StringName) -> int:
	return int(_deltas.get(player_id, 0))
