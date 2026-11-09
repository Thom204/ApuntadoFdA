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
	var melds := _evaluator.best_melds(rest, _closing_pattern(ctx), _settings.card_values)
	if melds.is_empty():
		return ValidationResult.reject(ValidationResult.Reason.INCOMPLETE_MELDS)
	var leftover := _leftover_of(rest, melds)
	var points := _evaluator.points_of(leftover, _settings.card_values)
	if not _accepts_leftover(leftover, points):
		return ValidationResult.reject(ValidationResult.Reason.LEFTOVER_TOO_HIGH, leftover, points)
	return ValidationResult.accept(melds, leftover, points)


## Penalización de un perdedor: valor de las cartas que no puede combinar (RD07).
func penalty_for(cards: Array[Card]) -> int:
	return _evaluator.min_leftover_points(cards, _settings.card_values)


## Variación de puntaje de quien cierra (RD13). Con puntaje alto = malo, es negativa.
func closer_score_delta() -> int:
	return _settings.closer_score_delta


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
