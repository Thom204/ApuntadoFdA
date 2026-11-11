class_name MeldCheck
extends RefCounted
## Respuesta de la consulta "¿estas cartas combinan?" (value object, RF-02). Sirve
## para que el jugador organice su mano: no cambia el estado de la partida.
## `message` es el texto que ve el jugador.

enum Result { SET, RUN, INVALID, CARD_NOT_IN_HAND }

const _MESSAGES := {
	Result.SET: "Grupo válido: %d cartas del mismo valor.",
	Result.RUN: "Escalera válida: %d cartas seguidas de la misma pinta.",
	Result.INVALID: "Esas cartas no forman un grupo ni una escalera.",
	Result.CARD_NOT_IN_HAND: "Alguna de esas cartas no está en tu mano.",
}

var result: int:
	get:
		return _result
var is_valid: bool:
	get:
		return _result == Result.SET or _result == Result.RUN
## Valor de las cartas consultadas: lo que dejarían de restar si quedan combinadas.
var points: int:
	get:
		return _points
var message: String:
	get:
		return _MESSAGES[_result] % _size if is_valid else _MESSAGES[_result]

var _result: int
var _points: int
var _size: int


func _init(p_result: int, p_size: int = 0, p_points: int = 0) -> void:
	_result = p_result
	_size = p_size
	_points = p_points


static func not_in_hand() -> MeldCheck:
	return MeldCheck.new(Result.CARD_NOT_IN_HAND)
