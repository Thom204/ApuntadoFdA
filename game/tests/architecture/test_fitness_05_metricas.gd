extends GutTest
## Métricas de modularidad y Ley de Deméter (E3, sección 4.2; Richards y Ford, cap. 3).
## Mide y publica; todavía no impone umbrales. El reporte queda en
## res://tests/results/metricas.md, que CI sube como artefacto junto con los JUnit.

const Config := preload("res://tests/architecture/support/arch_config.gd")
const Scanner := preload("res://tests/architecture/support/arch_scanner.gd")
const REPORT_PATH := "res://tests/results/metricas.md"

var _graph: Dictionary


func before_all() -> void:
	_graph = Scanner.cached_graph(Config.MODULES, Config.EXCLUDED_PATHS)


func _abstract_files() -> Array:
	var out: Array = []
	for f: String in _graph["files"]:
		if f.get_extension() == "gd" and Scanner.is_abstract_source(FileAccess.get_file_as_string(f)):
			out.append(f)
	return out


func _demeter_chains_by_module() -> Dictionary:
	var out := {}
	for f: String in _graph["files"]:
		var module_name := Scanner.module_of(f, Config.MODULES)
		if f.get_extension() != "gd" or module_name == "":
			continue
		for chain in Scanner.demeter_chains_in_source(FileAccess.get_file_as_string(f)):
			chain["file"] = f
			if not out.has(module_name):
				out[module_name] = []
			out[module_name].append(chain)
	return out


func test_metricas_de_cada_modulo_del_nucleo_se_publican() -> void:
	var metrics := Scanner.module_metrics(_graph["file_deps"], Config.MODULES, _abstract_files())
	var report := Scanner.metrics_report(metrics, _demeter_chains_by_module())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_PATH.get_base_dir()))
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	assert_not_null(file, "no se pudo escribir %s" % REPORT_PATH)
	if file != null:
		file.store_string(report)
		file.close()
	gut.p(report)
	for module_name in ["match", "turn", "scoring", "rules", "deck", "orchestration"]:
		assert_true(metrics.has(module_name), "sin métricas para %s" % module_name)
