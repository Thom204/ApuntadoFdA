extends GutTest
## Al terminar la partida se puede volver al inicio: la mesa pide salir de la sala y,
## cuando el servidor lo confirma, queda vacía para crear o unirse a otra.

const FakeTransport := preload("res://tests/support/fake_client_transport.gd")

var _transport: FakeTransport
var _table: TableView


func before_each() -> void:
	_transport = FakeTransport.new()
	var session := ClientSession.new(_transport, "t")
	_table = TableView.new()
	_table.size = Vector2(1280, 680)
	add_child_autofree(_table)
	_table.bind(session)


func _push(status: String) -> void:
	_transport.push({"event": "turn_changed", "data": {"player_id": "a"}, "view": {
		"match_id": "m-1", "mode": "apuntado", "mode_name": "Apuntado (101)", "status": status,
		"version": 9, "round_number": 3, "round_closed": true, "current_player": "a",
		"phase": "END", "top_discard": null, "deck_size": 20, "discard_size": 0, "winner": "a",
		"you": "a", "is_your_turn": false, "hand": [{"id": 7, "rank": 7, "suit": 0}],
		"players": [
			{"id": "a", "nickname": "Ana", "seat": 0, "active": true, "total": 40, "hand_size": 1, "is_current": false},
			{"id": "b", "nickname": "Beto", "seat": 1, "active": false, "total": 104, "hand_size": 10, "is_current": false},
		],
	}})


func test_partida_terminada_ofrece_volver_al_inicio() -> void:
	_push("FINISHED")
	assert_true(_table._leave_button.visible)
	assert_false(_table._next_round_button.visible)
	_table._leave_button.pressed.emit()
	assert_eq(_transport.last().get("type"), "leave_room")


func test_ronda_cerrada_no_ofrece_salir() -> void:
	_push("IN_PROGRESS")
	assert_false(_table._leave_button.visible)
	assert_true(_table._next_round_button.visible)


func test_al_salir_la_mesa_queda_vacia() -> void:
	_push("FINISHED")
	_transport.respond({"ok": true, "request": "leave_room", "data": {}})
	assert_false(_table._overlay.visible, "sin panel de fin de partida")
	assert_eq(_table._hand.get_child_count(), 0, "sin cartas en la mano")
	assert_false(_table._seats[0].visible, "sin rivales")
