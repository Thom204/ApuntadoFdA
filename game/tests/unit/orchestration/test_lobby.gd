extends GutTest
## Lobby: única entrada del protocolo con la red. Recibe `player_id` del adaptador
## (ya autenticado) y una solicitud en datos; devuelve una respuesta en datos.
## Cada prueba habla con el Lobby solo por handle(), como lo haría la red.

const Cards := preload("res://tests/support/cards.gd")
const Stacked := preload("res://tests/support/stacked_deck.gd")
const RecordingRepository := preload("res://tests/support/recording_repository.gd")
const JsonCheck := preload("res://tests/support/json_check.gd")

const CLOSER := "2S 3S 4S 8H 8D 8C JH QH KH 4D"

var _repo: RecordingRepository
var _decks: Array[Deck] = []
var _lobby: Lobby
var _action := 0


func before_each() -> void:
	_repo = RecordingRepository.new()
	_decks = []
	var registry := RuleRegistry.new(HandEvaluator.new())
	registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	_lobby = Lobby.new(registry, _repo,
		func(config: MatchConfig, _rng: RandomNumberGenerator) -> Deck:
			return _decks.pop_front() if not _decks.is_empty() else Deck.build(config.deck_count, false))


## Solicitud con un action_id nuevo.
func _req(player_id: StringName, type: String, fields: Dictionary = {}) -> Dictionary:
	_action += 1
	var request := {"type": type, "action_id": "act-%d" % _action}
	request.merge(fields, true)
	return _lobby.handle(player_id, request)


func _room_with(players: Array) -> String:
	var created := _req(players[0], "create_room", {"nickname": "Ana", "mode": "apuntado"})
	var room_id: String = created["data"]["room"]["room_id"]
	for p in players.slice(1):
		assert_true(_req(p, "join_room", {"room_id": room_id, "nickname": String(p).to_upper()})["ok"])
	return room_id


# ----------------------------------------------------------------- formato del protocolo
func test_una_solicitud_sin_tipo_es_invalida() -> void:
	var response := _lobby.handle(&"a", {"action_id": "x"})
	assert_false(response["ok"])
	assert_eq(response["error"], "INVALID_REQUEST")
	assert_ne(response["message"], "")


func test_un_tipo_desconocido_se_rechaza() -> void:
	assert_eq(_req(&"a", "bailar")["error"], "UNKNOWN_REQUEST")


func test_un_cambio_sin_action_id_es_invalido() -> void:
	var response := _lobby.handle(&"a", {"type": "create_room", "nickname": "Ana", "mode": "apuntado"})
	assert_eq(response["error"], "INVALID_REQUEST")


func test_la_respuesta_repite_el_tipo_y_el_action_id() -> void:
	var response := _lobby.handle(&"a", {"type": "create_room", "action_id": "abc", "nickname": "Ana", "mode": "apuntado"})
	assert_eq(response["request"], "create_room")
	assert_eq(response["action_id"], "abc")


# ----------------------------------------------------------------- salas
func test_quien_crea_la_sala_es_el_anfitrion() -> void:
	var response := _req(&"a", "create_room", {"nickname": "Ana", "mode": "apuntado"})
	assert_true(response["ok"], str(response))
	var room: Dictionary = response["data"]["room"]
	assert_eq(room["host_id"], "a")
	assert_eq(room["status"], "WAITING")
	assert_eq(room["mode"], "apuntado")
	assert_eq(room["players"], [{"id": "a", "nickname": "Ana"}])


func test_crear_sala_con_modalidad_desconocida_o_sin_apodo_falla() -> void:
	assert_eq(_req(&"a", "create_room", {"nickname": "Ana", "mode": "poker"})["error"], "UNKNOWN_MODE")
	assert_eq(_req(&"a", "create_room", {"mode": "apuntado"})["error"], "INVALID_REQUEST")


func test_unirse_agrega_al_jugador_en_el_siguiente_asiento() -> void:
	var room_id := _room_with([&"a"])
	var response := _req(&"b", "join_room", {"room_id": room_id, "nickname": "Beto"})
	assert_true(response["ok"], str(response))
	assert_eq(response["data"]["room"]["players"].map(func(p: Dictionary) -> String: return p["id"]), ["a", "b"])


func test_unirse_a_una_sala_inexistente_falla() -> void:
	assert_eq(_req(&"b", "join_room", {"room_id": "r-999", "nickname": "Beto"})["error"], "NO_ROOM")


func test_la_sala_admite_hasta_5_jugadores() -> void:
	var room_id := _room_with([&"a", &"b", &"c", &"d", &"e"])
	assert_eq(_req(&"f", "join_room", {"room_id": room_id, "nickname": "F"})["error"], "ROOM_FULL")


func test_un_jugador_esta_en_una_sola_sala() -> void:
	var room_id := _room_with([&"a"])
	assert_eq(_req(&"a", "create_room", {"nickname": "Ana", "mode": "apuntado"})["error"], "ALREADY_IN_ROOM")
	assert_eq(_req(&"a", "join_room", {"room_id": room_id, "nickname": "Ana"})["error"], "ALREADY_IN_ROOM")


func test_salir_de_la_sala_en_espera() -> void:
	var room_id := _room_with([&"a", &"b", &"c"])
	assert_true(_req(&"b", "leave_room")["ok"])
	var view := _lobby.handle(&"a", {"type": "get_view"})
	assert_eq(view["data"]["room"]["players"].map(func(p: Dictionary) -> String: return p["id"]), ["a", "c"])
	assert_eq(_req(&"b", "leave_room")["error"], "NOT_IN_ROOM")
	assert_true(_req(&"b", "join_room", {"room_id": room_id, "nickname": "Beto"})["ok"], "puede volver a entrar")


func test_si_sale_el_anfitrion_lo_reemplaza_el_siguiente() -> void:
	_room_with([&"a", &"b"])
	_req(&"a", "leave_room")
	assert_eq(_lobby.handle(&"b", {"type": "get_view"})["data"]["room"]["host_id"], "b")


# ----------------------------------------------------------------- inicio (lo decide el anfitrión)
## Sala de A y B ya iniciada con un mazo arreglado: A empieza con CLOSER + 9♣.
func _started(draws: String = "9C KS") -> Dictionary:
	_room_with([&"a", &"b"])
	_decks.append(Stacked.build([CLOSER, Stacked.junk(1)], draws))
	var response := _req(&"a", "start_match")
	assert_true(response["ok"], str(response))
	return response["data"]["view"]


func _card_id(view: Dictionary, label: String) -> int:
	for c: Dictionary in view["hand"]:
		if c["label"] == label:
			return c["id"]
	return -1


func _view(player_id: StringName) -> Dictionary:
	return _lobby.handle(player_id, {"type": "get_view"})["data"]["view"]


func test_solo_el_anfitrion_inicia_la_partida() -> void:
	_room_with([&"a", &"b"])
	assert_eq(_req(&"b", "start_match")["error"], "NOT_HOST")


func test_no_se_inicia_con_un_solo_jugador() -> void:
	_room_with([&"a"])
	assert_eq(_req(&"a", "start_match")["error"], "NOT_ENOUGH_PLAYERS")


func test_al_iniciar_la_sala_pasa_a_en_curso_y_cada_uno_recibe_su_vista() -> void:
	var view := _started()
	assert_eq(view["you"], "a")
	assert_eq(view["phase"], "DISCARD")
	assert_eq(view["hand"].size(), 11)
	assert_eq(_lobby.handle(&"b", {"type": "get_view"})["data"]["room"]["status"], "IN_PROGRESS")
	assert_eq(_view(&"b")["hand"].size(), 10)


func test_nadie_entra_ni_sale_con_la_partida_en_curso() -> void:
	_started()
	var room_id: String = _lobby.handle(&"a", {"type": "get_view"})["data"]["room"]["room_id"]
	assert_eq(_req(&"c", "join_room", {"room_id": room_id, "nickname": "C"})["error"], "ROOM_ALREADY_STARTED")
	assert_eq(_req(&"b", "leave_room")["error"], "ROOM_ALREADY_STARTED")
	assert_eq(_req(&"a", "start_match")["error"], "ROOM_ALREADY_STARTED")


# ----------------------------------------------------------------- comandos de juego
func test_un_comando_se_ejecuta_en_la_sala_del_jugador() -> void:
	var view := _started()
	var response := _req(&"a", "discard", {"card_id": _card_id(view, "9♣"), "expected_version": view["version"]})
	assert_true(response["ok"], str(response))
	assert_eq(response["data"]["view"]["version"], view["version"] + 1)
	assert_eq(response["data"]["view"]["current_player"], "b")
	assert_eq(response["data"]["card"]["label"], "9♣")


func test_un_comando_con_una_version_vieja_se_rechaza_sin_cambiar_nada() -> void:
	var view := _started()
	var response := _req(&"a", "discard", {"card_id": _card_id(view, "9♣"), "expected_version": view["version"] - 1})
	assert_eq(response["error"], "STALE_STATE")
	assert_eq(response["data"]["view"]["version"], view["version"], "la respuesta trae la mesa actual para resincronizar")
	assert_eq(_view(&"a")["hand"].size(), 11)


func test_un_comando_sin_version_es_invalido() -> void:
	var view := _started()
	assert_eq(_req(&"a", "discard", {"card_id": _card_id(view, "9♣")})["error"], "INVALID_REQUEST")


func test_un_reintento_con_el_mismo_action_id_no_se_ejecuta_dos_veces() -> void:
	var view := _started()
	_req(&"a", "discard", {"card_id": _card_id(view, "9♣"), "expected_version": view["version"]})
	var draw := {"type": "draw_from_deck", "action_id": "robo-1", "expected_version": view["version"] + 1}
	var first := _lobby.handle(&"b", draw)
	var retry := _lobby.handle(&"b", draw)
	assert_true(first["ok"], str(first))
	assert_eq(retry, first, "misma respuesta")
	assert_eq(_view(&"b")["hand"].size(), 11, "robó una sola vez")


func test_un_comando_rechazado_trae_el_codigo_del_catalogo() -> void:
	var view := _started()
	var response := _req(&"b", "draw_from_deck", {"expected_version": view["version"]})
	assert_eq(response["error"], "NOT_PLAYER_TURN")
	assert_eq(response["message"], "No es tu turno.")


func test_un_cierre_invalido_explica_el_motivo() -> void:
	_room_with([&"a", &"b"])
	_decks.append(Stacked.build(["2S 3S 4S 8H 8D 8C JH QH KH 6D", Stacked.junk(1)], "9C"))
	var view: Dictionary = _req(&"a", "start_match")["data"]["view"]
	var response := _req(&"a", "declare_closing", {"card_id": _card_id(view, "9♣"), "expected_version": view["version"]})
	assert_eq(response["error"], "INVALID_CLOSING")
	assert_string_contains(response["message"], "6 puntos")
	assert_eq(response["data"]["validation"]["reason"], "LEFTOVER_TOO_HIGH")


func test_un_cierre_valido_devuelve_la_liquidacion() -> void:
	var view := _started()
	var response := _req(&"a", "declare_closing", {"card_id": _card_id(view, "9♣"), "expected_version": view["version"]})
	assert_true(response["ok"], str(response))
	assert_true(response["data"]["validation"]["valid"])
	assert_true(response["data"]["view"]["round_closed"])


func test_quien_no_esta_en_una_sala_no_puede_jugar() -> void:
	assert_eq(_req(&"z", "draw_from_deck", {"expected_version": 1})["error"], "NOT_IN_ROOM")


func test_un_comando_de_juego_antes_de_iniciar_no_tiene_partida() -> void:
	_room_with([&"a", &"b"])
	assert_eq(_req(&"a", "draw_from_deck", {"expected_version": 0})["error"], "NO_MATCH")


# ----------------------------------------------------------------- consultas y JSON
func test_organizar_la_mano_por_el_protocolo() -> void:
	var view := _started()
	var ids := [_card_id(view, "8♥"), _card_id(view, "8♦"), _card_id(view, "8♣")]
	var response := _lobby.handle(&"a", {"type": "check_meld", "card_ids": ids})
	assert_true(response["ok"], str(response))
	assert_eq(response["data"]["check"]["result"], "SET")
	assert_eq(_lobby.handle(&"a", {"type": "check_meld", "card_ids": "8H"})["error"], "INVALID_REQUEST")


func test_consultar_sin_estar_en_una_sala_falla() -> void:
	assert_eq(_lobby.handle(&"z", {"type": "get_view"})["error"], "NOT_IN_ROOM")


func test_una_solicitud_que_paso_por_json_funciona() -> void:
	var view := _started()
	var request := {"type": "discard", "action_id": "j-1", "card_id": _card_id(view, "9♣"), "expected_version": view["version"]}
	var from_network: Dictionary = JSON.parse_string(JSON.stringify(request))
	assert_eq(typeof(from_network["card_id"]), TYPE_FLOAT, "JSON entrega los números como float")
	assert_true(_lobby.handle(&"a", from_network)["ok"])


func test_todas_las_respuestas_son_json() -> void:
	var responses: Array = []
	var created := _req(&"a", "create_room", {"nickname": "Ana", "mode": "apuntado"})
	responses.append(created)
	responses.append(_req(&"b", "join_room", {"room_id": created["data"]["room"]["room_id"], "nickname": "B"}))
	_decks.append(Stacked.build([CLOSER, Stacked.junk(1)], "9C"))
	var started := _req(&"a", "start_match")
	responses.append(started)
	var view: Dictionary = started["data"]["view"]
	responses.append(_req(&"b", "draw_from_deck", {"expected_version": view["version"]}))
	responses.append(_req(&"a", "declare_closing", {"card_id": _card_id(view, "9♣"), "expected_version": view["version"]}))
	responses.append(_lobby.handle(&"a", {"type": "check_meld", "card_ids": [_card_id(view, "2♠")]}))
	responses.append(_lobby.handle(&"b", {"type": "get_view"}))
	responses.append(_req(&"a", "bailar"))
	for response in responses:
		assert_true(JsonCheck.is_json_safe(response), str(response))


func test_crear_una_sala_entrega_su_orquestador_al_armado_del_servidor() -> void:
	watch_signals(_lobby)
	_req(&"a", "create_room", {"nickname": "Ana", "mode": "apuntado"})
	assert_signal_emitted(_lobby, "room_created")
	var params: Array = get_signal_parameters(_lobby, "room_created")
	assert_eq(params[0], &"r-1")
	assert_true(params[1] is MatchOrchestrator)


func test_la_sala_vacia_desaparece() -> void:
	var room_id := _room_with([&"a"])
	_req(&"a", "leave_room")
	assert_eq(_req(&"b", "join_room", {"room_id": room_id, "nickname": "Beto"})["error"], "NO_ROOM")
