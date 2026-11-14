extends GutTest
## Audit Trail (D-14, D-20; evidencia del E3, sección 3.2): una entrada por cada
## solicitud que atiende el Lobby, aceptada o rechazada, y por cada evento de juego.
## Nunca guarda manos ni vistas (D-10). Como las demás notificaciones, es diferida y
## no invoca comandos (FF-07).

const Stacked := preload("res://tests/support/stacked_deck.gd")
const RecordingRepository := preload("res://tests/support/recording_repository.gd")
const RecordingAuditSink := preload("res://tests/support/recording_audit_sink.gd")
const JsonCheck := preload("res://tests/support/json_check.gd")

const CLOSER := "2S 3S 4S 8H 8D 8C JH QH KH 4D"
const PENALTY := "JH QH KH 9S 8C 7D 5S 3C 2D 2C"

var _sink: RecordingAuditSink
var _lobby: Lobby
var _trail: AuditTrail
var _decks: Array[Deck] = []
var _action := 0
var _now := 1000


func before_each() -> void:
	_sink = RecordingAuditSink.new()
	_decks = []
	var registry := RuleRegistry.new(HandEvaluator.new())
	registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	_lobby = Lobby.new(registry, RecordingRepository.new(),
		func(config: MatchConfig, _rng: RandomNumberGenerator) -> Deck:
			return _decks.pop_front() if not _decks.is_empty() else Deck.build(config.deck_count, false))
	_trail = AuditTrail.new(_lobby, _sink, func() -> int: return _now)


func _req(player_id: StringName, type: String, fields: Dictionary = {}) -> Dictionary:
	_action += 1
	var request := {"type": type, "action_id": "au-%d" % _action}
	request.merge(fields, true)
	return _lobby.handle(player_id, request)


## A y B en una sala en curso; A empieza con el 9♣ extra y puede cerrar.
func _playing() -> String:
	var room_id: String = _req(&"a", "create_room", {"nickname": "Ana", "mode": "apuntado"})["data"]["room"]["room_id"]
	_req(&"b", "join_room", {"room_id": room_id, "nickname": "Beto"})
	_decks.append(Stacked.build([CLOSER, PENALTY], "9C KS"))
	_req(&"a", "start_match")
	return room_id


func _view() -> Dictionary:
	return _req(&"a", "get_view")["data"]["view"]


func _card_id(label: String) -> int:
	for c: Dictionary in _view()["hand"]:
		if c["label"] == label:
			return c["id"]
	return -1


# ----------------------------------------------------------------- solicitudes
func test_cada_solicitud_deja_una_entrada() -> void:
	var room_id := _playing()
	await wait_process_frames(1)
	var requests := _sink.of_kind("request")
	assert_eq(requests.map(func(e: Dictionary) -> String: return e["type"]),
		["create_room", "join_room", "start_match"])
	var start := requests[2]
	assert_eq(start["player_id"], "a")
	assert_eq(start["room_id"], room_id)
	assert_true(start["ok"])
	assert_eq(start["ts_ms"], 1000)


func test_una_solicitud_rechazada_queda_con_su_motivo() -> void:
	_playing()
	var version: int = _view()["version"]
	_req(&"a", "declare_closing", {"expected_version": version, "card_id": _card_id("8♥")})
	await wait_process_frames(1)
	var closing: Dictionary = _sink.of_kind("request").back()
	assert_eq(closing["type"], "declare_closing")
	assert_false(closing["ok"])
	assert_eq(closing["error"], "INVALID_CLOSING")
	assert_eq(closing["fields"]["card_id"], _card_id("8♥"))
	assert_false(closing["detail"]["validation"]["valid"], "por qué el cierre no era válido")


func test_no_guarda_manos_ni_vistas() -> void:
	_playing()
	_view()
	await wait_process_frames(1)
	var text := JSON.stringify(_sink.entries)
	assert_false(text.contains("\"hand\""), "las cartas de cada mano son privadas (D-10)")
	assert_false(text.contains("\"view\""))


# ----------------------------------------------------------------- eventos de juego
func test_los_eventos_de_juego_quedan_con_la_partida_y_su_version() -> void:
	var room_id := _playing()
	_req(&"a", "declare_closing", {"expected_version": _view()["version"], "card_id": _card_id("9♣")})
	await wait_process_frames(1)
	var events := _sink.of_kind("event")
	var names := events.map(func(e: Dictionary) -> String: return e["event"])
	assert_has(names, "round_started")
	assert_has(names, "move_performed")
	assert_has(names, "round_closed")
	var closed: Dictionary = events.filter(func(e: Dictionary) -> bool: return e["event"] == "round_closed")[0]
	assert_eq(closed["room_id"], room_id)
	assert_string_starts_with(closed["match_id"], "m-")
	assert_eq(closed["data"]["settlement"]["deltas"]["b"], -36)
	assert_true(closed["data"]["closing"]["valid"])


func test_un_turno_automatico_queda_marcado() -> void:
	_playing()
	_lobby.tick(0)
	_lobby.tick(Lobby.DEFAULT_TURN_TIMEOUT_MS)
	await wait_process_frames(1)
	var moves := _sink.of_kind("event").filter(func(e: Dictionary) -> bool: return e["event"] == "move_performed")
	assert_true(moves.back()["data"]["automatic"])


func test_todas_las_entradas_son_json() -> void:
	_playing()
	_req(&"a", "declare_closing", {"expected_version": _view()["version"], "card_id": _card_id("9♣")})
	await wait_process_frames(1)
	for entry in _sink.entries:
		assert_true(JsonCheck.is_json_safe(entry), str(entry))
