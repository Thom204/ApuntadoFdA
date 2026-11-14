class_name SettlementOutcome
extends RefCounted
## Resultado de liquidar una ronda (value object): la liquidación y sus consecuencias
## sobre la partida. Match lo aplica; el orquestador lo anuncia.

var settlement: RoundSettlement:
	get:
		return _settlement
## Marcador acumulado incluyendo esta ronda.
var scoreboard: Scoreboard:
	get:
		return _scoreboard
## Jugadores que salen en esta ronda: por llegar al umbral o por inactividad (D-12).
var eliminated: Array[StringName]:
	get:
		return _eliminated.duplicate()
var finished: bool:
	get:
		return _finished
## Vacío si la partida no terminó.
var winner_id: StringName:
	get:
		return _winner_id

var _settlement: RoundSettlement
var _scoreboard: Scoreboard
var _eliminated: Array[StringName]
var _finished: bool
var _winner_id: StringName


func _init(p_settlement: RoundSettlement, p_scoreboard: Scoreboard, p_eliminated: Array[StringName],
		p_finished: bool, p_winner_id: StringName) -> void:
	_settlement = p_settlement
	_scoreboard = p_scoreboard
	_eliminated = p_eliminated.duplicate()
	_finished = p_finished
	_winner_id = p_winner_id
