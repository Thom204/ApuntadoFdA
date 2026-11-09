class_name Player
extends RefCounted
## Participante de una partida. Un jugador eliminado sigue en la partida como
## espectador (D-08), pero ya no recibe turnos.

enum Status { ACTIVE, ELIMINATED }

var id: StringName:
	get:
		return _id
var nickname: String:
	get:
		return _nickname
var seat: int:
	get:
		return _seat
var status: int:
	get:
		return _status

var _id: StringName
var _nickname: String
var _seat: int
var _status: int = Status.ACTIVE


func _init(p_id: StringName, p_nickname: String, p_seat: int) -> void:
	_id = p_id
	_nickname = p_nickname
	_seat = p_seat


func eliminate() -> void:
	_status = Status.ELIMINATED


func is_active() -> bool:
	return _status == Status.ACTIVE
