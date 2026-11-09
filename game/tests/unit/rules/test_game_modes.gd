extends GutTest
## Reglas concretas: Clásica (4-3-3) y Apuntado (3 ternas, sobrante < 5, eliminación en 101).

const Cards := preload("res://tests/support/cards.gd")

var _classic: GameRule
var _apuntado: GameRule


func before_all() -> void:
	var registry := RuleRegistry.new(HandEvaluator.new())
	registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	_classic = registry.resolve(&"classic")
	_apuntado = registry.resolve(&"apuntado")


func _ctx() -> RoundContext:
	return RoundContext.new(1, [&"a", &"b"])


func _match_ctx(active: Array, totals: Dictionary, closer: StringName = &"", rounds: int = 1) -> MatchContext:
	var typed: Array[StringName] = []
	typed.assign(active)
	return MatchContext.new(typed, totals, rounds, closer)


func _last(cards: Array[Card]) -> Card:
	return cards[cards.size() - 1]


# ----------------------------------------------------------------- Clásica (RF05, RD05)
func test_clasica_cierre_valido_cuarta_dos_ternas_y_descarte() -> void:
	var hand := Cards.parse("7H 7S 7D 7C 3H 4H 5H KC KD KS 9D")
	var result := _classic.validate_closing(hand, _last(hand), _ctx())
	assert_true(result.is_valid, result.message)
	assert_eq(result.melds.size(), 3)
	assert_eq(result.leftover.size(), 0)


func test_clasica_rechaza_tres_ternas_sin_cuarta() -> void:
	var hand := Cards.parse("7H 7S 7D 3H 4H 5H KC KD KS 2C 9D")
	var result := _classic.validate_closing(hand, _last(hand), _ctx())
	assert_false(result.is_valid)
	assert_eq(result.reason, ValidationResult.Reason.INCOMPLETE_MELDS)


func test_clasica_rechaza_si_el_descarte_era_necesario_para_la_cuarta() -> void:
	var hand := Cards.parse("7H 7S 7D 7C 3H 4H 5H KC KD KS 9D")
	var result := _classic.validate_closing(hand, hand[0], _ctx())
	assert_false(result.is_valid, "sin el 7♥ no hay cuarta")


func test_clasica_nunca_elimina_y_termina_con_el_primer_cierre() -> void:
	assert_false(_classic.is_eliminated(500))
	assert_true(_classic.is_match_over(_match_ctx([&"a", &"b"], {}, &"a", 1)))
	assert_eq(_classic.select_winner(_match_ctx([&"a", &"b"], {}, &"b", 1)), &"b")


# ----------------------------------------------------------------- Apuntado (RF06, RD06)
func test_apuntado_cierre_valido_con_sobrante_menor_a_5() -> void:
	var hand := Cards.parse("2S 3S 4S 8H 8D 8C JH QH KH 4D 9C")
	var result := _apuntado.validate_closing(hand, _last(hand), _ctx())
	assert_true(result.is_valid, result.message)
	assert_eq(result.leftover_points, 4)


func test_apuntado_rechaza_sobrante_de_exactamente_5() -> void:
	var hand := Cards.parse("2S 3S 4S 8H 8D 8C JH QH KH 5D 9C")
	var result := _apuntado.validate_closing(hand, _last(hand), _ctx())
	assert_false(result.is_valid)
	assert_eq(result.reason, ValidationResult.Reason.LEFTOVER_TOO_HIGH)
	assert_eq(result.leftover_points, 5)


func test_apuntado_rechaza_sobrante_de_6() -> void:
	var hand := Cards.parse("2S 3S 4S 8H 8D 8C JH QH KH 6D 9C")
	assert_eq(_apuntado.validate_closing(hand, _last(hand), _ctx()).reason, ValidationResult.Reason.LEFTOVER_TOO_HIGH)


func test_apuntado_rechaza_ternas_incompletas() -> void:
	var hand := Cards.parse("2S 3S 4S 8H 8D JH QH KD 2D 4C 9C")
	assert_eq(_apuntado.validate_closing(hand, _last(hand), _ctx()).reason, ValidationResult.Reason.INCOMPLETE_MELDS)


func test_apuntado_elige_la_descomposicion_que_permite_cerrar() -> void:
	# Con 2-3-4-5♠ debe usar 3-4-5♠ y dejar el 2♠ (2 pts) para que el cierre sea válido.
	var hand := Cards.parse("2S 3S 4S 5S 8H 8D 8C JH QH KH 9C")
	var result := _apuntado.validate_closing(hand, _last(hand), _ctx())
	assert_true(result.is_valid, result.message)
	assert_eq(result.leftover_points, 2)


func test_apuntado_eliminacion_exacta_en_101() -> void:
	assert_false(_apuntado.is_eliminated(100))
	assert_true(_apuntado.is_eliminated(101))
	assert_true(_apuntado.is_eliminated(130))


func test_apuntado_termina_cuando_queda_un_jugador() -> void:
	assert_false(_apuntado.is_match_over(_match_ctx([&"a", &"b"], {&"a": 40, &"b": 90})))
	assert_true(_apuntado.is_match_over(_match_ctx([&"a"], {&"a": 40, &"b": 120})))
	assert_eq(_apuntado.select_winner(_match_ctx([&"a"], {&"a": 40, &"b": 120})), &"a")


# ----------------------------------------------------------------- puntuación (RD07, RD13)
func test_penalizacion_es_el_valor_de_las_cartas_no_combinadas() -> void:
	var hand := Cards.parse("8H 8D 8C 2S KH 5C")
	assert_eq(_apuntado.penalty_for(hand), 17)


func test_quien_cierra_resta_10() -> void:
	assert_eq(_apuntado.closer_score_delta(), -10)
	assert_eq(_classic.closer_score_delta(), -10)


func test_ambas_modalidades_reparten_10_cartas() -> void:
	assert_eq(_classic.cards_to_deal(_ctx()), 10)
	assert_eq(_apuntado.cards_to_deal(_ctx()), 10)
