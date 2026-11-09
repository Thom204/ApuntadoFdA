class_name Turn
extends RefCounted
## Turno de un jugador. Delega en su fase actual (patrón State).

enum Action { DRAW_FROM_DECK, DRAW_FROM_DISCARD, DISCARD, DECLARE_CLOSING }

var player_id: StringName:
	get:
		return _player_id
var number: int:
	get:
		return _number

var _player_id: StringName
var _number: int
var _phase: TurnPhase = DrawPhase.new()


func _init(p_player_id: StringName, p_number: int) -> void:
	_player_id = p_player_id
	_number = p_number


## Turno recuperado en la fase indicada por su nombre (DRAW, DISCARD o END).
static func resumed(p_player_id: StringName, p_number: int, phase_name: StringName) -> Turn:
	var turn := Turn.new(p_player_id, p_number)
	match phase_name:
		&"DISCARD":
			turn._phase = DiscardPhase.new()
		&"END":
			turn._phase = EndPhase.new()
	return turn


func can(action: int) -> bool:
	return _phase.allows(action)


func apply(action: int) -> void:
	_phase = _phase.next(action)


func is_over() -> bool:
	return _phase is EndPhase


func phase_name() -> StringName:
	return _phase.name()
