class_name Match
extends RefCounted
## Partida (raíz de agregado). Frontera de consistencia: ronda en curso, jugadores,
## liquidaciones e historial. Es la única entrada para jugar: cada comando valida,
## ejecuta, y en un cierre válido liquida (RoundScoring) y aplica eliminaciones y
## fin de partida en el mismo paso. El marcador no se almacena: se deriva de las
## liquidaciones.

enum Status { WAITING_FOR_PLAYERS, IN_PROGRESS, FINISHED }

const SNAPSHOT_VERSION := 1
## Turnos automáticos seguidos (D-12) con los que un jugador queda eliminado al
## liquidarse la ronda. Es del dominio y no configuración: decide quién sigue en la
## partida y se deriva del historial guardado (turn_move.is_automatic).
const MAX_AUTOMATIC_TURNS := 3

var id: StringName:
	get:
		return _id
var status: int:
	get:
		return _status

var _id: StringName
var _status: int = Status.WAITING_FOR_PLAYERS
var _config: MatchConfig
var _rule: GameRule
var _rng: RandomNumberGenerator
var _players: Array[Player] = []
var _round_number := 0
var _current_round: Round
var _settlements: Array[RoundSettlement] = []
var _history := MatchHistory.new()
var _winner_id := &""
var _last_starter := &""
## Sube con cada cambio de estado: permite rechazar comandos viejos (STALE_STATE, ADR-04).
var _state_version := 0


func _init(p_id: StringName, p_config: MatchConfig, p_rule: GameRule, p_rng: RandomNumberGenerator) -> void:
	_id = p_id
	_config = p_config
	_rule = p_rule
	_rng = p_rng
	for i in p_config.players.size():
		var p: Dictionary = p_config.players[i]
		_players.append(Player.new(StringName(p["id"]), str(p.get("nickname", p["id"])), i))


# ======================================================================= ciclo de rondas
func can_start_next_round() -> bool:
	if _status == Status.FINISHED:
		return false
	return _current_round == null or _settlements.size() == _round_number


## Inicia una ronda con los jugadores activos; empieza el siguiente al que inició la
## ronda anterior. Falso si la partida terminó o la ronda actual no se ha liquidado.
func start_next_round(deck: Deck) -> bool:
	if not can_start_next_round():
		return false
	var order := _turn_order_for_next_round()
	_last_starter = order[0]
	_round_number += 1
	_attach_round(Round.new(_round_number, _rule, order, _rng))
	_current_round.start(deck)
	_status = Status.IN_PROGRESS
	_state_version += 1
	return true


# ======================================================================= comandos
## `automatic`: jugada del servidor por turno vencido (D-12); ver Round.
func draw_from_deck(player_id: StringName, automatic: bool = false) -> MatchActionResult:
	return _play(func(r: Round) -> RoundActionResult: return r.draw_from_deck(player_id, automatic))


func draw_from_discard(player_id: StringName, automatic: bool = false) -> MatchActionResult:
	return _play(func(r: Round) -> RoundActionResult: return r.draw_from_discard(player_id, automatic))


func discard(player_id: StringName, card_id: int, automatic: bool = false) -> MatchActionResult:
	return _play(func(r: Round) -> RoundActionResult: return r.discard(player_id, card_id, automatic))


## Un cierre rechazado no cambia nada (RD16). Uno válido cierra la ronda, la liquida,
## elimina a quien llegue al umbral y evalúa el fin de la partida, todo en este paso.
func declare_closing(player_id: StringName, card_id: int) -> MatchActionResult:
	var result := _play(func(r: Round) -> RoundActionResult: return r.declare_closing(player_id, card_id))
	if result.ok:
		result._outcome = _conclude_round()
	return result


# ======================================================================= consultas
## Ronda en curso para las consultas de la vista pública. Los comandos no pasan por aquí.
func current_round() -> Round:
	return _current_round


func round_number() -> int:
	return _round_number


func mode() -> StringName:
	return _config.mode


func config() -> MatchConfig:
	return _config


func rng() -> RandomNumberGenerator:
	return _rng


func players() -> Array[Player]:
	return _players.duplicate()


func active_player_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for p in _players:
		if p.is_active():
			out.append(p.id)
	return out


## Mano privada de un jugador (copia); vacía si no hay ronda o no juega en ella.
func hand_of(player_id: StringName) -> Array[Card]:
	return [] if _current_round == null else _current_round.cards_of(player_id)


## ¿Estas cartas de la mano de `player_id` combinan? Consulta de solo lectura: vale en
## cualquier momento de la ronda, no registra movimiento ni cambia el turno.
func check_meld(player_id: StringName, card_ids: Array[int]) -> MeldCheck:
	var hand := hand_of(player_id)
	var cards: Array[Card] = []
	for card_id in card_ids:
		var card := _card_in(hand, card_id)
		if card == null or card in cards:
			return MeldCheck.not_in_hand()
		cards.append(card)
	return _rule.check_meld(cards)


func scoreboard() -> Scoreboard:
	return Scoreboard.from_settlements(_settlements)


func settlements() -> Array[RoundSettlement]:
	return _settlements.duplicate()


func winner_id() -> StringName:
	return _winner_id


func state_version() -> int:
	return _state_version


func has_player(player_id: StringName) -> bool:
	return _players.any(func(p: Player) -> bool: return p.id == player_id)


## Estado público de la ronda en curso (Round.public_state); vacío si no hay ronda.
func table_state() -> Dictionary:
	return {} if _current_round == null else _current_round.public_state()


func history() -> MatchHistory:
	return _history


## Turnos automáticos seguidos del jugador, contados desde su última jugada a mano.
## Cada turno termina en un descarte, así que se cuentan los descartes automáticos.
func automatic_streak(player_id: StringName) -> int:
	var streak := 0
	var moves := _history.all()
	for i in range(moves.size() - 1, -1, -1):
		var move := moves[i]
		if move.player_id != player_id:
			continue
		if not move.automatic:
			break
		if move.action == Turn.Action.DISCARD:
			streak += 1
	return streak


# ======================================================================= snapshot (ADR-04, D-15)
## Estado completo de la partida en datos planos y JSON-compatibles. Es lo único que
## cruza el seam de persistencia: el adaptador lo mapea a tablas o lo guarda tal cual.
func to_snapshot() -> Dictionary:
	return {
		"version": SNAPSHOT_VERSION,
		"id": String(_id),
		"status": _status,
		"config": _config_to_data(),
		# uint64 como texto: un número JSON perdería precisión.
		"rng_seed": str(_rng.seed),
		"rng_state": str(_rng.state),
		"eliminated": _eliminated_ids(),
		"round_number": _round_number,
		"round": null if _current_round == null else _current_round.to_snapshot(),
		"settlements": _settlements.map(func(s: RoundSettlement) -> Dictionary: return _settlement_to_data(s)),
		"history": _history.all().map(func(m: MoveRecord) -> Dictionary: return m.to_data()),
		"winner_id": String(_winner_id),
		"last_starter": String(_last_starter),
		"state_version": _state_version,
	}


## Configuración guardada en un snapshot, para resolver la regla antes de reconstruir.
static func config_from_snapshot(snapshot: Dictionary) -> MatchConfig:
	var data: Dictionary = snapshot["config"]
	var players: Array[Dictionary] = []
	for p: Dictionary in data["players"]:
		players.append({"id": StringName(p["id"]), "nickname": str(p["nickname"])})
	var settings: RuleSettings = null
	if data["settings"] != null:
		settings = RuleSettings.from_dictionary(data["settings"])
	var config := MatchConfig.new(StringName(data["mode"]), players, settings)
	config.deck_count = int(data["deck_count"])
	config.rng_seed = int(data["rng_seed"])
	return config


## Reconstruye la partida con la regla ya resuelta. Null si la versión no coincide.
static func from_snapshot(snapshot: Dictionary, rule: GameRule) -> Match:
	if int(snapshot.get("version", -1)) != SNAPSHOT_VERSION:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = str(snapshot["rng_seed"]).to_int()
	rng.state = str(snapshot["rng_state"]).to_int()
	var m := Match.new(StringName(snapshot["id"]), config_from_snapshot(snapshot), rule, rng)
	m._status = int(snapshot["status"])
	for p in m._players:
		if snapshot["eliminated"].has(String(p.id)):
			p.eliminate()
	m._round_number = int(snapshot["round_number"])
	if snapshot["round"] != null:
		m._attach_round(Round.from_snapshot(snapshot["round"], rule, rng))
	for s: Dictionary in snapshot["settlements"]:
		m._settlements.append(_settlement_from_data(s))
	for move: Dictionary in snapshot["history"]:
		m._history.record(MoveRecord.from_data(move))
	m._winner_id = StringName(snapshot["winner_id"])
	m._last_starter = StringName(snapshot["last_starter"])
	m._state_version = int(snapshot.get("state_version", 0))
	return m


# ======================================================================= internos
func _play(action: Callable) -> MatchActionResult:
	if _status == Status.FINISHED or _current_round == null:
		return MatchActionResult.rejected(Round.Error.ROUND_CLOSED)
	var previous_player := _current_round.current_player_id()
	var result: RoundActionResult = action.call(_current_round)
	if not result.ok:
		return MatchActionResult.new(result)
	_state_version += 1
	var current := _current_round.current_player_id()
	return MatchActionResult.new(result, _history.last(), current if current != previous_player else &"")


func _conclude_round() -> SettlementOutcome:
	var hands := {}
	for player_id in active_player_ids():
		hands[player_id] = _current_round.cards_of(player_id)
	var inactive: Array[StringName] = []
	for player_id in active_player_ids():
		if automatic_streak(player_id) >= MAX_AUTOMATIC_TURNS:
			inactive.append(player_id)
	var outcome := RoundScoring.settle(_round_number, _current_round.closer_id(), hands, _rule, _settlements, inactive)
	_settlements.append(outcome.settlement)
	for p in _players:
		if p.id in outcome.eliminated:
			p.eliminate()
	if outcome.finished:
		_status = Status.FINISHED
		_winner_id = outcome.winner_id
	return outcome


func _attach_round(r: Round) -> void:
	_current_round = r
	_current_round.move_performed.connect(_history.record)


func _turn_order_for_next_round() -> Array[StringName]:
	var active := active_player_ids()
	var start := 0
	if _last_starter != &"":
		start = _index_after(_last_starter, active)
	var order: Array[StringName] = []
	for i in active.size():
		order.append(active[(start + i) % active.size()])
	return order


## Posición en `active` del primer jugador activo que se sienta después de `player_id`.
func _index_after(player_id: StringName, active: Array[StringName]) -> int:
	var seat := _seat_of(player_id)
	for offset in range(1, _players.size() + 1):
		var candidate := _players[(seat + offset) % _players.size()]
		if candidate.is_active():
			return active.find(candidate.id)
	return 0


func _seat_of(player_id: StringName) -> int:
	for p in _players:
		if p.id == player_id:
			return p.seat
	return 0


func _eliminated_ids() -> Array:
	var out := []
	for p in _players:
		if not p.is_active():
			out.append(String(p.id))
	return out


func _config_to_data() -> Dictionary:
	var players := _players.map(func(p: Player) -> Dictionary: return {"id": String(p.id), "nickname": p.nickname})
	return {
		"mode": String(_config.mode),
		"players": players,
		"settings": null if _config.settings == null else _config.settings.to_dictionary(),
		"deck_count": _config.deck_count,
		"rng_seed": _config.rng_seed,
	}


static func _settlement_to_data(s: RoundSettlement) -> Dictionary:
	var deltas := {}
	for player_id in s.deltas:
		deltas[String(player_id)] = s.delta_of(player_id)
	return {"round_number": s.round_number, "closer_id": String(s.closer_id), "deltas": deltas}


static func _settlement_from_data(data: Dictionary) -> RoundSettlement:
	var deltas := {}
	for player_id in data["deltas"]:
		deltas[StringName(player_id)] = int(data["deltas"][player_id])
	return RoundSettlement.new(int(data["round_number"]), StringName(data["closer_id"]), deltas)


func _card_in(cards: Array[Card], card_id: int) -> Card:
	for c in cards:
		if c.instance_id == card_id:
			return c
	return null
