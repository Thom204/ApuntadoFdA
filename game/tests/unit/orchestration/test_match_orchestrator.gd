extends GutTest
## Match Orchestration (Mediator + Facade, ADR-05): comandos síncronos, persistir
## antes de anunciar y eventos IGameEvents solo tras guardar.

const Cards := preload("res://tests/support/cards.gd")
const Stacked := preload("res://tests/support/stacked_deck.gd")
const RecordingRepository := preload("res://tests/support/recording_repository.gd")

const CLOSER := "2S 3S 4S 8H 8D 8C JH QH KH 4D"

var _repo: RecordingRepository
var _decks: Array[Deck] = []
var _orch: MatchOrchestrator


func before_each() -> void:
	_repo = RecordingRepository.new()
	_decks = []
	var registry := RuleRegistry.new(HandEvaluator.new())
	registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	_orch = MatchOrchestrator.new(registry, _repo, _next_deck)


func _next_deck(_config: MatchConfig, _rng: RandomNumberGenerator) -> Deck:
	return _decks.pop_front() if not _decks.is_empty() else Deck.build(2, false)


func _config(mode: StringName = &"apuntado", ids: Array = [&"a", &"b"]) -> MatchConfig:
	var players: Array[Dictionary] = []
	for id in ids:
		players.append({"id": id, "nickname": str(id).to_upper()})
	return MatchConfig.new(mode, players)


func _start(hands: Array, draws: String, mode: StringName = &"apuntado") -> void:
	_decks.append(Stacked.build(hands, "AH", draws))
	assert_true(_orch.create_match(_config(mode)).ok)


func _id(player: StringName, text: String) -> int:
	var wanted := Cards.one(text)
	for c in _orch.hand_of(player):
		if c.rank == wanted.rank and c.suit == wanted.suit:
			return c.instance_id
	return -1


# ----------------------------------------------------------------- creación
func test_lista_las_modalidades_disponibles() -> void:
	var ids := _orch.available_modes().map(func(m: Dictionary) -> StringName: return m["id"])
	assert_has(ids, &"classic")
	assert_has(ids, &"apuntado")


func test_crear_partida_con_modalidad_desconocida_falla() -> void:
	var result := _orch.create_match(_config(&"poker"))
	assert_false(result.ok)
	assert_eq(result.error, &"UNKNOWN_MODE")


func test_crear_partida_con_configuracion_invalida_falla() -> void:
	assert_eq(_orch.create_match(_config(&"apuntado", [&"a"])).error, &"INVALID_CONFIG")


func test_crear_partida_guarda_y_luego_anuncia_la_ronda() -> void:
	watch_signals(_orch)
	_start([CLOSER, Stacked.junk(1)], "9C")
	assert_eq(_repo.saves, ["snapshot"] as Array[String])
	assert_signal_emitted_with_parameters(_orch, "round_started", [1])
	assert_signal_emitted_with_parameters(_orch, "turn_changed", [&"a"])


# ----------------------------------------------------------------- comandos de turno
func test_accion_fuera_de_turno_se_rechaza_sin_guardar_ni_emitir() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	watch_signals(_orch)
	var saves_before := _repo.saves.size()
	var result := _orch.draw_from_deck(&"b")
	assert_eq(result.error, &"NOT_PLAYER_TURN")
	assert_ne(result.message, "")
	assert_eq(_repo.saves.size(), saves_before)
	assert_signal_not_emitted(_orch, "move_performed")


func test_robar_y_descartar_emiten_movimientos_y_cambio_de_turno() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	watch_signals(_orch)
	assert_true(_orch.draw_from_deck(&"a").ok)
	assert_true(_orch.discard(&"a", _id(&"a", "9C")).ok)
	assert_signal_emit_count(_orch, "move_performed", 2)
	assert_signal_emitted_with_parameters(_orch, "turn_changed", [&"b"])
	assert_eq(_orch.public_view()["current_player"], &"b")


func test_cierre_invalido_devuelve_el_motivo_y_no_emite_nada() -> void:
	_start(["2S 3S 4S 8H 8D 8C JH QH KH 6D", Stacked.junk(1)], "9C")
	_orch.draw_from_deck(&"a")
	watch_signals(_orch)
	var result := _orch.declare_closing(&"a", _id(&"a", "9C"))
	assert_eq(result.error, &"INVALID_CLOSING")
	assert_eq(result.validation.reason, ValidationResult.Reason.LEFTOVER_TOO_HIGH)
	assert_string_contains(result.message, "sobrantes")
	assert_signal_not_emitted(_orch, "round_closed")
	assert_eq(_orch.hand_of(&"a").size(), 11)


func test_cierre_valido_liquida_en_una_escritura_y_anuncia_la_ronda() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	_orch.draw_from_deck(&"a")
	watch_signals(_orch)
	assert_true(_orch.declare_closing(&"a", _id(&"a", "9C")).ok)
	assert_eq(_repo.saves.back(), "settlement:1")
	assert_signal_emitted(_orch, "round_closed")
	var settlement: RoundSettlement = get_signal_parameters(_orch, "round_closed")[0]
	assert_eq(settlement.delta_of(&"b"), 65)
	assert_eq(_orch.public_view()["players"][1]["total"], 65)
	assert_signal_not_emitted(_orch, "match_finished")


func test_siguiente_ronda_solo_tras_liquidar() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	assert_eq(_orch.start_next_round().error, &"ROUND_IN_PROGRESS")
	_orch.draw_from_deck(&"a")
	_orch.declare_closing(&"a", _id(&"a", "9C"))
	watch_signals(_orch)
	assert_true(_orch.start_next_round().ok)
	assert_signal_emitted_with_parameters(_orch, "round_started", [2])
	assert_signal_emitted_with_parameters(_orch, "turn_changed", [&"b"])


func test_clasica_cierre_valido_termina_la_partida() -> void:
	_start(["7H 7S 7D 7C 3H 4H 5H KC KD KS", Stacked.junk(1)], "9D", &"classic")
	_orch.draw_from_deck(&"a")
	watch_signals(_orch)
	assert_true(_orch.declare_closing(&"a", _id(&"a", "9D")).ok)
	assert_signal_emitted_with_parameters(_orch, "match_finished", [&"a"])
	assert_eq(_orch.start_next_round().error, &"MATCH_FINISHED")
	assert_eq(_orch.draw_from_deck(&"b").error, &"MATCH_FINISHED")


func test_eliminacion_emite_player_eliminated_y_fin_de_partida() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	_orch.draw_from_deck(&"a")
	_orch.declare_closing(&"a", _id(&"a", "9C"))
	# Ronda 2: empieza B (descarta lo robado) y A vuelve a cerrar: B llega a 130.
	_decks.append(Stacked.build([Stacked.junk(1), CLOSER], "AH", "KS 9C"))
	_orch.start_next_round()
	_orch.draw_from_deck(&"b")
	_orch.discard(&"b", _id(&"b", "KS"))
	_orch.draw_from_deck(&"a")
	watch_signals(_orch)
	assert_true(_orch.declare_closing(&"a", _id(&"a", "9C")).ok)
	assert_signal_emitted_with_parameters(_orch, "player_eliminated", [&"b"])
	assert_signal_emitted_with_parameters(_orch, "match_finished", [&"a"])
	assert_eq(_orch.public_view()["winner"], &"a")


# ----------------------------------------------------------------- persistir antes de anunciar (ADR-05)
func test_si_la_persistencia_falla_no_se_emite_ningun_evento() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	_repo.fail = true
	watch_signals(_orch)
	var result := _orch.draw_from_deck(&"a")
	assert_eq(result.error, &"PERSISTENCE_FAILED")
	assert_signal_not_emitted(_orch, "move_performed")
	assert_signal_not_emitted(_orch, "turn_changed")


func test_si_la_persistencia_falla_la_partida_vuelve_al_estado_previo() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	_repo.fail = true
	_orch.draw_from_deck(&"a")
	assert_eq(_orch.hand_of(&"a").size(), 10, "la carta robada vuelve al mazo")
	assert_eq(_orch.public_view()["phase"], &"DRAW")
	assert_eq(_orch.history().size(), 0)
	_repo.fail = false
	assert_true(_orch.draw_from_deck(&"a").ok, "se puede reintentar")
	assert_eq(str(_orch.hand_of(&"a").back()), "9♣", "y roba la misma carta")


func test_si_falla_la_liquidacion_la_ronda_sigue_abierta_y_sin_puntos() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	_orch.draw_from_deck(&"a")
	_repo.fail = true
	watch_signals(_orch)
	assert_eq(_orch.declare_closing(&"a", _id(&"a", "9C")).error, &"PERSISTENCE_FAILED")
	assert_signal_not_emitted(_orch, "round_closed")
	assert_false(_orch.public_view()["round_closed"])
	assert_eq(_orch.settlements().size(), 0)
	assert_eq(_orch.public_view()["players"][1]["total"], 0)
	_repo.fail = false
	assert_true(_orch.declare_closing(&"a", _id(&"a", "9C")).ok)


# ----------------------------------------------------------------- recuperación (D-15)
func test_una_partida_guardada_se_recupera_en_otro_orquestador() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	_orch.draw_from_deck(&"a")
	var id := _orch.match_id()
	var registry := RuleRegistry.new(HandEvaluator.new())
	registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	var other := MatchOrchestrator.new(registry, _repo)
	assert_true(other.resume_match(id).ok)
	assert_eq(other.public_view()["phase"], &"DISCARD")
	assert_eq(other.hand_of(&"a").size(), 11)
	assert_true(other.declare_closing(&"a", _id(&"a", "9C")).ok, "continúa donde quedó")
	assert_eq(other.public_view()["players"][1]["total"], 65)


func test_recuperar_una_partida_inexistente_falla() -> void:
	assert_eq(_orch.resume_match(&"m-nada").error, &"NO_MATCH")


# ----------------------------------------------------------------- vistas (RNF 3)
func test_la_vista_publica_no_expone_manos_ajenas() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	var view := _orch.public_view()
	assert_eq(view["mode"], &"apuntado")
	assert_eq(view["round_number"], 1)
	assert_eq(view["phase"], &"DRAW")
	assert_eq(view["players"][0]["hand_size"], 10)
	assert_false(view["players"][0].has("cards"))
	assert_eq(_orch.hand_of(&"a").size(), 10)


# ----------------------------------------------------------------- invariante de conservación
func test_simulacion_de_300_turnos_con_5_jugadores_no_pierde_ni_duplica_cartas() -> void:
	var config := _config(&"apuntado", [&"a", &"b", &"c", &"d", &"e"])
	config.rng_seed = 2026
	assert_true(_orch.create_match(config).ok)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for turn in 300:
		var view := _orch.public_view()
		var player: StringName = view["current_player"]
		if rng.randf() < 0.3 and view["discard_size"] > 0:
			assert_true(_orch.draw_from_discard(player).ok)
		else:
			assert_true(_orch.draw_from_deck(player).ok)
		var hand := _orch.hand_of(player)
		assert_true(_orch.discard(player, hand[rng.randi_range(0, hand.size() - 1)].instance_id).ok)
		assert_eq(_total_cards(), 104, "turno %d" % turn)


func _total_cards() -> int:
	var view := _orch.public_view()
	var total: int = view["deck_size"] + view["discard_size"]
	for p in view["players"]:
		total += p["hand_size"]
	return total


# ----------------------------------------------------------------- latencia (DA-03)
func test_declare_closing_de_punta_a_punta_p95_menor_a_200_ms() -> void:
	var times: Array[int] = []
	for _i in 20:
		before_each()
		_start([CLOSER, Stacked.junk(1)], "9C")
		_orch.draw_from_deck(&"a")
		var start := Time.get_ticks_usec()
		_orch.declare_closing(&"a", _id(&"a", "9C"))
		times.append(Time.get_ticks_usec() - start)
	times.sort()
	assert_lt(times[18] / 1000.0, 200.0)
