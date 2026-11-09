class_name RoundActionResult
extends RefCounted
## Resultado de una acción sobre la ronda (value object).

var ok: bool:
	get:
		return _error == Round.Error.OK
var error: int:
	get:
		return _error
## Carta robada (solo en acciones de robo).
var card: Card:
	get:
		return _card
## Resultado de la validación (solo en declare_closing).
var validation: ValidationResult:
	get:
		return _validation

var _error: int
var _card: Card
var _validation: ValidationResult


func _init(p_error: int, p_card: Card = null, p_validation: ValidationResult = null) -> void:
	_error = p_error
	_card = p_card
	_validation = p_validation
