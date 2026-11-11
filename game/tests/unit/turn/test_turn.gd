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


## A empieza con junk(0) + 9♥ (carta extra); luego el mazo da, en orden, el resto de `draws`.
func _junk_round(mode: StringName = &"apuntado", draws: String = "9H KS KH") -> Round:
	return _round(mode, Stacked.build([Stacked.junk(0), Stacked.junk(1), Stacked.junk(2)], draws))


## A abre la ronda descartando su 9♥: el pozo arranca con esa carta y juega B.
func _opened_round(draws: String = "9H KS KH") -> Round:
	var r := _junk_round(&"apuntado", draws)
	assert_true(r.discard(A, _id_of(r, A, "9H")).ok)
	return r


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
func test_quien_empieza_recibe_11_cartas_y_el_pozo_arranca_vacio() -> void:
	var r := _junk_round()
	assert_eq(r.cards_of(A).size(), 11)
	for p in [B, C]:
		assert_eq(r.cards_of(p).size(), 10)
	assert_null(r.top_discard())
	assert_eq(r.discard_size(), 0)
	assert_eq(r.current_player_id(), A)
	assert_eq(r.current_phase(), &"DISCARD")


func test_start_con_mazo_real_conserva_las_104_cartas() -> void:
	var deck := Deck.build(2, false)
	var r := _round(&"apuntado", deck)
	var total := r.deck_size()
	for p in [A, B, C]:
		total += r.cards_of(p).size()
	assert_eq(total, 104)


# ----------------------------------------------------------------- primer turno
func test_quien_empieza_no_roba() -> void:
	var r := _junk_round()
	assert_eq(r.draw_from_deck(A).error, Round.Error.ACTION_NOT_ALLOWED)
	assert_eq(r.draw_from_discard(A).error, Round.Error.ACTION_NOT_ALLOWED)
	assert_eq(r.cards_of(A).size(), 11)


func test_el_primer_descarte_abre_el_pozo_y_el_siguiente_roba() -> void:
	var r := _opened_round()
	assert_eq(r.cards_of(A).size(), 10)
	assert_eq(str(r.top_discard()), "9♥")
	assert_eq(r.current_player_id(), B)
	assert_eq(r.current_phase(), &"DRAW")


# ----------------------------------------------------------------- turno activo (RD03, RD10)
func test_solo_el_jugador_activo_puede_robar() -> void:
	var r := _opened_round()
	assert_eq(r.draw_from_deck(C).error, Round.Error.NOT_PLAYER_TURN)
	assert_eq(r.cards_of(C).size(), 10)


func test_robar_del_mazo_pasa_a_11_cartas_y_no_permite_robar_otra_vez() -> void:
	var r := _opened_round()
	var result := r.draw_from_deck(B)
	assert_true(result.ok)
	assert_eq(str(result.card), "K♠")
	assert_eq(r.cards_of(B).size(), 11)
	assert_eq(r.draw_from_deck(B).error, Round.Error.ACTION_NOT_ALLOWED)
	assert_eq(r.draw_from_discard(B).error, Round.Error.ACTION_NOT_ALLOWED)


func test_robar_del_pozo_toma_el_tope() -> void:
	var r := _opened_round()
	var result := r.draw_from_discard(B)
	assert_eq(str(result.card), "9♥")
	assert_null(r.top_discard(), "el pozo queda vacío")


func test_la_carta_robada_del_pozo_se_puede_volver_a_descartar() -> void:
	var r := _opened_round()
	r.draw_from_discard(B)
	assert_true(r.discard(B, _id_of(r, B, "9H")).ok)
	assert_true(r.draw_from_discard(C).ok, "C toma el 9♥ que B devolvió")


# ----------------------------------------------------------------- descarte (RD04)
func test_no_se_puede_descartar_sin_robar() -> void:
	var r := _opened_round()
	assert_eq(r.discard(B, _id_of(r, B, "2D")).error, Round.Error.ACTION_NOT_ALLOWED)


func test_descartar_deja_10_cartas_pone_el_tope_y_pasa_el_turno() -> void:
	var r := _opened_round()
	r.draw_from_deck(B)
	var id := _id_of(r, B, "2D")
	assert_true(r.discard(B, id).ok)
	assert_eq(r.cards_of(B).size(), 10)
	assert_eq(r.top_discard().instance_id, id)
	assert_eq(r.current_player_id(), C)


func test_descartar_una_carta_ajena_se_rechaza() -> void:
	var r := _opened_round()
	r.draw_from_deck(B)
	assert_eq(r.discard(B, 99999).error, Round.Error.CARD_NOT_IN_HAND)
	assert_eq(r.current_player_id(), B)


func test_el_turno_rota_en_orden_y_vuelve_al_primero() -> void:
	var r := _opened_round()
	for p in [B, C]:
		r.draw_from_deck(p)
		r.discard(p, r.cards_of(p)[0].instance_id)
	assert_eq(r.current_player_id(), A)
	assert_eq(r.current_phase(), &"DRAW", "desde la segunda vuelta A también roba")


func test_cada_movimiento_queda_registrado() -> void:
	var r := _junk_round()
	watch_signals(r)
	r.discard(A, _id_of(r, A, "9H"))
	r.draw_from_deck(B)
	assert_signal_emit_count(r, "move_performed", 2)
	var move: MoveRecord = get_signal_parameters(r, "move_performed", 1)[0]
	assert_eq(move.action, Turn.Action.DRAW_FROM_DECK)
	assert_eq(move.player_id, B)
	assert_eq(move.sequence, 2)


func test_el_movimiento_lleva_la_carta_visible_y_oculta_la_robada_del_mazo() -> void:
	var r := _junk_round()
	watch_signals(r)
	r.discard(A, _id_of(r, A, "9H"))
	r.draw_from_discard(B)
	r.discard(B, _id_of(r, B, "9H"))
	r.draw_from_deck(C)
	var moves: Array = []
	for i in 4:
		moves.append(get_signal_parameters(r, "move_performed", i)[0])
	assert_eq(str(moves[0].card), "9♥", "descarte: visible")
	assert_eq(str(moves[1].card), "9♥", "tomar del pozo: visible")
	assert_null(moves[3].card, "robar del mazo: secreta")
	assert_eq(moves[3].card_id, -1)


func test_el_movimiento_conserva_su_carta_al_guardarse() -> void:
	var r := _junk_round()
	watch_signals(r)
	r.discard(A, _id_of(r, A, "9H"))
	var move: MoveRecord = get_signal_parameters(r, "move_performed", 0)[0]
	var copy := MoveRecord.from_data(JSON.parse_string(JSON.stringify(move.to_data())))
	assert_eq(str(copy.card), "9♥")
	assert_eq(copy.card_id, move.card_id)


# ----------------------------------------------------------------- mazo agotado
func test_mazo_vacio_se_rellena_con_el_pozo() -> void:
	var r := _opened_round("9H KS")
	r.draw_from_deck(B)
	r.discard(B, _id_of(r, B, "2D"))
	assert_eq(r.deck_size(), 0)
	var result := r.draw_from_deck(C)
	assert_true(result.ok, "toma el 9♥ del fondo del pozo")
	assert_eq(str(r.top_discard()), "2♦", "el tope del pozo se conserva")


# ----------------------------------------------------------------- cierre (RD15, RD16, RD17)
## A empieza con `closer_hand` + `extra` (11 cartas) y puede cerrar en su primer turno.
func _closing_round(mode: StringName, closer_hand: String, extra: String) -> Round:
	return _round(mode, Stacked.build([closer_hand, Stacked.junk(1), Stacked.junk(2)], extra))


func test_no_se_puede_cerrar_sin_robar() -> void:
	var r := _opened_round()
	assert_eq(r.declare_closing(B, _id_of(r, B, "2D")).error, Round.Error.ACTION_NOT_ALLOWED)


func test_cierre_invalido_no_cambia_mano_turno_ni_ronda() -> void:
	var r := _closing_round(&"apuntado", "2S 3S 4S 8H 8D 8C JH QH KH 6D", "9C")
	var result := r.declare_closing(A, _id_of(r, A, "9C"))
	assert_false(result.ok)
	assert_eq(result.error, Round.Error.INVALID_CLOSING)
	assert_eq(result.validation.reason, ValidationResult.Reason.LEFTOVER_TOO_HIGH)
	assert_eq(r.cards_of(A).size(), 11, "la mano no cambia")
	assert_eq(r.current_player_id(), A, "sigue su turno")
	assert_false(r.is_closed())
	assert_true(r.discard(A, _id_of(r, A, "9C")).ok, "puede seguir y descartar")


func test_quien_empieza_puede_cerrar_en_su_primer_descarte() -> void:
	var r := _closing_round(&"apuntado", "2S 3S 4S 8H 8D 8C JH QH KH 4D", "9C")
	var result := r.declare_closing(A, _id_of(r, A, "9C"))
	assert_true(result.ok, result.validation.message)
	assert_true(r.is_closed())
	assert_eq(r.closer_id(), A)
	assert_eq(str(r.top_discard()), "9♣")
	assert_eq(r.draw_from_deck(B).error, Round.Error.ROUND_CLOSED)
	assert_eq(r.declare_closing(A, 0).error, Round.Error.ROUND_CLOSED, "un segundo cierre se rechaza")


func test_clasica_cierre_valido() -> void:
	var r := _closing_round(&"classic", "7H 7S 7D 7C 3H 4H 5H KC KD KS", "9D")
	assert_true(r.declare_closing(A, _id_of(r, A, "9D")).ok)


# ----------------------------------------------------------------- snapshot (ADR-04, D-15)
func test_snapshot_reconstruye_la_ronda_a_mitad_de_turno() -> void:
	var r := _opened_round()
	r.draw_from_deck(B)
	var copy := Round.from_snapshot(r.to_snapshot(), _registry.resolve(&"apuntado"), RandomNumberGenerator.new())
	assert_eq_deep(copy.to_snapshot(), r.to_snapshot())
	assert_eq(copy.current_phase(), &"DISCARD")
	assert_eq(copy.cards_of(B).size(), 11)
	assert_true(copy.discard(B, _id_of(copy, B, "KS")).ok, "sigue jugando desde la fase restaurada")
	assert_eq(copy.current_player_id(), C)
