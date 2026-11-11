extends GameRule
## Modalidad Apuntado (RF06, RD06, RD14). Dos formas normales de cerrar:
## - Tocar: 3 ternas + 1 carta suelta que vale como máximo max_leftover_points (5).
## - Ganar completo: 1 cuarta + 2 ternas, sin sobrante. El puntaje con signo se acumula entre
## rondas: quien cierra suma +10 y cada perdedor resta sus cartas sueltas. Sale quien
## llega a -elimination_threshold (-101). Gana quien llega a +WIN_TARGET (+51) o el
## último jugador activo. "Irse a pintas" (las 10 cartas de una misma pinta) cierra
## sin combinaciones y suma +PINTAS_SCORE. Plug-in de reglas: sin class_name (ADR-03).

const CARDS_PER_PLAYER := 10
## Puntaje con el que se gana la partida. Es propio de la modalidad, no un parámetro
## de RuleSettings, para no cambiar el contrato v1 (ADR-03, elemento 6).
const WIN_TARGET := 51
## Puntos de "irse a pintas". Constante de la modalidad por la misma razón.
const PINTAS_SCORE := 25


func cards_to_deal(_ctx: RoundContext) -> int:
	return CARDS_PER_PLAYER


func is_eliminated(total_score: int) -> bool:
	return total_score <= -_settings.elimination_threshold


func is_match_over(ctx: MatchContext) -> bool:
	if ctx.active_players.size() <= 1:
		return true
	return ctx.total_of(select_winner(ctx)) >= WIN_TARGET


## El de mayor puntaje entre los activos: quien llegó a +51 o el último que queda.
func select_winner(ctx: MatchContext) -> StringName:
	var best := &""
	for player_id in ctx.active_players:
		if best == &"" or ctx.total_of(player_id) > ctx.total_of(best):
			best = player_id
	return best


## "Irse a pintas": las 10 cartas de la misma pinta (y por tanto del mismo color).
func special_closing_score(cards: Array[Card]) -> int:
	if cards.size() != CARDS_PER_PLAYER:
		return 0
	for c in cards:
		if c.is_joker() or not c.same_suit_as(cards[0]):
			return 0
	return PINTAS_SCORE


func _closing_patterns(ctx: RoundContext) -> Array:
	return [_closing_pattern(ctx), _complete_pattern()]


## Tocar: 3 ternas; la décima carta queda suelta.
func _closing_pattern(_ctx: RoundContext) -> Array[MeldSpec]:
	return [
		MeldSpec.new(MeldSpec.Type.ANY, 3),
		MeldSpec.new(MeldSpec.Type.ANY, 3),
		MeldSpec.new(MeldSpec.Type.ANY, 3),
	]


## Ganar completo: 1 cuarta + 2 ternas = las 10 cartas.
func _complete_pattern() -> Array[MeldSpec]:
	return [
		MeldSpec.new(MeldSpec.Type.ANY, 4),
		MeldSpec.new(MeldSpec.Type.ANY, 3),
		MeldSpec.new(MeldSpec.Type.ANY, 3),
	]


func _accepts_leftover(_leftover: Array[Card], points: int) -> bool:
	return points <= _settings.max_leftover_points
