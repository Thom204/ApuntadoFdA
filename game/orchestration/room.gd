class_name Room
extends RefCounted
## Sala: jugadores en espera, su anfitrión y la partida que juegan (ADR-04: esperando ->
## en curso -> finalizada). La partida empieza cuando el anfitrión la inicia. Si el
## anfitrión sale mientras se espera, lo reemplaza el siguiente en llegar.

var id: StringName:
	get:
		return _id
var host_id: StringName:
	get:
		return _players[0]["id"] if not _players.is_empty() else &""
var mode: StringName:
	get:
		return _mode
var orchestrator: MatchOrchestrator:
	get:
		return _orchestrator

var _id: StringName
var _mode: StringName
var _mode_name: String
var _orchestrator: MatchOrchestrator
## [{ "id": StringName, "nickname": String }] en orden de llegada (= asiento).
var _players: Array[Dictionary] = []
var _started := false


func _init(p_id: StringName, p_mode: StringName, p_mode_name: String, p_orchestrator: MatchOrchestrator) -> void:
	_id = p_id
	_mode = p_mode
	_mode_name = p_mode_name
	_orchestrator = p_orchestrator


func add(player_id: StringName, nickname: String) -> void:
	_players.append({"id": player_id, "nickname": nickname})


func remove(player_id: StringName) -> void:
	_players = _players.filter(func(p: Dictionary) -> bool: return p["id"] != player_id)


func has(player_id: StringName) -> bool:
	return _players.any(func(p: Dictionary) -> bool: return p["id"] == player_id)


func is_full() -> bool:
	return _players.size() >= MatchConfig.MAX_PLAYERS


func is_empty() -> bool:
	return _players.is_empty()


func members() -> Array[StringName]:
	var out: Array[StringName] = []
	for p in _players:
		out.append(p["id"])
	return out


func is_waiting() -> bool:
	return not _started


func is_playing() -> bool:
	return _started and _orchestrator.status_name() == "IN_PROGRESS"


## WAITING mientras se espera; luego el estado de la partida (IN_PROGRESS o FINISHED).
func status() -> String:
	return "WAITING" if not _started else _orchestrator.status_name()


## Crea la partida con los jugadores de la sala, en orden de asiento.
func start() -> CommandResult:
	var result := _orchestrator.create_match(MatchConfig.new(_mode, _players))
	_started = result.ok
	return result


## La sala en datos del protocolo (solo tipos JSON).
func view() -> Dictionary:
	return {
		"room_id": String(_id),
		"host_id": String(host_id),
		"mode": String(_mode),
		"mode_name": _mode_name,
		"status": status(),
		"max_players": MatchConfig.MAX_PLAYERS,
		"players": _players.map(func(p: Dictionary) -> Dictionary:
			return {"id": String(p["id"]), "nickname": p["nickname"]}),
	}
