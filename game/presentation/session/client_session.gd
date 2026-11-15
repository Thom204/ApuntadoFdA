class_name ClientSession
extends RefCounted
## Sesión de un jugador en el cliente: lo único que la interfaz usa para hablar con el
## servidor. Arma las solicitudes del protocolo (action_id nuevo y expected_version de la
## última vista) y guarda la última sala y la última vista que mandó el servidor.
##
## La interfaz no valida reglas (RNF 6): pide, y dibuja lo que llegue por las señales.
## Una vista más vieja que la que ya se tiene se descarta, porque la respuesta a un
## comando y el aviso de la misma jugada pueden llegar en cualquier orden.

## La sala cambió (entró o salió alguien, empezó la partida). {} si ya no hay sala.
signal room_changed(room: Dictionary)
## Llegó una vista más nueva de la mesa (mano propia + estado público).
signal view_changed(view: Dictionary)
## Evento de juego: round_started, turn_changed, move_performed, round_closed,
## player_eliminated, match_finished. Se emite después de actualizar la vista.
signal event_received(event: String, data: Dictionary)
## El servidor rechazó una solicitud. `response.message` ya viene en español.
signal request_failed(response: Dictionary)
## Resultado de check_meld: { result, valid, points, message }.
signal meld_checked(check: Dictionary)

var room: Dictionary = {}
var view: Dictionary = {}

var _transport: IClientTransport
var _action_prefix: String
var _action_count := 0


## `action_prefix` distingue los action_id de esta sesión; si se omite, se genera uno.
func _init(transport: IClientTransport, action_prefix: String = "") -> void:
	_transport = transport
	_action_prefix = action_prefix if action_prefix != "" else "c%06d" % (randi() % 1000000)
	transport.response_received.connect(_on_response)
	transport.message_received.connect(_on_message)


# ======================================================================= salas
func create_room(nickname: String, mode: StringName) -> void:
	_send("create_room", {"nickname": nickname, "mode": String(mode)})


func join_room(room_id: String, nickname: String) -> void:
	_send("join_room", {"room_id": room_id, "nickname": nickname})


func leave_room() -> void:
	_send("leave_room")


func start_match() -> void:
	_send("start_match")


## Pide la sala y la vista actuales (al reconectar o si algo se perdió).
func refresh() -> void:
	_transport.send({"type": "get_view"})


## ¿Estas cartas de mi mano combinan? Solo consulta; no cambia la mesa.
func check_meld(card_ids: Array[int]) -> void:
	_transport.send({"type": "check_meld", "card_ids": card_ids})


# ======================================================================= jugadas
func draw_from_deck() -> void:
	_play("draw_from_deck")


func draw_from_discard() -> void:
	_play("draw_from_discard")


func discard(card_id: int) -> void:
	_play("discard", {"card_id": card_id})


## Cierra la ronda descartando `card_id`; el servidor evalúa la mano que queda.
func declare_closing(card_id: int) -> void:
	_play("declare_closing", {"card_id": card_id})


func start_next_round() -> void:
	_play("start_next_round")


# ======================================================================= consultas
func has_match() -> bool:
	return not view.is_empty()


func is_my_turn() -> bool:
	return bool(view.get("is_your_turn", false))


func phase() -> String:
	return str(view.get("phase", ""))


func my_id() -> String:
	return str(view.get("you", ""))


# ======================================================================= internos
func _play(type: String, fields: Dictionary = {}) -> void:
	var with_version := fields.duplicate()
	with_version["expected_version"] = int(view.get("version", 0))
	_send(type, with_version)


func _send(type: String, fields: Dictionary = {}) -> void:
	_action_count += 1
	var request := {"type": type, "action_id": "%s-%d" % [_action_prefix, _action_count]}
	request.merge(fields)
	_transport.send(request)


func _on_response(response: Dictionary) -> void:
	var data: Dictionary = response.get("data", {})
	if response.get("ok", false) and response.get("request", "") == "leave_room":
		view = {}
		_set_room({})
	if data.has("room"):
		_set_room(data["room"])
	if data.has("view"):
		_set_view(data["view"])
	if data.has("check"):
		meld_checked.emit(data["check"])
	if not response.get("ok", false):
		request_failed.emit(response)


func _on_message(message: Dictionary) -> void:
	var event := str(message.get("event", ""))
	var data: Dictionary = message.get("data", {})
	if event == "room_updated":
		_set_room(data)
		return
	_set_view(message.get("view", {}))
	event_received.emit(event, data)


func _set_room(new_room: Dictionary) -> void:
	room = new_room
	room_changed.emit(room)


func _set_view(new_view: Dictionary) -> void:
	if new_view.is_empty() or not _is_newer(new_view):
		return
	view = new_view
	view_changed.emit(view)


func _is_newer(new_view: Dictionary) -> bool:
	if view.is_empty() or new_view.get("match_id") != view.get("match_id"):
		return true
	return int(new_view.get("version", 0)) > int(view.get("version", 0))
