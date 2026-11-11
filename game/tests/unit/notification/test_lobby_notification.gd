extends GutTest
## Lobby Notification: lo único que el armado del servidor conecta. Avisa a los miembros
## de una sala cuando la sala cambia y conecta la notificación de cada partida, de modo
## que los eventos de juego llegan solo a los jugadores de esa sala.

const Stacked := preload("res://tests/support/stacked_deck.gd")
const RecordingRepository := preload("res://tests/support/recording_repository.gd")
const RecordingChannel := preload("res://tests/support/recording_channel.gd")

const CLOSER := "2S 3S 4S 8H 8D 8C JH QH KH 4D"

var _channel: RecordingChannel
var _lobby: Lobby
var _lobby_notification: LobbyNotification
var _decks: Array[Deck] = []
var _action := 0


func before_each() -> void:
	_channel = RecordingChannel.new()
	_decks = []
	var registry := RuleRegistry.new(HandEvaluator.new())
	registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	_lobby = Lobby.new(registry, RecordingRepository.new(),
		func(config: MatchConfig, _rng: RandomNumberGenerator) -> Deck:
			return _decks.pop_front() if not _decks.is_empty() else Deck.build(config.deck_count, false))
	_lobby_notification = LobbyNotification.new(_lobby, _channel)


func _req(player_id: StringName, type: String, fields: Dictionary = {}) -> Dictionary:
	_action += 1
	var request := {"type": type, "action_id": "n-%d" % _action}
	request.merge(fields, true)
	return _lobby.handle(player_id, request)


func _room_with(players: Array) -> String:
	var room_id: String = _req(players[0], "create_room", {"nickname": "Ana", "mode": "apuntado"})["data"]["room"]["room_id"]
	for p in players.slice(1):
		_req(p, "join_room", {"room_id": room_id, "nickname": String(p)})
	return room_id


func test_entrar_a_la_sala_avisa_a_todos_sus_miembros() -> void:
	_room_with([&"a", &"b"])
	await wait_process_frames(1)
	for player_id in [&"a", &"b"]:
		var last: Dictionary = _channel.to(player_id).back()
		assert_eq(last["event"], "room_updated", String(player_id))
		assert_eq(last["data"]["players"].size(), 2)


func test_los_eventos_de_la_partida_llegan_a_los_jugadores_de_la_sala() -> void:
	_room_with([&"a", &"b"])
	_decks.append(Stacked.build([CLOSER, Stacked.junk(1)], "9C"))
	_req(&"a", "start_match")
	await wait_process_frames(1)
	for player_id in [&"a", &"b"]:
		var events := _channel.events_to(player_id)
		assert_has(events, "round_started", String(player_id))
		assert_has(events, "turn_changed", String(player_id))
	var to_b: Array = _channel.to(&"b").filter(func(m: Dictionary) -> bool: return m["event"] == "round_started")
	assert_eq(to_b[0]["view"]["you"], "b")


func test_los_eventos_de_una_sala_no_llegan_a_otra() -> void:
	_room_with([&"a", &"b"])
	_room_with([&"c", &"d"])
	_req(&"a", "start_match")
	await wait_process_frames(1)
	assert_false(_channel.events_to(&"c").has("round_started"))
	assert_false(_channel.events_to(&"c").has("turn_changed"))
