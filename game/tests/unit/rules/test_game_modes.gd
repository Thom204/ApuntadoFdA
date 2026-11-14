extends GutTest
## Reglas concretas: Clásica (4-3-3) y Apuntado (3 ternas + sobrante de máximo 5 o cuarta + 2 ternas, sale quien llega a -101, gana quien llega a +51).

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
func test_apuntado_tocar_con_sobrante_de_4() -> void:
	var hand := Cards.parse("2S 3S 4S 8H 8D 8C JH QH KH 4D 9C")
	var result := _apuntado.validate_closing(hand, _last(hand), _ctx())
	assert_true(result.is_valid, result.message)
	assert_eq(result.leftover_points, 4)


## Checklist de pruebas del E3 (2.3): sobrar exactamente 5 puntos es un cierre inválido.
func test_apuntado_rechaza_sobrante_de_exactamente_5() -> void:
	var hand := Cards.parse("2S 3S 4S 8H 8D 8C JH QH KH 5D 9C")
	var result := _apuntado.validate_closing(hand, _last(hand), _ctx())
	assert_eq(result.reason, ValidationResult.Reason.LEFTOVER_TOO_HIGH, "el sobrante debe ser < 5")
	assert_eq(result.leftover_points, 5)


func test_apuntado_rechaza_sobrante_de_6() -> void:
	var hand := Cards.parse("2S 3S 4S 8H 8D 8C JH QH KH 6D 9C")
	assert_eq(_apuntado.validate_closing(hand, _last(hand), _ctx()).reason, ValidationResult.Reason.LEFTOVER_TOO_HIGH)


func test_apuntado_ganar_completo_con_cuarta_y_dos_ternas() -> void:
	var hand := Cards.parse("7H 7S 7D 7C 3H 4H 5H KC KD KS 9D")
	var result := _apuntado.validate_closing(hand, _last(hand), _ctx())
	assert_true(result.is_valid, result.message)
	assert_eq(result.leftover.size(), 0)
	assert_eq(result.melds.size(), 3)


func test_apuntado_ganar_completo_con_escalera_de_4() -> void:
	var hand := Cards.parse("2S 3S 4S 5S 8H 8D 8C JH QH KH 9C")
	var result := _apuntado.validate_closing(hand, _last(hand), _ctx())
	assert_true(result.is_valid, result.message)
	assert_eq(result.leftover_points, 0, "usa la escalera de 4 en vez de dejar el 2♠ suelto")


func test_apuntado_rechaza_dos_escaleras_de_5() -> void:
	var hand := Cards.parse("2S 3S 4S 5S 6S 8H 9H 10H JH QH 9C")
	assert_eq(_apuntado.validate_closing(hand, _last(hand), _ctx()).reason, ValidationResult.Reason.INCOMPLETE_MELDS)


func test_apuntado_rechaza_ternas_incompletas() -> void:
	var hand := Cards.parse("2S 3S 4S 8H 8D JH QH KD 2D 4C 9C")
	assert_eq(_apuntado.validate_closing(hand, _last(hand), _ctx()).reason, ValidationResult.Reason.INCOMPLETE_MELDS)


func test_apuntado_eliminacion_exacta_en_menos_101() -> void:
	assert_false(_apuntado.is_eliminated(-100))
	assert_true(_apuntado.is_eliminated(-101))
	assert_true(_apuntado.is_eliminated(-130))
	assert_false(_apuntado.is_eliminated(101), "los puntos positivos no eliminan")


func test_apuntado_termina_cuando_queda_un_jugador() -> void:
	assert_false(_apuntado.is_match_over(_match_ctx([&"a", &"b"], {&"a": -40, &"b": -90})))
	assert_true(_apuntado.is_match_over(_match_ctx([&"a"], {&"a": -40, &"b": -120})))
	assert_eq(_apuntado.select_winner(_match_ctx([&"a"], {&"a": -40, &"b": -120})), &"a")


func test_apuntado_gana_quien_llega_a_51() -> void:
	assert_false(_apuntado.is_match_over(_match_ctx([&"a", &"b"], {&"a": 50, &"b": -20})))
	assert_true(_apuntado.is_match_over(_match_ctx([&"a", &"b"], {&"a": 51, &"b": -20})))
	assert_eq(_apuntado.select_winner(_match_ctx([&"a", &"b"], {&"a": 51, &"b": -20})), &"a")


# ----------------------------------------------------------------- puntuación (RD07, RD13)
func test_penalizacion_es_el_valor_de_las_cartas_no_combinadas() -> void:
	var hand := Cards.parse("8H 8D 8C 2S KH 5C")
	assert_eq(_apuntado.penalty_for(hand), 17)


# ----------------------------------------------------------------- organizar la mano (RF-02)
func test_check_meld_caso_01_escalera_aceptada() -> void:
	var check := _apuntado.check_meld(Cards.parse("5H 6H 7H"))
	assert_eq(check.result, MeldCheck.Result.RUN)
	assert_true(check.is_valid)
	assert_eq(check.points, 18)
	assert_string_contains(check.message, "Escalera")


func test_check_meld_caso_02_grupo_rechazado() -> void:
	var check := _apuntado.check_meld(Cards.parse("8H 8C 9S"))
	assert_eq(check.result, MeldCheck.Result.INVALID)
	assert_false(check.is_valid)


func test_check_meld_grupo_del_mismo_valor() -> void:
	var check := _apuntado.check_meld(Cards.parse("7H 7C 7S"))
	assert_eq(check.result, MeldCheck.Result.SET)
	assert_eq(check.points, 21)


func test_check_meld_rechaza_los_ejemplos_de_la_diapositiva() -> void:
	assert_false(_apuntado.check_meld(Cards.parse("4H 5C 6H")).is_valid, "mezcla pinta")
	assert_false(_apuntado.check_meld(Cards.parse("9S 8C 10S")).is_valid)
	assert_false(_apuntado.check_meld(Cards.parse("7H 7C")).is_valid, "menos de 3 cartas")


# ----------------------------------------------------------------- irse a pintas
## 10 corazones sin ninguna combinación (pares de A, 2, 5, 8 y J; baraja doble).
const PINTAS := "2H 2H 5H 5H 8H 8H JH JH AH AH"


func test_apuntado_irse_a_pintas_cierra_sin_combinaciones() -> void:
	var hand := Cards.parse(PINTAS + " 9C")
	var result := _apuntado.validate_closing(hand, _last(hand), _ctx())
	assert_true(result.is_valid, result.message)


func test_irse_a_pintas_suma_25() -> void:
	assert_eq(_apuntado.closer_score_for(Cards.parse(PINTAS)), 25)
	assert_eq(_apuntado.closer_score_for(Cards.parse("2S 3S 4S 8H 8D 8C JH QH KH 4D")), 10)


func test_una_carta_de_otra_pinta_no_es_irse_a_pintas() -> void:
	var hand := Cards.parse("2H 2H 5H 5H 8H 8H JH JH AH AD 9C")
	assert_eq(_apuntado.closer_score_for(hand.slice(0, 10)), 10)
	assert_false(_apuntado.validate_closing(hand, _last(hand), _ctx()).is_valid)


func test_clasica_no_tiene_irse_a_pintas() -> void:
	var hand := Cards.parse(PINTAS + " 9C")
	assert_false(_classic.validate_closing(hand, _last(hand), _ctx()).is_valid)
	assert_eq(_classic.closer_score_for(Cards.parse(PINTAS)), 10)


func test_quien_cierra_suma_10() -> void:
	assert_eq(_apuntado.closer_score_delta(), 10)
	assert_eq(_classic.closer_score_delta(), 10)


func test_ambas_modalidades_reparten_10_cartas() -> void:
	assert_eq(_classic.cards_to_deal(_ctx()), 10)
	assert_eq(_apuntado.cards_to_deal(_ctx()), 10)
