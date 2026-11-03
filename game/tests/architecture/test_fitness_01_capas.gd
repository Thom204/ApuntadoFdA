extends GutTest
## FF-01 Aislamiento de capas (regla 5.1 y D-05)
## FF-04 El núcleo no usa APIs de interfaz, transporte ni persistencia (D-05)

const Config := preload("res://tests/architecture/support/arch_config.gd")
const Scanner := preload("res://tests/architecture/support/arch_scanner.gd")

var _graph: Dictionary


func before_all() -> void:
	_graph = Scanner.cached_graph(Config.MODULES, Config.EXCLUDED_PATHS)


func test_ff01_la_presentacion_y_el_nucleo_respetan_las_capas() -> void:
	var violations := Scanner.forbidden_dependencies(_graph, Config.forbidden_dependencies())
	assert_true(violations.is_empty(),
		"FF-01 violada (%d):\n  %s" % [violations.size(), "\n  ".join(violations)])


func test_ff04_el_nucleo_no_usa_apis_de_ui_red_ni_persistencia() -> void:
	var core_files: Array = []
	for f: String in _graph["files"]:
		if f.get_extension() == "gd" and Scanner.module_of(f, Config.MODULES) in Config.CORE_MODULES:
			core_files.append(f)
	var violations := Scanner.forbidden_usages(
		core_files, Config.FORBIDDEN_IN_CORE_IDENTIFIERS, Config.FORBIDDEN_IN_CORE_PATTERNS)
	assert_true(violations.is_empty(),
		"FF-04 violada (%d):\n  %s" % [violations.size(), "\n  ".join(violations)])
