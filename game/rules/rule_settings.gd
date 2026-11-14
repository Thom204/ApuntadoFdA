class_name RuleSettings
extends RefCounted
## Parámetros de una regla (datos, no comportamiento). Los valores por defecto salen
## de la sección [defaults] del plugin.cfg y la partida puede sobrescribirlos.
## Son exactamente las columnas que persiste match_session (ADR-03, elemento 6).

## Puntos negativos acumulados con los que un jugador sale: total <= -umbral.
var elimination_threshold: int = 101
## Valor máximo (inclusivo) que puede sumar el sobrante de un cierre. Apuntado: 4, es decir,
## sobrante < 5 puntos (E3: sobrar exactamente 5 es inválido).
var max_leftover_points: int = 4
## Puntos que suma quien cierra la ronda (RD13).
var closer_score_delta: int = 10
var jokers_enabled: bool = false
var card_values: CardValueTable = CardValueTable.standard()


static func from_dictionary(values: Dictionary) -> RuleSettings:
	var s := RuleSettings.new()
	s.elimination_threshold = int(values.get("elimination_threshold", s.elimination_threshold))
	s.max_leftover_points = int(values.get("max_leftover_points", s.max_leftover_points))
	s.closer_score_delta = int(values.get("closer_score_delta", s.closer_score_delta))
	s.jokers_enabled = bool(values.get("jokers_enabled", s.jokers_enabled))
	return s


func to_dictionary() -> Dictionary:
	return {
		"elimination_threshold": elimination_threshold,
		"max_leftover_points": max_leftover_points,
		"closer_score_delta": closer_score_delta,
		"jokers_enabled": jokers_enabled,
	}
