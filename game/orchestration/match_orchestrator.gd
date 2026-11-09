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
		return CommandResult.failure(&"INVALID_CONFIG")
	var rule := _registry.resolve(config.mode, config.settings)
	if rule == null:
		return CommandResult.failure(&"UNKNOWN_MODE")
	var rng := RandomNumberGenerator.new()
	if config.rng_seed != 0:
		rng.seed = config.rng_seed
	else:
		rng.randomize()
	var created := Match.new(StringName("m-%08x" % rng.randi()), config, rule, rng)
	created.start_next_round(_deck_factory.call(config, rng))
	if not _repository.save_snapshot(created.to_snapshot()):
		return CommandResult.failure(&"PERSISTENCE_FAILED")
	_match = created
	_rule = rule
	_announce_round()
	return CommandResult.success()


## Recupera una partida guardada (D-15). No emite eventos: la UI consulta public_view().
func resume_match(match_id: StringName) -> CommandResult:
	var snapshot := _repository.load(match_id)
	if snapshot.is_empty():
		return CommandResult.failure(&"NO_MATCH")
	var config := Match.config_from_snapshot(snapshot)
	var rule := _registry.resolve(config.mode, config.settings)
	if rule == null:
		return CommandResult.failure(&"UNKNOWN_MODE")
	var resumed := Match.from_snapshot(snapshot, rule)
	if resumed == null:
		return CommandResult.failure(&"NO_MATCH")
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


func start_next_round() -> CommandResult:
	var blocked := _blocked()
	if blocked != null:
		return blocked
	if not _match.can_start_next_round():
		return CommandResult.failure(&"ROUND_IN_PROGRESS")
	var before := _match.to_snapshot()
	_match.start_next_round(_deck_factory.call(_match.config(), _match.rng()))
	if not _repository.save_snapshot(_match.to_snapshot()):
		_restore(before)
		return CommandResult.failure(&"PERSISTENCE_FAILED")
	_announce_round()
	return CommandResult.success()


# ======================================================================= consultas
## Mano privada de un jugador (copia).
func hand_of(player_id: StringName) -> Array[Card]:
	return [] if _match == null else _match.hand_of(player_id)


## Id de la partida en curso; vacío si no hay ninguna.
func match_id() -> StringName:
	return &"" if _match == null else _match.id


## Estado público de la mesa: nunca incluye las cartas de ninguna mano (RNF 3).
func public_view() -> Dictionary:
	if _match == null:
		return {}
	var active_round := _match.current_round()
	return {
		"match_id": _match.id,
		"mode": _match.mode(),
		"mode_name": _registry.display_name(_match.mode()),
		"status": Match.Status.keys()[_match.status],
		"round_number": _match.round_number(),
		"round_closed": active_round.is_closed(),
		"current_player": active_round.current_player_id(),
		"phase": active_round.current_phase(),
		"top_discard": active_round.top_discard(),
		"deck_size": active_round.deck_size(),
		"discard_size": active_round.discard_size(),
		"players": _players_view(active_round),
		"winner": _match.winner_id(),
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
		return CommandResult.failure(StringName(Round.Error.keys()[result.error]), result.validation)
	if not _persist(result):
		_restore(before)
		return CommandResult.failure(&"PERSISTENCE_FAILED")
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
		return CommandResult.failure(&"NO_MATCH")
	if _match.status == Match.Status.FINISHED:
		return CommandResult.failure(&"MATCH_FINISHED")
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
	turn_changed.emit(_match.current_round().current_player_id())


func _players_view(active_round: Round) -> Array[Dictionary]:
	var board := _match.scoreboard()
	var out: Array[Dictionary] = []
	for p in _match.players():
		out.append({
			"id": p.id,
			"nickname": p.nickname,
			"seat": p.seat,
			"active": p.is_active(),
			"total": board.total_of(p.id),
			"hand_size": active_round.hand_size_of(p.id),
			"is_current": p.id == active_round.current_player_id(),
		})
	return out


func _default_deck(config: MatchConfig, rng: RandomNumberGenerator) -> Deck:
	var jokers := config.settings.jokers_enabled if config.settings != null else false
	var deck := Deck.build(config.deck_count, jokers)
	deck.shuffle(rng)
	return deck
