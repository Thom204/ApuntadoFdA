class_name LocalServer
extends RefCounted
## Servidor en el mismo proceso: el Lobby real con su notificación, sin red. Sirve para
## jugar en un solo equipo (hot seat, "simulación multi-instancia en un mismo
## dispositivo" del E3) y para desarrollar la interfaz mientras la red no existe.
##
## Cada jugador se conecta con connect_player y recibe un LocalTransport, que es el
## mismo puerto (IClientTransport) que usará el adaptador de red. Los mensajes del
## servidor llegan diferidos (al final del frame), como llegarían por red.

var lobby: Lobby

var _router := _Router.new()
var _notification: LobbyNotification


func _init(p_lobby: Lobby) -> void:
	lobby = p_lobby
	_notification = LobbyNotification.new(lobby, _router)


func connect_player(player_id: StringName) -> LocalTransport:
	var transport := LocalTransport.new(self, player_id)
	_router.transports[player_id] = weakref(transport)
	return transport


## Llamar cada segundo (turnos automáticos, D-11 y D-12).
func tick(now_ms: int) -> void:
	lobby.tick(now_ms)


## Entrega los mensajes del servidor al transporte de cada jugador. Guarda los
## transportes con weakref para no formar un ciclo con LocalTransport -> LocalServer.
class _Router:
	extends IPlayerChannel

	var transports: Dictionary = {}  # player_id -> WeakRef(LocalTransport)

	func send(player_id: StringName, message: Dictionary) -> void:
		var ref: WeakRef = transports.get(player_id)
		var transport: LocalTransport = ref.get_ref() if ref != null else null
		if transport != null:
			transport.deliver(message)
