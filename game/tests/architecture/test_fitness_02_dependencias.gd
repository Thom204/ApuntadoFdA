extends GutTest
## FF-02 Independencia entre modalidades (regla 5.1)
## FF-03 Sin dependencias cíclicas entre módulos

const Config := preload("res://tests/architecture/support/arch_config.gd")
const Scanner := preload("res://tests/architecture/support/arch_scanner.gd")

var _graph: Dictionary


func before_all() -> void:
	_graph = Scanner.cached_graph(Config.MODULES, Config.EXCLUDED_PATHS)


func test_ff02_las_modalidades_no_dependen_entre_si() -> void:
	var violations := Scanner.variant_cross_dependencies(_graph, Config.VARIANT_GROUPS)
	assert_true(violations.is_empty(),
		"FF-02 violada (%d):\n  %s" % [violations.size(), "\n  ".join(violations)])


func test_ff03_no_hay_ciclos_entre_modulos() -> void:
	if not Config.ENFORCE_ACYCLIC_MODULES:
		pending("FF-03 desactivada en ArchConfig.ENFORCE_ACYCLIC_MODULES")
		return
	var cycle := Scanner.find_cycle(_graph["module_deps"])
	var detail := ""
	if not cycle.is_empty():
		detail = " -> ".join(cycle)
		var module_deps: Dictionary = _graph["module_deps"]
		for k in range(cycle.size() - 1):
			var evidence: Array = module_deps[cycle[k]][cycle[k + 1]]
			detail += "\n  %s -> %s: %s" % [cycle[k], cycle[k + 1], evidence[0]]
	assert_true(cycle.is_empty(), "FF-03 violada, ciclo entre módulos:\n  " + detail)
