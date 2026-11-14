-- ============================================================================
--  Migración 0001: esquema inicial (ADR-04, E2 figura 2.2, docs/diagrams/er-diagram.puml)
--  9 tablas + 1 vista, 3FN, tablas STRICT. Las claves foráneas las activa la
--  conexión (PRAGMA foreign_keys = ON) en SqliteGateway.open.
--
--  Diferencias con el ER del E2 (ver ADR-04, cuestiones abiertas 3 y 4):
--  - player.password_hash es anulable: la autenticación es del adaptador de red.
--  - match_session no guarda cards_per_player: lo define el plug-in
--    (GameRule.cards_to_deal), no la partida (ADR-03).
--  - match_session agrega closer_score_delta (parámetro de la regla), el estado del
--    RNG y last_starter_participant_id (recuperar el mazo y la rotación tras un
--    reinicio, D-15). Los parámetros de la regla son NULL todos juntos cuando la
--    partida usa los valores por defecto del plug-in.
--  - hand_state agrega turn_position: el orden de turno de la ronda.
-- ============================================================================

CREATE TABLE player (
	player_id     INTEGER PRIMARY KEY,
	username      TEXT    NOT NULL UNIQUE,
	password_hash TEXT,
	created_at    INTEGER NOT NULL
) STRICT;

CREATE TABLE match_session (
	session_id                  TEXT    PRIMARY KEY,
	host_player_id              INTEGER NOT NULL REFERENCES player (player_id),
	mode                        TEXT    NOT NULL,
	status                      TEXT    NOT NULL CHECK (status IN ('WAITING', 'IN_PROGRESS', 'FINISHED')),
	deck_count                  INTEGER NOT NULL CHECK (deck_count >= 1),
	elimination_threshold       INTEGER,
	max_leftover_points         INTEGER,
	closer_score_delta          INTEGER,
	jokers_enabled              INTEGER CHECK (jokers_enabled IN (0, 1)),
	config_rng_seed             INTEGER NOT NULL,
	rng_seed                    TEXT    NOT NULL,
	rng_state                   TEXT    NOT NULL,
	winner_participant_id       INTEGER REFERENCES match_participant (participant_id),
	last_starter_participant_id INTEGER REFERENCES match_participant (participant_id),
	version                     INTEGER NOT NULL CHECK (version >= 0),
	created_at                  INTEGER NOT NULL,
	finished_at                 INTEGER,
	CHECK ((elimination_threshold IS NULL) = (max_leftover_points IS NULL)
		AND (elimination_threshold IS NULL) = (closer_score_delta IS NULL)
		AND (elimination_threshold IS NULL) = (jokers_enabled IS NULL))
) STRICT;

CREATE TABLE match_participant (
	participant_id      INTEGER PRIMARY KEY,
	session_id          TEXT    NOT NULL REFERENCES match_session (session_id),
	player_id           INTEGER NOT NULL REFERENCES player (player_id),
	seat                INTEGER NOT NULL CHECK (seat BETWEEN 0 AND 4),
	nickname            TEXT    NOT NULL,
	status              TEXT    NOT NULL CHECK (status IN ('ACTIVE', 'ELIMINATED')),
	eliminated_in_round INTEGER,
	joined_at           INTEGER NOT NULL,
	UNIQUE (session_id, seat),
	UNIQUE (session_id, player_id)
) STRICT;

CREATE TABLE round (
	round_id              INTEGER PRIMARY KEY,
	session_id            TEXT    NOT NULL REFERENCES match_session (session_id),
	round_number          INTEGER NOT NULL CHECK (round_number >= 1),
	status                TEXT    NOT NULL CHECK (status IN ('IN_PROGRESS', 'CLOSED', 'SETTLED')),
	turn_participant_id   INTEGER REFERENCES match_participant (participant_id),
	turn_number           INTEGER NOT NULL CHECK (turn_number >= 0),
	turn_phase            TEXT    NOT NULL CHECK (turn_phase IN ('DRAW', 'DISCARD', 'END')),
	closer_participant_id INTEGER REFERENCES match_participant (participant_id),
	started_at            INTEGER NOT NULL,
	closed_at             INTEGER,
	UNIQUE (session_id, round_number)
) STRICT;

CREATE TABLE hand_state (
	hand_id         INTEGER PRIMARY KEY,
	round_id        INTEGER NOT NULL REFERENCES round (round_id),
	participant_id  INTEGER NOT NULL REFERENCES match_participant (participant_id),
	is_closing_hand INTEGER NOT NULL CHECK (is_closing_hand IN (0, 1)),
	turn_position   INTEGER NOT NULL CHECK (turn_position >= 0),
	UNIQUE (round_id, participant_id),
	UNIQUE (round_id, turn_position)
) STRICT;

-- Catálogo de cartas: instance_id es único dentro de la baraja (Deck.build).
CREATE TABLE card (
	card_instance_id INTEGER PRIMARY KEY,
	rank             INTEGER NOT NULL CHECK (rank BETWEEN 0 AND 13),
	suit             TEXT    CHECK (suit IN ('HEARTS', 'DIAMONDS', 'CLUBS', 'SPADES'))
) STRICT;

CREATE TABLE card_placement (
	round_id         INTEGER NOT NULL REFERENCES round (round_id),
	card_instance_id INTEGER NOT NULL REFERENCES card (card_instance_id),
	zone             TEXT    NOT NULL CHECK (zone IN ('DECK', 'DISCARD', 'HAND')),
	hand_id          INTEGER REFERENCES hand_state (hand_id) ON DELETE CASCADE,
	position         INTEGER NOT NULL CHECK (position >= 0),
	PRIMARY KEY (round_id, card_instance_id),
	CHECK ((zone = 'HAND') = (hand_id IS NOT NULL))
) STRICT;

-- Historial de acciones (D-14): solo inserciones (ver los triggers de abajo).
CREATE TABLE turn_move (
	move_id          INTEGER PRIMARY KEY,
	round_id         INTEGER NOT NULL REFERENCES round (round_id),
	sequence         INTEGER NOT NULL CHECK (sequence >= 1),
	participant_id   INTEGER NOT NULL REFERENCES match_participant (participant_id),
	action           TEXT    NOT NULL CHECK (action IN ('DRAW_FROM_DECK', 'DRAW_FROM_DISCARD', 'DISCARD', 'DECLARE_CLOSING')),
	card_instance_id INTEGER REFERENCES card (card_instance_id),
	is_automatic     INTEGER NOT NULL CHECK (is_automatic IN (0, 1)),
	created_at_ms    INTEGER NOT NULL,
	UNIQUE (round_id, sequence)
) STRICT;

CREATE TRIGGER turn_move_sin_cambios BEFORE UPDATE ON turn_move
BEGIN
	SELECT RAISE(ABORT, 'turn_move es solo de inserciones (D-14)');
END;

CREATE TRIGGER turn_move_sin_borrado BEFORE DELETE ON turn_move
BEGIN
	SELECT RAISE(ABORT, 'turn_move es solo de inserciones (D-14)');
END;

CREATE TABLE round_score (
	round_id       INTEGER NOT NULL REFERENCES round (round_id),
	participant_id INTEGER NOT NULL REFERENCES match_participant (participant_id),
	score_delta    INTEGER NOT NULL,
	PRIMARY KEY (round_id, participant_id)
) STRICT;

-- El acumulado es un dato derivado: no se almacena (3FN).
CREATE VIEW v_cumulative_score AS
SELECT r.session_id         AS session_id,
       s.participant_id     AS participant_id,
       SUM(s.score_delta)   AS total,
       COUNT(*)             AS rounds_played
  FROM round_score s
  JOIN round r ON r.round_id = s.round_id
 GROUP BY r.session_id, s.participant_id;

PRAGMA user_version = 1;
