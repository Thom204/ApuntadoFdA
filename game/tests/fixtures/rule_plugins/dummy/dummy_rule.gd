extends GameRule
## Plug-in mínimo de prueba: demuestra que una variante nueva se carga sin tocar el núcleo.

func cards_to_deal(_ctx: RoundContext) -> int:
	return 7


func is_eliminated(_total_score: int) -> bool:
	return false


func is_match_over(ctx: MatchContext) -> bool:
	return ctx.rounds_played >= 1


func select_winner(ctx: MatchContext) -> StringName:
	return ctx.last_closer_id


func _closing_pattern(_ctx: RoundContext) -> Array[MeldSpec]:
	return [MeldSpec.new(MeldSpec.Type.ANY, 3), MeldSpec.new(MeldSpec.Type.ANY, 3)]


func _accepts_leftover(leftover: Array[Card], _points: int) -> bool:
	return leftover.is_empty()
