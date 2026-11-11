extends GutTest
## FF-07 Eventos post-commit (ADR-05, cumplimiento 2 y 3)
##   - Solo Match Orchestration emite IGameEvents.
##   - No hay un bus de eventos global (autoload).
##   - Los suscriptores de IGameEvents no invocan comandos: un evento no dispara un comando.

const Config := preload("res://tests/architecture/support/arch_config.gd")
const Scanner := preload("res://tests/architecture/support/arch_scanner.gd")

var _graph: Dictionary


func before_all() -> void:
	_graph = Scanner.cached_graph(Config.MODULES, Config.EXCLUDED_PATHS)


func _gd_files_where(keep: Callable) -> Array:
	var out: Array = []
	for f: String in _graph["files"]:
		if f.get_extension() == "gd" and keep.call(f):
			out.append(f)
	return out


func test_ff07_solo_orchestration_emite_los_eventos_de_juego() -> void:
	var files := _gd_files_where(func(f: String) -> bool:
		return Scanner.module_of(f, Config.MODULES) != Config.EVENT_EMITTER_MODULE \
			and not f in Config.EVENT_EMIT_ALLOWED_FILES)
	var violations := Scanner.forbidden_usages(files, [], [Config.event_emit_pattern()])
	assert_true(violations.is_empty(),
		"FF-07 violada, IGameEvents emitido fuera de %s (%d):\n  %s"
		% [Config.EVENT_EMITTER_MODULE, violations.size(), "\n  ".join(violations)])


func test_ff07_no_hay_bus_de_eventos_global() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK)
	assert_false(cfg.has_section("autoload"),
		"FF-07 violada: project.godot declara autoloads %s" % [cfg.get_section_keys("autoload") if cfg.has_section("autoload") else []])


func test_ff07_los_suscriptores_de_eventos_no_invocan_comandos() -> void:
	var files := _gd_files_where(func(f: String) -> bool:
		return Scanner.module_of(f, Config.MODULES) in Config.EVENT_SUBSCRIBER_MODULES)
	var violations := Scanner.forbidden_usages(files, [], [Config.command_call_pattern()])
	assert_true(violations.is_empty(),
		"FF-07 violada, un suscriptor invoca un comando (%d):\n  %s" % [violations.size(), "\n  ".join(violations)])
