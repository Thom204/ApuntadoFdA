class_name NetworkChannel
extends IPlayerChannel
## Canal de salida que convierte notificaciones de dominio en RPC dirigidas al peer
## que actualmente posee la sesión de cada jugador.

var _session: NetworkSession


func _init(session: NetworkSession) -> void:
	_session = session


func send(player_id: StringName, message: Dictionary) -> void:
	_session.send_to_player(player_id, message)
