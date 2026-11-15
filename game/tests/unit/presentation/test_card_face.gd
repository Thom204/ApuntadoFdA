extends GutTest
## Cómo se muestran las cartas del protocolo ({ id, rank, suit }) y la carta dibujada
## con nodos (CardView).

const CardViewScene := preload("res://presentation/table/card_view.tscn")

const SEVEN_OF_HEARTS := {"id": 10, "rank": 7, "suit": 0}
const KING_OF_SPADES := {"id": 11, "rank": 13, "suit": 3}
const JOKER := {"id": 104, "rank": 0, "suit": -1}


func test_esquina_con_valor_y_palo() -> void:
	assert_eq(CardFace.corner_text(SEVEN_OF_HEARTS), "7♥")
	assert_eq(CardFace.corner_text(KING_OF_SPADES), "K♠")
	assert_eq(CardFace.corner_text({"id": 1, "rank": 1, "suit": 1}), "A♦")


func test_comodin() -> void:
	assert_eq(CardFace.corner_text(JOKER), "★")
	assert_eq(CardFace.center_text(JOKER), "★")
	assert_false(CardFace.is_red(JOKER))


func test_corazones_y_diamantes_son_rojos() -> void:
	assert_true(CardFace.is_red(SEVEN_OF_HEARTS))
	assert_false(CardFace.is_red(KING_OF_SPADES))


func test_ordenar_por_palo_o_por_valor() -> void:
	var two_of_spades := {"id": 1, "rank": 2, "suit": 3}
	var hand := [KING_OF_SPADES, JOKER, SEVEN_OF_HEARTS, two_of_spades]
	var ids_by_suit := CardFace.sorted(hand, true).map(func(c: Dictionary) -> int: return c["id"])
	var ids_by_rank := CardFace.sorted(hand, false).map(func(c: Dictionary) -> int: return c["id"])
	assert_eq(ids_by_suit, [10, 1, 11, 104])
	assert_eq(ids_by_rank, [1, 10, 11, 104])


func test_nombre_para_el_tooltip() -> void:
	assert_eq(CardFace.spoken_name(SEVEN_OF_HEARTS), "7 de corazones")
	assert_eq(CardFace.spoken_name({"id": 2, "rank": 1, "suit": 3}), "As de picas")
	assert_eq(CardFace.spoken_name(JOKER), "Comodín")


func test_cada_carta_numerica_lleva_tantas_pintas_como_su_valor() -> void:
	for rank in range(1, 11):
		assert_eq(CardFace.pip_positions(rank).size(), rank, "pintas del %d" % rank)
	assert_eq(CardFace.pip_positions(12), [], "las figuras no llevan pintas")


func test_las_pintas_son_simetricas_de_arriba_a_abajo() -> void:
	for rank in range(2, 11):
		var pips := CardFace.pip_positions(rank)
		for at in pips:
			var mirrored := Vector2(1.0 - at.x, 1.0 - at.y)
			var found := pips.any(func(p: Vector2) -> bool: return p.is_equal_approx(mirrored))
			# El 7 es la excepción clásica: su pinta central extra va solo arriba.
			if rank != 7 or not at.is_equal_approx(Vector2(0.5, 0.25)):
				assert_true(found, "el %d tiene la pinta %s y su espejo" % [rank, at])


func test_card_view_muestra_la_carta_y_su_reverso() -> void:
	var card: CardView = CardViewScene.instantiate()
	add_child_autofree(card)
	assert_eq(card.size, CardView.CARD_SIZE, "proporción 5:7 de una carta de póker")
	card.show_card(SEVEN_OF_HEARTS)
	assert_eq(card.card_id, 10)
	assert_true(card.is_face_up())
	assert_eq(card.tooltip_text, "7 de corazones")
	card.show_back()
	assert_eq(card.card_id, -1)
	assert_false(card.is_face_up())


func test_card_view_emite_pressed_solo_si_es_interactiva() -> void:
	var card: CardView = CardViewScene.instantiate()
	add_child_autofree(card)
	card.show_card(KING_OF_SPADES)
	watch_signals(card)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	card._gui_input(click)
	assert_signal_not_emitted(card, "pressed")
	card.interactive = true
	card._gui_input(click)
	assert_signal_emitted_with_parameters(card, "pressed", [11])
