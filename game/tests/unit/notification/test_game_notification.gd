extends GutTest
## Game Notification (ADR-05, decisión 3): se suscribe a IGameEvents con CONNECT_DEFERRED
## y envía a cada jugador, por IPlayerChannel, el evento y SU vista de la mesa (RNF 3).

const Cards := preload("res://tests/support/cards.gd")
const Stacked := preload("res://tests/support/stacked_deck.gd")
const RecordingRepository := preload("res://tests/support/recording_repository.gd")
const RecordingChannel := preload("res://tests/support/recording_channel.gd")
const JsonCheck := preload("res://tests/support/json_check.gd")

const CLOSER := "2S 3S 4S 8H 8D 8C JH QH KH 4D"

var _repo: RecordingRepository
var _channel: RecordingChannel
var _decks: Array[Deck] = []
var _orch: MatchOrchestrator
var _game_notification: GameNotification


func before_each() -> void:
	_repo = RecordingRepository.new()
	_channel = RecordingChannel.new()
	_decks = []
	var registry := RuleRegistry.new(HandEvaluator.new())
	registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	_orch = MatchOrchestrator.new(registry, _repo,
		func(config: MatchConfig, _rng: RandomNumberGenerator) -> Deck:
			return _decks.pop_front() if not _decks.is_empty() else Deck.build(config.deck_count, false))
	_game_notification = GameNotification.new(_orch, _channel)


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


func test_cada_evento_llega_a_cada_jugador_con_su_propia_vista() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	await wait_process_frames(1)
	for player_id in [&"a", &"b"]:
		assert_eq(_channel.events_to(player_id), ["round_started", "turn_changed"], String(player_id))
		for message in _channel.to(player_id):
			assert_eq(message["view"]["you"], String(player_id))
	assert_eq(_channel.to(&"a")[0]["view"]["hand"].size(), 11)
	assert_eq(_channel.to(&"b")[0]["view"]["hand"].size(), 10)


func test_los_mensajes_salen_despues_de_que_el_comando_responde() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	await wait_process_frames(1)
	var before := _channel.sent.size()
	assert_true(_orch.discard(&"a", _id(&"a", "9C")).ok)
	assert_eq(_channel.sent.size(), before, "CONNECT_DEFERRED: nada se envía dentro del comando")
	await wait_process_frames(1)
	assert_eq(_channel.events_to(&"b").slice(2), ["move_performed", "turn_changed"])


func test_si_falla_el_guardado_no_se_notifica_nada() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	await wait_process_frames(1)
	var before := _channel.sent.size()
	_repo.fail = true
	_orch.discard(&"a", _id(&"a", "9C"))
	await wait_process_frames(1)
	assert_eq(_channel.sent.size(), before)


func test_el_cierre_publica_la_liquidacion_a_todos() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	assert_true(_orch.declare_closing(&"a", _id(&"a", "9C")).ok)
	await wait_process_frames(1)
	var closed: Array = _channel.to(&"b").filter(func(m: Dictionary) -> bool: return m["event"] == "round_closed")
	assert_eq(closed.size(), 1)
	var settlement: Dictionary = closed[0]["data"]["settlement"]
	assert_eq(settlement["closer_id"], "a")
	assert_eq(settlement["deltas"]["a"], 10)
	assert_eq(settlement["deltas"]["b"], -65)
	assert_true(closed[0]["data"]["closing"]["valid"])


func test_un_descarte_publica_la_carta_y_un_robo_del_mazo_no() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C KS")
	_orch.discard(&"a", _id(&"a", "9C"))
	_orch.draw_from_deck(&"b")
	await wait_process_frames(1)
	var moves: Array = _channel.to(&"a").filter(func(m: Dictionary) -> bool: return m["event"] == "move_performed")
	assert_eq(moves[0]["data"]["action"], "DISCARD")
	assert_eq(moves[0]["data"]["card"]["label"], "9♣", "el descarte queda a la vista")
	assert_eq(moves[1]["data"]["action"], "DRAW_FROM_DECK")
	assert_null(moves[1]["data"]["card"], "la carta robada del mazo es secreta")
	assert_false(moves[0]["data"]["automatic"])


func test_un_turno_automatico_se_anuncia_como_tal() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	_orch.play_automatic_turn(&"a")
	await wait_process_frames(1)
	var moves: Array = _channel.to(&"b").filter(func(m: Dictionary) -> bool: return m["event"] == "move_performed")
	assert_true(moves[0]["data"]["automatic"], "el cliente puede mostrar que jugó el servidor")


func test_todos_los_mensajes_son_json() -> void:
	_start([CLOSER, Stacked.junk(1)], "9C")
	_orch.declare_closing(&"a", _id(&"a", "9C"))
	await wait_process_frames(1)
	for s in _channel.sent:
		assert_true(JsonCheck.is_json_safe(s["message"]), str(s["message"]))
