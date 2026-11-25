class_name Lobby
extends RefCounted
## Lobby: única entrada del protocolo con la red (IMatchCommands para todas las salas).
## El adaptador de red autentica al peer, pone el `player_id` (nunca viene en la
## solicitud) y entrega la solicitud tal cual llegó:
##
##   handle(player_id, { "type": ..., "action_id": ..., ...campos }) -> respuesta
##   respuesta = { ok, request, action_id, error, message, data }
##
## Todo lo que entra y sale es nativo de JSON. Cada solicitud que cambia algo exige un
## `action_id`: si llega repetido, se devuelve la misma respuesta sin ejecutar otra vez
## (reintentos de red, ADR-04). Un jugador está en una sola sala a la vez, así que los
## comandos de juego no llevan room_id.
##
## Inactividad (D-11, D-12): el servidor llama tick(now_ms) cada segundo y avisa las
## caídas de conexión con set_connected. Si el turno no avanza en turn_timeout_ms
## (disconnected_timeout_ms si el jugador está desconectado), se juega un turno
## automático por él. Si nadie de la sala está conectado, la partida espera.
##
## Señales para quien arma el servidor (composition root), no para el dominio:
##   room_created(room_id, orchestrator): conectar la notificación de la partida.
##   room_updated(room_id): la sala cambió (alguien entró o salió, o empezó la partida).
##     Si la sala quedó vacía ya no existe: room_view(room_id) devuelve {}.
##   request_handled(player_id, room_id, request, response): cada solicitud atendida,
##     aceptada o rechazada, para la auditoría (AuditTrail). `room_id` es la sala del
##     jugador después de atenderla (vacío si no está en ninguna).

signal room_created(room_id: StringName, orchestrator: MatchOrchestrator)
signal room_updated(room_id: StringName)
signal request_handled(player_id: StringName, room_id: StringName, request: Dictionary, response: Dictionary)

## Cuántas respuestas recuerda para reconocer reintentos.
const MAX_REMEMBERED_ACTIONS := 256
## Tiempos de turno por defecto; el servidor los puede cambiar (D-19).
const DEFAULT_TURN_TIMEOUT_MS := 45000
const DEFAULT_DISCONNECTED_TIMEOUT_MS := 10000

var turn_timeout_ms := DEFAULT_TURN_TIMEOUT_MS
var disconnected_timeout_ms := DEFAULT_DISCONNECTED_TIMEOUT_MS

var _registry: RuleRegistry
var _repository: IMatchRepository
var _deck_factory: Callable
var _rooms: Dictionary = {}       # room_id -> Room
var _room_of: Dictionary = {}     # player_id -> room_id
var _room_count := 0
## type -> { "run": Callable(player_id, request) -> outcome, "mutates": bool }
var _handlers: Dictionary = {}
var _remembered: Dictionary = {}  # "player_id|action_id" -> respuesta
var _remembered_order: Array[String] = []
var _clock := TurnClock.new()
var _crypto := Crypto.new()


func _init(registry: RuleRegistry, repository: IMatchRepository, deck_factory: Callable = Callable()) -> void:
	_registry = registry
	_repository = repository
	_deck_factory = deck_factory
	_handlers = {
		"create_room": {"run": _create_room, "mutates": true},
		"join_room": {"run": _join_room, "mutates": true},
		"leave_room": {"run": _leave_room, "mutates": true},
		"get_view": {"run": _get_view, "mutates": false},
		"check_meld": {"run": _check_meld, "mutates": false},
		"start_match": {"run": _start_match, "mutates": true},
		"draw_from_deck": {"mutates": true, "run": func(p: StringName, r: Dictionary) -> Dictionary:
			return _play(p, r, func(o: MatchOrchestrator) -> CommandResult: return o.draw_from_deck(p))},
		"draw_from_discard": {"mutates": true, "run": func(p: StringName, r: Dictionary) -> Dictionary:
			return _play(p, r, func(o: MatchOrchestrator) -> CommandResult: return o.draw_from_discard(p))},
		"discard": {"mutates": true, "run": func(p: StringName, r: Dictionary) -> Dictionary:
			return _play_card(p, r, func(o: MatchOrchestrator, id: int) -> CommandResult: return o.discard(p, id))},
		"declare_closing": {"mutates": true, "run": func(p: StringName, r: Dictionary) -> Dictionary:
			return _play_card(p, r, func(o: MatchOrchestrator, id: int) -> CommandResult: return o.declare_closing(p, id))},
		"start_next_round": {"mutates": true, "run": func(p: StringName, r: Dictionary) -> Dictionary:
			return _play(p, r, func(o: MatchOrchestrator) -> CommandResult: return o.start_next_round())},
	}


func handle(player_id: StringName, request: Dictionary) -> Dictionary:
	var response := _dispatch(player_id, request)
	request_handled.emit(player_id, _room_of.get(player_id, &""), request, response)
	return response


func _dispatch(player_id: StringName, request: Dictionary) -> Dictionary:
	var type := str(request.get("type", ""))
	var action_id := str(request.get("action_id", ""))
	if type == "":
		return _response(type, action_id, _fail(ErrorCatalog.INVALID_REQUEST))
	if not _handlers.has(type):
		return _response(type, action_id, _fail(ErrorCatalog.UNKNOWN_REQUEST))
	var handler: Dictionary = _handlers[type]
	var key := "%s|%s" % [player_id, action_id]
	if handler["mutates"] and action_id == "":
		return _response(type, action_id, _fail(ErrorCatalog.INVALID_REQUEST))
	if handler["mutates"] and _remembered.has(key):
		return _remembered[key]
	var response := _response(type, action_id, handler["run"].call(player_id, request))
	if handler["mutates"] and response["ok"]:
		_remember(key, response)
	return response


# ======================================================================= inactividad
## Juega un turno automático en cada sala cuyo turno venció. Devuelve por quién jugó.
func tick(now_ms: int) -> Array[StringName]:
	var played: Array[StringName] = []
	for room: Room in _rooms.values():
		var player_id := _due_player(room, now_ms)
		if player_id == &"":
			continue
		room.orchestrator.play_automatic_turn(player_id)
		_clock.restart(room.id, room.orchestrator.state_version(), now_ms)
		played.append(player_id)
	return played


## La red avisa cuando la conexión de un jugador se cae (false) o vuelve (true).
func set_connected(player_id: StringName, connected: bool) -> void:
	var room := _room_for(player_id)
	if room == null:
		return
	room.set_connected(player_id, connected)
	room_updated.emit(room.id)


func _due_player(room: Room, now_ms: int) -> StringName:
	var player_id := room.orchestrator.current_turn() if room.is_playing() else &""
	if player_id == &"" or not room.anyone_connected():
		_clock.forget(room.id)
		return &""
	var timeout := turn_timeout_ms if room.is_connected_player(player_id) else disconnected_timeout_ms
	return player_id if _clock.is_due(room.id, room.orchestrator.state_version(), now_ms, timeout) else &""


# ======================================================================= salas
func _create_room(player_id: StringName, request: Dictionary) -> Dictionary:
	var nickname := str(request.get("nickname", "")).strip_edges()
	var mode := StringName(str(request.get("mode", "")))
	if nickname == "" or mode == &"":
		return _fail(ErrorCatalog.INVALID_REQUEST)
	if _room_of.has(player_id):
		return _fail(ErrorCatalog.ALREADY_IN_ROOM)
	if not mode in _registry.available_modes():
		return _fail(ErrorCatalog.UNKNOWN_MODE)
	_room_count += 1
	var room := Room.new(StringName("r-%d" % _room_count), _new_room_code(), mode, _registry.display_name(mode),
		MatchOrchestrator.new(_registry, _repository, _deck_factory))
	_rooms[room.id] = room
	_seat(room, player_id, nickname)
	room_created.emit(room.id, room.orchestrator)
	return _ok({"room": room.view()})


func _join_room(player_id: StringName, request: Dictionary) -> Dictionary:
	var room_code := str(request.get("room_code", "")).strip_edges().to_upper()
	var room_id := StringName(str(request.get("room_id", "")))
	var nickname := str(request.get("nickname", "")).strip_edges()
	if _invalid_join_request(room_code, room_id, nickname):
		return _fail(ErrorCatalog.INVALID_REQUEST)
	if _room_of.has(player_id):
		return _fail(ErrorCatalog.ALREADY_IN_ROOM)
	var room := _find_room(room_code, room_id)
	if room == null:
		return _fail(ErrorCatalog.NO_ROOM)
	var rejection := _join_rejection(room)
	if rejection != &"":
		return _fail(rejection)
	_seat(room, player_id, nickname)
	return _ok({"room": room.view()})


func _invalid_join_request(room_code: String, room_id: StringName, nickname: String) -> bool:
	return (room_code == "" and room_id == &"") or nickname == ""


func _find_room(room_code: String, room_id: StringName) -> Room:
	for candidate: Room in _rooms.values():
		if (room_code != "" and candidate.code == room_code) or (room_code == "" and candidate.id == room_id):
			return candidate
	return null


func _join_rejection(room: Room) -> StringName:
	if not room.is_waiting():
		return ErrorCatalog.ROOM_ALREADY_STARTED
	if room.is_full():
		return ErrorCatalog.ROOM_FULL
	return &""


func _new_room_code() -> String:
	var code := _crypto.generate_random_bytes(3).hex_encode().to_upper()
	while _room_code_exists(code):
		code = _crypto.generate_random_bytes(3).hex_encode().to_upper()
	return code


func _room_code_exists(code: String) -> bool:
	for room: Room in _rooms.values():
		if room.code == code:
			return true
	return false


## MVP: no se sale de una partida en curso (falta la política de desconexión).
func _leave_room(player_id: StringName, _request: Dictionary) -> Dictionary:
	var room := _room_for(player_id)
	if room == null:
		return _fail(ErrorCatalog.NOT_IN_ROOM)
	if room.is_playing():
		return _fail(ErrorCatalog.ROOM_ALREADY_STARTED)
	room.remove(player_id)
	_room_of.erase(player_id)
	if room.is_empty():
		_rooms.erase(room.id)
	room_updated.emit(room.id)
	return _ok()


func _get_view(player_id: StringName, _request: Dictionary) -> Dictionary:
	var room := _room_for(player_id)
	if room == null:
		return _fail(ErrorCatalog.NOT_IN_ROOM)
	return _ok({"room": room.view(), "view": room.orchestrator.view_for(player_id)})


## Solo el anfitrión, con la sala en espera y al menos 2 jugadores.
func _start_match(player_id: StringName, _request: Dictionary) -> Dictionary:
	var room := _room_for(player_id)
	if room == null:
		return _fail(ErrorCatalog.NOT_IN_ROOM)
	if not room.is_waiting():
		return _fail(ErrorCatalog.ROOM_ALREADY_STARTED)
	if room.host_id != player_id:
		return _fail(ErrorCatalog.NOT_HOST)
	if room.members().size() < MatchConfig.MIN_PLAYERS:
		return _fail(ErrorCatalog.NOT_ENOUGH_PLAYERS)
	var result := room.start()
	if not result.ok:
		return _fail(result.error)
	room_updated.emit(room.id)
	return _ok({"view": room.orchestrator.view_for(player_id)})


# ======================================================================= comandos de juego
func _play_card(player_id: StringName, request: Dictionary, command: Callable) -> Dictionary:
	if not _is_number(request.get("card_id")):
		return _fail(ErrorCatalog.INVALID_REQUEST)
	var card_id := int(request["card_id"])
	return _play(player_id, request, func(o: MatchOrchestrator) -> CommandResult: return command.call(o, card_id))


## Camino común de los comandos de juego: sala del jugador -> versión esperada ->
## comando en el orquestador -> respuesta con la vista actualizada del jugador.
## Con una versión vieja no se ejecuta nada y se devuelve la mesa actual (STALE_STATE).
func _play(player_id: StringName, request: Dictionary, command: Callable) -> Dictionary:
	var room := _room_for(player_id)
	if room == null:
		return _fail(ErrorCatalog.NOT_IN_ROOM)
	if room.is_waiting():
		return _fail(ErrorCatalog.NO_MATCH)
	if not _is_number(request.get("expected_version")):
		return _fail(ErrorCatalog.INVALID_REQUEST)
	var orchestrator := room.orchestrator
	if int(request["expected_version"]) != orchestrator.state_version():
		return _fail(ErrorCatalog.STALE_STATE, {"view": orchestrator.view_for(player_id)})
	var result: CommandResult = command.call(orchestrator)
	var data := {"view": orchestrator.view_for(player_id)}
	if result.card != null:
		data["card"] = WireFormat.card(result.card)
	if result.validation != null:
		data["validation"] = WireFormat.validation(result.validation)
	return _ok(data) if result.ok else _fail(result.error, data, result.message)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## Organizar la mano (RF-02): ¿estas cartas de mi mano combinan? Solo lectura.
func _check_meld(player_id: StringName, request: Dictionary) -> Dictionary:
	var room := _room_for(player_id)
	if room == null:
		return _fail(ErrorCatalog.NOT_IN_ROOM)
	var raw: Variant = request.get("card_ids")
	if typeof(raw) != TYPE_ARRAY or not raw.all(_is_number):
		return _fail(ErrorCatalog.INVALID_REQUEST)
	var card_ids: Array[int] = []
	for id in raw:
		card_ids.append(int(id))
	return _ok({"check": WireFormat.meld_check(room.orchestrator.check_meld(player_id, card_ids))})


func _seat(room: Room, player_id: StringName, nickname: String) -> void:
	room.add(player_id, nickname)
	_room_of[player_id] = room.id
	room_updated.emit(room.id)


func _room_for(player_id: StringName) -> Room:
	return _rooms.get(_room_of.get(player_id, &""))


# ======================================================================= consultas para el armado
## Jugadores de una sala (para notificar cambios de la sala).
func members(room_id: StringName) -> Array[StringName]:
	var room: Room = _rooms.get(room_id)
	return [] if room == null else room.members()


## La sala en datos del protocolo; vacío si no existe.
func room_view(room_id: StringName) -> Dictionary:
	var room: Room = _rooms.get(room_id)
	return {} if room == null else room.view()


# ======================================================================= respuestas
func _ok(data: Dictionary = {}) -> Dictionary:
	return {"error": &"", "data": data}


func _fail(code: StringName, data: Dictionary = {}, message: String = "") -> Dictionary:
	return {"error": code, "data": data, "message": message}


func _response(type: String, action_id: String, outcome: Dictionary) -> Dictionary:
	var code: StringName = outcome["error"]
	var message: String = outcome.get("message", "")
	return {
		"ok": code == &"",
		"request": type,
		"action_id": action_id,
		"error": String(code),
		"message": message if message != "" else ErrorCatalog.message_for(code),
		"data": outcome["data"],
	}


func _remember(key: String, response: Dictionary) -> void:
	_remembered[key] = response
	_remembered_order.append(key)
	if _remembered_order.size() > MAX_REMEMBERED_ACTIONS:
		_remembered.erase(_remembered_order.pop_front())
