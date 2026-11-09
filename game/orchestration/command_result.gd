class_name CommandResult
extends RefCounted
## Respuesta de un comando de IMatchCommands. `message` es el texto para el jugador.

const _MESSAGES := {
	&"NOT_PLAYER_TURN": "No es tu turno.",
	&"ACTION_NOT_ALLOWED": "Esa acción no está permitida ahora: primero roba una carta y luego descarta o cierra.",
	&"ROUND_CLOSED": "La ronda ya está cerrada.",
	&"CARD_NOT_IN_HAND": "Esa carta no está en tu mano.",
	&"DISCARD_EMPTY": "El pozo de descarte está vacío.",
	&"DECK_EMPTY": "No quedan cartas para robar.",
	&"NO_MATCH": "No hay una partida en curso.",
	&"MATCH_FINISHED": "La partida ya terminó.",
	&"ROUND_IN_PROGRESS": "La ronda actual sigue en juego.",
	&"UNKNOWN_MODE": "La modalidad elegida no está disponible.",
	&"INVALID_CONFIG": "La partida necesita entre 2 y 5 jugadores con nombres distintos.",
	&"PERSISTENCE_FAILED": "No se pudo guardar la partida. Intenta de nuevo.",
}

var ok: bool:
	get:
		return _error == &""
var error: StringName:
	get:
		return _error
var message: String:
	get:
		if _error == &"INVALID_CLOSING" and _validation != null:
			return _validation.message
		return _MESSAGES.get(_error, "")
var validation: ValidationResult:
	get:
		return _validation
var card: Card:
	get:
		return _card

var _error: StringName = &""
var _validation: ValidationResult
var _card: Card


static func success(p_validation: ValidationResult = null, p_card: Card = null) -> CommandResult:
	var r := CommandResult.new()
	r._validation = p_validation
	r._card = p_card
	return r


static func failure(p_error: StringName, p_validation: ValidationResult = null) -> CommandResult:
	var r := CommandResult.new()
	r._error = p_error
	r._validation = p_validation
	return r
