extends GutTest
## Pruebas de las propias fitness functions: si el escáner falla, una regla podría
## "pasar" sin estar comprobando nada. Usan texto en memoria, no el código del juego.

const Scanner := preload("res://tests/architecture/support/arch_scanner.gd")


# ----------------------------------------------------------------- sanitize
func test_sanitize_quita_comentarios_y_vacia_textos() -> void:
	var src := 'var a = "if or and" # if b\nvar c = 1'
	var clean := Scanner.sanitize(src, false)
	assert_false(clean.contains("if"), "no debe quedar ninguna palabra clave: %s" % clean)
	assert_true(clean.contains("var c = 1"))


func test_sanitize_conserva_numeracion_de_lineas_en_textos_multilinea() -> void:
	var src := 'var doc = """uno\ndos\ntres"""\nvar x = 1'
	assert_eq(Scanner.sanitize(src, false).count("\n"), src.count("\n"))


func test_sanitize_no_confunde_numeral_dentro_de_un_texto() -> void:
	var src := 'var url = "res://a/b.gd#frag"\nvar y = 2'
	assert_true(Scanner.sanitize(src, true).contains("res://a/b.gd#frag"))


# ----------------------------------------------------------------- dependencias
func test_detecta_preload_load_y_extends_por_ruta() -> void:
	var src := 'extends "res://rules/base.gd"\nconst A = preload("res://deck/card.gd")\nfunc f():\n\treturn load("res://scoring/x.gd")'
	var deps := Scanner.dependencies_in_source(src, "res://m/x.gd", {})
	assert_has(deps, "res://rules/base.gd")
	assert_has(deps, "res://deck/card.gd")
	assert_has(deps, "res://scoring/x.gd")


func test_detecta_dependencia_por_class_name_y_autoload() -> void:
	var names := {"Card": "res://deck/card.gd", "MatchOrchestrator": "res://orchestration/o.gd"}
	var src := "func f(c: Card):\n\tMatchOrchestrator.start()"
	var deps := Scanner.dependencies_in_source(src, "res://m/x.gd", names)
	assert_has(deps, "res://deck/card.gd")
	assert_has(deps, "res://orchestration/o.gd")


func test_ignora_referencias_en_comentarios_y_textos() -> void:
	var names := {"Card": "res://deck/card.gd"}
	var src := '# usa Card\nvar s = "Card"\n'
	assert_eq(Scanner.dependencies_in_source(src, "res://m/x.gd", names).size(), 0)


func test_detecta_dependencias_en_escenas() -> void:
	var tscn := '[ext_resource type="Script" path="res://infrastructure/persistence/repo.gd" id="1"]'
	var deps := Scanner.dependencies_in_source(tscn, "res://presentation/t.tscn", {})
	assert_has(deps, "res://infrastructure/persistence/repo.gd")


func test_module_of_usa_el_prefijo_mas_largo() -> void:
	var modules := {"res://infrastructure/": "infra", "res://infrastructure/network/": "infra.net"}
	assert_eq(Scanner.module_of("res://infrastructure/network/a.gd", modules), "infra.net")
	assert_eq(Scanner.module_of("res://infrastructure/b.gd", modules), "infra")
	assert_eq(Scanner.module_of("res://otro/c.gd", modules), "")


# ----------------------------------------------------------------- reglas sobre un grafo sintético
func _graph(module_edges: Dictionary, file_deps: Dictionary = {}) -> Dictionary:
	return {"module_deps": module_edges, "file_deps": file_deps, "files": PackedStringArray()}


func test_forbidden_dependencies_reporta_la_violacion() -> void:
	var g := _graph({"presentation": {"infrastructure.persistence": ["a.gd -> b.gd"]}})
	var rules := {"presentation": ["infrastructure.persistence"]}
	assert_eq(Scanner.forbidden_dependencies(g, rules).size(), 1)


func test_forbidden_dependencies_no_reporta_dependencias_permitidas() -> void:
	var g := _graph({"presentation": {"infrastructure.network": ["a.gd -> b.gd"]}})
	var rules := {"presentation": ["infrastructure.persistence"]}
	assert_eq(Scanner.forbidden_dependencies(g, rules).size(), 0)


func test_find_cycle_detecta_un_ciclo_de_tres_modulos() -> void:
	var g := {"a": {"b": []}, "b": {"c": []}, "c": {"a": []}}
	var cycle := Scanner.find_cycle(g)
	assert_false(cycle.is_empty())
	assert_eq(cycle[0], cycle[cycle.size() - 1], "el ciclo debe cerrarse sobre el mismo módulo")


func test_find_cycle_acepta_un_grafo_aciclico() -> void:
	assert_true(Scanner.find_cycle({"a": {"b": [], "c": []}, "b": {"c": []}}).is_empty())


func test_variantes_distintas_no_pueden_depender_entre_si() -> void:
	var groups := {"clasica": ["res://rules/modes/classic"], "apuntado": ["res://rules/modes/apuntado"]}
	var bad := _graph({}, {"res://rules/modes/classic_rule.gd": PackedStringArray(["res://rules/modes/apuntado_rule.gd"])})
	var ok := _graph({}, {"res://rules/modes/classic_rule.gd": PackedStringArray(["res://deck/card.gd"])})
	assert_eq(Scanner.variant_cross_dependencies(bad, groups).size(), 1)
	assert_eq(Scanner.variant_cross_dependencies(ok, groups).size(), 0)


func test_forbidden_usages_encuentra_apis_prohibidas_con_linea() -> void:
	var path := "user://arch_tmp_forbidden.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('extends Node\nvar ws := WebSocketPeer.new()\n# Control en un comentario\n@rpc("any_peer")\nfunc f(): pass\n')
	f.close()
	var found := Scanner.forbidden_usages([path], ["WebSocketPeer", "Control"], ["@rpc"])
	assert_eq(found.size(), 2, "WebSocketPeer (línea 2) y @rpc (línea 4); el comentario no cuenta: %s" % [found])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ----------------------------------------------------------------- complejidad ciclomática
func _cc(src: String) -> int:
	return Scanner.function_complexities(src)[0]["cc"]


func test_cc_de_una_funcion_lineal_es_1() -> void:
	assert_eq(_cc("func f():\n\treturn 1\n"), 1)


func test_cc_cuenta_if_elif_y_no_cuenta_else() -> void:
	assert_eq(_cc("func f(x):\n\tif x == 1:\n\t\tpass\n\telif x == 2:\n\t\tpass\n\telse:\n\t\tpass\n"), 3)


func test_cc_cuenta_bucles_operadores_y_ternario() -> void:
	var src := "func f(a, b):\n\tfor i in a:\n\t\twhile b and i or b:\n\t\t\tpass\n\treturn 1 if a else 2\n"
	assert_eq(_cc(src), 1 + 1 + 1 + 2 + 1)   # for + while + (and, or) + ternario


func test_cc_cuenta_las_ramas_de_match_sin_la_comodin() -> void:
	var src := "func f(x):\n\tmatch x:\n\t\t1:\n\t\t\tpass\n\t\t2, 3:\n\t\t\tpass\n\t\t_:\n\t\t\tpass\n"
	assert_eq(_cc(src), 3)


func test_cc_cuenta_ramas_de_match_escritas_en_una_sola_linea() -> void:
	var src := "func f(x):\n\tmatch x:\n\t\t1: print(1)\n\t\t2, 3: print(2)\n\t\t_: print(3)\n"
	assert_eq(_cc(src), 3)


func test_cc_ignora_palabras_clave_en_textos_y_comentarios() -> void:
	assert_eq(_cc('func f():\n\t# if a or b\n\tvar s = "if x and y"\n\treturn s\n'), 1)


func test_cc_separa_funciones_y_soporta_encabezados_multilinea() -> void:
	var src := "func a(x):\n\tif x:\n\t\tpass\n\nfunc b(\n\t\tp1,\n\t\tp2\n) -> void:\n\tpass\n"
	var result := Scanner.function_complexities(src)
	assert_eq(result.size(), 2)
	assert_eq(result[0]["cc"], 2)
	assert_eq(result[1]["cc"], 1)
