class_name ClientNetworkEndpoint
extends Node
## Extremo RPC del cliente. Debe vivir en /root/NetworkSession para que coincida con
## el nodo remoto del servidor. Solo transporta datos y notifica señales al adaptador.

const SERVER_PEER_ID := 1
const SESSION_CONFIG_PATH := "user://apuntado_session.cfg"
const MAX_QUEUED_REQUESTS := 128

signal connection_established(session: Dictionary)
signal connection_failed(error: int)
signal connection_closed
signal response_received(response: Dictionary)
signal message_received(message: Dictionary)

var _peer: WebSocketMultiplayerPeer
var _authenticated := false
var _resume_token := ""
var _player_id := ""
var _outbox: Array[Dictionary] = []
var _pending_actions: Dictionary = {} # action_id -> solicitud para reintento idempotente
var _pending_order: Array[String] = []


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _exit_tree() -> void:
	_disconnect_peer()


func connect_to_server(url: String, resume_token: String = "") -> Error:
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		connection_failed.emit(ERR_INVALID_PARAMETER)
		return ERR_INVALID_PARAMETER
	_requeue_pending_actions()
	_disconnect_peer()
	_resume_token = resume_token if resume_token != "" else _load_resume_token()
	_peer = WebSocketMultiplayerPeer.new()
	var result := _peer.create_client(url)
	if result != OK:
		_peer = null
		connection_failed.emit(result)
		return result
	multiplayer.multiplayer_peer = _peer
	return OK


func disconnect_from_server() -> void:
	_requeue_pending_actions()
	_disconnect_peer()
	connection_closed.emit()


func is_connected_and_ready() -> bool:
	return _authenticated


func player_id() -> String:
	return _player_id


func resume_token() -> String:
	return _resume_token


func send_request(request_data: Dictionary) -> void:
	var request := request_data.duplicate(true)
	var action_id := str(request.get("action_id", ""))
	if action_id != "":
		if not _pending_actions.has(action_id):
			_pending_order.append(action_id)
		_pending_actions[action_id] = request
	if not _authenticated:
		_queue_request(request)
		return
	_send_request_rpc(request)


## Métodos RPC: sus configuraciones y firmas deben coincidir con NetworkSession.
@rpc("any_peer", "call_remote", "reliable")
func hello(_resume_token: String = "") -> void:
	pass


@rpc("any_peer", "call_remote", "reliable")
func request(_data: Dictionary) -> void:
	pass


@rpc("authority", "call_remote", "reliable")
func welcome(data: Dictionary) -> void:
	var next_player_id := str(data.get("player_id", ""))
	var next_token := str(data.get("resume_token", ""))
	if next_player_id == "" or next_token == "":
		push_error("El servidor envió un welcome incompleto")
		_disconnect_peer()
		connection_failed.emit(ERR_INVALID_DATA)
		return
	_player_id = next_player_id
	_resume_token = next_token
	_authenticated = true
	_save_resume_token(_resume_token)

	var resumed := bool(data.get("resumed", false))
	if resumed:
		_send_request_rpc({"type": "get_view"})
	_flush_outbox()
	connection_established.emit({
		"player_id": _player_id,
		"resume_token": _resume_token,
		"resumed": resumed,
	})


@rpc("authority", "call_remote", "reliable")
func response(data: Dictionary) -> void:
	var action_id := str(data.get("action_id", ""))
	if action_id != "":
		_pending_actions.erase(action_id)
		_pending_order.erase(action_id)
		_remove_queued_action(action_id)
	response_received.emit(data.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func event(data: Dictionary) -> void:
	message_received.emit(data.duplicate(true))


func _on_connected_to_server() -> void:
	hello.rpc_id(SERVER_PEER_ID, _resume_token)


func _on_connection_failed() -> void:
	_authenticated = false
	_player_id = ""
	connection_failed.emit(ERR_CANT_CONNECT)


func _on_server_disconnected() -> void:
	_authenticated = false
	_player_id = ""
	_requeue_pending_actions()
	connection_closed.emit()


func _send_request_rpc(request_data: Dictionary) -> void:
	request.rpc_id(SERVER_PEER_ID, request_data)


func _flush_outbox() -> void:
	var queued := _outbox.duplicate(true)
	_outbox.clear()
	for request_data in queued:
		_send_request_rpc(request_data)


func _queue_request(request_data: Dictionary) -> void:
	var action_id := str(request_data.get("action_id", ""))
	if action_id != "":
		for queued in _outbox:
			if str(queued.get("action_id", "")) == action_id:
				return
	if _outbox.size() >= MAX_QUEUED_REQUESTS:
		_outbox.pop_front()
	_outbox.append(request_data)


func _requeue_pending_actions() -> void:
	var retry := []
	for action_id in _pending_order:
		if _pending_actions.has(action_id):
			retry.append(_pending_actions[action_id])
	for request_data in retry:
		_queue_request(request_data)


func _remove_queued_action(action_id: String) -> void:
	_outbox = _outbox.filter(func(item: Dictionary) -> bool:
		return str(item.get("action_id", "")) != action_id)


func _disconnect_peer() -> void:
	_authenticated = false
	_player_id = ""
	if _peer != null:
		if multiplayer.multiplayer_peer == _peer:
			multiplayer.multiplayer_peer = null
		_peer = null


func _load_resume_token() -> String:
	var config := ConfigFile.new()
	if config.load(SESSION_CONFIG_PATH) != OK:
		return ""
	return str(config.get_value("session", "resume_token", ""))


func _save_resume_token(token: String) -> void:
	var config := ConfigFile.new()
	config.set_value("session", "resume_token", token)
	var error := config.save(SESSION_CONFIG_PATH)
	if error != OK:
		push_warning("No se pudo persistir el token de reanudación (error %d)" % error)
	elif OS.has_feature("web") and not OS.is_userfs_persistent():
		push_warning("El navegador no garantiza persistencia de user://; la sesión podría no reanudarse al recargar")
