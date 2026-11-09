class_name MatchContext
extends RefCounted
## Datos de la partida que recibe la regla para decidir el fin y el ganador
## (value object inmutable). Los totales llegan como datos para que rules no
## dependa de scoring.

var active_players: Array[StringName]:
	get:
		return _active_players.duplicate()
var totals: Dictionary:
	get:
		return _totals.duplicate()
var rounds_played: int:
	get:
		return _rounds_played
var last_closer_id: StringName:
	get:
		return _last_closer_id

var _active_players: Array[StringName]
var _totals: Dictionary
var _rounds_played: int
var _last_closer_id: StringName


func _init(p_active: Array[StringName], p_totals: Dictionary, p_rounds_played: int, p_last_closer: StringName) -> void:
	_active_players = p_active.duplicate()
	_totals = p_totals.duplicate()
	_rounds_played = p_rounds_played
	_last_closer_id = p_last_closer


func total_of(player_id: StringName) -> int:
	return int(_totals.get(player_id, 0))
