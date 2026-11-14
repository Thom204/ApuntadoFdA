class_name SqliteGateway
extends RefCounted
## Acceso a SQLite (ADR-04, elemento 3): el único archivo que conoce el binding
## (Sqlite3Wrapper de sqlite3.gd). Ofrece sentencias con parámetros posicionales (?),
## consultas que devuelven filas como diccionarios y transacciones.
##
## Al abrir activa las claves foráneas en la conexión, antes de cualquier transacción
## (directriz de ADR-04: activarlas dentro de una transacción no tiene efecto).
## Ningún error se absorbe en silencio (checklist de code-completion del E3): cada
## operación devuelve si salió bien y el motivo queda en `last_error` para quien la
## llamó, que decide cómo reportarlo.

const _SQLITE_INTEGER := 1
const _SQLITE_FLOAT := 2
const _SQLITE_NULL := 5
## El binding copia el texto enlazado (SQLITE_TRANSIENT).
const _TRANSIENT := -1
const _INT32_MAX := 2147483647

var last_error := ""

var _api := Sqlite3Wrapper.new()
var _db := Sqlite3Handle.new()
var _open := false


## Motivo del último `open` fallido.
static var open_error := ""


## Conexión abierta con las claves foráneas activas; null si no se pudo abrir
## (el motivo queda en `open_error`).
static func open(path: String) -> SqliteGateway:
	var gateway := SqliteGateway.new()
	open_error = ""
	if gateway._api.open(path, gateway._db) != gateway._api.ok():
		open_error = "no se pudo abrir %s: %s" % [path, gateway._api.errmsg(gateway._db)]
		return null
	gateway._open = true
	if not gateway.execute_script("PRAGMA foreign_keys = ON;"):
		open_error = gateway.last_error
		gateway.close()
		return null
	return gateway


func close() -> void:
	if _open:
		_api.close_v2(_db)
		_open = false


## Varias sentencias sin parámetros (migraciones, PRAGMA).
func execute_script(sql: String) -> bool:
	var result: Dictionary = _api.exec(_db, sql, Callable())
	if int(result.get("code", -1)) != _api.ok():
		return _fail(str(result.get("error_message", "")))
	last_error = ""
	return true


## Una sentencia con parámetros; verdadero si terminó sin error.
func execute(sql: String, params: Array = []) -> bool:
	var stmt := _prepare(sql, params)
	if stmt == null:
		return false
	var code := _api.step(stmt)
	while code == _api.row():
		code = _api.step(stmt)
	_api.finalize(stmt)
	if code != _api.done():
		return _fail(_api.errmsg(_db))
	last_error = ""
	return true


## Filas de una consulta, cada una como { columna: valor }. Vacío si falla: revisar
## `last_error` cuando hace falta distinguir "sin filas" de "error".
func query(sql: String, params: Array = []) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var stmt := _prepare(sql, params)
	if stmt == null:
		return rows
	var code := _api.step(stmt)
	while code == _api.row():
		rows.append(_read_row(stmt))
		code = _api.step(stmt)
	_api.finalize(stmt)
	if code != _api.done():
		_fail(_api.errmsg(_db))
		return []
	last_error = ""
	return rows


## Primera columna de la primera fila; `fallback` si no hay filas.
func scalar(sql: String, params: Array = [], fallback: Variant = null) -> Variant:
	var rows := query(sql, params)
	if rows.is_empty():
		return fallback
	return rows[0].values()[0]


## Clave (rowid) de la última fila insertada en esta conexión.
func last_insert_id() -> int:
	return _api.last_insert_rowid(_db)


## Ejecuta `work` (Callable -> bool) en una transacción: COMMIT si devuelve true,
## ROLLBACK si devuelve false o si el COMMIT falla. Nunca deja escrituras parciales.
func transaction(work: Callable) -> bool:
	if not execute_script("BEGIN IMMEDIATE;"):
		return false
	var ok: bool = work.call()
	var reason := last_error
	if ok and execute_script("COMMIT;"):
		return true
	_api.exec(_db, "ROLLBACK;", Callable())
	last_error = reason if reason != "" else last_error
	return false


# ======================================================================= internos
func _prepare(sql: String, params: Array) -> Sqlite3StmtHandle:
	var prepared: Dictionary = _api.prepare_v2(_db, sql, -1)
	if int(prepared.get("error_code", -1)) != _api.ok():
		_fail("%s | %s" % [_api.errmsg(_db), sql])
		return null
	var stmt: Sqlite3StmtHandle = prepared["statement"]
	for i in params.size():
		if _bind(stmt, i + 1, params[i]) != _api.ok():
			_fail("%s | parámetro %d de %s" % [_api.errmsg(_db), i + 1, sql])
			_api.finalize(stmt)
			return null
	return stmt


func _bind(stmt: Sqlite3StmtHandle, index: int, value: Variant) -> int:
	match typeof(value):
		TYPE_NIL:
			return _api.bind_null(stmt, index)
		TYPE_BOOL:
			return _api.bind_int64(stmt, index, 1 if value else 0)
		TYPE_INT:
			# bind_int64 del binding trunca a 32 bits: los enteros grandes (marcas de
			# tiempo en ms) van como texto y la tabla STRICT los convierte sin pérdida.
			if value > _INT32_MAX or value < -_INT32_MAX:
				return _api.bind_text(stmt, index, str(value), -1, _TRANSIENT)
			return _api.bind_int64(stmt, index, value)
		TYPE_FLOAT:
			return _api.bind_double(stmt, index, value)
		_:
			return _api.bind_text(stmt, index, str(value), -1, _TRANSIENT)


func _read_row(stmt: Sqlite3StmtHandle) -> Dictionary:
	var row := {}
	for column in _api.column_count(stmt):
		row[_api.column_name(stmt, column)] = _read_value(stmt, column)
	return row


func _read_value(stmt: Sqlite3StmtHandle, column: int) -> Variant:
	match _api.column_type(stmt, column):
		_SQLITE_NULL:
			return null
		_SQLITE_INTEGER:
			return _api.column_int64(stmt, column)
		_SQLITE_FLOAT:
			return _api.column_double(stmt, column)
		_:
			return _api.column_text(stmt, column)


func _fail(message: String) -> bool:
	last_error = message
	return false
