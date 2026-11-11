class_name GameNotification
extends RefCounted
## Game Notification (ADR-05, decisión 3): se suscribe a IGameEvents con CONNECT_DEFERRED
## y envía a cada jugador de la partida, por IPlayerChannel, un mensaje
##   { "event": String, "data": Dictionary, "view": view_for(jugador) }
## La vista ya viene filtrada para ese jugador (RNF 3). Al ser diferido, el envío ocurre
## al final del frame, fuera de la pila del comando: notificar no puede abortar un
## comando ya guardado. Solo consulta al orquestador; nunca le envía comandos (FF-07).
##
## Quien la crea debe conservar la referencia mientras dure la partida.

var _orchestrator: MatchOrchestrator
var _channel: IPlayerChannel


func _init(orchestrator: MatchOrchestrator, channel: IPlayerChannel) -> void:
	_orchestrator = orchestrator
	_channel = channel
	orchestrator.round_started.connect(_on_round_started, CONNECT_DEFERRED)
	orchestrator.turn_changed.connect(_on_turn_changed, CONNECT_DEFERRED)
	orchestrator.move_performed.connect(_on_move_performed, CONNECT_DEFERRED)
	orchestrator.round_closed.connect(_on_round_closed, CONNECT_DEFERRED)
	orchestrator.player_eliminated.connect(_on_player_eliminated, CONNECT_DEFERRED)
	orchestrator.match_finished.connect(_on_match_finished, CONNECT_DEFERRED)


func _on_round_started(round_number: int) -> void:
	_broadcast("round_started", {"round_number": round_number})


func _on_turn_changed(player_id: StringName) -> void:
	_broadcast("turn_changed", {"player_id": String(player_id)})


func _on_move_performed(move: MoveRecord) -> void:
	_broadcast("move_performed", WireFormat.move(move))


func _on_round_closed(settlement: RoundSettlement, validation: ValidationResult) -> void:
	_broadcast("round_closed", {
		"settlement": WireFormat.settlement(settlement),
		"closing": WireFormat.validation(validation),
	})


func _on_player_eliminated(player_id: StringName) -> void:
	_broadcast("player_eliminated", {"player_id": String(player_id)})


func _on_match_finished(winner_id: StringName) -> void:
	_broadcast("match_finished", {"winner_id": String(winner_id)})


func _broadcast(event: String, data: Dictionary) -> void:
	for player_id in _orchestrator.player_ids():
		_channel.send(player_id, {"event": event, "data": data, "view": _orchestrator.view_for(player_id)})
