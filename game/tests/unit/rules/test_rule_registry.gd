extends GutTest
## Rule Selection: descubrimiento y validación de plug-ins en tiempo de ejecución (ADR-03).

const FIXTURES := "res://tests/fixtures/rule_plugins"

var _registry: RuleRegistry


func before_each() -> void:
	_registry = RuleRegistry.new(HandEvaluator.new())


func test_descubre_classic_y_apuntado() -> void:
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	assert_has(_registry.available_modes(), &"classic")
	assert_has(_registry.available_modes(), &"apuntado")
	assert_true(_registry.has_required_modes())


func test_resolve_devuelve_una_instancia_nueva_por_partida() -> void:
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	var a := _registry.resolve(&"apuntado")
	var b := _registry.resolve(&"apuntado")
	assert_not_null(a)
	assert_ne(a, b)
	assert_eq(a.mode_id(), &"apuntado")


func test_resolve_de_una_modalidad_desconocida_devuelve_null() -> void:
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	assert_null(_registry.resolve(&"poker"))


func test_resolve_aplica_los_valores_por_defecto_del_plugin() -> void:
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	var settings := _registry.default_settings(&"apuntado")
	assert_eq(settings.elimination_threshold, 101)
	assert_eq(settings.max_leftover_points, 5)


func test_resolve_acepta_parametros_propios_de_la_partida() -> void:
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	var settings := _registry.default_settings(&"apuntado")
	settings.elimination_threshold = 51
	var rule := _registry.resolve(&"apuntado", settings)
	assert_false(rule.is_eliminated(50))
	assert_true(rule.is_eliminated(51))


func test_carga_un_plugin_nuevo_sin_tocar_el_nucleo() -> void:
	_registry.load_plugins(FIXTURES)
	assert_has(_registry.available_modes(), &"dummy")


func test_rechaza_version_de_contrato_distinta() -> void:
	_registry.load_plugins(FIXTURES)
	assert_does_not_have(_registry.available_modes(), &"bad_version")
	assert_true(_has_rejection("bad_version"))


func test_rechaza_script_que_no_hereda_de_game_rule() -> void:
	_registry.load_plugins(FIXTURES)
	assert_does_not_have(_registry.available_modes(), &"not_a_rule")
	assert_true(_has_rejection("not_a_rule"))


func test_rechaza_id_duplicado() -> void:
	_registry.load_plugins(FIXTURES)
	assert_true(_has_rejection("duplicado"), "el segundo plug-in con id 'dummy' se rechaza")


func test_sin_classic_ni_apuntado_no_cumple_el_minimo() -> void:
	_registry.load_plugins(FIXTURES)
	assert_false(_registry.has_required_modes())


func _has_rejection(fragment: String) -> bool:
	for line in _registry.rejections():
		if line.contains(fragment):
			return true
	return false
