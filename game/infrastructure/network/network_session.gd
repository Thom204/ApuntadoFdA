class_name NetworkSession
extends Node
## Adaptador de red autoritativo (ADR-05). Es el único componente que conoce RPC,
## MultiplayerAPI y WebSocketMultiplayerPeer. El Lobby valida todas las solicitudes;
## este nodo solo asocia cada peer autenticado con una identidad opaca y transporta
## respuestas y eventos.

const DEFAULT_PORT := 7777
const DEFAULT_BIND_ADDRESS := "*"
const DEFAULT_DB_PATH := "user://apuntado_server.db"
const DEFAULT_AUDIT_PATH := "user://apuntado_server.jsonl"

var _peer: WebSocketMultiplayerPeer
var _registry: RuleRegistry
var _repository: SqlMatchRepository
var _lobby: Lobby
var _channel: NetworkChannel
var _notifications: LobbyNotification
var _audit: AuditTrail
var _audit_sink: JsonlAuditSink
var _timer: Timer
var _crypto := Crypto.new()

var _player_for_peer: Dictionary = {}  # peer_id -> player_id
var _peer_for_player: Dictionary = {}  # player_id -> peer_id (solo peers conectados)
var _player_for_token: Dictionary = {} # token -> player_id; solo vive mientras vive el proceso
var _token_for_player: Dictionary = {} # player_id -> token


func _ready() -> void:
	if not _start_services():
		get_tree().quit(1)
		return
	if not _start_listener():
		_close_services()
		get_tree().quit(1)
		return
	_start_turn_clock()
	print("Apuntado server listening on %s:%d" % [_bind_address(), _port()])


func _exit_tree() -> void:
	_close_services()


func _start_services() -> bool:
	_registry = RuleRegistry.new(HandEvaluator.new())
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	if not _registry.has_required_modes():
		push_error("No se encontraron los modos requeridos: %s" % _registry.rejections())
		return false

	var db_path := _environment_or("APUNTADO_DB", DEFAULT_DB_PATH)
	_repository = SqlMatchRepository.open(ProjectSettings.globalize_path(db_path))
	if _repository == null:
		push_error("No se pudo abrir SQLite: %s" % SqlMatchRepository.open_error)
		return false

	var audit_path := _environment_or("APUNTADO_AUDIT_LOG", DEFAULT_AUDIT_PATH)
	_audit_sink = JsonlAuditSink.open(ProjectSettings.globalize_path(audit_path))
	if _audit_sink == null:
		push_error("No se pudo abrir el log de auditoría: %s" % JsonlAuditSink.open_error)
		_repository.close()
		return false

	_lobby = Lobby.new(_registry, _repository)
	_channel = NetworkChannel.new(self)
	_notifications = LobbyNotification.new(_lobby, _channel)
	_audit = AuditTrail.new(_lobby, _audit_sink)
	return true


func _start_listener() -> bool:
	_peer = WebSocketMultiplayerPeer.new()
	var result := _peer.create_server(_port(), _bind_address())
	if result != OK:
		push_error("No se pudo iniciar WebSocket en %s:%d (error %d)" % [_bind_address(), _port(), result])
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return true


func _start_turn_clock() -> void:
	_timer = Timer.new()
	_timer.name = "TurnClock"
	_timer.wait_time = 1.0
	_timer.timeout.connect(func() -> void: _lobby.tick(Time.get_ticks_msec()))
	add_child(_timer)
	_timer.start()


func _close_services() -> void:
	if _timer != null:
		_timer.stop()
	if _peer != null:
		if multiplayer.multiplayer_peer == _peer:
			multiplayer.multiplayer_peer = null
		_peer = null
	if _repository != null:
		_repository.close()
		_repository = null
	if _audit_sink != null:
		_audit_sink.close()
		_audit_sink = null


## Handshake del cliente. El token es una credencial de portador: no contiene estado
## de juego y no se acepta como player_id en las solicitudes del Lobby.
@rpc("any_peer", "call_remote", "reliable")
func hello(resume_token: String = "") -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		return
	if _player_for_peer.has(peer_id):
		_send_welcome(peer_id, _player_for_peer[peer_id], _token_for_player[_player_for_peer[peer_id]], true)
		return

	var player_id: StringName
	var resumed := resume_token != "" and _player_for_token.has(resume_token)
	if resumed:
		player_id = _player_for_token[resume_token]
	else:
		player_id = _new_player_id()
		resume_token = _new_resume_token()
		_player_for_token[resume_token] = player_id
		_token_for_player[player_id] = resume_token

	# Un token solo puede tener una conexión activa. Retirar los mapas antes de cerrar
	# la conexión vieja evita que su señal tardía marque offline a la nueva sesión.
	var previous_peer := int(_peer_for_player.get(player_id, 0))
	if previous_peer > 0 and previous_peer != peer_id:
		_player_for_peer.erase(previous_peer)
		_peer_for_player.erase(player_id)
		_peer.disconnect_peer(previous_peer, true)

	_player_for_peer[peer_id] = player_id
	_peer_for_player[player_id] = peer_id
	_lobby.set_connected(player_id, true)
	_send_welcome(peer_id, player_id, resume_token, resumed)


## Solicitudes del protocolo. La identidad siempre procede del mapa de sesión, nunca
## del Dictionary enviado por el cliente.
@rpc("any_peer", "call_remote", "reliable")
func request(data: Dictionary) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		return
	if not _player_for_peer.has(peer_id):
		response.rpc_id(peer_id, _protocol_error(data, ErrorCatalog.INVALID_REQUEST))
		return
	if not _is_wire_value(data):
		response.rpc_id(peer_id, _protocol_error(data, ErrorCatalog.INVALID_REQUEST))
		return
	var player_id: StringName = _player_for_peer[peer_id]
	response.rpc_id(peer_id, _lobby.handle(player_id, data.duplicate(true)))


## RPC de salida: los clientes implementan estos mismos métodos en la misma ruta de nodo.
@rpc("authority", "call_remote", "reliable")
func welcome(_data: Dictionary) -> void:
	pass


@rpc("authority", "call_remote", "reliable")
func response(_data: Dictionary) -> void:
	pass


@rpc("authority", "call_remote", "reliable")
func event(_data: Dictionary) -> void:
	pass


func send_to_player(player_id: StringName, message: Dictionary) -> void:
	if not _peer_for_player.has(player_id):
		return
	event.rpc_id(int(_peer_for_player[player_id]), message)


func _on_peer_disconnected(peer_id: int) -> void:
	if not _player_for_peer.has(peer_id):
		return
	var player_id: StringName = _player_for_peer[peer_id]
	_player_for_peer.erase(peer_id)
	if int(_peer_for_player.get(player_id, 0)) == peer_id:
		_peer_for_player.erase(player_id)
		_lobby.set_connected(player_id, false)


func _send_welcome(peer_id: int, player_id: StringName, token: String, resumed: bool) -> void:
	welcome.rpc_id(peer_id, {
		"player_id": String(player_id),
		"resume_token": token,
		"resumed": resumed,
	})


func _new_player_id() -> StringName:
	var candidate := StringName("p-" + _crypto.generate_random_bytes(16).hex_encode())
	while _token_for_player.has(candidate):
		candidate = StringName("p-" + _crypto.generate_random_bytes(16).hex_encode())
	return candidate


func _new_resume_token() -> String:
	var token := _crypto.generate_random_bytes(32).hex_encode()
	while _player_for_token.has(token):
		token = _crypto.generate_random_bytes(32).hex_encode()
	return token


func _protocol_error(request_data: Dictionary, code: StringName) -> Dictionary:
	var request_type := str(request_data.get("type", ""))
	var action_id := str(request_data.get("action_id", ""))
	return {
		"ok": false,
		"request": request_type,
		"action_id": action_id,
		"error": String(code),
		"message": ErrorCatalog.message_for(code),
		"data": {},
	}


func _is_wire_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for item in value:
				if not _is_wire_value(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING or not _is_wire_value(value[key]):
					return false
			return true
		_:
			return false


func _port() -> int:
	var raw := OS.get_environment("APUNTADO_PORT")
	var value := DEFAULT_PORT if raw == "" else raw.to_int()
	return value if value >= 1 and value <= 65535 else DEFAULT_PORT


func _bind_address() -> String:
	return _environment_or("APUNTADO_BIND_ADDRESS", DEFAULT_BIND_ADDRESS)


static func _environment_or(name: String, fallback: String) -> String:
	var value := OS.get_environment(name).strip_edges()
	return fallback if value == "" else value
