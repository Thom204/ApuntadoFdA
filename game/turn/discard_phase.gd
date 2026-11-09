class_name DiscardPhase
extends TurnPhase
## Tras robar: el jugador descarta o declara el cierre (RD15). Un cierre rechazado
## deja al jugador en esta misma fase (RD16).


func allows(action: int) -> bool:
	return action == Turn.Action.DISCARD or action == Turn.Action.DECLARE_CLOSING


func next(_action: int) -> TurnPhase:
	return EndPhase.new()


func name() -> StringName:
	return &"DISCARD"
