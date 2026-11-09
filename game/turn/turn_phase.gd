@abstract class_name TurnPhase extends RefCounted
## Patrón State: cada fase decide qué acciones permite y a qué fase lleva.
## Draw -> Discard -> End. Separa CUÁNDO se actúa (State) de QUÉ gana (Strategy).

@abstract func allows(action: int) -> bool
@abstract func next(action: int) -> TurnPhase


func name() -> StringName:
	return &""
