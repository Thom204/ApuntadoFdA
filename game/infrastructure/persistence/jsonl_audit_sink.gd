class_name JsonlAuditSink
extends IAuditSink
## Adaptador de auditoría en archivo (D-20): una línea JSON por entrada (JSONL), solo
## agrega al final. Cada línea se baja a disco al escribirse, para que la evidencia de
## una sesión sobreviva a una caída del servidor. La ruta la entrega la configuración
## del servidor (D-19), fuera de res://.

## Motivo del último `open` fallido.
static var open_error := ""

var _file: FileAccess


## Abre (o crea) el archivo y se ubica al final; null si no se pudo.
static func open(path: String) -> JsonlAuditSink:
	open_error = ""
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	var file := FileAccess.open(path, mode)
	if file == null:
		open_error = "no se pudo abrir %s: %s" % [path, error_string(FileAccess.get_open_error())]
		return null
	file.seek_end()
	var sink := JsonlAuditSink.new()
	sink._file = file
	return sink


func write(entry: Dictionary) -> void:
	if _file == null:
		return
	_file.store_line(JSON.stringify(entry))
	_file.flush()


func close() -> void:
	if _file != null:
		_file.close()
		_file = null
