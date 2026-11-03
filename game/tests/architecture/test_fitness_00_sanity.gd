extends GutTest
## Evita los "falsos verdes": si el análisis no ve código, las demás fitness functions
## pasarían sin comprobar nada.

const Config := preload("res://tests/architecture/support/arch_config.gd")
const Scanner := preload("res://tests/architecture/support/arch_scanner.gd")


func test_el_analisis_encuentra_scripts() -> void:
	var files := Scanner.list_files("res://", ["gd"], Config.EXCLUDED_PATHS)
	assert_gt(files.size(), 0,
		"El escáner no encontró ningún .gd fuera de %s. Revisa EXCLUDED_PATHS." % [Config.EXCLUDED_PATHS])


func test_cada_modulo_declarado_tiene_archivos() -> void:
	var files := Scanner.list_files("res://", ["gd", "tscn", "tres"], Config.EXCLUDED_PATHS)
	var modules_with_files := 0
	for prefix: String in Config.MODULES.keys():
		var has_files := false
		for f in files:
			if f.begins_with(prefix):
				has_files = true
				break
		if has_files:
			modules_with_files += 1
		else:
			pending("Módulo sin archivos todavía: %s (si la carpeta cambió de nombre, ajusta ArchConfig.MODULES)" % prefix)
	assert_gt(modules_with_files, 0, "Ningún módulo de ArchConfig.MODULES coincide con carpetas del proyecto.")
