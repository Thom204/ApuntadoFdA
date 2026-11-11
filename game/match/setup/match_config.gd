class_name MatchConfig
extends RefCounted
## Configuración de una partida antes de iniciarla (Match Setup, RF01).
##
## MVP: admite de 2 a 5 jugadores en el mismo dispositivo. RD01 exige exactamente
## 5; se relaja para las pruebas con usuarios y se documenta como deriva.

const MIN_PLAYERS := 2
const MAX_PLAYERS := 5
## Hasta este número de jugadores alcanza una baraja de 52; con más se usan dos.
const SINGLE_DECK_MAX_PLAYERS := 4

## Identificador del plug-in de reglas (catálogo abierto, ADR-03).
var mode: StringName
## [{ "id": StringName, "nickname": String }] en orden de asiento.
var players: Array[Dictionary]
## Null = valores por defecto del plug-in.
var settings: RuleSettings
## Barajas de 52 cartas. Por defecto, según el número de jugadores (decks_for).
var deck_count: int = 2
## 0 = barajado aleatorio; otro valor reproduce la partida.
var rng_seed: int = 0


func _init(p_mode: StringName, p_players: Array[Dictionary], p_settings: RuleSettings = null) -> void:
	mode = p_mode
	players = p_players.duplicate(true)
	settings = p_settings
	deck_count = decks_for(players.size())


## 1 baraja para 2-4 jugadores (41 cartas repartidas como máximo) y 2 para 5, porque
## 5 manos (51 cartas) dejarían una sola en el mazo.
static func decks_for(player_count: int) -> int:
	return 1 if player_count <= SINGLE_DECK_MAX_PLAYERS else 2


func is_valid() -> bool:
	if mode == &"" or players.size() < MIN_PLAYERS or players.size() > MAX_PLAYERS:
		return false
	var ids := {}
	for p in players:
		ids[StringName(p.get("id", ""))] = true
	return ids.size() == players.size() and not ids.has(&"")
