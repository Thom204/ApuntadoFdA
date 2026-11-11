class_name ErrorCatalog
extends RefCounted
## Catálogo de errores (D-09): códigos estables que viajan por la red y el mensaje que
## ve el jugador. Es el único lugar donde viven los textos de error. No depende de
## ningún otro módulo (FF-01): cualquiera puede usarlo.
##
## Cambiar un código rompe al cliente. Agregar uno es compatible.

# --- protocolo (Lobby)
const INVALID_REQUEST := &"INVALID_REQUEST"
const UNKNOWN_REQUEST := &"UNKNOWN_REQUEST"
const STALE_STATE := &"STALE_STATE"
# --- salas
const NO_ROOM := &"NO_ROOM"
const ROOM_FULL := &"ROOM_FULL"
const ROOM_ALREADY_STARTED := &"ROOM_ALREADY_STARTED"
const ALREADY_IN_ROOM := &"ALREADY_IN_ROOM"
const NOT_IN_ROOM := &"NOT_IN_ROOM"
const NOT_HOST := &"NOT_HOST"
const NOT_ENOUGH_PLAYERS := &"NOT_ENOUGH_PLAYERS"
# --- partida
const INVALID_CONFIG := &"INVALID_CONFIG"
const UNKNOWN_MODE := &"UNKNOWN_MODE"
const NO_MATCH := &"NO_MATCH"
const MATCH_FINISHED := &"MATCH_FINISHED"
const ROUND_IN_PROGRESS := &"ROUND_IN_PROGRESS"
const PERSISTENCE_FAILED := &"PERSISTENCE_FAILED"
# --- ronda y turno
const ROUND_CLOSED := &"ROUND_CLOSED"
const NOT_PLAYER_TURN := &"NOT_PLAYER_TURN"
const ACTION_NOT_ALLOWED := &"ACTION_NOT_ALLOWED"
const CARD_NOT_IN_HAND := &"CARD_NOT_IN_HAND"
const DISCARD_EMPTY := &"DISCARD_EMPTY"
const DECK_EMPTY := &"DECK_EMPTY"
const INVALID_CLOSING := &"INVALID_CLOSING"

const _MESSAGES := {
	INVALID_REQUEST: "La solicitud está incompleta o mal formada.",
	UNKNOWN_REQUEST: "Esa acción no existe.",
	STALE_STATE: "La mesa cambió mientras jugabas. Se actualizó; vuelve a intentarlo.",
	NO_ROOM: "Esa sala no existe.",
	ROOM_FULL: "La sala está llena.",
	ROOM_ALREADY_STARTED: "La partida de esa sala ya empezó.",
	ALREADY_IN_ROOM: "Ya estás en una sala.",
	NOT_IN_ROOM: "No estás en ninguna sala.",
	NOT_HOST: "Solo el anfitrión puede iniciar la partida.",
	NOT_ENOUGH_PLAYERS: "Se necesitan al menos 2 jugadores para empezar.",
	INVALID_CONFIG: "La partida necesita entre 2 y 5 jugadores con nombres distintos.",
	UNKNOWN_MODE: "La modalidad elegida no está disponible.",
	NO_MATCH: "No hay una partida en curso.",
	MATCH_FINISHED: "La partida ya terminó.",
	ROUND_IN_PROGRESS: "La ronda actual sigue en juego.",
	PERSISTENCE_FAILED: "No se pudo guardar la partida. Intenta de nuevo.",
	ROUND_CLOSED: "La ronda ya está cerrada.",
	NOT_PLAYER_TURN: "No es tu turno.",
	ACTION_NOT_ALLOWED: "Esa acción no está permitida en este momento del turno.",
	CARD_NOT_IN_HAND: "Esa carta no está en tu mano.",
	DISCARD_EMPTY: "El pozo de descarte está vacío.",
	DECK_EMPTY: "No quedan cartas para robar.",
	INVALID_CLOSING: "Tus cartas no cumplen las condiciones para cerrar.",
}


static func codes() -> Array:
	return _MESSAGES.keys()


static func has(code: StringName) -> bool:
	return _MESSAGES.has(code)


## Mensaje para el jugador; vacío si el código no existe.
static func message_for(code: StringName) -> String:
	return _MESSAGES.get(code, "")
