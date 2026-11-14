extends GutTest
## Esquema creado desde las migraciones (ADR-04, cumplimiento 3). Prueba el contrato
## con la base de datos: las claves foráneas rechazan filas huérfanas, se respeta la
## unicidad por sala, la clave compuesta de round_score y la vista suma los puntajes.

var _path: String
var _db: SqliteGateway


func before_each() -> void:
	_path = ProjectSettings.globalize_path("user://test_esquema_%d.db" % Time.get_ticks_usec())
	var repo := SqlMatchRepository.open(_path)
	assert_not_null(repo, "crea el esquema desde las migraciones")
	repo.close()
	_db = SqliteGateway.open(_path)
	_seed()


func after_each() -> void:
	_db.close()
	for suffix in ["", "-journal", "-wal", "-shm"]:
		if FileAccess.file_exists(_path + suffix):
			DirAccess.remove_absolute(_path + suffix)


## Una sala con dos participantes y una ronda: la base mínima de cada prueba.
func _seed() -> void:
	assert_true(_db.execute_script(
		"INSERT INTO player (player_id, username, created_at) VALUES (1, 'ana', 0), (2, 'beto', 0);"
		+ "INSERT INTO match_session (session_id, host_player_id, mode, status, deck_count, config_rng_seed,"
		+ " rng_seed, rng_state, version, created_at) VALUES ('m1', 1, 'apuntado', 'IN_PROGRESS', 1, 0, '0', '0', 1, 0);"
		+ "INSERT INTO match_participant (participant_id, session_id, player_id, seat, nickname, status, joined_at)"
		+ " VALUES (10, 'm1', 1, 0, 'Ana', 'ACTIVE', 0), (20, 'm1', 2, 1, 'Beto', 'ACTIVE', 0);"
		+ "INSERT INTO round (round_id, session_id, round_number, status, turn_number, turn_phase, started_at)"
		+ " VALUES (100, 'm1', 1, 'SETTLED', 1, 'END', 0), (200, 'm1', 2, 'SETTLED', 1, 'END', 0);"
		+ "INSERT INTO card (card_instance_id, rank, suit) VALUES (7, 9, 'CLUBS');"), _db.last_error)


func test_las_claves_foraneas_estan_activas() -> void:
	assert_eq(int(_db.scalar("PRAGMA foreign_keys;")), 1)


func test_rechaza_un_participante_de_una_sala_que_no_existe() -> void:
	assert_false(_db.execute(
		"INSERT INTO match_participant (session_id, player_id, seat, nickname, status, joined_at)"
		+ " VALUES ('no-existe', 1, 2, 'X', 'ACTIVE', 0)"))
	assert_string_contains(_db.last_error, "FOREIGN KEY")


func test_un_jugador_no_ocupa_dos_asientos_en_la_misma_sala() -> void:
	assert_false(_db.execute(
		"INSERT INTO match_participant (session_id, player_id, seat, nickname, status, joined_at)"
		+ " VALUES ('m1', 1, 3, 'Ana otra vez', 'ACTIVE', 0)"))
	assert_string_contains(_db.last_error, "UNIQUE")


func test_dos_jugadores_no_comparten_asiento() -> void:
	_db.execute("INSERT INTO player (player_id, username, created_at) VALUES (3, 'caro', 0)")
	assert_false(_db.execute(
		"INSERT INTO match_participant (session_id, player_id, seat, nickname, status, joined_at)"
		+ " VALUES ('m1', 3, 0, 'Caro', 'ACTIVE', 0)"))


func test_un_participante_tiene_un_solo_puntaje_por_ronda() -> void:
	assert_true(_db.execute("INSERT INTO round_score VALUES (100, 10, 10)"))
	assert_false(_db.execute("INSERT INTO round_score VALUES (100, 10, -3)"))
	assert_string_contains(_db.last_error, "UNIQUE")


func test_la_vista_suma_los_puntajes_de_cada_participante() -> void:
	_db.execute_script("INSERT INTO round_score VALUES (100, 10, 10), (100, 20, -36), (200, 10, -8), (200, 20, 10);")
	var rows := _db.query("SELECT participant_id, total, rounds_played FROM v_cumulative_score"
		+ " WHERE session_id = 'm1' ORDER BY participant_id")
	assert_eq_deep(rows, [
		{"participant_id": 10, "total": 2, "rounds_played": 2},
		{"participant_id": 20, "total": -26, "rounds_played": 2},
	])


func test_tipos_estrictos_rechazan_texto_en_una_columna_entera() -> void:
	assert_false(_db.execute("INSERT INTO round_score VALUES (200, 10, 'mucho')"))


func test_una_carta_en_mano_necesita_su_mano() -> void:
	assert_false(_db.execute("INSERT INTO card_placement VALUES (100, 7, 'HAND', NULL, 0)"))
	assert_string_contains(_db.last_error, "CHECK")


func test_el_historial_de_jugadas_es_solo_de_inserciones() -> void:
	assert_true(_db.execute("INSERT INTO turn_move (round_id, sequence, participant_id, action, card_instance_id,"
		+ " is_automatic, created_at_ms) VALUES (100, 1, 10, 'DISCARD', 7, 0, 0)"))
	assert_false(_db.execute("UPDATE turn_move SET action = 'DECLARE_CLOSING'"))
	assert_false(_db.execute("DELETE FROM turn_move"))
	assert_string_contains(_db.last_error, "D-14")


func test_la_version_del_esquema_queda_registrada() -> void:
	assert_eq(int(_db.scalar("PRAGMA user_version;")), SqlMatchRepository.SCHEMA_VERSION)
