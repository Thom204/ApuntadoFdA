extends GutTest
## Turno automático (D-12): cuando el turno de un jugador vence, el servidor juega por
## él. Roba del mazo (o del pozo si el mazo está vacío) y descarta la carta que robó;
## si ya estaba en fase de descarte, descarta la última carta de su mano. La jugada
## queda marcada como automática, se guarda antes de anunciarse (ADR-05) y, con
## MAX_AUTOMATIC_TURNS turnos automáticos seguidos, el jugador queda eliminado al
## liquidarse la ronda.

const Cards := preload("res://tests/support/cards.gd")
const Stacked := preload("res://tests/support/stacked_deck.gd")
const RecordingRepository := preload("res://tests/support/recording_repository.gd")

## Mano de A que cierra en Apuntado con el 9♣ (sobrante 4♦).
const CLOSER := "2S 3S 4S 8H 8D 8C JH QH KH 4D"

var _repo: RecordingRepository
var _decks: Array[Deck] = []
var _orch: MatchOrchestrator


func before_each() -> void:
	_repo = RecordingRepository.new()
	_decks = []
	var registry := RuleRegistry.new(HandEvaluator.new())
	registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	_orch = MatchOrchestrator.new(registry, _repo,
		func(config: MatchConfig, _rng: RandomNumberGenerator) -> Deck:
			return _decks.pop_front() if not _decks.is_empty() else Deck.build(config.deck_count, false))


func _start(hands: Array, draws: String) -> void:
	_decks.append(Stacked.build(hands, draws))
	var players: Array[Dictionary] = [{"id": &"a", "nickname": "A"}, {"id": &"b", "nickname": "B"}]
	assert_true(_orch.create_match(MatchConfig.new(&"apuntado", players)).ok)


func _id(player: StringName, text: String) -> int:
	var wanted := Cards.one(text)
	for c in _orch.hand_of(player):
		if c.rank == wanted.rank and c.suit == wanted.suit:
			return c.instance_id
	return -1


func _top_discard() -> Dictionary:
	return _orch.view_for(&"a")["top_discard"]


## A juega a mano: roba del mazo y descarta lo que robó.
func _a_plays_by_hand() -> void:
	assert_true(_orch.draw_from_deck(&"a").ok)
	var drawn: Card = _orch.hand_of(&"a").back()
	assert_true(_orch.discard(&"a", drawn.instance_id).ok)


# ----------------------------------------------------------------- qué juega
func test_en_su_turno_de_apertura_descarta_la_ultima_carta_de_su_mano() -> void:
	_start([CLOSER, Stacked.junk(1)], "KD")
	var result := _orch.play_automatic_turn(&"a")
	assert_true(result.ok, str(result.error))
	assert_eq(_orch.hand_of(&"a").size(), 10)
	assert_eq(_top_discard()["label"], "K♦", "la carta extra que recibió al empezar")
	assert_eq(_orch.view_for(&"a")["current_player"], "b")


func test_en_fase_de_robo_roba_del_mazo_y_descarta_lo_que_robo() -> void:
	_start([CLOSER, Stacked.junk(1)], "KD KC")
	_orch.discard(&"a", _id(&"a", "KD"))
	var hand_before := _orch.hand_of(&"b").map(func(c: Card) -> int: return c.instance_id)
	assert_true(_orch.play_automatic_turn(&"b").ok)
	assert_eq(_orch.hand_of(&"b").map(func(c: Card) -> int: return c.instance_id), hand_before, "su mano no cambia")
	assert_eq(_top_discard()["label"], "K♣")
	assert_eq(_orch.view_for(&"a")["current_player"], "a")


func test_las_jugadas_quedan_marcadas_como_automaticas() -> void:
	_start([CLOSER, Stacked.junk(1)], "KD KC")
	_orch.discard(&"a", _id(&"a", "KD"))
	_orch.play_automatic_turn(&"b")
	var moves := _orch.history()
	assert_false(moves[0].automatic, "el descarte de A fue a mano")
	assert_true(moves[1].automatic)
	assert_true(moves[2].automatic)
	assert_eq(moves[1].action_name(), "DRAW_FROM_DECK")
	assert_eq(moves[2].action_name(), "DISCARD")


func test_solo_juega_por_quien_tiene_el_turno() -> void:
	_start([CLOSER, Stacked.junk(1)], "KD")
	var result := _orch.play_automatic_turn(&"b")
	assert_false(result.ok)
	assert_eq(result.error, &"NOT_PLAYER_TURN")
	assert_eq(_orch.history().size(), 0)


func test_se_guarda_antes_de_anunciarse() -> void:
	_start([CLOSER, Stacked.junk(1)], "KD")
	watch_signals(_orch)
	_repo.fail = true
	var result := _orch.play_automatic_turn(&"a")
	assert_eq(result.error, &"PERSISTENCE_FAILED")
	assert_signal_not_emitted(_orch, "move_performed")
	assert_eq(_orch.hand_of(&"a").size(), 11, "el estado vuelve al último guardado")


# ----------------------------------------------------------------- eliminación por inactividad
func test_tres_turnos_automaticos_seguidos_eliminan_al_liquidar_la_ronda() -> void:
	_start([CLOSER, Stacked.junk(1)], "KD KC 2H 6C 10D QS 9C")
	watch_signals(_orch)
	_orch.discard(&"a", _id(&"a", "KD"))
	for i in Match.MAX_AUTOMATIC_TURNS:
		assert_true(_orch.play_automatic_turn(&"b").ok)
		if i < Match.MAX_AUTOMATIC_TURNS - 1:
			_a_plays_by_hand()
	assert_true(_orch.draw_from_deck(&"a").ok)
	assert_true(_orch.declare_closing(&"a", _id(&"a", "9C")).ok)
	assert_signal_emitted_with_parameters(_orch, "player_eliminated", [&"b"])
	assert_signal_emitted_with_parameters(_orch, "match_finished", [&"a"])


func test_una_jugada_a_mano_reinicia_la_racha() -> void:
	_start([CLOSER, Stacked.junk(1)], "KD KC 2H 6C 10D QS 5H 7S 9C")
	watch_signals(_orch)
	_orch.discard(&"a", _id(&"a", "KD"))
	_orch.play_automatic_turn(&"b")
	_a_plays_by_hand()
	assert_true(_orch.draw_from_deck(&"b").ok)
	assert_true(_orch.discard(&"b", _orch.hand_of(&"b").back().instance_id).ok, "B vuelve y juega a mano")
	_a_plays_by_hand()
	_orch.play_automatic_turn(&"b")
	_a_plays_by_hand()
	_orch.play_automatic_turn(&"b")
	_orch.draw_from_deck(&"a")
	assert_true(_orch.declare_closing(&"a", _id(&"a", "9C")).ok)
	assert_signal_not_emitted(_orch, "player_eliminated", "solo 2 automáticos seguidos")
