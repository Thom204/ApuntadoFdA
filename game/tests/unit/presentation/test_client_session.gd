extends GutTest
## ClientSession: arma las solicitudes del protocolo y guarda la última sala y vista.
## Se prueba solo por su interfaz, con un transporte falso en lugar del servidor.

const FakeTransport := preload("res://tests/support/fake_client_transport.gd")

var _transport: FakeTransport
var _session: ClientSession


func before_each() -> void:
	_transport = FakeTransport.new()
	_session = ClientSession.new(_transport, "t")


func _view(version: int, match_id: String = "m-1") -> Dictionary:
	return {"match_id": match_id, "version": version, "is_your_turn": true, "phase": "DRAW", "you": "a"}


func _ok(request: String, data: Dictionary) -> Dictionary:
	return {"ok": true, "request": request, "action_id": "x", "error": "", "message": "", "data": data}


func test_cada_comando_lleva_un_action_id_nuevo() -> void:
	_session.create_room("Ana", &"apuntado")
	_session.start_match()
	assert_eq(_transport.sent[0], {"type": "create_room", "action_id": "t-1", "nickname": "Ana", "mode": "apuntado"})
	assert_eq(_transport.sent[1]["action_id"], "t-2")


func test_las_jugadas_llevan_la_version_de_la_ultima_vista() -> void:
	_transport.respond(_ok("get_view", {"view": _view(7)}))
	_session.discard(31)
	assert_eq(_transport.last(), {"type": "discard", "action_id": "t-1", "card_id": 31, "expected_version": 7})


func test_las_consultas_no_llevan_action_id() -> void:
	_session.check_meld([1, 2, 3])
	_session.refresh()
	assert_eq(_transport.sent[0], {"type": "check_meld", "card_ids": [1, 2, 3]})
	assert_eq(_transport.sent[1], {"type": "get_view"})


func test_una_vista_mas_vieja_se_descarta() -> void:
	watch_signals(_session)
	_transport.push({"event": "turn_changed", "data": {}, "view": _view(5)})
	_transport.respond(_ok("discard", {"view": _view(4)}))
	assert_eq(int(_session.view["version"]), 5)
	assert_signal_emit_count(_session, "view_changed", 1)


func test_una_partida_nueva_reemplaza_la_vista_aunque_su_version_sea_menor() -> void:
	_transport.push({"event": "turn_changed", "data": {}, "view": _view(9, "m-1")})
	_transport.push({"event": "round_started", "data": {"round_number": 1}, "view": _view(1, "m-2")})
	assert_eq(_session.view["match_id"], "m-2")


func test_el_evento_llega_con_la_vista_ya_actualizada() -> void:
	var seen := []
	_session.event_received.connect(func(event: String, _data: Dictionary) -> void:
		seen.append([event, int(_session.view["version"])]))
	_transport.push({"event": "move_performed", "data": {}, "view": _view(3)})
	assert_eq(seen, [["move_performed", 3]])


func test_room_updated_cambia_la_sala_y_no_es_un_evento_de_juego() -> void:
	watch_signals(_session)
	_transport.push({"event": "room_updated", "data": {"room_id": "r-1"}, "view": {}})
	assert_eq(_session.room, {"room_id": "r-1"})
	assert_signal_not_emitted(_session, "event_received")


func test_un_rechazo_avisa_y_actualiza_la_mesa_si_viene_con_vista() -> void:
	watch_signals(_session)
	_transport.respond({"ok": false, "request": "discard", "action_id": "x", "error": "STALE_STATE",
		"message": "La mesa cambió.", "data": {"view": _view(8)}})
	assert_signal_emitted(_session, "request_failed")
	assert_eq(int(_session.view["version"]), 8)


func test_salir_de_la_sala_limpia_sala_y_vista() -> void:
	_transport.respond(_ok("get_view", {"room": {"room_id": "r-1"}, "view": _view(2)}))
	_transport.respond(_ok("leave_room", {}))
	assert_eq(_session.room, {})
	assert_false(_session.has_match())
