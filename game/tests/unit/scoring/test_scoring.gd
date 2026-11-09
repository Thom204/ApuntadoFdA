extends GutTest
## Round Scoring: liquidación de una ronda, eliminaciones por umbral y fin de partida.

const Cards := preload("res://tests/support/cards.gd")

## Penalización 36: J-Q-K♥ combinan; 9+8+7+5+3+2+2 quedan sueltas.
const PENALTY_36 := "JH QH KH 9S 8C 7D 5S 3C 2D 2C"
## Penalización 35: igual que PENALTY_36 con un 8♠ en lugar del 9♠.
const PENALTY_35 := "JH QH KH 8S 8C 7D 5S 3C 2D 2C"

var _registry: RuleRegistry


func before_all() -> void:
	_registry = RuleRegistry.new(HandEvaluator.new())
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)


func _settlement(n: int, closer: StringName, deltas: Dictionary) -> RoundSettlement:
	return RoundSettlement.new(n, closer, deltas)


func _hands(by_player: Dictionary) -> Dictionary:
	var out := {}
	for player_id in by_player:
		out[player_id] = Cards.parse(by_player[player_id])
	return out


func _previous(deltas: Dictionary) -> Array[RoundSettlement]:
	var out: Array[RoundSettlement] = [_settlement(1, &"a", deltas)]
	return out


# ----------------------------------------------------------------- value objects
func test_settlement_expone_la_variacion_de_cada_jugador() -> void:
	var s := _settlement(1, &"a", {&"a": -10, &"b": 23})
	assert_eq(s.delta_of(&"a"), -10)
	assert_eq(s.delta_of(&"b"), 23)
	assert_eq(s.delta_of(&"zz"), 0, "un jugador sin fila no cambia")
	assert_eq(s.closer_id, &"a")


func test_settlement_es_inmutable() -> void:
	var s := _settlement(1, &"a", {&"a": -10})
	var deltas := s.deltas
	deltas[&"a"] = 999
	assert_eq(s.delta_of(&"a"), -10)


func test_scoreboard_suma_las_rondas() -> void:
	var board := Scoreboard.from_settlements([
		_settlement(1, &"a", {&"a": -10, &"b": 30}),
		_settlement(2, &"b", {&"a": 15, &"b": -10}),
	])
	assert_eq(board.total_of(&"a"), 5)
	assert_eq(board.total_of(&"b"), 20)


func test_scoreboard_vacio_da_cero() -> void:
	assert_eq(Scoreboard.from_settlements([]).total_of(&"a"), 0)


# ----------------------------------------------------------------- liquidación (RD07, RD13)
func test_settle_resta_10_al_que_cierra_y_penaliza_a_los_demas() -> void:
	var outcome := RoundScoring.settle(1, &"a", _hands({
		&"a": "2S 3S 4S 8H 8D 8C JH QH KH 4D",
		&"b": "9H JD KC 9S JH KD 9C JS KH 2D",
		&"c": "2H 4D 6C 8S 10H QD AC 3S 5H 7D",
	}), _registry.resolve(&"apuntado"), [])
	assert_eq(outcome.settlement.round_number, 1)
	assert_eq(outcome.settlement.closer_id, &"a")
	assert_eq(outcome.settlement.delta_of(&"a"), -10)
	assert_eq(outcome.settlement.delta_of(&"b"), 2, "9-9-9, J-J-J y K-K-K se combinan; solo cuenta el 2♦")
	assert_eq(outcome.settlement.delta_of(&"c"), 2 + 4 + 6 + 8 + 10 + 10 + 10 + 3 + 5 + 7)
	assert_true(outcome.eliminated.is_empty())
	assert_false(outcome.finished)


# ----------------------------------------------------------------- Apuntado: umbral 101 (RD14)
func test_apuntado_elimina_exactamente_al_llegar_a_101_y_termina() -> void:
	var outcome := RoundScoring.settle(2, &"a", _hands({&"a": "", &"b": PENALTY_36}),
		_registry.resolve(&"apuntado"), _previous({&"a": -10, &"b": 65}))
	assert_eq(outcome.scoreboard.total_of(&"b"), 101)
	assert_eq(outcome.eliminated, [&"b"] as Array[StringName])
	assert_true(outcome.finished)
	assert_eq(outcome.winner_id, &"a")


func test_apuntado_con_100_puntos_sigue_en_juego() -> void:
	var outcome := RoundScoring.settle(2, &"a", _hands({&"a": "", &"b": PENALTY_35}),
		_registry.resolve(&"apuntado"), _previous({&"a": -10, &"b": 65}))
	assert_eq(outcome.scoreboard.total_of(&"b"), 100)
	assert_true(outcome.eliminated.is_empty())
	assert_false(outcome.finished)
	assert_eq(outcome.winner_id, &"")


func test_apuntado_con_tres_jugadores_sigue_tras_una_eliminacion() -> void:
	var outcome := RoundScoring.settle(2, &"a", _hands({&"a": "", &"b": PENALTY_36, &"c": PENALTY_36}),
		_registry.resolve(&"apuntado"), _previous({&"a": -10, &"b": 65, &"c": 0}))
	assert_eq(outcome.eliminated, [&"b"] as Array[StringName])
	assert_false(outcome.finished, "quedan A y C")


# ----------------------------------------------------------------- Clásica (RD05)
func test_clasica_termina_con_el_primer_cierre_y_gana_quien_cierra() -> void:
	var outcome := RoundScoring.settle(1, &"b", _hands({&"a": PENALTY_36, &"b": ""}),
		_registry.resolve(&"classic"), [])
	assert_true(outcome.eliminated.is_empty(), "en Clásica nadie se elimina por puntos")
	assert_true(outcome.finished)
	assert_eq(outcome.winner_id, &"b")
