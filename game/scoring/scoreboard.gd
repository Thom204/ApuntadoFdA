class_name Scoreboard
extends RefCounted
## Marcador acumulado (value object). No se almacena: se deriva de las liquidaciones,
## igual que la vista v_cumulative_score (fuente única de verdad, ADR-04).

var _totals: Dictionary = {}


static func from_settlements(settlements: Array) -> Scoreboard:
	var board := Scoreboard.new()
	for s: RoundSettlement in settlements:
		for player_id in s.deltas:
			board._totals[player_id] = board.total_of(player_id) + s.delta_of(player_id)
	return board


func total_of(player_id: StringName) -> int:
	return int(_totals.get(player_id, 0))


func totals() -> Dictionary:
	return _totals.duplicate()
