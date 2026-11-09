class_name MatchConfig
extends RefCounted
## Configuración de una partida antes de iniciarla (Match Setup, RF01).
##
## MVP: admite de 2 a 5 jugadores en el mismo dispositivo. RD01 exige exactamente
## 5; se relaja para las pruebas con usuarios y se documenta como deriva.

const MIN_PLAYERS := 2
const MAX_PLAYERS := 5

## Identificador del plug-in de reglas (catálogo abierto, ADR-03).
var mode: StringName
## [{ "id": StringName, "nickname": String }] en orden de asiento.
var players: Array[Dictionary]
## Null = valores por defecto del plug-in.
var settings: RuleSettings
var deck_count: int = 2
## 0 = barajado aleatorio; otro valor reproduce la partida.
var rng_seed: int = 0


func _init(p_mode: StringName, p_players: Array[Dictionary], p_settings: RuleSettings = null) -> void:
	mode = p_mode
	players = p_players.duplicate(true)
	settings = p_settings


func is_valid() -> bool:
	if mode == &"" or players.size() < MIN_PLAYERS or players.size() > MAX_PLAYERS:
		return false
	var ids := {}
	for p in players:
		ids[StringName(p.get("id", ""))] = true
	return ids.size() == players.size() and not ids.has(&"")
