extends GameRule
## Modalidad Apuntado (RF06, RD06, RD14): se cierra con 3 ternas y un sobrante que
## vale menos de max_leftover_points (5). Las penalizaciones se acumulan entre rondas
## y queda eliminado quien llegue o pase de elimination_threshold (101). Gana el
## último jugador activo. Plug-in de reglas: sin class_name (ADR-03).

const CARDS_PER_PLAYER := 10


func cards_to_deal(_ctx: RoundContext) -> int:
	return CARDS_PER_PLAYER


func is_eliminated(total_score: int) -> bool:
	return total_score >= _settings.elimination_threshold


func is_match_over(ctx: MatchContext) -> bool:
	return ctx.active_players.size() <= 1


func select_winner(ctx: MatchContext) -> StringName:
	var best := &""
	for player_id in ctx.active_players:
		if best == &"" or ctx.total_of(player_id) < ctx.total_of(best):
			best = player_id
	return best


func _closing_pattern(_ctx: RoundContext) -> Array[MeldSpec]:
	return [
		MeldSpec.new(MeldSpec.Type.ANY, 3),
		MeldSpec.new(MeldSpec.Type.ANY, 3),
		MeldSpec.new(MeldSpec.Type.ANY, 3),
	]


func _accepts_leftover(_leftover: Array[Card], points: int) -> bool:
	return points < _settings.max_leftover_points
