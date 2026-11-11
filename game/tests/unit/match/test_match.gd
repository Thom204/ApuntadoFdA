extends GutTest
## Match (raíz de agregado): rondas sucesivas, acumulación, salida en -101 y fin.

const Cards := preload("res://tests/support/cards.gd")
const Stacked := preload("res://tests/support/stacked_deck.gd")

## Mano de A que cierra en Apuntado descartando el 9♣ (sobrante 4♦).
const CLOSER := "2S 3S 4S 8H 8D 8C JH QH KH 4D"
## Mano que resta 36 (J-Q-K♥ combinan; 9+8+7+5+3+2+2 sueltas).
const PENALTY_36 := "JH QH KH 9S 8C 7D 5S 3C 2D 2C"

var _registry: RuleRegistry


func before_all() -> void:
	_registry = RuleRegistry.new(HandEvaluator.new())
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)


func _config(mode: StringName, ids: Array) -> MatchConfig:
	var players: Array[Dictionary] = []
	for id in ids:
		players.append({"id": id, "nickname": str(id).to_upper()})
	return MatchConfig.new(mode, players)


func _match(mode: StringName, ids: Array = [&"a", &"b"]) -> Match:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	return Match.new(&"m1", _config(mode, ids), _registry.resolve(mode), rng)


func _id_of(m: Match, player: StringName, text: String) -> int:
	var wanted := Cards.one(text)
	for c in m.hand_of(player):
		if c.rank == wanted.rank and c.suit == wanted.suit:
			return c.instance_id
	return -1


## A empieza con 11 cartas (la extra es el 9♣) y cierra en su primer descarte.
## `hands` va en el orden de turno de la ronda.
func _a_closes_first(m: Match, hands: Array) -> MatchActionResult:
	assert_true(m.start_next_round(Stacked.build(hands, "9C")))
	assert_eq(m.current_round().current_player_id(), &"a")
	var result := m.declare_closing(&"a", _id_of(m, &"a", "9C"))
	assert_true(result.ok)
	return result


## B empieza (descarta su carta extra, el K♠) y luego A roba el 9♣ y cierra.
func _a_closes_second(m: Match, b_hand: String) -> MatchActionResult:
	assert_true(m.start_next_round(Stacked.build([b_hand, CLOSER], "KS 9C")))
	assert_eq(m.current_round().current_player_id(), &"b")
	m.discard(&"b", _id_of(m, &"b", "KS"))
	m.draw_from_deck(&"a")
	var result := m.declare_closing(&"a", _id_of(m, &"a", "9C"))
	assert_true(result.ok)
	return result


# ----------------------------------------------------------------- configuración
func test_config_valida_de_2_a_5_jugadores_con_ids_unicos() -> void:
	assert_true(_config(&"apuntado", [&"a", &"b"]).is_valid())
	assert_true(_config(&"apuntado", [&"a", &"b", &"c", &"d", &"e"]).is_valid())
	assert_false(_config(&"apuntado", [&"a"]).is_valid())
	assert_false(_config(&"apuntado", [&"a", &"b", &"c", &"d", &"e", &"f"]).is_valid())
	assert_false(_config(&"apuntado", [&"a", &"a"]).is_valid())
	assert_false(_config(&"", [&"a", &"b"]).is_valid())


func test_una_baraja_hasta_4_jugadores_y_dos_con_5() -> void:
	assert_eq(_config(&"apuntado", [&"a", &"b"]).deck_count, 1)
	assert_eq(_config(&"apuntado", [&"a", &"b", &"c", &"d"]).deck_count, 1)
	assert_eq(_config(&"apuntado", [&"a", &"b", &"c", &"d", &"e"]).deck_count, 2)


# ----------------------------------------------------------------- rondas
func test_la_partida_empieza_esperando_y_pasa_a_en_curso() -> void:
	var m := _match(&"apuntado")
	assert_eq(m.status, Match.Status.WAITING_FOR_PLAYERS)
	m.start_next_round(Deck.build(2, false))
	assert_eq(m.status, Match.Status.IN_PROGRESS)
	assert_eq(m.round_number(), 1)


func test_no_se_inicia_otra_ronda_sin_liquidar_la_actual() -> void:
	var m := _match(&"apuntado")
	m.start_next_round(Deck.build(2, false))
	assert_false(m.start_next_round(Deck.build(2, false)))


func test_el_historial_registra_los_movimientos_de_la_ronda() -> void:
	var m := _match(&"apuntado")
	_a_closes_first(m, [CLOSER, Stacked.junk(1)])
	assert_eq(m.history().moves_of_round(1).size(), 1, "quien empieza cierra sin robar")


# ----------------------------------------------------------------- comandos del agregado
func test_cada_comando_devuelve_el_movimiento_y_el_cambio_de_turno() -> void:
	var m := _match(&"apuntado")
	m.start_next_round(Stacked.build([CLOSER, Stacked.junk(1)], "AH KS"))
	var discarded := m.discard(&"a", _id_of(m, &"a", "AH"))
	assert_eq(discarded.move.action, Turn.Action.DISCARD)
	assert_eq(discarded.next_player_id, &"b")
	assert_null(discarded.outcome, "solo un cierre liquida")
	var drew := m.draw_from_deck(&"b")
	assert_true(drew.ok)
	assert_eq(str(drew.card), "K♠")
	assert_eq(drew.move.action, Turn.Action.DRAW_FROM_DECK)
	assert_eq(drew.next_player_id, &"", "robar no pasa el turno")


func test_un_comando_rechazado_no_registra_movimiento() -> void:
	var m := _match(&"apuntado")
	m.start_next_round(Stacked.build([CLOSER, Stacked.junk(1)], "9C"))
	var result := m.draw_from_deck(&"b")
	assert_eq(result.error, Round.Error.NOT_PLAYER_TURN)
	assert_null(result.move)
	assert_eq(m.history().size(), 0)


func test_cierre_invalido_no_liquida() -> void:
	var m := _match(&"apuntado")
	m.start_next_round(Stacked.build(["2S 3S 4S 8H 8D 8C JH QH KH 6D", Stacked.junk(1)], "9C"))
	var result := m.declare_closing(&"a", _id_of(m, &"a", "9C"))
	assert_eq(result.error, Round.Error.INVALID_CLOSING)
	assert_null(result.outcome)
	assert_true(m.settlements().is_empty())


func test_cierre_valido_liquida_en_el_mismo_paso() -> void:
	var m := _match(&"apuntado")
	var result := _a_closes_first(m, [CLOSER, Stacked.junk(1)])
	assert_eq(result.outcome.settlement.delta_of(&"b"), -65)
	assert_eq(m.settlements().size(), 1)
	assert_true(m.can_start_next_round())


func test_no_se_juega_en_una_ronda_ya_liquidada() -> void:
	var m := _match(&"apuntado")
	_a_closes_first(m, [CLOSER, Stacked.junk(1)])
	assert_eq(m.draw_from_deck(&"b").error, Round.Error.ROUND_CLOSED)


# ----------------------------------------------------------------- organizar la mano (RF-02)
func _ids(m: Match, player: StringName, texts: Array) -> Array[int]:
	var out: Array[int] = []
	for t in texts:
		out.append(_id_of(m, player, t))
	return out


func test_check_meld_valida_cartas_de_la_propia_mano_sin_cambiar_nada() -> void:
	var m := _match(&"apuntado")
	m.start_next_round(Stacked.build([CLOSER, Stacked.junk(1)], "9C"))
	var before := m.to_snapshot()
	assert_eq(m.check_meld(&"a", _ids(m, &"a", ["2S", "3S", "4S"])).result, MeldCheck.Result.RUN)
	assert_false(m.check_meld(&"a", _ids(m, &"a", ["2S", "8H", "JH"])).is_valid)
	assert_eq(m.check_meld(&"b", _ids(m, &"b", ["2D", "4C", "6S"])).result, MeldCheck.Result.INVALID,
		"se puede consultar fuera de turno")
	assert_eq_deep(m.to_snapshot(), before)


func test_check_meld_rechaza_cartas_ajenas_o_repetidas() -> void:
	var m := _match(&"apuntado")
	m.start_next_round(Stacked.build([CLOSER, Stacked.junk(1)], "9C"))
	var own := _ids(m, &"a", ["8H", "8D"])
	var foreign: Array[int] = [own[0], own[1], _id_of(m, &"b", "2D")]
	assert_eq(m.check_meld(&"a", foreign).result, MeldCheck.Result.CARD_NOT_IN_HAND)
	var repeated: Array[int] = [own[0], own[0], own[1]]
	assert_eq(m.check_meld(&"a", repeated).result, MeldCheck.Result.CARD_NOT_IN_HAND)


# ----------------------------------------------------------------- Apuntado: acumulación y -101
func test_apuntado_acumula_penalizaciones_entre_rondas() -> void:
	var m := _match(&"apuntado")
	_a_closes_first(m, [CLOSER, Stacked.junk(1)])
	assert_eq(m.scoreboard().total_of(&"a"), 10)
	assert_eq(m.scoreboard().total_of(&"b"), -65)
	assert_eq(m.status, Match.Status.IN_PROGRESS)


func test_la_siguiente_ronda_empieza_con_el_siguiente_jugador() -> void:
	var m := _match(&"apuntado")
	_a_closes_first(m, [CLOSER, Stacked.junk(1)])
	m.start_next_round(Deck.build(2, false))
	assert_eq(m.current_round().current_player_id(), &"b")


func test_apuntado_elimina_exactamente_al_llegar_a_menos_101_y_termina() -> void:
	var m := _match(&"apuntado")
	_a_closes_first(m, [CLOSER, Stacked.junk(1)])
	var result := _a_closes_second(m, PENALTY_36)
	assert_eq(m.scoreboard().total_of(&"b"), -101)
	assert_eq(result.outcome.eliminated, [&"b"] as Array[StringName])
	assert_eq(m.status, Match.Status.FINISHED)
	assert_eq(m.winner_id(), &"a")


func test_apuntado_con_tres_jugadores_sigue_tras_una_eliminacion() -> void:
	var m := _match(&"apuntado", [&"a", &"b", &"c"])
	# Ronda 1: B y C quedan en -65.
	_a_closes_first(m, [CLOSER, Stacked.junk(1), Stacked.junk(2)])
	# Ronda 2 (empieza B con el K♠ extra): B baja a -130, eliminado; C baja a -67.
	m.start_next_round(Stacked.build(
		[Stacked.junk(1), "9H JD KC 9S JH KD 9C JS KH 2D", CLOSER], "KS QS 9C"))
	m.discard(&"b", _id_of(m, &"b", "KS"))
	m.draw_from_deck(&"c")
	m.discard(&"c", _id_of(m, &"c", "QS"))
	m.draw_from_deck(&"a")
	var result := m.declare_closing(&"a", _id_of(m, &"a", "9C"))
	assert_true(result.ok)
	assert_eq(result.outcome.eliminated, [&"b"] as Array[StringName])
	assert_eq(m.status, Match.Status.IN_PROGRESS)
	assert_eq(m.active_player_ids(), [&"a", &"c"] as Array[StringName])
	m.start_next_round(Deck.build(2, false))
	assert_eq(m.current_round().turn_order(), [&"c", &"a"] as Array[StringName], "B ya no juega; empieza C")


# ----------------------------------------------------------------- Clásica
func test_clasica_termina_con_el_primer_cierre_y_gana_quien_cierra() -> void:
	var m := _match(&"classic")
	m.start_next_round(Stacked.build(["7H 7S 7D 7C 3H 4H 5H KC KD KS", Stacked.junk(1)], "9D"))
	var result := m.declare_closing(&"a", _id_of(m, &"a", "9D"))
	assert_true(result.ok)
	assert_true(result.outcome.finished)
	assert_eq(m.status, Match.Status.FINISHED)
	assert_eq(m.winner_id(), &"a")
	assert_false(m.start_next_round(Deck.build(2, false)), "no hay más rondas")


# ----------------------------------------------------------------- snapshot (ADR-04, D-15)
## Partida a mitad de la ronda 2: una liquidación, historial y B (que empieza, con
## 11 cartas) en DISCARD.
func _match_in_progress() -> Match:
	var m := _match(&"apuntado")
	_a_closes_first(m, [CLOSER, Stacked.junk(1)])
	m.start_next_round(Stacked.build([Stacked.junk(1), CLOSER], "KS 9C"))
	return m


func test_snapshot_ida_y_vuelta_conserva_todo_el_estado() -> void:
	var m := _match_in_progress()
	var copy := Match.from_snapshot(m.to_snapshot(), _registry.resolve(&"apuntado"))
	assert_eq_deep(copy.to_snapshot(), m.to_snapshot())
	assert_eq(copy.round_number(), 2)
	assert_eq(copy.scoreboard().total_of(&"b"), -65)
	assert_eq(copy.history().size(), m.history().size())
	assert_eq(copy.current_round().current_phase(), &"DISCARD")


func test_snapshot_sobrevive_a_json() -> void:
	var m := _match_in_progress()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(m.to_snapshot()))
	var copy := Match.from_snapshot(parsed, _registry.resolve(&"apuntado"))
	assert_eq_deep(copy.to_snapshot(), m.to_snapshot())


func test_la_partida_recuperada_sigue_igual_que_la_original() -> void:
	var m := _match_in_progress()
	var copy := Match.from_snapshot(m.to_snapshot(), _registry.resolve(&"apuntado"))
	for game: Match in [m, copy]:
		game.discard(&"b", _id_of(game, &"b", "KS"))
		game.draw_from_deck(&"a")
		assert_true(game.declare_closing(&"a", _id_of(game, &"a", "9C")).ok)
	assert_eq(copy.status, Match.Status.FINISHED, "B llega a -130")
	assert_eq(copy.winner_id(), m.winner_id())
	assert_eq(copy.rng().randi(), m.rng().randi(), "el RNG sigue la misma secuencia")


func test_snapshot_de_otra_version_se_rechaza() -> void:
	var snapshot := _match_in_progress().to_snapshot()
	snapshot["version"] = 99
	assert_null(Match.from_snapshot(snapshot, _registry.resolve(&"apuntado")))
