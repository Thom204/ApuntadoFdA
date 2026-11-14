class_name MatchOrchestrator
extends RefCounted
## Match Orchestration (Mediator + Facade, ADR-01 y ADR-05): implementa IMatchCommands.
## Invoca, no decide: cada comando lo ejecuta el agregado Match, que devuelve lo que
## ocurrió; el orquestador persiste el snapshot por el puerto IMatchRepository y SOLO
## después emite los eventos de IGameEvents.
##
## Orden fijo de cada comando:
##   ejecutar en Match -> persistir snapshot -> emitir
## Si la persistencia falla, la partida vuelve al snapshot previo y no se emite nada.
##
## MVP: una partida por orquestador (varios jugadores en el mismo dispositivo).

# ======================================================================= IGameEvents
signal round_started(round_number: int)
signal turn_changed(player_id: StringName)
signal move_performed(move: MoveRecord)
signal round_closed(settlement: RoundSettlement, validation: ValidationResult)
signal player_eliminated(player_id: StringName)
signal match_finished(winner_id: StringName)

var _registry: RuleRegistry
var _repository: IMatchRepository
var _deck_factory: Callable
var _match: Match
var _rule: GameRule


## `deck_factory(config: MatchConfig, rng: RandomNumberGenerator) -> Deck` entrega un
## mazo barajado para cada ronda; por defecto, baraja doble con el RNG de la partida.
func _init(registry: RuleRegistry, repository: IMatchRepository, deck_factory: Callable = Callable()) -> void:
	_registry = registry
	_repository = repository
	_deck_factory = deck_factory if deck_factory.is_valid() else _default_deck


# ======================================================================= IMatchCommands
func available_modes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mode in _registry.available_modes():
		out.append({"id": mode, "name": _registry.display_name(mode)})
	return out


func create_match(config: MatchConfig) -> CommandResult:
	if not config.is_valid():
		return CommandResult.failure(ErrorCatalog.INVALID_CONFIG)
	var rule := _registry.resolve(config.mode, config.settings)
	if rule == null:
		return CommandResult.failure(ErrorCatalog.UNKNOWN_MODE)
	var rng := RandomNumberGenerator.new()
	if config.rng_seed != 0:
		rng.seed = config.rng_seed
	else:
		rng.randomize()
	var created := Match.new(StringName("m-%08x" % rng.randi()), config, rule, rng)
	created.start_next_round(_deck_factory.call(config, rng))
	if not _repository.save_snapshot(created.to_snapshot()):
		return CommandResult.failure(ErrorCatalog.PERSISTENCE_FAILED)
	_match = created
	_rule = rule
	_announce_round()
	return CommandResult.success()


## Recupera una partida guardada (D-15). No emite eventos: cada cliente pide view_for().
func resume_match(match_id: StringName) -> CommandResult:
	var snapshot := _repository.load(match_id)
	if snapshot.is_empty():
		return CommandResult.failure(ErrorCatalog.NO_MATCH)
	var config := Match.config_from_snapshot(snapshot)
	var rule := _registry.resolve(config.mode, config.settings)
	if rule == null:
		return CommandResult.failure(ErrorCatalog.UNKNOWN_MODE)
	var resumed := Match.from_snapshot(snapshot, rule)
	if resumed == null:
		return CommandResult.failure(ErrorCatalog.NO_MATCH)
	_match = resumed
	_rule = rule
	return CommandResult.success()


func draw_from_deck(player_id: StringName) -> CommandResult:
	return _execute(func(m: Match) -> MatchActionResult: return m.draw_from_deck(player_id))


func draw_from_discard(player_id: StringName) -> CommandResult:
	return _execute(func(m: Match) -> MatchActionResult: return m.draw_from_discard(player_id))


func discard(player_id: StringName, card_id: int) -> CommandResult:
	return _execute(func(m: Match) -> MatchActionResult: return m.discard(player_id, card_id))


## Cierre válido: Match liquida la ronda; se guarda en una sola escritura atómica y
## se anuncia el resultado, las eliminaciones y, si aplica, el fin de la partida.
func declare_closing(player_id: StringName, card_id: int) -> CommandResult:
	return _execute(func(m: Match) -> MatchActionResult: return m.declare_closing(player_id, card_id))


## Turno automático (D-12): el servidor juega por `player_id` cuando su turno vence.
## Roba del mazo (o del pozo si el mazo se agotó) y descarta la carta que robó; si
## ya estaba en fase de descarte, descarta la última carta de su mano. Son dos comandos
## normales: cada uno se guarda antes de anunciarse. Si el descarte fallara, el
## jugador queda en fase de descarte y el siguiente turno automático lo completa.
func play_automatic_turn(player_id: StringName) -> CommandResult:
	var blocked := _blocked()
	if blocked != null:
		return blocked
	var table := _match.table_state()
	if table.get("current_player", &"") != player_id:
		return CommandResult.failure(ErrorCatalog.NOT_PLAYER_TURN)
	if table["phase"] == &"DRAW":
		var draw := _execute(func(m: Match) -> MatchActionResult: return m.draw_from_deck(player_id, true))
		if draw.error == ErrorCatalog.DECK_EMPTY:
			draw = _execute(func(m: Match) -> MatchActionResult: return m.draw_from_discard(player_id, true))
		if not draw.ok:
			return draw
	var card_id: int = _match.hand_of(player_id).back().instance_id
	return _execute(func(m: Match) -> MatchActionResult: return m.discard(player_id, card_id, true))


func start_next_round() -> CommandResult:
	var blocked := _blocked()
	if blocked != null:
		return blocked
	if not _match.can_start_next_round():
		return CommandResult.failure(ErrorCatalog.ROUND_IN_PROGRESS)
	var before := _match.to_snapshot()
	_match.start_next_round(_deck_factory.call(_match.config(), _match.rng()))
	if not _repository.save_snapshot(_match.to_snapshot()):
		_restore(before)
		return CommandResult.failure(ErrorCatalog.PERSISTENCE_FAILED)
	_announce_round()
	return CommandResult.success()


# ======================================================================= consultas
## Mano privada de un jugador (copia).
func hand_of(player_id: StringName) -> Array[Card]:
	return [] if _match == null else _match.hand_of(player_id)


## ¿Estas cartas de su mano combinan? (RF-02). Solo lectura: no guarda ni emite.
func check_meld(player_id: StringName, card_ids: Array[int]) -> MeldCheck:
	return MeldCheck.not_in_hand() if _match == null else _match.check_meld(player_id, card_ids)


## Estado de la partida (IN_PROGRESS, FINISHED...); vacío si no hay partida.
## Jugador que debe jugar ahora; vacío si no hay partida, terminó o la ronda está
## cerrada esperando la siguiente (no hay turno que vencer).
func current_turn() -> StringName:
	if _match == null or _match.status == Match.Status.FINISHED:
		return &""
	var table := _match.table_state()
	if table.is_empty() or table["closed"]:
		return &""
	return table["current_player"]


func status_name() -> String:
	return "" if _match == null else Match.Status.keys()[_match.status]


## Todos los jugadores sentados en la partida, también los eliminados (siguen mirando).
func player_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if _match != null:
		for p in _match.players():
			out.append(p.id)
	return out


## Id de la partida en curso; vacío si no hay ninguna.
func match_id() -> StringName:
	return &"" if _match == null else _match.id


## Versión del estado de la partida: sube con cada cambio guardado. Un comando que
## llega con otra versión es viejo (STALE_STATE, ADR-04).
func state_version() -> int:
	return 0 if _match == null else _match.state_version()


## Lo que ve `player_id` (C4, RNF 3): la mesa pública, su propia mano y si es su turno.
## Nunca incluye cartas de otra mano. Vacío si no juega esta partida. Solo tipos JSON.
func view_for(player_id: StringName) -> Dictionary:
	if _match == null or not _match.has_player(player_id):
		return {}
	var table := _match.table_state()
	return {
		"match_id": String(_match.id),
		"mode": String(_match.mode()),
		"mode_name": _registry.display_name(_match.mode()),
		"status": Match.Status.keys()[_match.status],
		"version": _match.state_version(),
		"round_number": _match.round_number(),
		"round_closed": table["closed"],
		"current_player": String(table["current_player"]),
		"phase": String(table["phase"]),
		"top_discard": WireFormat.card(table["top_discard"]),
		"deck_size": table["deck_size"],
		"discard_size": table["discard_size"],
		"players": _players_view(table),
		"winner": String(_match.winner_id()),
		"you": String(player_id),
		"is_your_turn": player_id == table["current_player"],
		"hand": WireFormat.cards(_match.hand_of(player_id)),
	}


func history() -> Array[MoveRecord]:
	return [] if _match == null else _match.history().all()


func settlements() -> Array[RoundSettlement]:
	return [] if _match == null else _match.settlements()


# ======================================================================= internos
func _execute(command: Callable) -> CommandResult:
	var blocked := _blocked()
	if blocked != null:
		return blocked
	var before := _match.to_snapshot()
	var result: MatchActionResult = command.call(_match)
	if not result.ok:
		return CommandResult.failure(Round.error_code(result.error), result.validation)
	if not _persist(result):
		_restore(before)
		return CommandResult.failure(ErrorCatalog.PERSISTENCE_FAILED)
	_announce(result)
	return CommandResult.success(result.validation, result.card)


func _persist(result: MatchActionResult) -> bool:
	var snapshot := _match.to_snapshot()
	if result.outcome != null:
		return _repository.save_settlement(snapshot, result.outcome.settlement)
	return _repository.save_snapshot(snapshot)


## Deshace un comando cuya escritura falló: la partida vuelve al último estado guardado.
func _restore(snapshot: Dictionary) -> void:
	_match = Match.from_snapshot(snapshot, _rule)


func _blocked() -> CommandResult:
	if _match == null:
		return CommandResult.failure(ErrorCatalog.NO_MATCH)
	if _match.status == Match.Status.FINISHED:
		return CommandResult.failure(ErrorCatalog.MATCH_FINISHED)
	return null


func _announce(result: MatchActionResult) -> void:
	if result.move != null:
		move_performed.emit(result.move)
	if result.next_player_id != &"":
		turn_changed.emit(result.next_player_id)
	var outcome := result.outcome
	if outcome == null:
		return
	round_closed.emit(outcome.settlement, result.validation)
	for eliminated in outcome.eliminated:
		player_eliminated.emit(eliminated)
	if outcome.finished:
		match_finished.emit(outcome.winner_id)


func _announce_round() -> void:
	round_started.emit(_match.round_number())
	turn_changed.emit(_match.table_state()["current_player"])


func _players_view(table: Dictionary) -> Array[Dictionary]:
	var board := _match.scoreboard()
	var hand_sizes: Dictionary = table["hand_sizes"]
	var out: Array[Dictionary] = []
	for p in _match.players():
		out.append({
			"id": String(p.id),
			"nickname": p.nickname,
			"seat": p.seat,
			"active": p.is_active(),
			"total": board.total_of(p.id),
			"hand_size": hand_sizes.get(p.id, 0),
			"is_current": p.id == table["current_player"],
		})
	return out


func _default_deck(config: MatchConfig, rng: RandomNumberGenerator) -> Deck:
	var jokers := config.settings.jokers_enabled if config.settings != null else false
	var deck := Deck.build(config.deck_count, jokers)
	deck.shuffle(rng)
	return deck
