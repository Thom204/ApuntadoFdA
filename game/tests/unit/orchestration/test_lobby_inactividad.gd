extends GutTest
## Inactividad y desconexión (D-11, D-12), vistas desde la red. El núcleo no tiene
## reloj: el servidor llama tick(now_ms) cada segundo y la prueba pasa el tiempo a mano.
## Si el turno no avanza en turn_timeout_ms (o disconnected_timeout_ms cuando el
## jugador está desconectado), el servidor juega un turno automático por él.

const Stacked := preload("res://tests/support/stacked_deck.gd")
const RecordingRepository := preload("res://tests/support/recording_repository.gd")

const CLOSER := "2S 3S 4S 8H 8D 8C JH QH KH 4D"
const SECOND := 1000

var _decks: Array[Deck] = []
var _lobby: Lobby
var _action := 0


func before_each() -> void:
	_decks = []
	var registry := RuleRegistry.new(HandEvaluator.new())
	registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	_lobby = Lobby.new(registry, RecordingRepository.new(),
		func(config: MatchConfig, _rng: RandomNumberGenerator) -> Deck:
			return _decks.pop_front() if not _decks.is_empty() else Deck.build(config.deck_count, false))


func _req(player_id: StringName, type: String, fields: Dictionary = {}) -> Dictionary:
	_action += 1
	var request := {"type": type, "action_id": "i-%d" % _action}
	request.merge(fields, true)
	return _lobby.handle(player_id, request)


## Sala de A y B en curso; A empieza con 11 cartas (la extra es el K♦). El reloj
## empieza a contar en el primer tick.
func _playing() -> void:
	var room_id: String = _req(&"a", "create_room", {"nickname": "Ana", "mode": "apuntado"})["data"]["room"]["room_id"]
	_req(&"b", "join_room", {"room_id": room_id, "nickname": "Beto"})
	_decks.append(Stacked.build([CLOSER, Stacked.junk(1)], "KD KC 2H 6C"))
	assert_true(_req(&"a", "start_match")["ok"])
	_lobby.tick(0)


func _view(player_id: StringName = &"a") -> Dictionary:
	return _req(player_id, "get_view")["data"]["view"]


# ----------------------------------------------------------------- tiempo de turno
func test_los_valores_por_defecto_son_los_del_servidor() -> void:
	assert_eq(_lobby.turn_timeout_ms, Lobby.DEFAULT_TURN_TIMEOUT_MS)
	assert_eq(Lobby.DEFAULT_TURN_TIMEOUT_MS, 45 * SECOND)
	assert_eq(Lobby.DEFAULT_DISCONNECTED_TIMEOUT_MS, 10 * SECOND)


func test_antes_de_que_venza_el_turno_no_pasa_nada() -> void:
	_playing()
	var version: int = _view()["version"]
	assert_eq(_lobby.tick(45 * SECOND - 1), [] as Array[StringName])
	assert_eq(_view()["version"], version)


func test_al_vencer_el_turno_el_servidor_juega_por_el_jugador() -> void:
	_playing()
	assert_eq(_lobby.tick(45 * SECOND), [&"a"] as Array[StringName])
	var view := _view()
	assert_eq(view["current_player"], "b")
	assert_eq(view["top_discard"]["label"], "K♦")


func test_una_jugada_reinicia_la_cuenta() -> void:
	_playing()
	_lobby.tick(30 * SECOND)
	var hand: Array = _view()["hand"]
	assert_true(_req(&"a", "discard", {"expected_version": _view()["version"], "card_id": hand.back()["id"]})["ok"])
	assert_eq(_lobby.tick(46 * SECOND), [] as Array[StringName], "el turno de B empezó a contar ahora")
	assert_eq(_lobby.tick(46 * SECOND + 44 * SECOND), [] as Array[StringName])
	assert_eq(_lobby.tick(46 * SECOND + 45 * SECOND), [&"b"] as Array[StringName])


func test_cada_turno_automatico_reinicia_la_cuenta_del_siguiente() -> void:
	_playing()
	_lobby.tick(45 * SECOND)
	assert_eq(_lobby.tick(46 * SECOND), [] as Array[StringName], "B tiene su propio tiempo")
	assert_eq(_lobby.tick(90 * SECOND), [&"b"] as Array[StringName])


func test_los_tiempos_se_configuran_en_el_servidor() -> void:
	_lobby.turn_timeout_ms = 5 * SECOND
	_playing()
	assert_eq(_lobby.tick(5 * SECOND), [&"a"] as Array[StringName])


# ----------------------------------------------------------------- desconexión
func test_un_jugador_desconectado_tiene_menos_tiempo() -> void:
	_playing()
	_lobby.set_connected(&"a", false)
	assert_eq(_lobby.tick(10 * SECOND - 1), [] as Array[StringName])
	assert_eq(_lobby.tick(10 * SECOND), [&"a"] as Array[StringName])


func test_al_reconectarse_vuelve_al_tiempo_normal() -> void:
	_playing()
	_lobby.set_connected(&"a", false)
	_lobby.set_connected(&"a", true)
	assert_eq(_lobby.tick(10 * SECOND), [] as Array[StringName])


func test_si_nadie_esta_conectado_la_partida_espera() -> void:
	_playing()
	_lobby.set_connected(&"a", false)
	_lobby.set_connected(&"b", false)
	assert_eq(_lobby.tick(600 * SECOND), [] as Array[StringName])


func test_la_sala_muestra_quien_esta_desconectado() -> void:
	_playing()
	_lobby.set_connected(&"b", false)
	var players: Array = _req(&"a", "get_view")["data"]["room"]["players"]
	assert_eq(players.map(func(p: Dictionary) -> bool: return p["connected"]), [true, false])


func test_conectarse_o_desconectarse_avisa_a_la_sala() -> void:
	_playing()
	watch_signals(_lobby)
	_lobby.set_connected(&"b", false)
	assert_signal_emitted(_lobby, "room_updated")


func test_un_jugador_sin_sala_no_cambia_nada() -> void:
	watch_signals(_lobby)
	_lobby.set_connected(&"nadie", false)
	assert_signal_not_emitted(_lobby, "room_updated")


# ----------------------------------------------------------------- cuándo no aplica
func test_una_sala_en_espera_no_tiene_reloj() -> void:
	_req(&"a", "create_room", {"nickname": "Ana", "mode": "apuntado"})
	assert_eq(_lobby.tick(600 * SECOND), [] as Array[StringName])


func test_con_la_ronda_cerrada_no_hay_turno_que_jugar() -> void:
	var room_id: String = _req(&"a", "create_room", {"nickname": "Ana", "mode": "apuntado"})["data"]["room"]["room_id"]
	_req(&"b", "join_room", {"room_id": room_id, "nickname": "Beto"})
	_decks.append(Stacked.build([CLOSER, "JH QH KH 9S 8C 7D 5S 3C 2D 2C"], "9C"))
	_req(&"a", "start_match")
	var hand: Array = _view()["hand"]
	assert_true(_req(&"a", "declare_closing", {"expected_version": _view()["version"], "card_id": hand.back()["id"]})["ok"])
	_lobby.tick(0)
	assert_eq(_lobby.tick(600 * SECOND), [] as Array[StringName])
