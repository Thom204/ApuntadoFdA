class_name LocalTransport
extends IClientTransport
## Adaptador local del puerto del cliente: entrega cada solicitud al Lobby del mismo
## proceso como lo haría la red, con el player_id puesto por el servidor (nunca por el
## cliente). Copia los datos en ambos sentidos para que cliente y servidor no compartan
## diccionarios, igual que si viajaran por la red.

var _server: LocalServer
var _player_id: StringName


func _init(server: LocalServer, player_id: StringName) -> void:
	_server = server
	_player_id = player_id


func send(request: Dictionary) -> void:
	var response := _server.lobby.handle(_player_id, request.duplicate(true))
	response_received.emit(response.duplicate(true))


## El servidor empuja un mensaje a este jugador.
func deliver(message: Dictionary) -> void:
	message_received.emit(message.duplicate(true))
