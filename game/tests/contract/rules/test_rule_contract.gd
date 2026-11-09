extends GutTest
## Batería de contrato (ADR-03, Cumplimiento 1 y 6): se aplica a TODOS los plug-ins
## que RuleRegistry descubre en res://rules/modes/. Un plug-in nuevo queda cubierto
## sin escribir pruebas adicionales.

const Cards := preload("res://tests/support/cards.gd")

var _registry: RuleRegistry


func before_all() -> void:
	_registry = RuleRegistry.new(HandEvaluator.new())
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)


func _rules() -> Array[GameRule]:
	var out: Array[GameRule] = []
	for mode in _registry.available_modes():
		out.append(_registry.resolve(mode))
	return out


func _ctx() -> RoundContext:
	return RoundContext.new(1, [&"a", &"b", &"c"])


func test_se_descubren_plugins() -> void:
	assert_gt(_registry.available_modes().size(), 0)


func test_contract_version_coincide() -> void:
	for rule in _rules():
		assert_eq(rule.contract_version(), GameRule.CONTRACT_VERSION, rule.mode_id())


func test_cards_to_deal_cabe_en_la_baraja_para_cinco_jugadores() -> void:
	for rule in _rules():
		var n := rule.cards_to_deal(_ctx())
		assert_between(n, 1, 20, rule.mode_id())
		assert_lt(n * 5 + 1, 104, "%s: 5 manos + pozo caben en la baraja doble" % rule.mode_id())


func test_validate_closing_rechaza_descarte_ajeno_a_la_mano() -> void:
	for rule in _rules():
		var hand := Cards.parse("2H 3H 4H 5S 6S 7S 9C 9D 9S KH KD")
		var foreign := Cards.one("QC")
		var result := rule.validate_closing(hand, foreign, _ctx())
		assert_false(result.is_valid, rule.mode_id())
		assert_eq(result.reason, ValidationResult.Reason.CARD_NOT_IN_HAND, rule.mode_id())


func test_validate_closing_rechaza_mano_de_tamano_incorrecto() -> void:
	for rule in _rules():
		var hand := Cards.parse("2H 3H 4H 5S 6S 7S 9C 9D 9S KH")
		var result := rule.validate_closing(hand, hand[0], _ctx())
		assert_eq(result.reason, ValidationResult.Reason.WRONG_HAND_SIZE, rule.mode_id())


func test_validate_closing_rechaza_mano_sin_combinaciones() -> void:
	for rule in _rules():
		var hand := Cards.parse("2H 4D 6C 8S 10H QD AC 3S 5H 7D 9C")
		var result := rule.validate_closing(hand, hand[0], _ctx())
		assert_false(result.is_valid, rule.mode_id())
		assert_ne(result.message, "", "%s: el rechazo explica el motivo al jugador" % rule.mode_id())


func test_penalty_for_es_deterministica() -> void:
	for rule in _rules():
		var hand := Cards.parse("2H 3H 4H 9C KD 5S")
		assert_eq(rule.penalty_for(hand), rule.penalty_for(hand), rule.mode_id())


func test_validate_closing_p95_menor_a_150_ms() -> void:
	for rule in _rules():
		var hand := Cards.parse("7H 7S 7D 7C 5H 6H 8H 6S 8S 9S 10D")
		var times: Array[int] = []
		for _i in 20:
			var start := Time.get_ticks_usec()
			rule.validate_closing(hand, hand[10], _ctx())
			times.append(Time.get_ticks_usec() - start)
		times.sort()
		assert_lt(times[18] / 1000.0, 150.0, "%s: p95 de validate_closing" % rule.mode_id())
