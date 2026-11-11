class_name LobbyNotification
extends RefCounted
## Lobby Notification: lo único que el armado del servidor conecta junto con el Lobby.
##   - Al crearse una sala, le conecta su GameNotification: los eventos de juego llegan
##     solo a los jugadores de esa sala, cada uno con su propia vista.
##   - Cuando una sala cambia (alguien entra o sale, empieza la partida), envía a sus
##     miembros { "event": "room_updated", "data": <sala>, "view": {} }.
## Como GameNotification, es diferida (CONNECT_DEFERRED) y no invoca comandos (FF-07).
##
## Quien la crea debe conservar la referencia mientras viva el servidor.

var _lobby: Lobby
var _channel: IPlayerChannel
var _games: Dictionary = {}  # room_id -> GameNotification


func _init(lobby: Lobby, channel: IPlayerChannel) -> void:
	_lobby = lobby
	_channel = channel
	# Síncrono a propósito: la partida puede iniciarse en el mismo frame en que se creó
	# la sala, y su notificación tiene que estar conectada antes del primer evento.
	lobby.room_created.connect(_on_room_created)
	lobby.room_updated.connect(_on_room_updated, CONNECT_DEFERRED)


func _on_room_created(room_id: StringName, orchestrator: MatchOrchestrator) -> void:
	_games[room_id] = GameNotification.new(orchestrator, _channel)


func _on_room_updated(room_id: StringName) -> void:
	var room := _lobby.room_view(room_id)
	if room.is_empty():
		_games.erase(room_id)
		return
	for player_id in _lobby.members(room_id):
		_channel.send(player_id, {"event": "room_updated", "data": room, "view": {}})
