@abstract class_name GameRule extends RefCounted
## Contrato v1 de las reglas de juego (ADR-03): Strategy + Template Method.
##
## Cada modalidad es un plug-in en res://rules/modes/<id>/ (regla + plugin.cfg) que
## hereda de esta clase SIN declarar class_name. RuleRegistry lo descubre al arrancar.
## La regla recibe datos (Array[Card], contextos inmutables) y devuelve datos
## (ValidationResult); nunca toca entidades, red ni persistencia (H4).
##
## Cambiar este archivo es cambiar el contrato: exige subir CONTRACT_VERSION y un ADR.

const CONTRACT_VERSION := 1

var _mode_id: StringName
var _settings: RuleSettings
var _evaluator: HandEvaluator


## Lo invoca RuleRegistry al instanciar el plug-in.
func configure(mode_id: StringName, settings: RuleSettings, evaluator: HandEvaluator) -> void:
	_mode_id = mode_id
	_settings = settings
	_evaluator = evaluator


func mode_id() -> StringName:
	return _mode_id


func contract_version() -> int:
	return CONTRACT_VERSION


# ======================================================================= métodos abstractos
@abstract func cards_to_deal(ctx: RoundContext) -> int
@abstract func is_eliminated(total_score: int) -> bool
@abstract func is_match_over(ctx: MatchContext) -> bool
@abstract func select_winner(ctx: MatchContext) -> StringName
@abstract func _closing_pattern(ctx: RoundContext) -> Array[MeldSpec]
@abstract func _accepts_leftover(leftover: Array[Card], points: int) -> bool


# ======================================================================= Template Method
## Valida un cierre: `cards` es la mano completa (cards_to_deal + 1) y `discard` la
## carta que el jugador baja al pozo para cerrar.
func validate_closing(cards: Array[Card], discard: Card, ctx: RoundContext) -> ValidationResult:
	if cards.size() != cards_to_deal(ctx) + 1:
		return ValidationResult.reject(ValidationResult.Reason.WRONG_HAND_SIZE)
	if not _contains(cards, discard):
		return ValidationResult.reject(ValidationResult.Reason.CARD_NOT_IN_HAND)
	var rest := _without(cards, [discard])
	if special_closing_score(rest) > 0:
		return ValidationResult.accept([], [], 0)
	var best := _best_closing(rest, ctx)
	if best.is_empty():
		return ValidationResult.reject(ValidationResult.Reason.INCOMPLETE_MELDS)
	if not _accepts_leftover(best["leftover"], best["points"]):
		return ValidationResult.reject(ValidationResult.Reason.LEFTOVER_TOO_HIGH, best["leftover"], best["points"])
	return ValidationResult.accept(best["melds"], best["leftover"], best["points"])


## Patrones de cierre que acepta la modalidad. Por defecto, solo _closing_pattern();
## una modalidad con varias formas de cerrar (Apuntado: tocar o ganar completo) lo
## redefine. Gancho opcional.
func _closing_patterns(ctx: RoundContext) -> Array:
	return [_closing_pattern(ctx)]


## Entre todos los patrones que se pueden cumplir, el que deja el sobrante de menor
## valor: {melds, leftover, points}. Vacío si no se cumple ninguno.
func _best_closing(rest: Array[Card], ctx: RoundContext) -> Dictionary:
	var best := {}
	for pattern: Array[MeldSpec] in _closing_patterns(ctx):
		var melds := _evaluator.best_melds(rest, pattern, _settings.card_values)
		if melds.is_empty():
			continue
		var leftover := _leftover_of(rest, melds)
		var points := _evaluator.points_of(leftover, _settings.card_values)
		if best.is_empty() or points < best["points"]:
			best = {"melds": melds, "leftover": leftover, "points": points}
	return best


## Consulta de solo lectura (RF-02): ¿`cards` forman un grupo o una escalera válidos?
## Sirve para organizar la mano; no cambia nada.
func check_meld(cards: Array[Card]) -> MeldCheck:
	var points := _evaluator.points_of(cards, _settings.card_values)
	match _evaluator.meld_type(cards):
		MeldSpec.Type.SET:
			return MeldCheck.new(MeldCheck.Result.SET, cards.size(), points)
		MeldSpec.Type.RUN:
			return MeldCheck.new(MeldCheck.Result.RUN, cards.size(), points)
	return MeldCheck.new(MeldCheck.Result.INVALID, cards.size(), points)


## Penalización de un perdedor: valor (positivo) de las cartas que no puede combinar
## (RD07). RoundScoring se la resta del total.
func penalty_for(cards: Array[Card]) -> int:
	return _evaluator.min_leftover_points(cards, _settings.card_values)


## Puntos que suma quien cierra (RD13). El puntaje tiene signo: positivo es bueno.
func closer_score_delta() -> int:
	return _settings.closer_score_delta


## Cierre especial que no exige combinaciones (p. ej. "irse a pintas" en Apuntado):
## devuelve sus puntos, o 0 si `cards` (la mano sin el descarte) no lo forma. Gancho
## opcional: por defecto ninguna modalidad lo tiene.
func special_closing_score(_cards: Array[Card]) -> int:
	return 0


## Puntos de quien cerró con `cards` (su mano tras descartar): los del cierre especial
## si lo formó; si no, closer_score_delta().
func closer_score_for(cards: Array[Card]) -> int:
	var special := special_closing_score(cards)
	return special if special > 0 else closer_score_delta()


# ======================================================================= utilidades
func _leftover_of(cards: Array[Card], melds: Array[Meld]) -> Array[Card]:
	var used: Array = []
	for m in melds:
		used.append_array(m.cards)
	return _without(cards, used)


func _contains(cards: Array[Card], card: Card) -> bool:
	if card == null:
		return false
	for c in cards:
		if c.instance_id == card.instance_id:
			return true
	return false


func _without(cards: Array[Card], removed: Array) -> Array[Card]:
	var out: Array[Card] = []
	for c in cards:
		if not _contains(_typed(removed), c):
			out.append(c)
	return out


func _typed(cards: Array) -> Array[Card]:
	var out: Array[Card] = []
	out.assign(cards)
	return out
