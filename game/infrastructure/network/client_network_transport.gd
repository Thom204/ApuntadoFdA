class_name ClientNetworkTransport
extends IClientTransport
## Implementación WebSocket del puerto que consume ClientSession. La presentación no
## necesita conocer el endpoint RPC ni MultiplayerAPI.

signal connection_established(session: Dictionary)
signal connection_failed(error: int)
signal connection_closed

var _endpoint: ClientNetworkEndpoint


func _init(endpoint: ClientNetworkEndpoint) -> void:
	_endpoint = endpoint
	_endpoint.connection_established.connect(func(session: Dictionary) -> void:
		connection_established.emit(session))
	_endpoint.connection_failed.connect(func(error: int) -> void:
		connection_failed.emit(error))
	_endpoint.connection_closed.connect(func() -> void:
		connection_closed.emit())
	_endpoint.response_received.connect(func(response: Dictionary) -> void:
		response_received.emit(response))
	_endpoint.message_received.connect(func(message: Dictionary) -> void:
		message_received.emit(message))


func connect_to_server(url: String, resume_token: String = "") -> Error:
	return _endpoint.connect_to_server(url, resume_token)


func disconnect_from_server() -> void:
	_endpoint.disconnect_from_server()


func is_connected_and_ready() -> bool:
	return _endpoint.is_connected_and_ready()


func player_id() -> String:
	return _endpoint.player_id()


func resume_token() -> String:
	return _endpoint.resume_token()


func send(request: Dictionary) -> void:
	_endpoint.send_request(request)
