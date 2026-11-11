extends IPlayerChannel
## Adaptador de prueba de IPlayerChannel: guarda cada mensaje en lugar de enviarlo.

## [{ "to": StringName, "message": Dictionary }] en orden de envío.
var sent: Array[Dictionary] = []


func send(player_id: StringName, message: Dictionary) -> void:
	sent.append({"to": player_id, "message": message})


func to(player_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in sent:
		if s["to"] == player_id:
			out.append(s["message"])
	return out


func events_to(player_id: StringName) -> Array:
	return to(player_id).map(func(m: Dictionary) -> String: return m["event"])
