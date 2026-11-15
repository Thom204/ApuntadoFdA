extends IClientTransport
## Doble de prueba del puerto del cliente: guarda lo que se envía y deja que la prueba
## haga llegar respuestas y mensajes del servidor cuando quiera.

var sent: Array[Dictionary] = []


func send(request: Dictionary) -> void:
	sent.append(request)


func last() -> Dictionary:
	return sent.back() if not sent.is_empty() else {}


func respond(response: Dictionary) -> void:
	response_received.emit(response)


func push(message: Dictionary) -> void:
	message_received.emit(message)
