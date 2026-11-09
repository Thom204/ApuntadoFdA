class_name DrawPhase
extends TurnPhase
## Inicio del turno: el jugador debe robar exactamente una carta (RD10).


func allows(action: int) -> bool:
	return action == Turn.Action.DRAW_FROM_DECK or action == Turn.Action.DRAW_FROM_DISCARD


func next(_action: int) -> TurnPhase:
	return DiscardPhase.new()


func name() -> StringName:
	return &"DRAW"
