class_name ValidationResult
extends RefCounted
## Resultado de validar un cierre (value object). `message` es el texto que ve el
## jugador cuando el cierre se rechaza (retroalimentación de la prueba con usuarios).

enum Reason { NONE, WRONG_HAND_SIZE, CARD_NOT_IN_HAND, INCOMPLETE_MELDS, LEFTOVER_TOO_HIGH }

const _MESSAGES := {
	Reason.NONE: "Cierre válido.",
	Reason.WRONG_HAND_SIZE: "Debes robar antes de cerrar: la mano debe tener una carta más de lo repartido.",
	Reason.CARD_NOT_IN_HAND: "La carta de descarte no está en tu mano.",
	Reason.INCOMPLETE_MELDS: "Tus cartas no forman las combinaciones que exige la modalidad.",
	Reason.LEFTOVER_TOO_HIGH: "Las cartas sobrantes suman %d puntos: son demasiados para cerrar.",
}

var is_valid: bool:
	get:
		return _reason == Reason.NONE
var reason: int:
	get:
		return _reason
var melds: Array[Meld]:
	get:
		return _melds.duplicate()
var leftover: Array[Card]:
	get:
		return _leftover.duplicate()
var leftover_points: int:
	get:
		return _leftover_points
var message: String:
	get:
		if _reason == Reason.LEFTOVER_TOO_HIGH:
			return _MESSAGES[_reason] % _leftover_points
		return _MESSAGES[_reason]

var _reason: int = Reason.NONE
var _melds: Array[Meld] = []
var _leftover: Array[Card] = []
var _leftover_points: int = 0


static func accept(p_melds: Array[Meld], p_leftover: Array[Card], points: int) -> ValidationResult:
	var r := ValidationResult.new()
	r._melds = p_melds.duplicate()
	r._leftover = p_leftover.duplicate()
	r._leftover_points = points
	return r


static func reject(p_reason: int, p_leftover: Array[Card] = [], points: int = 0) -> ValidationResult:
	var r := ValidationResult.new()
	r._reason = p_reason
	r._leftover = p_leftover.duplicate()
	r._leftover_points = points
	return r
