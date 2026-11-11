extends GutTest
## Catálogo de errores (D-09, C5): códigos estables del protocolo con la red y sus
## mensajes para el jugador.

## Códigos que ya viajan por la red. Cambiar uno rompe al cliente: esta lista es el
## contrato, no se deriva del código.
const WIRE_CODES := [
	"INVALID_REQUEST", "UNKNOWN_REQUEST", "STALE_STATE",
	"NO_ROOM", "ROOM_FULL", "ROOM_ALREADY_STARTED", "ALREADY_IN_ROOM", "NOT_IN_ROOM",
	"NOT_HOST", "NOT_ENOUGH_PLAYERS",
	"INVALID_CONFIG", "UNKNOWN_MODE", "NO_MATCH", "MATCH_FINISHED", "ROUND_IN_PROGRESS",
	"PERSISTENCE_FAILED",
	"ROUND_CLOSED", "NOT_PLAYER_TURN", "ACTION_NOT_ALLOWED", "CARD_NOT_IN_HAND",
	"DISCARD_EMPTY", "DECK_EMPTY", "INVALID_CLOSING",
]


func test_los_codigos_del_protocolo_son_estables() -> void:
	var codes: Array = []
	for code in ErrorCatalog.codes():
		codes.append(String(code))
	codes.sort()
	var expected := WIRE_CODES.duplicate()
	expected.sort()
	assert_eq(codes, expected)


func test_cada_codigo_tiene_un_mensaje_para_el_jugador() -> void:
	for code in ErrorCatalog.codes():
		assert_ne(ErrorCatalog.message_for(code), "", String(code))


func test_un_codigo_desconocido_no_tiene_mensaje() -> void:
	assert_false(ErrorCatalog.has(&"NO_EXISTE"))
	assert_eq(ErrorCatalog.message_for(&"NO_EXISTE"), "")


func test_cada_error_de_la_ronda_tiene_codigo_en_el_catalogo() -> void:
	for error_value in Round.Error.values():
		if error_value == Round.Error.OK:
			continue
		var code := Round.error_code(error_value)
		assert_true(ErrorCatalog.has(code), "Round.Error %d -> %s" % [error_value, code])


func test_el_codigo_de_un_error_de_ronda_no_depende_del_nombre_del_enum() -> void:
	assert_eq(Round.error_code(Round.Error.NOT_PLAYER_TURN), ErrorCatalog.NOT_PLAYER_TURN)
	assert_eq(Round.error_code(Round.Error.INVALID_CLOSING), ErrorCatalog.INVALID_CLOSING)
