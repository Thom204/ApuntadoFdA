extends GutTest
## Deck Management: Card, Deck, DiscardPile y Hand.


func _card(id: int, rank: int, suit: int) -> Card:
	return Card.new(id, rank, suit)


# ----------------------------------------------------------------- Card
func test_card_follows_detecta_rango_consecutivo_del_mismo_palo() -> void:
	var six := _card(1, Card.Rank.SIX, Card.Suit.HEARTS)
	var seven := _card(2, Card.Rank.SEVEN, Card.Suit.HEARTS)
	var seven_spades := _card(3, Card.Rank.SEVEN, Card.Suit.SPADES)
	assert_true(seven.follows(six))
	assert_false(seven_spades.follows(six), "distinto palo no es consecutivo")
	assert_false(six.follows(seven))


func test_card_same_rank_y_same_suit() -> void:
	var a := _card(1, Card.Rank.KING, Card.Suit.CLUBS)
	var b := _card(2, Card.Rank.KING, Card.Suit.HEARTS)
	assert_true(a.same_rank_as(b))
	assert_false(a.same_suit_as(b))


func test_card_joker() -> void:
	assert_true(_card(1, Card.Rank.JOKER, Card.Suit.NONE).is_joker())
	assert_false(_card(2, Card.Rank.ACE, Card.Suit.CLUBS).is_joker())


func test_card_texto_corto() -> void:
	assert_eq(str(_card(1, Card.Rank.TEN, Card.Suit.HEARTS)), "10♥")
	assert_eq(str(_card(2, Card.Rank.ACE, Card.Suit.SPADES)), "A♠")
	assert_eq(str(_card(3, Card.Rank.JOKER, Card.Suit.NONE)), "JOKER")


# ----------------------------------------------------------------- Deck
func test_deck_doble_sin_comodines_tiene_104_cartas_con_ids_unicos() -> void:
	var deck := Deck.build(2, false)
	assert_eq(deck.size(), 104)
	var ids := {}
	for c in deck.deal(104):
		ids[c.instance_id] = true
	assert_eq(ids.size(), 104)


func test_deck_doble_con_comodines_tiene_108_cartas() -> void:
	assert_eq(Deck.build(2, true).size(), 108)


func test_deck_barajado_es_deterministico_con_la_misma_semilla() -> void:
	var a := Deck.build(2, false)
	var b := Deck.build(2, false)
	a.shuffle(_rng(42))
	b.shuffle(_rng(42))
	assert_eq(_ids(a.deal(10)), _ids(b.deal(10)))


func test_deck_draw_y_deal_reducen_el_tamano() -> void:
	var deck := Deck.build(1, false)
	deck.draw()
	assert_eq(deck.size(), 51)
	assert_eq(deck.deal(10).size(), 10)
	assert_eq(deck.size(), 41)


func test_deck_draw_vacio_devuelve_null() -> void:
	var deck := Deck.build(1, false)
	deck.deal(52)
	assert_true(deck.is_empty())
	assert_null(deck.draw())


func test_deck_refill_recupera_el_pozo_sin_el_tope() -> void:
	var deck := Deck.build(1, false)
	var pile := DiscardPile.new()
	for c in deck.deal(52):
		pile.push(c)
	var top := pile.peek_top()
	deck.refill_from(pile, _rng(1))
	assert_eq(deck.size(), 51)
	assert_eq(pile.peek_top(), top, "el tope del pozo se conserva")
	assert_eq(pile.size(), 1)


# ----------------------------------------------------------------- DiscardPile
func test_discard_pile_push_peek_take() -> void:
	var pile := DiscardPile.new()
	assert_true(pile.is_empty())
	assert_null(pile.peek_top())
	var a := _card(1, Card.Rank.TWO, Card.Suit.CLUBS)
	var b := _card(2, Card.Rank.THREE, Card.Suit.CLUBS)
	pile.push(a)
	pile.push(b)
	assert_eq(pile.peek_top(), b)
	assert_eq(pile.take_top(), b)
	assert_eq(pile.peek_top(), a)


# ----------------------------------------------------------------- Hand
func test_hand_add_find_take() -> void:
	var hand := Hand.new(&"p1")
	var a := _card(7, Card.Rank.FIVE, Card.Suit.HEARTS)
	hand.add(a)
	assert_eq(hand.size(), 1)
	assert_eq(hand.find(7), a)
	assert_null(hand.find(99))
	assert_eq(hand.take(7), a)
	assert_eq(hand.size(), 0)
	assert_null(hand.take(7), "tomar una carta ausente devuelve null")


func test_hand_cards_devuelve_una_copia() -> void:
	var hand := Hand.new(&"p1")
	hand.add(_card(1, Card.Rank.FIVE, Card.Suit.HEARTS))
	var copy := hand.cards()
	copy.clear()
	assert_eq(hand.size(), 1, "modificar la copia no altera la mano")


# ----------------------------------------------------------------- utilidades
func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _ids(cards: Array[Card]) -> Array:
	var out := []
	for c in cards:
		out.append(c.instance_id)
	return out
