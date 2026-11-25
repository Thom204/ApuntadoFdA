extends GutTest
## LocalServer + LocalTransport + ClientSession: el camino completo del cliente al
## Lobby real en el mismo proceso, como lo usará la mesa local (hot seat).

const RecordingRepository := preload("res://tests/support/recording_repository.gd")

var _server: LocalServer
var _ana: ClientSession
var _beto: ClientSession


func before_each() -> void:
	var registry := RuleRegistry.new(HandEvaluator.new())
	registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	_server = LocalServer.new(Lobby.new(registry, RecordingRepository.new()))
	_ana = ClientSession.new(_server.connect_player(&"a"), "a")
	_beto = ClientSession.new(_server.connect_player(&"b"), "b")


func _start() -> void:
	_ana.create_room("Ana", &"apuntado")
	_beto.join_room(str(_ana.room["room_code"]), "Beto")
	_ana.start_match()
	await wait_process_frames(1)


func test_crear_y_unirse_deja_a_los_dos_en_la_misma_sala() -> void:
	_ana.create_room("Ana", &"apuntado")
	_beto.join_room(str(_ana.room["room_code"]), "Beto")
	await wait_process_frames(1)
	assert_eq(_ana.room["players"].size(), 2, "Ana se entera por room_updated")
	assert_eq(_beto.room["room_id"], _ana.room["room_id"])


func test_al_empezar_cada_uno_ve_solo_su_mano() -> void:
	await _start()
	assert_true(_ana.has_match())
	assert_true(_beto.has_match(), "Beto recibe la vista por round_started")
	assert_eq(_ana.my_id(), "a")
	assert_eq(_beto.my_id(), "b")
	assert_ne(_ana.view["hand"], _beto.view["hand"])


## Quien abre la ronda empieza con una carta de más y en fase de descarte.
func test_una_jugada_llega_al_otro_jugador() -> void:
	await _start()
	var player := _ana if _ana.is_my_turn() else _beto
	var other := _beto if player == _ana else _ana
	assert_eq(player.phase(), "DISCARD")
	var card: Dictionary = player.view["hand"][0]
	player.discard(int(card["id"]))
	await wait_process_frames(1)
	assert_eq(other.view["top_discard"], card, "el rival ve el descarte en el pozo")
	assert_true(other.is_my_turn())
	assert_eq(other.phase(), "DRAW")


func test_jugar_fuera_de_turno_se_rechaza_con_mensaje() -> void:
	await _start()
	var waiting := _beto if _ana.is_my_turn() else _ana
	var failures := []
	waiting.request_failed.connect(func(r: Dictionary) -> void: failures.append(r))
	waiting.draw_from_deck()
	assert_eq(failures.size(), 1)
	assert_ne(str(failures[0]["message"]), "")
