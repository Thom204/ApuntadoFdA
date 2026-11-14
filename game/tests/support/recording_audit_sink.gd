extends IAuditSink
## Doble de prueba del puerto IAuditSink: guarda las entradas en memoria.

var entries: Array[Dictionary] = []


func write(entry: Dictionary) -> void:
	entries.append(entry)


func of_kind(kind: String) -> Array[Dictionary]:
	return entries.filter(func(e: Dictionary) -> bool: return e["kind"] == kind)
