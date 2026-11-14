class_name AuditTrail
extends RefCounted
## Audit Trail (D-14, D-20): registro de auditoría de todo lo que pasa en el servidor.
## Es la evidencia de las pruebas con usuarios (E3, sección 3.2): con `ts_ms` se puede
## medir el tiempo de cada turno, y las solicitudes rechazadas muestran los errores de
## regla que cometió cada jugador.
##
## Escribe dos tipos de entrada en el IAuditSink:
##   { kind: "request", ts_ms, player_id, room_id, type, action_id, ok, error,
##     fields: <campos de la solicitud>, detail: { validation?, card? } }
##   { kind: "event", ts_ms, room_id, match_id, version, event, data }
## Nunca guarda manos ni vistas (D-10): de la respuesta solo conserva el resultado.
## Diferida (CONNECT_DEFERRED) como el resto de las notificaciones y sin invocar
## comandos (FF-07). Los eventos de una solicitud se escriben antes que la solicitud.
##
## Quien la crea (el armado del servidor) debe conservar la referencia.

## Campos de la respuesta que se conservan dentro de `detail`.
const _DETAIL_KEYS := ["validation", "card", "check"]

var _sink: IAuditSink
var _clock: Callable


## `clock() -> int`: milisegundos actuales; por defecto, la hora del sistema.
func _init(lobby: Lobby, sink: IAuditSink, clock: Callable = Callable()) -> void:
	_sink = sink
	_clock = clock if clock.is_valid() else func() -> int: return int(Time.get_unix_time_from_system() * 1000.0)
	# Síncrono a propósito, como LobbyNotification: la partida puede empezar en el mismo
	# frame en que se creó la sala.
	lobby.room_created.connect(_on_room_created)
	lobby.request_handled.connect(_on_request_handled, CONNECT_DEFERRED)


func _on_room_created(room_id: StringName, orchestrator: MatchOrchestrator) -> void:
	var log_event := func(event: String, data: Dictionary) -> void:
		_sink.write({
			"kind": "event", "ts_ms": _clock.call(), "room_id": String(room_id),
			"match_id": String(orchestrator.match_id()), "version": orchestrator.state_version(),
			"event": event, "data": data,
		})
	orchestrator.round_started.connect(func(n: int) -> void:
		log_event.call("round_started", {"round_number": n}), CONNECT_DEFERRED)
	orchestrator.turn_changed.connect(func(p: StringName) -> void:
		log_event.call("turn_changed", {"player_id": String(p)}), CONNECT_DEFERRED)
	orchestrator.move_performed.connect(func(m: MoveRecord) -> void:
		log_event.call("move_performed", WireFormat.move(m)), CONNECT_DEFERRED)
	orchestrator.round_closed.connect(func(s: RoundSettlement, v: ValidationResult) -> void:
		log_event.call("round_closed", {"settlement": WireFormat.settlement(s), "closing": WireFormat.validation(v)}),
		CONNECT_DEFERRED)
	orchestrator.player_eliminated.connect(func(p: StringName) -> void:
		log_event.call("player_eliminated", {"player_id": String(p)}), CONNECT_DEFERRED)
	orchestrator.match_finished.connect(func(w: StringName) -> void:
		log_event.call("match_finished", {"winner_id": String(w)}), CONNECT_DEFERRED)


func _on_request_handled(player_id: StringName, room_id: StringName, request: Dictionary, response: Dictionary) -> void:
	var fields := request.duplicate(true)
	fields.erase("type")
	fields.erase("action_id")
	var detail := {}
	var data: Dictionary = response.get("data", {})
	for key in _DETAIL_KEYS:
		if data.has(key):
			detail[key] = data[key]
	_sink.write({
		"kind": "request", "ts_ms": _clock.call(), "player_id": String(player_id), "room_id": String(room_id),
		"type": response["request"], "action_id": response["action_id"], "ok": response["ok"],
		"error": response["error"], "fields": fields, "detail": detail,
	})
