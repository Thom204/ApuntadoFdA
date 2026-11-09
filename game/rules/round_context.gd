class_name RoundContext
extends RefCounted
## Datos de la ronda que recibe la regla (value object inmutable).

var round_number: int:
	get:
		return _round_number
var active_players: Array[StringName]:
	get:
		return _active_players.duplicate()

var _round_number: int
var _active_players: Array[StringName]


func _init(p_round_number: int, p_active_players: Array[StringName]) -> void:
	_round_number = p_round_number
	_active_players = p_active_players.duplicate()
