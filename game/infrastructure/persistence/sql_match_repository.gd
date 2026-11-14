class_name SqlMatchRepository
extends IMatchRepository
## Adaptador SQLite del puerto de persistencia (ADR-04): traduce el snapshot de Match
## a las 9 tablas del esquema relacional (migrations/) y de vuelta.
##
## - Cada escritura es una transacción: o se guarda todo o nada (cumplimiento 4).
## - Concurrencia optimista: un snapshot con una versión igual o menor que la guardada
##   se rechaza (cumplimiento 5, D-07).
## - turn_move es solo de inserciones: se agregan las jugadas nuevas (D-14).
## - card_placement guarda dónde está cada carta de la ronda en curso: mazo, pozo o
##   mano, en orden (D-13, D-18).
## - Al abrir aplica las migraciones pendientes; si la base es de una versión más
##   nueva que la esperada, no abre (fail fast, cumplimiento 8).
##
## El mapeo vive aquí y no en un MatchMapper aparte (ADR-04 nombra uno): solo este
## adaptador lo usa, y como módulo suelto sería tan grande como su interfaz. Las
## diferencias del esquema con el ER del E2 están al inicio de la migración 0001.

## Versión del esquema que este código espera (PRAGMA user_version).
const SCHEMA_VERSION := 1
const MIGRATIONS: Array[String] = [
	"res://infrastructure/persistence/migrations/0001_esquema_inicial.sql",
]
## Formato del snapshot que este mapeo sabe leer y escribir (Match.SNAPSHOT_VERSION).
const SNAPSHOT_FORMAT := 1

## Índice = valor de Match.Status.
const _STATUS_NAMES: Array[String] = ["WAITING", "IN_PROGRESS", "FINISHED"]
const _SUIT_NAMES := {
	Card.Suit.HEARTS: "HEARTS", Card.Suit.DIAMONDS: "DIAMONDS",
	Card.Suit.CLUBS: "CLUBS", Card.Suit.SPADES: "SPADES",
}

var _db: SqliteGateway
## Durante una escritura: player_id (texto del dominio) -> participant_id.
var _participants: Dictionary = {}


## Motivo del último `open` fallido, para el log del servidor.
static var open_error := ""


## Repositorio listo para usar, con el esquema al día; null si la base no se pudo
## abrir o migrar (motivo en `open_error`). La ruta la entrega la configuración del
## servidor (D-19).
static func open(path: String) -> SqlMatchRepository:
	open_error = ""
	var db := SqliteGateway.open(path)
	if db == null:
		open_error = SqliteGateway.open_error
		return null
	if not _migrate(db):
		open_error = db.last_error
		db.close()
		return null
	var repo := SqlMatchRepository.new()
	repo._db = db
	return repo


func close() -> void:
	if _db != null:
		_db.close()


## Último error de la base (vacío si la última operación salió bien).
func last_error() -> String:
	return _db.last_error


# ======================================================================= IMatchRepository
func save_snapshot(snapshot: Dictionary) -> bool:
	return _db.transaction(func() -> bool: return _write(snapshot))


## La liquidación ya viene dentro del snapshot; se guarda en la misma transacción que
## el resto del estado: puntajes, eliminaciones y versión, o nada.
func save_settlement(snapshot: Dictionary, _settlement: RoundSettlement) -> bool:
	return save_snapshot(snapshot)


func load(match_id: StringName) -> Dictionary:
	var sessions := _db.query("SELECT * FROM match_session WHERE session_id = ?", [String(match_id)])
	if sessions.is_empty():
		return {}
	var session := sessions[0]
	var names := _participant_names(session["session_id"])
	var current := _latest_round(session["session_id"])
	return {
		"version": SNAPSHOT_FORMAT,
		"id": session["session_id"],
		"status": _STATUS_NAMES.find(session["status"]),
		"config": _read_config(session, names),
		"rng_seed": session["rng_seed"],
		"rng_state": session["rng_state"],
		"eliminated": _eliminated(session["session_id"]),
		"round_number": 0 if current.is_empty() else current["round_number"],
		"round": null if current.is_empty() else _read_round(current, names),
		"settlements": _read_settlements(session["session_id"], names),
		"history": _read_history(session["session_id"], names),
		"winner_id": names.get(session["winner_participant_id"], ""),
		"last_starter": names.get(session["last_starter_participant_id"], ""),
		"state_version": session["version"],
	}


# ======================================================================= migraciones
static func _migrate(db: SqliteGateway) -> bool:
	var current := int(db.scalar("PRAGMA user_version;", [], 0))
	if current > SCHEMA_VERSION:
		db.last_error = "el esquema de la base (v%d) es más nuevo que el esperado (v%d)" % [current, SCHEMA_VERSION]
		return false
	for i in range(current, SCHEMA_VERSION):
		var sql := FileAccess.get_file_as_string(MIGRATIONS[i])
		if sql == "":
			db.last_error = "no se pudo leer la migración %s" % MIGRATIONS[i]
			return false
		if not db.transaction(func() -> bool: return db.execute_script(sql)):
			return false
	return int(db.scalar("PRAGMA user_version;", [], 0)) == SCHEMA_VERSION


# ======================================================================= escritura
func _write(s: Dictionary) -> bool:
	_participants = {}
	return (_check_format(s) and _check_version(s) and _write_session(s)
		and _write_participants(s) and _write_settlements(s) and _write_current_round(s)
		and _write_moves(s) and _write_pointers(s))


func _check_format(s: Dictionary) -> bool:
	if int(s.get("version", -1)) == SNAPSHOT_FORMAT:
		return true
	return _reject("formato de snapshot desconocido: %s" % s.get("version"))


## Barrera de concurrencia optimista (D-07): la versión guardada debe ser menor.
func _check_version(s: Dictionary) -> bool:
	var stored: Variant = _db.scalar("SELECT version FROM match_session WHERE session_id = ?", [s["id"]])
	if _db.last_error != "":
		return false
	if stored != null and int(stored) >= int(s["state_version"]):
		return _reject("STALE_STATE: la partida %s ya está en la versión %d" % [s["id"], stored])
	return true


func _write_session(s: Dictionary) -> bool:
	var config: Dictionary = s["config"]
	var players: Array = config["players"]
	for p: Dictionary in players:
		if not _db.execute("INSERT INTO player (username, created_at) VALUES (?, ?) ON CONFLICT DO NOTHING", [p["id"], _now()]):
			return false
	var host: Variant = _db.scalar("SELECT player_id FROM player WHERE username = ?", [players[0]["id"]])
	var settings: Variant = config["settings"]
	var finished := int(s["status"]) == Match.Status.FINISHED
	return _db.execute(
		"INSERT INTO match_session (session_id, host_player_id, mode, status, deck_count,"
		+ " elimination_threshold, max_leftover_points, closer_score_delta, jokers_enabled,"
		+ " config_rng_seed, rng_seed, rng_state, version, created_at, finished_at)"
		+ " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
		+ " ON CONFLICT (session_id) DO UPDATE SET status = excluded.status,"
		+ " rng_state = excluded.rng_state, version = excluded.version,"
		+ " finished_at = COALESCE(match_session.finished_at, excluded.finished_at)",
		[s["id"], host, config["mode"], _STATUS_NAMES[int(s["status"])], int(config["deck_count"]),
		_setting(settings, "elimination_threshold"), _setting(settings, "max_leftover_points"),
		_setting(settings, "closer_score_delta"), _setting(settings, "jokers_enabled"),
		int(config["rng_seed"]), str(s["rng_seed"]), str(s["rng_state"]), int(s["state_version"]),
		_now(), _now() if finished else null])


func _write_participants(s: Dictionary) -> bool:
	var players: Array = s["config"]["players"]
	for seat in players.size():
		var p: Dictionary = players[seat]
		if not _db.execute(
				"INSERT INTO match_participant (session_id, player_id, seat, nickname, status, joined_at)"
				+ " SELECT ?, player_id, ?, ?, 'ACTIVE', ? FROM player WHERE username = ? ON CONFLICT DO NOTHING",
				[s["id"], seat, p["nickname"], _now(), p["id"]]):
			return false
	for row in _db.query(
			"SELECT mp.participant_id AS id, p.username AS name FROM match_participant mp"
			+ " JOIN player p ON p.player_id = mp.player_id WHERE mp.session_id = ?", [s["id"]]):
		_participants[row["name"]] = row["id"]
	for name: String in s["eliminated"]:
		if not _db.execute(
				"UPDATE match_participant SET status = 'ELIMINATED',"
				+ " eliminated_in_round = COALESCE(eliminated_in_round, ?) WHERE participant_id = ?",
				[int(s["round_number"]), _participants[name]]):
			return false
	return true


func _write_settlements(s: Dictionary) -> bool:
	for st: Dictionary in s["settlements"]:
		var round_id := _ensure_round(s["id"], int(st["round_number"]))
		if round_id < 0 or not _db.execute(
				"UPDATE round SET status = 'SETTLED', closer_participant_id = ?,"
				+ " closed_at = COALESCE(closed_at, ?) WHERE round_id = ?",
				[_participant_or_null(st["closer_id"]), _now(), round_id]):
			return false
		for name: String in st["deltas"]:
			if not _db.execute("INSERT INTO round_score (round_id, participant_id, score_delta) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
					[round_id, _participants.get(name), int(st["deltas"][name])]):
				return false
	return true


## La ronda en curso se reescribe entera: turno, manos y la ubicación de cada carta.
func _write_current_round(s: Dictionary) -> bool:
	if s["round"] == null:
		return true
	var r: Dictionary = s["round"]
	var number := int(r["number"])
	var round_id := _ensure_round(s["id"], number)
	if round_id < 0:
		return false
	var order: Array = r["turn_order"]
	var closer := str(r["closer_id"])
	if not _db.execute(
			"UPDATE round SET status = ?, turn_participant_id = ?, turn_number = ?, turn_phase = ?,"
			+ " closer_participant_id = ?, closed_at = CASE WHEN ? THEN COALESCE(closed_at, ?) ELSE NULL END"
			+ " WHERE round_id = ?",
			[_round_status(s, number, closer), _participants[order[int(r["turn_index"])]], int(r["turn_count"]),
			r["phase"], _participant_or_null(closer), closer != "", _now(), round_id]):
		return false
	if not (_db.execute("DELETE FROM card_placement WHERE round_id = ?", [round_id])
			and _db.execute("DELETE FROM hand_state WHERE round_id = ?", [round_id])):
		return false
	for position in order.size():
		var name: String = order[position]
		if not _db.execute(
				"INSERT INTO hand_state (round_id, participant_id, is_closing_hand, turn_position) VALUES (?, ?, ?, ?)",
				[round_id, _participants[name], name == closer, position]):
			return false
		if not _place_all(round_id, r["hands"][name], "HAND", _db.last_insert_id()):
			return false
	return _place_all(round_id, r["deck"], "DECK", null) and _place_all(round_id, r["discard"], "DISCARD", null)


## Solo las jugadas que la base todavía no tiene: turn_move nunca se modifica.
func _write_moves(s: Dictionary) -> bool:
	var stored := {}
	for row in _db.query(
			"SELECT r.round_number AS n, MAX(m.sequence) AS seq FROM turn_move m"
			+ " JOIN round r ON r.round_id = m.round_id WHERE r.session_id = ? GROUP BY r.round_number", [s["id"]]):
		stored[int(row["n"])] = int(row["seq"])
	for move: Dictionary in s["history"]:
		var number := int(move["round_number"])
		if int(move["sequence"]) <= stored.get(number, 0):
			continue
		var round_id := _ensure_round(s["id"], number)
		var card: Variant = move["card"]
		if round_id < 0 or (card != null and not _ensure_card(card)):
			return false
		if not _db.execute(
				"INSERT INTO turn_move (round_id, sequence, participant_id, action, card_instance_id,"
				+ " is_automatic, created_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?)",
				[round_id, int(move["sequence"]), _participants[move["player_id"]],
				Turn.Action.keys()[int(move["action"])], null if card == null else int(card[0]),
				bool(move.get("automatic", false)), int(move["timestamp_ms"])]):
			return false
	return true


func _write_pointers(s: Dictionary) -> bool:
	return _db.execute(
		"UPDATE match_session SET winner_participant_id = ?, last_starter_participant_id = ? WHERE session_id = ?",
		[_participant_or_null(s["winner_id"]), _participant_or_null(s["last_starter"]), s["id"]])


func _ensure_round(session_id: String, number: int) -> int:
	if not _db.execute(
			"INSERT INTO round (session_id, round_number, status, turn_number, turn_phase, started_at)"
			+ " VALUES (?, ?, 'IN_PROGRESS', 0, 'DRAW', ?) ON CONFLICT DO NOTHING", [session_id, number, _now()]):
		return -1
	return int(_db.scalar("SELECT round_id FROM round WHERE session_id = ? AND round_number = ?",
		[session_id, number], -1))


func _place_all(round_id: int, cards: Array, zone: String, hand_id: Variant) -> bool:
	for position in cards.size():
		var card: Array = cards[position]
		if not _ensure_card(card):
			return false
		if not _db.execute(
				"INSERT INTO card_placement (round_id, card_instance_id, zone, hand_id, position) VALUES (?, ?, ?, ?, ?)",
				[round_id, int(card[0]), zone, hand_id, position]):
			return false
	return true


## Catálogo de cartas: la primera vez se registra; después debe coincidir.
func _ensure_card(card: Array) -> bool:
	var suit: Variant = _SUIT_NAMES.get(int(card[2]))
	if not _db.execute("INSERT INTO card (card_instance_id, rank, suit) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
			[int(card[0]), int(card[1]), suit]):
		return false
	var rows := _db.query("SELECT rank, suit FROM card WHERE card_instance_id = ?", [int(card[0])])
	if rows.is_empty() or int(rows[0]["rank"]) != int(card[1]) or rows[0]["suit"] != suit:
		return _reject("la carta %d no coincide con el catálogo" % int(card[0]))
	return true


func _round_status(s: Dictionary, number: int, closer: String) -> String:
	for st: Dictionary in s["settlements"]:
		if int(st["round_number"]) == number:
			return "SETTLED"
	return "CLOSED" if closer != "" else "IN_PROGRESS"


func _participant_or_null(name: Variant) -> Variant:
	return _participants.get(str(name)) if str(name) != "" else null


static func _setting(settings: Variant, key: String) -> Variant:
	if settings == null:
		return null
	var value: Variant = settings[key]
	return int(value) if typeof(value) != TYPE_BOOL else (1 if value else 0)


func _reject(message: String) -> bool:
	_db.last_error = message
	return false


static func _now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


# ======================================================================= lectura
## participant_id -> player_id del dominio.
func _participant_names(session_id: String) -> Dictionary:
	var names := {}
	for row in _db.query(
			"SELECT mp.participant_id AS id, p.username AS name FROM match_participant mp"
			+ " JOIN player p ON p.player_id = mp.player_id WHERE mp.session_id = ?", [session_id]):
		names[row["id"]] = row["name"]
	return names


func _read_config(session: Dictionary, names: Dictionary) -> Dictionary:
	var players := []
	for row in _db.query("SELECT participant_id, nickname FROM match_participant WHERE session_id = ? ORDER BY seat",
			[session["session_id"]]):
		players.append({"id": names[row["participant_id"]], "nickname": row["nickname"]})
	var settings: Variant = null
	if session["elimination_threshold"] != null:
		settings = {
			"elimination_threshold": session["elimination_threshold"],
			"max_leftover_points": session["max_leftover_points"],
			"closer_score_delta": session["closer_score_delta"],
			"jokers_enabled": session["jokers_enabled"] == 1,
		}
	return {
		"mode": session["mode"],
		"players": players,
		"settings": settings,
		"deck_count": session["deck_count"],
		"rng_seed": session["config_rng_seed"],
	}


func _eliminated(session_id: String) -> Array:
	var out := []
	for row in _db.query(
			"SELECT p.username AS name FROM match_participant mp JOIN player p ON p.player_id = mp.player_id"
			+ " WHERE mp.session_id = ? AND mp.status = 'ELIMINATED' ORDER BY mp.seat", [session_id]):
		out.append(row["name"])
	return out


func _latest_round(session_id: String) -> Dictionary:
	var rows := _db.query("SELECT * FROM round WHERE session_id = ? ORDER BY round_number DESC LIMIT 1", [session_id])
	return {} if rows.is_empty() else rows[0]


func _read_round(r: Dictionary, names: Dictionary) -> Dictionary:
	var order := []
	var hands := {}
	for hand in _db.query("SELECT hand_id, participant_id FROM hand_state WHERE round_id = ? ORDER BY turn_position",
			[r["round_id"]]):
		var name: String = names[hand["participant_id"]]
		order.append(name)
		hands[name] = _cards_in(r["round_id"], "HAND", hand["hand_id"])
	var last_move: Variant = _db.scalar("SELECT MAX(sequence) FROM turn_move WHERE round_id = ?", [r["round_id"]])
	return {
		"number": r["round_number"],
		"turn_order": order,
		"deck": _cards_in(r["round_id"], "DECK"),
		"discard": _cards_in(r["round_id"], "DISCARD"),
		"hands": hands,
		"turn_index": order.find(names.get(r["turn_participant_id"], "")),
		"turn_count": r["turn_number"],
		"phase": r["turn_phase"],
		"move_sequence": 0 if last_move == null else last_move,
		"closer_id": names.get(r["closer_participant_id"], ""),
	}


func _cards_in(round_id: int, zone: String, hand_id: Variant = null) -> Array:
	var sql := ("SELECT c.card_instance_id AS id, c.rank AS rank, c.suit AS suit FROM card_placement cp"
		+ " JOIN card c ON c.card_instance_id = cp.card_instance_id WHERE cp.round_id = ? AND cp.zone = ?")
	var params: Array = [round_id, zone]
	if hand_id != null:
		sql += " AND cp.hand_id = ?"
		params.append(hand_id)
	var out := []
	for row in _db.query(sql + " ORDER BY cp.position", params):
		out.append(_card_data(row))
	return out


func _read_settlements(session_id: String, names: Dictionary) -> Array:
	var out := []
	for r in _db.query("SELECT round_id, round_number, closer_participant_id FROM round"
			+ " WHERE session_id = ? AND status = 'SETTLED' ORDER BY round_number", [session_id]):
		var deltas := {}
		for score in _db.query("SELECT participant_id, score_delta FROM round_score WHERE round_id = ?", [r["round_id"]]):
			deltas[names[score["participant_id"]]] = score["score_delta"]
		out.append({"round_number": r["round_number"], "closer_id": names.get(r["closer_participant_id"], ""),
			"deltas": deltas})
	return out


func _read_history(session_id: String, names: Dictionary) -> Array:
	var out := []
	for row in _db.query(
			"SELECT r.round_number AS round_number, m.sequence AS sequence, m.participant_id AS participant_id,"
			+ " m.action AS action, m.is_automatic AS is_automatic, m.created_at_ms AS created_at_ms,"
			+ " c.card_instance_id AS id, c.rank AS rank, c.suit AS suit FROM turn_move m"
			+ " JOIN round r ON r.round_id = m.round_id LEFT JOIN card c ON c.card_instance_id = m.card_instance_id"
			+ " WHERE r.session_id = ? ORDER BY r.round_number, m.sequence", [session_id]):
		out.append({
			"sequence": row["sequence"],
			"round_number": row["round_number"],
			"player_id": names[row["participant_id"]],
			"action": Turn.Action.keys().find(row["action"]),
			"card": null if row["id"] == null else _card_data(row),
			"timestamp_ms": row["created_at_ms"],
			"automatic": row["is_automatic"] == 1,
		})
	return out


static func _card_data(row: Dictionary) -> Array:
	var suit: int = Card.Suit.NONE if row["suit"] == null else Card.Suit[row["suit"]]
	return [row["id"], row["rank"], suit]
