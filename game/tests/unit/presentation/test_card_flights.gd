extends GutTest
## Qué cartas vuelan entre dos vistas (TableView.plan_moves). Se deduce solo de las vistas,
## así que vale igual para tus jugadas, las de los rivales y los turnos automáticos.

const SEVEN := {"id": 7, "rank": 7, "suit": 0}
const KING := {"id": 13, "rank": 13, "suit": 3}
const ACE := {"id": 1, "rank": 1, "suit": 1}


func _view(hand: Array, deck: int, discard: int, top: Variant, rival_cards: int, round_number := 1) -> Dictionary:
	return {
		"match_id": "m-1", "round_number": round_number, "you": "a",
		"hand": hand, "deck_size": deck, "discard_size": discard, "top_discard": top,
		"players": [
			{"id": "a", "hand_size": hand.size()},
			{"id": "b", "hand_size": rival_cards},
		],
	}


func test_robar_del_mazo_vuela_del_mazo_a_tu_mano() -> void:
	var moves := TableView.plan_moves(_view([SEVEN], 20, 1, ACE, 10), _view([SEVEN, KING], 19, 1, ACE, 10))
	assert_eq(moves, [{"kind": "draw_me", "card": KING, "from": "deck"}])


func test_robar_del_pozo_vuela_del_pozo_a_tu_mano() -> void:
	var moves := TableView.plan_moves(_view([SEVEN], 20, 1, ACE, 10), _view([SEVEN, ACE], 20, 0, null, 10))
	assert_eq(moves, [{"kind": "draw_me", "card": ACE, "from": "discard"}])


func test_descartar_vuela_de_tu_mano_al_pozo() -> void:
	var moves := TableView.plan_moves(_view([SEVEN, KING], 19, 1, ACE, 10), _view([SEVEN], 19, 2, KING, 10))
	assert_eq(moves, [{"kind": "discard_me", "card": KING}])


func test_un_rival_roba_del_pozo_y_se_lleva_la_carta_de_arriba() -> void:
	var moves := TableView.plan_moves(_view([SEVEN], 19, 2, KING, 10), _view([SEVEN], 19, 1, ACE, 11))
	assert_eq(moves, [{"kind": "draw_other", "player": "b", "from": "discard", "card": KING}])


func test_un_rival_descarta_y_la_carta_queda_arriba_del_pozo() -> void:
	var moves := TableView.plan_moves(_view([SEVEN], 19, 1, ACE, 11), _view([SEVEN], 19, 2, KING, 10))
	assert_eq(moves, [{"kind": "discard_other", "player": "b", "card": KING}])


func test_una_ronda_nueva_no_anima_el_reparto() -> void:
	var moves := TableView.plan_moves(_view([SEVEN], 19, 1, ACE, 10), _view([KING, ACE], 30, 1, SEVEN, 10, 2))
	assert_eq(moves, [])


func test_sin_vista_anterior_no_hay_nada_que_animar() -> void:
	assert_eq(TableView.plan_moves({}, _view([SEVEN], 20, 1, ACE, 10)), [])
