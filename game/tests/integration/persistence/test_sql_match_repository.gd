extends GutTest
## Adaptador SQLite de IMatchRepository (ADR-04), probado a través del puerto con un
## archivo de base de datos temporal. Lo que se guarda es lo que se recupera
## (cumplimiento 7), la liquidación es atómica (4), una versión vieja se rechaza (5) y
## el esquema se crea desde las migraciones con fail fast (8).

const Cards := preload("res://tests/support/cards.gd")
const Stacked := preload("res://tests/support/stacked_deck.gd")

## Mano de A que cierra en Apuntado descartando el 9♣ (sobrante 4♦).
const CLOSER := "2S 3S 4S 8H 8D 8C JH QH KH 4D"
## Mano que resta 36 (J-Q-K♥ combinan; 9+8+7+5+3+2+2 sueltas).
const PENALTY_36 := "JH QH KH 9S 8C 7D 5S 3C 2D 2C"

var _registry: RuleRegistry
var _path: String
var _repo: SqlMatchRepository


func before_all() -> void:
	_registry = RuleRegistry.new(HandEvaluator.new())
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)


func before_each() -> void:
	_path = ProjectSettings.globalize_path("user://test_sql_repo_%d.db" % Time.get_ticks_usec())
	_repo = SqlMatchRepository.open(_path)
	assert_not_null(_repo, "abre y migra la base")


func after_each() -> void:
	if _repo != null:
		_repo.close()
	for suffix in ["", "-journal", "-wal", "-shm"]:
		if FileAccess.file_exists(_path + suffix):
			DirAccess.remove_absolute(_path + suffix)


# ----------------------------------------------------------------- ayudas
func _match(mode: StringName, ids: Array = [&"a", &"b"], settings: RuleSettings = null) -> Match:
	var players: Array[Dictionary] = []
	for id in ids:
		players.append({"id": id, "nickname": str(id).to_upper()})
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var config := MatchConfig.new(mode, players, settings)
	config.rng_seed = 7
	return Match.new(&"m-test", config, _registry.resolve(mode, settings), rng)


func _shuffled(m: Match) -> Deck:
	var deck := Deck.build(m.config().deck_count, false)
	deck.shuffle(m.rng())
	return deck


func _id_of(m: Match, player: StringName, text: String) -> int:
	var wanted := Cards.one(text)
	for c in m.hand_of(player):
		if c.rank == wanted.rank and c.suit == wanted.suit:
			return c.instance_id
	return -1


## Lo que vuelve de la base, comparado como JSON: el puerto promete datos planos.
func _json(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _reopened() -> SqlMatchRepository:
	_repo.close()
	_repo = SqlMatchRepository.open(_path)
	return _repo


func _assert_round_trip(m: Match) -> void:
	var snapshot := m.to_snapshot()
	assert_eq_deep(_json(_reopened().load(StringName(snapshot["id"]))), _json(snapshot))


# ----------------------------------------------------------------- recuperación (C-7)
func test_recupera_una_partida_recien_creada() -> void:
	var m := _match(&"apuntado")
	m.start_next_round(_shuffled(m))
	assert_true(_repo.save_snapshot(m.to_snapshot()))
	_assert_round_trip(m)


func test_recupera_una_partida_a_media_ronda() -> void:
	var m := _match(&"apuntado", [&"a", &"b", &"c"])
	m.start_next_round(_shuffled(m))
	_repo.save_snapshot(m.to_snapshot())
	var starter := m.current_round().current_player_id()
	m.discard(starter, m.hand_of(starter)[0].instance_id)
	var next := m.current_round().current_player_id()
	m.draw_from_deck(next)
	assert_true(_repo.save_snapshot(m.to_snapshot()))
	_assert_round_trip(m)


func test_recupera_una_ronda_liquidada_y_la_siguiente() -> void:
	var m := _match(&"apuntado")
	m.start_next_round(Stacked.build([CLOSER, PENALTY_36], "9C"))
	_repo.save_snapshot(m.to_snapshot())
	assert_true(m.declare_closing(&"a", _id_of(m, &"a", "9C")).ok)
	assert_true(_repo.save_settlement(m.to_snapshot(), m.settlements()[0]))
	_assert_round_trip(m)
	m.start_next_round(_shuffled(m))
	assert_true(_repo.save_snapshot(m.to_snapshot()))
	_assert_round_trip(m)


func test_recupera_una_partida_clasica() -> void:
	var m := _match(&"classic", [&"a", &"b", &"c", &"d", &"e"])
	m.start_next_round(_shuffled(m))
	assert_true(_repo.save_snapshot(m.to_snapshot()))
	_assert_round_trip(m)


func test_recupera_los_parametros_propios_de_la_regla() -> void:
	var settings := RuleSettings.from_dictionary({"elimination_threshold": 51, "max_leftover_points": 2})
	var m := _match(&"apuntado", [&"a", &"b"], settings)
	m.start_next_round(_shuffled(m))
	assert_true(_repo.save_snapshot(m.to_snapshot()))
	_assert_round_trip(m)


func test_una_partida_que_no_existe_vuelve_vacia() -> void:
	assert_eq(_repo.load(&"m-nada"), {})


## Tras un reinicio, el orquestador retoma la partida desde la base y sigue jugando.
func test_el_orquestador_retoma_la_partida_desde_la_base() -> void:
	var registry := _registry
	var config := MatchConfig.new(&"apuntado", [{"id": &"a", "nickname": "A"}, {"id": &"b", "nickname": "B"}])
	config.rng_seed = 11
	var first := MatchOrchestrator.new(registry, _repo)
	assert_true(first.create_match(config).ok)
	var starter := StringName(first.view_for(&"a")["current_player"])
	assert_true(first.discard(starter, first.hand_of(starter)[0].instance_id).ok)
	var view_before := first.view_for(&"a")
	var resumed := MatchOrchestrator.new(registry, _reopened())
	assert_true(resumed.resume_match(first.match_id()).ok)
	assert_eq_deep(_json(resumed.view_for(&"a")), _json(view_before))
	var next := StringName(view_before["current_player"])
	assert_true(resumed.draw_from_deck(next).ok, "la partida sigue después de recuperarla")


# ----------------------------------------------------------------- concurrencia (C-5)
func test_rechaza_un_snapshot_con_una_version_ya_guardada() -> void:
	var m := _match(&"apuntado")
	m.start_next_round(_shuffled(m))
	var snapshot := m.to_snapshot()
	assert_true(_repo.save_snapshot(snapshot))
	assert_false(_repo.save_snapshot(snapshot), "misma versión: STALE_STATE")
	assert_string_contains(_repo.last_error(), "STALE_STATE")


# ----------------------------------------------------------------- atomicidad (C-4)
func test_una_liquidacion_que_falla_a_medias_no_deja_nada() -> void:
	var m := _match(&"apuntado")
	m.start_next_round(Stacked.build([CLOSER, PENALTY_36], "9C"))
	_repo.save_snapshot(m.to_snapshot())
	var before := _json(_repo.load(&"m-test"))
	m.declare_closing(&"a", _id_of(m, &"a", "9C"))
	var broken := m.to_snapshot()
	# Un puntaje de alguien que no participa viola la clave foránea a mitad de la escritura.
	broken["settlements"][0]["deltas"]["intruso"] = -5
	assert_false(_repo.save_settlement(broken, m.settlements()[0]))
	assert_eq_deep(_json(_reopened().load(&"m-test")), before)


# ----------------------------------------------------------------- migraciones (C-8)
func test_no_abre_una_base_de_un_esquema_mas_nuevo() -> void:
	_repo.close()
	var db := SqliteGateway.open(_path)
	db.execute_script("PRAGMA user_version = %d;" % (SqlMatchRepository.SCHEMA_VERSION + 1))
	db.close()
	_repo = SqlMatchRepository.open(_path)
	assert_null(_repo, "fail fast: el servidor no acepta salas con un esquema desconocido")


func test_abrir_de_nuevo_no_vuelve_a_migrar() -> void:
	var m := _match(&"apuntado")
	m.start_next_round(_shuffled(m))
	_repo.save_snapshot(m.to_snapshot())
	assert_not_null(_reopened())
	assert_false(_repo.load(&"m-test").is_empty(), "los datos siguen ahí")
