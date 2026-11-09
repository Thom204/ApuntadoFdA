class_name EndPhase
extends TurnPhase
## Turno terminado: no admite acciones.


func allows(_action: int) -> bool:
	return false


func next(_action: int) -> TurnPhase:
	return self


func name() -> StringName:
	return &"END"
