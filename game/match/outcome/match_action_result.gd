class_name MatchActionResult
extends RefCounted
## Resultado de un comando sobre la partida (value object). Trae todo lo que ocurrió
## para que el orquestador persista y anuncie sin consultar el interior del agregado.

var ok: bool:
	get:
		return _error == Round.Error.OK
## Round.Error
var error: int:
	get:
		return _error
## Carta robada o descartada.
var card: Card:
	get:
		return _card
## Solo en declare_closing.
var validation: ValidationResult:
	get:
		return _validation
## Movimiento registrado; null si la acción se rechazó.
var move: MoveRecord:
	get:
		return _move
## Jugador al que pasó el turno; vacío si el turno no cambió.
var next_player_id: StringName:
	get:
		return _next_player_id
## Solo en un cierre válido: liquidación, eliminaciones y fin de partida.
var outcome: SettlementOutcome:
	get:
		return _outcome

var _error: int
var _card: Card
var _validation: ValidationResult
var _move: MoveRecord
var _next_player_id: StringName
var _outcome: SettlementOutcome


## Match fija `_outcome` tras liquidar un cierre válido.
func _init(p_round_result: RoundActionResult, p_move: MoveRecord = null, p_next_player_id: StringName = &"") -> void:
	_error = p_round_result.error
	_card = p_round_result.card
	_validation = p_round_result.validation
	_move = p_move
	_next_player_id = p_next_player_id


static func rejected(p_error: int) -> MatchActionResult:
	return MatchActionResult.new(RoundActionResult.new(p_error))
