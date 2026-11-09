class_name InMemoryMatchRepository
extends IMatchRepository
## Adaptador de persistencia en memoria (sin base de datos). Guarda una copia
## profunda del snapshot, de modo que lo que se recupera es lo que se guardó y no
## el objeto vivo. Sirve para jugar y probar mientras llega el adaptador SQLite (ADR-04).

var _snapshots: Dictionary = {}


func save_snapshot(snapshot: Dictionary) -> bool:
	_snapshots[StringName(snapshot["id"])] = snapshot.duplicate(true)
	return true


func save_settlement(snapshot: Dictionary, _settlement: RoundSettlement) -> bool:
	return save_snapshot(snapshot)


func load(match_id: StringName) -> Dictionary:
	var stored: Dictionary = _snapshots.get(match_id, {})
	return stored.duplicate(true)
