extends GutTest
## Turn Orchestration: fases del turno (State) y reglas de la ronda (RD03, RD04,
## RD10, RD15, RD16, RD17, invariante de conservación de cartas).

const Cards := preload("res://tests/support/cards.gd")
const Stacked := preload("res://tests/support/stacked_deck.gd")

const A := &"a"
const B := &"b"
const C := &"c"

var _registry: RuleRegistry


func before_all() -> void:
	_registry = RuleRegistry.new(HandEvaluator.new())
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)


func _round(mode: StringName, deck: Deck, players: Array = [A, B, C]) -> Round:
	var order: Array[StringName] = []
	order.assign(players)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var r := Round.new(1, _registry.resolve(mode), order, rng)
	r.start(deck)
	return r


func _junk_round(mode: StringName = &"apuntado", draws: String = "KS KH") -> Round:
	return _round(mode, Stacked.build([Stacked.junk(0), Stacked.junk(1), Stacked.junk(2)], "9H", draws))


func _id_of(r: Round, player: StringName, text: String) -> int:
	var wanted := Cards.one(text)
	for c in r.cards_of(player):
		if c.rank == wanted.rank and c.suit == wanted.suit:
			return c.instance_id
	return -1


# ----------------------------------------------------------------- fases (State)
func test_fases_draw_discard_end() -> void:
	var phase: TurnPhase = DrawPhase.new()
	assert_true(phase.allows(Turn.Action.DRAW_FROM_DECK))
	assert_true(phase.allows(Turn.Action.DRAW_FROM_DISCARD))
	assert_false(phase.allows(Turn.Action.DISCARD))
	assert_false(phase.allows(Turn.Action.DECLARE_CLOSING))
	phase = phase.next(Turn.Action.DRAW_FROM_DECK)
	assert_true(phase is DiscardPhase)
	assert_true(phase.allows(Turn.Action.DISCARD))
	assert_true(phase.allows(Turn.Action.DECLARE_CLOSING))
	assert_false(phase.allows(Turn.Action.DRAW_FROM_DECK))
	phase = phase.next(Turn.Action.DISCARD)
	assert_true(phase is EndPhase)
	assert_false(phase.allows(Turn.Action.DRAW_FROM_DECK))


# ----------------------------------------------------------------- reparto
func test_start_reparte_10_cartas_y_abre_el_pozo() -> void:
	var r := _junk_round()
	for p in [A, B, C]:
		assert_eq(r.cards_of(p).size(), 10)
	assert_eq(str(r.top_discard()), "9♥")
	assert_eq(r.current_player_id(), A)


func test_start_con_mazo_real_conserva_las_104_cartas() -> void:
	var deck := Deck.build(2, false)
	var r := _round(&"apuntado", deck)
	var total := r.deck_size() + 1
	for p in [A, B, C]:
		total += r.cards_of(p).size()
	assert_eq(total, 104)


# ----------------------------------------------------------------- turno activo (RD03, RD10)
func test_solo_el_jugador_activo_puede_robar() -> void:
	var r := _junk_round()
	assert_eq(r.draw_from_deck(B).error, Round.Error.NOT_PLAYER_TURN)
	assert_eq(r.cards_of(B).size(), 10)


func test_robar_del_mazo_pasa_a_11_cartas_y_no_permite_robar_otra_vez() -> void:
	var r := _junk_round()
	var result := r.draw_from_deck(A)
	assert_true(result.ok)
	assert_eq(str(result.card), "K♠")
	assert_eq(r.cards_of(A).size(), 11)
	assert_eq(r.draw_from_deck(A).error, Round.Error.ACTION_NOT_ALLOWED)
	assert_eq(r.draw_from_discard(A).error, Round.Error.ACTION_NOT_ALLOWED)


func test_robar_del_pozo_toma_el_tope() -> void:
	var r := _junk_round()
	var result := r.draw_from_discard(A)
	assert_eq(str(result.card), "9♥")
	assert_null(r.top_discard(), "el pozo queda vacío")


func test_la_carta_robada_del_pozo_se_puede_volver_a_descartar() -> void:
	var r := _junk_round()
	r.draw_from_discard(A)
	assert_true(r.discard(A, _id_of(r, A, "9H")).ok)
	assert_true(r.draw_from_discard(B).ok, "B toma el 9♥ que A devolvió")


# ----------------------------------------------------------------- descarte (RD04)
func test_no_se_puede_descartar_sin_robar() -> void:
	var r := _junk_round()
	assert_eq(r.discard(A, _id_of(r, A, "2H")).error, Round.Error.ACTION_NOT_ALLOWED)


func test_descartar_deja_10_cartas_pone_el_tope_y_pasa_el_turno() -> void:
	var r := _junk_round()
	r.draw_from_deck(A)
	var id := _id_of(r, A, "2H")
	assert_true(r.discard(A, id).ok)
	assert_eq(r.cards_of(A).size(), 10)
	assert_eq(r.top_discard().instance_id, id)
	assert_eq(r.current_player_id(), B)


func test_descartar_una_carta_ajena_se_rechaza() -> void:
	var r := _junk_round()
	r.draw_from_deck(A)
	assert_eq(r.discard(A, 99999).error, Round.Error.CARD_NOT_IN_HAND)
	assert_eq(r.current_player_id(), A)


func test_el_turno_rota_en_orden_y_vuelve_al_primero() -> void:
	var r := _junk_round(&"apuntado", "KS KH QS")
	for p in [A, B, C]:
		r.draw_from_deck(p)
		r.discard(p, r.cards_of(p)[0].instance_id)
	assert_eq(r.current_player_id(), A)


func test_cada_movimiento_queda_registrado() -> void:
	var r := _junk_round()
	watch_signals(r)
	r.draw_from_deck(A)
	r.discard(A, _id_of(r, A, "2H"))
	assert_signal_emit_count(r, "move_performed", 2)
	var move: MoveRecord = get_signal_parameters(r, "move_performed", 1)[0]
	assert_eq(move.action, Turn.Action.DISCARD)
	assert_eq(move.player_id, A)
	assert_eq(move.sequence, 2)


# ----------------------------------------------------------------- mazo agotado
func test_mazo_vacio_se_rellena_con_el_pozo() -> void:
	var r := _junk_round(&"apuntado", "KS")
	r.draw_from_deck(A)
	r.discard(A, _id_of(r, A, "2H"))
	assert_eq(r.deck_size(), 0)
	var result := r.draw_from_deck(B)
	assert_true(result.ok, "toma el 9♥ del fondo del pozo")
	assert_eq(str(r.top_discard()), "2♥", "el tope del pozo se conserva")


# ----------------------------------------------------------------- cierre (RD15, RD16, RD17)
func _closing_round(mode: StringName, closer_hand: String, draw: String) -> Round:
	return _round(mode, Stacked.build([closer_hand, Stacked.junk(1), Stacked.junk(2)], "9H", draw))


func test_no_se_puede_cerrar_sin_robar() -> void:
	var r := _closing_round(&"apuntado", "2S 3S 4S 8H 8D 8C JH QH KH 4D", "9C")
	assert_eq(r.declare_closing(A, _id_of(r, A, "4D")).error, Round.Error.ACTION_NOT_ALLOWED)


func test_cierre_invalido_no_cambia_mano_turno_ni_ronda() -> void:
	var r := _closing_round(&"apuntado", "2S 3S 4S 8H 8D 8C JH QH KH 6D", "9C")
	r.draw_from_deck(A)
	var result := r.declare_closing(A, _id_of(r, A, "9C"))
	assert_false(result.ok)
	assert_eq(result.error, Round.Error.INVALID_CLOSING)
	assert_eq(result.validation.reason, ValidationResult.Reason.LEFTOVER_TOO_HIGH)
	assert_eq(r.cards_of(A).size(), 11, "la mano no cambia")
	assert_eq(r.current_player_id(), A, "sigue su turno")
	assert_false(r.is_closed())
	assert_true(r.discard(A, _id_of(r, A, "9C")).ok, "puede seguir y descartar")


func test_cierre_valido_cierra_la_ronda_y_bloquea_acciones() -> void:
	var r := _closing_round(&"apuntado", "2S 3S 4S 8H 8D 8C JH QH KH 4D", "9C")
	r.draw_from_deck(A)
	var result := r.declare_closing(A, _id_of(r, A, "9C"))
	assert_true(result.ok, result.validation.message)
	assert_true(r.is_closed())
	assert_eq(r.closer_id(), A)
	assert_eq(str(r.top_discard()), "9♣")
	assert_eq(r.draw_from_deck(B).error, Round.Error.ROUND_CLOSED)
	assert_eq(r.declare_closing(A, 0).error, Round.Error.ROUND_CLOSED, "un segundo cierre se rechaza")


func test_clasica_cierre_valido() -> void:
	var r := _closing_round(&"classic", "7H 7S 7D 7C 3H 4H 5H KC KD KS", "9D")
	r.draw_from_deck(A)
	assert_true(r.declare_closing(A, _id_of(r, A, "9D")).ok)


# ----------------------------------------------------------------- snapshot (ADR-04, D-15)
func test_snapshot_reconstruye_la_ronda_a_mitad_de_turno() -> void:
	var r := _junk_round()
	r.draw_from_deck(A)
	var copy := Round.from_snapshot(r.to_snapshot(), _registry.resolve(&"apuntado"), RandomNumberGenerator.new())
	assert_eq_deep(copy.to_snapshot(), r.to_snapshot())
	assert_eq(copy.current_phase(), &"DISCARD")
	assert_eq(copy.cards_of(A).size(), 11)
	assert_true(copy.discard(A, _id_of(copy, A, "KS")).ok, "sigue jugando desde la fase restaurada")
	assert_eq(copy.current_player_id(), B)
