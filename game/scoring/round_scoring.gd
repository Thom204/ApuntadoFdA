class_name RoundScoring
extends RefCounted
## Round Scoring: liquida una ronda cerrada y decide sus consecuencias (eliminación
## por umbral, fin de partida y ganador). Puntaje con signo: positivo es bueno. Es el único lugar donde vive esa política;
## los valores concretos (penalización, umbral, condición de fin) los pone la regla.
## Sin estado: recibe datos y devuelve un SettlementOutcome.


## `hands`: { player_id: Array[Card] } de los jugadores que jugaron la ronda, en
## orden de asiento. `previous`: liquidaciones de las rondas anteriores.
static func settle(round_number: int, closer_id: StringName, hands: Dictionary, rule: GameRule,
		previous: Array[RoundSettlement]) -> SettlementOutcome:
	var settlement := RoundSettlement.new(round_number, closer_id, _deltas(closer_id, hands, rule))
	var all: Array[RoundSettlement] = previous.duplicate()
	all.append(settlement)
	var board := Scoreboard.from_settlements(all)
	var eliminated: Array[StringName] = []
	var remaining: Array[StringName] = []
	for player_id: StringName in hands:
		if rule.is_eliminated(board.total_of(player_id)):
			eliminated.append(player_id)
		else:
			remaining.append(player_id)
	var ctx := MatchContext.new(remaining, board.totals(), all.size(), closer_id)
	var finished := rule.is_match_over(ctx)
	var winner := rule.select_winner(ctx) if finished else &""
	return SettlementOutcome.new(settlement, board, eliminated, finished, winner)


## Quien cerró suma closer_score_for (+10, o +25 si se fue a pintas); a cada perdedor se le resta el valor de
## las cartas que no puede combinar (RD07, RD13).
static func _deltas(closer_id: StringName, hands: Dictionary, rule: GameRule) -> Dictionary:
	var deltas := {}
	for player_id: StringName in hands:
		if player_id == closer_id:
			deltas[player_id] = rule.closer_score_for(hands[player_id])
		else:
			deltas[player_id] = -rule.penalty_for(hands[player_id])
	return deltas
