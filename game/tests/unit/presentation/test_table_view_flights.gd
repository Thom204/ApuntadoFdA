extends GutTest
## La mesa anima solo cuando está en pantalla, pero siempre recuerda la última vista:
## así, al volver a mostrarse (otra pestaña en el modo local), la siguiente jugada vuela.

const FakeTransport := preload("res://tests/support/fake_client_transport.gd")

const SEVEN := {"id": 7, "rank": 7, "suit": 0}
const KING := {"id": 13, "rank": 13, "suit": 3}
const ACE := {"id": 1, "rank": 1, "suit": 1}

var _transport: FakeTransport
var _table: TableView


func before_each() -> void:
	_transport = FakeTransport.new()
	var session := ClientSession.new(_transport, "t")
	_table = TableView.new()
	_table.size = Vector2(1280, 680)
	add_child_autofree(_table)
	_table.bind(session)


func _push(version: int, hand: Array, deck: int) -> void:
	_transport.push({"event": "turn_changed", "data": {"player_id": "a"}, "view": {
		"match_id": "m-1", "mode": "apuntado", "mode_name": "Apuntado (101)", "status": "IN_PROGRESS",
		"version": version, "round_number": 1, "round_closed": false, "current_player": "a",
		"phase": "DISCARD", "top_discard": ACE, "deck_size": deck, "discard_size": 1, "winner": "",
		"you": "a", "is_your_turn": true, "hand": hand,
		"players": [
			{"id": "a", "nickname": "Ana", "seat": 0, "active": true, "total": 0, "hand_size": hand.size(), "is_current": true},
			{"id": "b", "nickname": "Beto", "seat": 1, "active": true, "total": 0, "hand_size": 10, "is_current": false},
		],
	}})


func test_robar_hace_volar_una_carta_hacia_la_mano() -> void:
	_push(1, [SEVEN], 20)
	_push(2, [SEVEN, KING], 19)
	assert_eq(_table._fx_layer.get_child_count(), 1, "una carta en vuelo")


func test_una_mesa_oculta_no_anima_pero_recuerda_la_vista() -> void:
	_table.visible = false
	_push(1, [SEVEN], 20)
	_push(2, [SEVEN, KING], 19)
	assert_eq(_table._fx_layer.get_child_count(), 0, "oculta: nada vuela")
	_table.visible = true
	_push(3, [SEVEN, KING, ACE], 18)
	assert_eq(_table._fx_layer.get_child_count(), 1, "visible otra vez: la jugada siguiente vuela")
