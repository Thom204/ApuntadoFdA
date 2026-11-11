extends RefCounted
## Configuración de las fitness functions arquitectónicas (Entregable 2, sección 5).
##
## Es el ÚNICO archivo que hay que tocar cuando cambie la estructura de carpetas
## del proyecto o se quiera endurecer/relajar una regla.

## Prefijo de ruta -> nombre de módulo. Se usa el prefijo MÁS LARGO que coincida,
## así que "res://infrastructure/network/" gana sobre un eventual "res://infrastructure/".
const MODULES := {
	"res://presentation/": "presentation",
	"res://infrastructure/network/": "infrastructure.network",
	"res://infrastructure/persistence/": "infrastructure.persistence",
	"res://orchestration/": "orchestration",
	"res://notification/": "notification",
	"res://match/": "match",
	"res://turn/": "turn",
	"res://scoring/": "scoring",
	"res://rules/": "rules",
	"res://deck/": "deck",
	"res://shared/": "shared",
}

## Carpetas que nunca se analizan (código de terceros, pruebas y caché del motor).
const EXCLUDED_PATHS := ["res://addons/", "res://tests/", "res://.godot/"]

## Módulos del núcleo: reglas de juego, estado de partida y coordinación (D-05).
const CORE_MODULES := [
	"match", "turn", "scoring", "rules", "deck", "orchestration", "notification"
]

## Módulos que no pueden tocar el binding de SQLite: todos salvo la persistencia (ADR-04).
const NDB_MODULES := [
	"match", "turn", "scoring", "rules", "deck", "orchestration", "notification", "presentation",
	"infrastructure.network", "shared"
]

## FF-02: grupos de archivos que representan modalidades. Ningún archivo de un grupo
## puede depender de un archivo de otro grupo (prefijos de ruta, no módulos).
const VARIANT_GROUPS := {
	"clasica": ["res://rules/modes/classic"],
	"apuntado": ["res://rules/modes/apuntado"],
}

## FF-06: carpeta de los plug-ins de reglas. Nada fuera de ella puede depender de un
## archivo de dentro (microkernel, ADR-03).
const PLUGIN_ROOT := "res://rules/modes/"

## FF-07 (ADR-05, cumplimiento 2 y 3): eventos de IGameEvents. Solo `orchestration`
## los emite. Excepción documentada: Round.move_performed es el evento interno que
## alimenta MatchHistory dentro de la misma transacción (ADR-05, decisión 3).
const IGAME_EVENTS := [
	"round_started", "turn_changed", "move_performed", "round_closed", "player_eliminated", "match_finished",
]
const EVENT_EMITTER_MODULE := "orchestration"
const EVENT_EMIT_ALLOWED_FILES := ["res://turn/round.gd"]
## Comandos de IMatchCommands y del Lobby: un suscriptor de eventos no puede llamarlos
## (un evento no dispara un comando).
const COMMAND_METHODS := [
	"create_match", "resume_match", "draw_from_deck", "draw_from_discard", "discard",
	"declare_closing", "start_next_round", "handle",
]
## Módulos que se suscriben a IGameEvents.
const EVENT_SUBSCRIBER_MODULES := ["notification"]


## `<evento>.emit(` para cualquier evento de IGAME_EVENTS.
static func event_emit_pattern() -> String:
	return "\\b(%s)\\.emit\\(" % "|".join(IGAME_EVENTS)


## `.<comando>(` para cualquier método de COMMAND_METHODS.
static func command_call_pattern() -> String:
	return "\\.(%s)\\(" % "|".join(COMMAND_METHODS)

## FF-03: exigir que el grafo de dependencias entre módulos sea acíclico.
const ENFORCE_ACYCLIC_MODULES := true

## FF-04: identificadores y patrones que el núcleo NO puede usar (D-05, ADR-05 cumplimiento 1):
## interfaz gráfica, transporte (HTTP/WebSocket/RPC), acceso a la base de datos y
## asincronía (el núcleo es síncrono y determinista).
const FORBIDDEN_IN_CORE_IDENTIFIERS := [
	"Control", "CanvasItem", "Node2D", "Node3D",
	"HTTPRequest", "HTTPClient", "WebSocketPeer", "WebSocketMultiplayerPeer",
	"ENetMultiplayerPeer", "MultiplayerPeer", "MultiplayerAPI", "multiplayer", "Sqlite3FileHandle",
	"await", "Thread", "WorkerThreadPool",
]
const FORBIDDEN_IN_CORE_PATTERNS := ["@rpc"]

const FORBIDDEN_OUTSIDE_PERSISTANCE := [
	"Sqlite3FileHandle"
]

## FF-05: límite de complejidad ciclomática por función (D-23) y carpetas donde se exige.
## Empezar por el motor de reglas y ampliar la lista a medida que el código lo permita.
const CC_LIMIT := 10
const CC_SCOPE := ["res://rules/", "res://turn/", "res://match/", "res://scoring/", "res://deck/", "res://orchestration/"]

## FF-01: dependencias prohibidas por módulo  { módulo: [módulos que NO puede usar] }.
static func forbidden_dependencies() -> Dictionary:
	var rules := {
		# Regla 5.1: la presentación no accede de forma directa a la persistencia.
		"presentation": ["infrastructure.persistence"],
	}
	# D-05: el núcleo no depende de interfaz, transporte ni persistencia concreta.
	for core_module in CORE_MODULES:
		rules[core_module] = ["presentation", "infrastructure.network", "infrastructure.persistence"]
	# Lo compartido (catálogo de errores, D-09) no depende de ningún otro módulo.
	var others: Array = []
	for module_name in MODULES.values():
		if module_name != "shared":
			others.append(module_name)
	rules["shared"] = others
	return rules
