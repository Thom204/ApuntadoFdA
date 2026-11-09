extends GameRule
## Modalidad Clásica (RF05, RD05): se cierra con 1 cuarta + 2 ternas + 1 carta de
## descarte, sin sobrante. La partida termina con el primer cierre válido y gana
## quien cerró. Plug-in de reglas: sin class_name (ADR-03).

const CARDS_PER_PLAYER := 10


func cards_to_deal(_ctx: RoundContext) -> int:
	return CARDS_PER_PLAYER


func is_eliminated(_total_score: int) -> bool:
	return false


func is_match_over(ctx: MatchContext) -> bool:
	return ctx.rounds_played >= 1


func select_winner(ctx: MatchContext) -> StringName:
	return ctx.last_closer_id


func _closing_pattern(_ctx: RoundContext) -> Array[MeldSpec]:
	return [
		MeldSpec.new(MeldSpec.Type.ANY, 4),
		MeldSpec.new(MeldSpec.Type.ANY, 3),
		MeldSpec.new(MeldSpec.Type.ANY, 3),
	]


func _accepts_leftover(leftover: Array[Card], _points: int) -> bool:
	return leftover.is_empty()
