class_name TurnClock
extends RefCounted
## Reloj de turnos del Lobby (D-12): recuerda, por sala, desde cuándo la partida está
## en la misma versión. El tiempo lo pone quien llama (tick del servidor), así que el
## núcleo sigue siendo determinista. Interno del Lobby: se prueba a través de
## Lobby.tick.
##
## Un cambio de versión se nota en el primer tick posterior: la cuenta del turno nuevo
## puede empezar hasta un intervalo de tick tarde (1 s en el servidor).

var _marks: Dictionary = {}  # room_id -> { "version": int, "since": int }


## Verdadero si la sala lleva `timeout_ms` o más en la misma versión. Si la versión
## cambió, la cuenta empieza de nuevo en `now_ms`.
func is_due(room_id: StringName, version: int, now_ms: int, timeout_ms: int) -> bool:
	var mark: Dictionary = _marks.get(room_id, {})
	if mark.is_empty() or mark["version"] != version:
		restart(room_id, version, now_ms)
		return false
	return now_ms - int(mark["since"]) >= timeout_ms


## La cuenta de la sala empieza ahora con esta versión (tras un turno automático).
func restart(room_id: StringName, version: int, now_ms: int) -> void:
	_marks[room_id] = {"version": version, "since": now_ms}


func forget(room_id: StringName) -> void:
	_marks.erase(room_id)
