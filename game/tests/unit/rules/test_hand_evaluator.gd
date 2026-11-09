extends GutTest
## Hand Evaluation: valores de cartas y búsqueda de combinaciones (ternas y cuartas).

const H := Card.Suit.HEARTS
const D := Card.Suit.DIAMONDS
const C := Card.Suit.CLUBS
const S := Card.Suit.SPADES

var _next_id := 0
var _eval: HandEvaluator
var _values: CardValueTable


func before_each() -> void:
	_next_id = 0
	_eval = HandEvaluator.new()
	_values = CardValueTable.standard()


func _c(rank: int, suit: int) -> Card:
	_next_id += 1
	return Card.new(_next_id, rank, suit)


func _hand(specs: Array) -> Array[Card]:
	var out: Array[Card] = []
	for s in specs:
		out.append(_c(s[0], s[1]))
	return out


func _pattern(sizes: Array) -> Array[MeldSpec]:
	var out: Array[MeldSpec] = []
	for n in sizes:
		out.append(MeldSpec.new(MeldSpec.Type.ANY, n))
	return out


func _covered(melds: Array[Meld]) -> int:
	var n := 0
	for m in melds:
		n += m.cards.size()
	return n


# ----------------------------------------------------------------- valores (RD12)
func test_valores_estandar_letras_valen_10_y_comodin_0() -> void:
	var cards := _hand([[Card.Rank.ACE, H], [Card.Rank.FIVE, S], [Card.Rank.KING, C], [Card.Rank.JOKER, Card.Suit.NONE]])
	assert_eq(_eval.points_of(cards, _values), 25)


func test_valores_numericos_valen_su_numero() -> void:
	assert_eq(_values.value_of(_c(Card.Rank.SEVEN, H)), 7)
	assert_eq(_values.value_of(_c(Card.Rank.TEN, H)), 10)
	assert_eq(_values.value_of(_c(Card.Rank.QUEEN, H)), 10)


# ----------------------------------------------------------------- combinaciones válidas (RD11)
func test_is_valid_meld_terna_del_mismo_valor_con_palos_mezclados() -> void:
	assert_true(_eval.is_valid_meld(_hand([[Card.Rank.NINE, H], [Card.Rank.NINE, S], [Card.Rank.NINE, H]])))


func test_is_valid_meld_escalera_del_mismo_palo() -> void:
	assert_true(_eval.is_valid_meld(_hand([[Card.Rank.FOUR, D], [Card.Rank.FIVE, D], [Card.Rank.SIX, D], [Card.Rank.SEVEN, D]])))


func test_is_valid_meld_rechaza_escalera_de_palos_distintos() -> void:
	assert_false(_eval.is_valid_meld(_hand([[Card.Rank.FOUR, D], [Card.Rank.FIVE, H], [Card.Rank.SIX, D]])))


func test_is_valid_meld_as_alto_y_bajo_pero_sin_vuelta() -> void:
	assert_true(_eval.is_valid_meld(_hand([[Card.Rank.ACE, S], [Card.Rank.TWO, S], [Card.Rank.THREE, S]])), "A-2-3")
	assert_true(_eval.is_valid_meld(_hand([[Card.Rank.QUEEN, S], [Card.Rank.KING, S], [Card.Rank.ACE, S]])), "Q-K-A")
	assert_false(_eval.is_valid_meld(_hand([[Card.Rank.KING, S], [Card.Rank.ACE, S], [Card.Rank.TWO, S]])), "K-A-2 no")


func test_is_valid_meld_rechaza_dos_cartas_y_comodines() -> void:
	assert_false(_eval.is_valid_meld(_hand([[Card.Rank.NINE, H], [Card.Rank.NINE, S]])))
	assert_false(_eval.is_valid_meld(_hand([[Card.Rank.NINE, H], [Card.Rank.NINE, S], [Card.Rank.JOKER, Card.Suit.NONE]])))


# ----------------------------------------------------------------- patrón clásico [4, 3, 3]
func test_best_melds_patron_clasico_cubre_las_diez_cartas() -> void:
	var cards := _hand([
		[Card.Rank.SEVEN, H], [Card.Rank.SEVEN, S], [Card.Rank.SEVEN, D], [Card.Rank.SEVEN, C],
		[Card.Rank.THREE, H], [Card.Rank.FOUR, H], [Card.Rank.FIVE, H],
		[Card.Rank.KING, C], [Card.Rank.KING, D], [Card.Rank.KING, S],
	])
	var melds := _eval.best_melds(cards, _pattern([4, 3, 3]), _values)
	assert_eq(melds.size(), 3)
	assert_eq(_covered(melds), 10)


func test_best_melds_cuarta_puede_ser_escalera() -> void:
	var cards := _hand([
		[Card.Rank.NINE, C], [Card.Rank.TEN, C], [Card.Rank.JACK, C], [Card.Rank.QUEEN, C],
		[Card.Rank.TWO, H], [Card.Rank.TWO, S], [Card.Rank.TWO, D],
		[Card.Rank.FIVE, S], [Card.Rank.SIX, S], [Card.Rank.SEVEN, S],
	])
	assert_eq(_eval.best_melds(cards, _pattern([4, 3, 3]), _values).size(), 3)


func test_best_melds_devuelve_vacio_si_el_patron_no_se_cumple() -> void:
	var cards := _hand([
		[Card.Rank.SEVEN, H], [Card.Rank.SEVEN, S], [Card.Rank.SEVEN, D],
		[Card.Rank.THREE, H], [Card.Rank.FOUR, H], [Card.Rank.FIVE, H],
		[Card.Rank.KING, C], [Card.Rank.KING, D], [Card.Rank.KING, S], [Card.Rank.TWO, C],
	])
	assert_eq(_eval.best_melds(cards, _pattern([4, 3, 3]), _values).size(), 0, "no hay cuarta")


func test_best_melds_resuelve_cartas_compartidas_entre_terna_y_escalera() -> void:
	# El 5♥ cabe en la cuarta 5-6-7-8♥ o en la terna de cincos; solo la segunda cierra:
	# JJJJ + 5♥5♠5♦ + 6-7-8♥.
	var cards := _hand([
		[Card.Rank.FIVE, H], [Card.Rank.SIX, H], [Card.Rank.SEVEN, H], [Card.Rank.EIGHT, H],
		[Card.Rank.FIVE, S], [Card.Rank.FIVE, D],
		[Card.Rank.JACK, C], [Card.Rank.JACK, D], [Card.Rank.JACK, S], [Card.Rank.JACK, H],
	])
	var melds := _eval.best_melds(cards, _pattern([4, 3, 3]), _values)
	assert_eq(melds.size(), 3)
	assert_eq(_covered(melds), 10)


# ----------------------------------------------------------------- patrón Apuntado [3, 3, 3]
func test_best_melds_apuntado_minimiza_el_sobrante() -> void:
	# Con 10 cartas y 3 ternas sobra 1. Hay dos opciones: dejar el K (10) o el 2 (2).
	var cards := _hand([
		[Card.Rank.TWO, S], [Card.Rank.THREE, S], [Card.Rank.FOUR, S],
		[Card.Rank.EIGHT, H], [Card.Rank.EIGHT, D], [Card.Rank.EIGHT, C],
		[Card.Rank.JACK, H], [Card.Rank.QUEEN, H], [Card.Rank.KING, H],
		[Card.Rank.FIVE, S],
	])
	var melds := _eval.best_melds(cards, _pattern([3, 3, 3]), _values)
	assert_eq(melds.size(), 3)
	var used := {}
	for m in melds:
		for c in m.cards:
			used[c.instance_id] = true
	var leftover := []
	for c in cards:
		if not used.has(c.instance_id):
			leftover.append(c)
	assert_eq(leftover.size(), 1)
	assert_eq(leftover[0].rank, Card.Rank.TWO, "3-4-5♠ deja el 2♠ (2 pts) en lugar de otra carta")


# ----------------------------------------------------------------- sobrante libre (penalización)
func test_min_leftover_points_descuenta_las_combinaciones() -> void:
	var cards := _hand([
		[Card.Rank.EIGHT, H], [Card.Rank.EIGHT, D], [Card.Rank.EIGHT, C],
		[Card.Rank.TWO, S], [Card.Rank.KING, H], [Card.Rank.FIVE, C],
	])
	assert_eq(_eval.min_leftover_points(cards, _values), 2 + 10 + 5)


func test_min_leftover_points_usa_escaleras_largas() -> void:
	var cards := _hand([
		[Card.Rank.TWO, D], [Card.Rank.THREE, D], [Card.Rank.FOUR, D], [Card.Rank.FIVE, D], [Card.Rank.SIX, D],
		[Card.Rank.NINE, S],
	])
	assert_eq(_eval.min_leftover_points(cards, _values), 9)


func test_min_leftover_points_sin_combinaciones_suma_todo() -> void:
	var cards := _hand([[Card.Rank.TWO, D], [Card.Rank.KING, S], [Card.Rank.SEVEN, H]])
	assert_eq(_eval.min_leftover_points(cards, _values), 19)


# ----------------------------------------------------------------- rendimiento (RNF 2)
func test_best_melds_mano_de_diez_cartas_en_menos_de_150_ms() -> void:
	var cards := _hand([
		[Card.Rank.SEVEN, H], [Card.Rank.SEVEN, S], [Card.Rank.SEVEN, D], [Card.Rank.SEVEN, C],
		[Card.Rank.FIVE, H], [Card.Rank.SIX, H], [Card.Rank.EIGHT, H],
		[Card.Rank.SIX, S], [Card.Rank.EIGHT, S], [Card.Rank.NINE, S],
	])
	var start := Time.get_ticks_msec()
	_eval.best_melds(cards, _pattern([3, 3, 3]), _values)
	_eval.min_leftover_points(cards, _values)
	assert_lt(Time.get_ticks_msec() - start, 150)
