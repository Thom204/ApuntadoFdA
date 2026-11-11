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


func test_plugin_dependencies_reporta_al_nucleo_que_depende_de_un_plugin() -> void:
	var g := _graph({}, {
		"res://match/m.gd": PackedStringArray(["res://rules/modes/apuntado/apuntado_rule.gd"]),
		"res://rules/rule_registry.gd": PackedStringArray(["res://rules/game_rule.gd"]),
		"res://rules/modes/apuntado/apuntado_rule.gd": PackedStringArray(["res://rules/game_rule.gd"]),
	})
	var found := Scanner.plugin_dependencies(g, "res://rules/modes/")
	assert_eq(found.size(), 1, "solo match -> plug-in: %s" % [found])
	assert_string_contains(found[0], "res://match/m.gd")


func test_plugin_dependencies_permite_que_un_plugin_use_su_propia_carpeta() -> void:
	var g := _graph({}, {
		"res://rules/modes/classic/classic_rule.gd": PackedStringArray(["res://rules/modes/classic/plugin.cfg"]),
	})
	assert_true(Scanner.plugin_dependencies(g, "res://rules/modes/").is_empty())


func test_plugin_dependencies_no_cuenta_la_carpeta_de_descubrimiento() -> void:
	# RuleRegistry conoce DÓNDE buscar plug-ins, no un plug-in concreto.
	var g := _graph({}, {"res://rules/rule_registry.gd": PackedStringArray(["res://rules/modes/"])})
	assert_true(Scanner.plugin_dependencies(g, "res://rules/modes/").is_empty())


func test_forbidden_usages_encuentra_apis_prohibidas_con_linea() -> void:
	var path := "user://arch_tmp_forbidden.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('extends Node\nvar ws := WebSocketPeer.new()\n# Control en un comentario\n@rpc("any_peer")\nfunc f(): pass\n')
	f.close()
	var found := Scanner.forbidden_usages([path], ["WebSocketPeer", "Control"], ["@rpc"])
	assert_eq(found.size(), 2, "WebSocketPeer (línea 2) y @rpc (línea 4); el comentario no cuenta: %s" % [found])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_patrones_de_ff07_detectan_emision_de_eventos_y_llamadas_a_comandos() -> void:
	const Config := preload("res://tests/architecture/support/arch_config.gd")
	var path := "user://arch_tmp_events.gd"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('func f(o):\n\tturn_changed.emit(&"a")\n\to.discard(&"a", 3)\n\t# match_finished.emit() en un comentario\n\tprint("o.discard(")\n')
	f.close()
	var emits := Scanner.forbidden_usages([path], [], [Config.event_emit_pattern()])
	var commands := Scanner.forbidden_usages([path], [], [Config.command_call_pattern()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert_eq(emits.size(), 1, "solo la línea 2: %s" % [emits])
	assert_eq(commands.size(), 1, "solo la línea 3: %s" % [commands])


# ----------------------------------------------------------------- métricas de modularidad (cap. 3)
const _MODULES := {"res://a/": "a", "res://b/": "b", "res://c/": "c"}


## a/x y a/y (abstracto); b/z usa a/x y a/y; c/w usa a/x y b/z. Valores calculados a mano.
func _fixture_deps() -> Dictionary:
	return {
		"res://a/x.gd": PackedStringArray(["res://a/y.gd", "res://addons/gut/gut.gd"]),
		"res://a/y.gd": PackedStringArray(),
		"res://b/z.gd": PackedStringArray(["res://a/x.gd", "res://a/y.gd"]),
		"res://c/w.gd": PackedStringArray(["res://a/x.gd", "res://b/z.gd"]),
	}


func test_module_metrics_calcula_ca_ce_inestabilidad_abstraccion_y_distancia() -> void:
	var m := Scanner.module_metrics(_fixture_deps(), _MODULES, ["res://a/y.gd"])
	assert_eq([m["a"]["ca"], m["a"]["ce"], m["a"]["files"]], [2, 0, 2], "a: lo usan b/z y c/w")
	assert_almost_eq(m["a"]["i"], 0.0, 0.001)
	assert_almost_eq(m["a"]["a"], 0.5, 0.001)
	assert_almost_eq(m["a"]["d"], 0.5, 0.001)
	assert_eq([m["b"]["ca"], m["b"]["ce"]], [1, 2])
	assert_almost_eq(m["b"]["i"], 0.667, 0.001)
	assert_almost_eq(m["b"]["d"], 0.333, 0.001)
	assert_eq([m["c"]["ca"], m["c"]["ce"]], [0, 2])
	assert_almost_eq(m["c"]["i"], 1.0, 0.001)
	assert_almost_eq(m["c"]["d"], 0.0, 0.001, "c es concreto e inestable: está sobre la secuencia principal")


func test_module_metrics_de_un_modulo_aislado_tiene_inestabilidad_cero() -> void:
	var m := Scanner.module_metrics({"res://a/x.gd": PackedStringArray()}, _MODULES, [])
	assert_eq(m["a"]["i"], 0.0)
	assert_almost_eq(m["a"]["d"], 1.0, 0.001, "concreto y estable: zona de dolor")


func test_is_abstract_source_reconoce_abstract_fuera_de_comentarios() -> void:
	assert_true(Scanner.is_abstract_source("@abstract class_name GameRule extends RefCounted\n"))
	assert_true(Scanner.is_abstract_source("extends RefCounted\n@abstract func load(id) -> Dictionary\n"))
	assert_false(Scanner.is_abstract_source("extends RefCounted\n# @abstract en un comentario\nvar s = \"@abstract\"\n"))


func test_metrics_report_tabula_cada_modulo_y_las_cadenas_de_demeter() -> void:
	var m := Scanner.module_metrics(_fixture_deps(), _MODULES, ["res://a/y.gd"])
	var chains := {"b": [{"line": 4, "chain": "x().y(", "text": "x().y()", "file": "res://b/z.gd"}]}
	var report := Scanner.metrics_report(m, chains)
	assert_string_contains(report, "| a | 2 | 2 | 0 | 0.00 | 0.50 | 0.50 | 0 |")
	assert_string_contains(report, "| b | 1 | 1 | 2 | 0.67 | 0.00 | 0.33 | 1 |")
	assert_string_contains(report, "res://b/z.gd:4")


# ----------------------------------------------------------------- Ley de Deméter
func test_demeter_detecta_llamadas_encadenadas_sobre_el_resultado_de_otra_llamada() -> void:
	var src := "func f():\n" \
		+ "\tvar a := _match.current_round().current_player_id()\n" \
		+ "\tvar b := hand.cards().size()\n" \
		+ "\tvar c := Deck.new().shuffle()\n" \
		+ "\tvar d := foo.bar()\n" \
		+ "\t# x.y().z()\n" \
		+ "\tvar e := str(x).to_upper()\n" \
		+ "\tvar g := _round().current_player_id()\n"
	var found := Scanner.demeter_chains_in_source(src)
	assert_eq(found.size(), 2, "líneas 2 y 8; size(), new() y str() no cuentan: %s" % [found])
	assert_eq(found[0]["line"], 2)
	assert_string_contains(found[0]["chain"], "current_round().current_player_id(")
	assert_eq(found[1]["line"], 8, "un método privado también cuenta")


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
