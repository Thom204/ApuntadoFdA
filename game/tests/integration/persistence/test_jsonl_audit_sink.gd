extends GutTest
## Adaptador de auditoría en archivo (D-20): una línea JSON por entrada, solo agrega
## al final y sobrevive a un reinicio del servidor (reabrir no borra lo anterior).

var _path: String


func before_each() -> void:
	_path = ProjectSettings.globalize_path("user://test_audit_%d.jsonl" % Time.get_ticks_usec())


func after_each() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)


func _lines() -> PackedStringArray:
	return FileAccess.get_file_as_string(_path).strip_edges().split("\n")


func test_escribe_una_linea_json_por_entrada() -> void:
	var sink := JsonlAuditSink.open(_path)
	assert_not_null(sink)
	sink.write({"kind": "event", "event": "round_started", "data": {"round_number": 1}})
	sink.write({"kind": "request", "type": "discard", "ok": true})
	sink.close()
	var lines := _lines()
	assert_eq(lines.size(), 2)
	assert_eq(JSON.parse_string(lines[0])["event"], "round_started")
	assert_eq(JSON.parse_string(lines[1])["type"], "discard")


func test_reabrir_el_archivo_agrega_al_final() -> void:
	var first := JsonlAuditSink.open(_path)
	first.write({"n": 1})
	first.close()
	var second := JsonlAuditSink.open(_path)
	second.write({"n": 2})
	second.close()
	assert_eq(Array(_lines()).map(func(l: String) -> int: return int(JSON.parse_string(l)["n"])), [1, 2])


func test_lo_escrito_se_ve_sin_cerrar_el_archivo() -> void:
	var sink := JsonlAuditSink.open(_path)
	sink.write({"n": 1})
	assert_eq(_lines().size(), 1, "si el servidor se cae, la evidencia ya está en disco")
	sink.close()


func test_una_ruta_imposible_no_abre() -> void:
	assert_null(JsonlAuditSink.open(ProjectSettings.globalize_path("user://no/existe/audit.jsonl")))
	assert_ne(JsonlAuditSink.open_error, "")
