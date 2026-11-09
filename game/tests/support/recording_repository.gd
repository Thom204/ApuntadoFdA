extends IMatchRepository
## Doble de prueba del puerto IMatchRepository: registra las escrituras, guarda los
## snapshots como texto JSON (como lo haría un adaptador real) y puede simular un
## fallo de persistencia.

var saves: Array[String] = []
var fail := false
var _stored: Dictionary = {}


func save_snapshot(snapshot: Dictionary) -> bool:
	saves.append("snapshot")
	return _store(snapshot)


func save_settlement(snapshot: Dictionary, settlement: RoundSettlement) -> bool:
	saves.append("settlement:%d" % settlement.round_number)
	return _store(snapshot)


func load(match_id: StringName) -> Dictionary:
	if not _stored.has(match_id):
		return {}
	return JSON.parse_string(_stored[match_id])


func _store(snapshot: Dictionary) -> bool:
	if fail:
		return false
	_stored[StringName(snapshot["id"])] = JSON.stringify(snapshot)
	return true
