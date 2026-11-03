extends GutTest
## FF-05 Complejidad ciclomática máxima por función (D-23)

const Config := preload("res://tests/architecture/support/arch_config.gd")
const Scanner := preload("res://tests/architecture/support/arch_scanner.gd")


func test_ff05_ninguna_funcion_supera_el_limite_de_complejidad() -> void:
	var files := Scanner.list_files("res://", ["gd"], Config.EXCLUDED_PATHS)
	var violations := Scanner.complexity_violations(files, Config.CC_SCOPE, Config.CC_LIMIT)
	assert_true(violations.is_empty(),
		"FF-05 violada (%d funciones con CC > %d):\n  %s" % [violations.size(), Config.CC_LIMIT, "\n  ".join(violations)])
