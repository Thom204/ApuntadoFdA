class_name RuleRegistry
extends RefCounted
## Registro y cargador de plug-ins de reglas (ADR-03). Es el único punto que
## instancia reglas, y solo por carga dinámica a partir de plugin.cfg: ningún
## archivo del núcleo referencia una regla concreta.
##
## v1 del MVP: los plug-ins se descubren como carpetas bajo un directorio res://.
## El empaquetado en .pck con verificación de hash (ADR-03, elemento 3) queda
## pendiente; el contrato y el descubrimiento ya son los definitivos.

const DEFAULT_PLUGIN_DIR := "res://rules/modes"
const REQUIRED_MODES: Array[StringName] = [&"classic", &"apuntado"]

var _evaluator: HandEvaluator
## id -> { script: Script, display_name: String, defaults: Dictionary }
var _catalog: Dictionary = {}
var _rejections: Array[String] = []


func _init(evaluator: HandEvaluator) -> void:
	_evaluator = evaluator


func load_plugins(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_rejections.append("%s: carpeta de plug-ins inexistente" % dir_path)
		return
	var folders := Array(dir.get_directories())
	folders.sort()
	for folder in folders:
		_load_one(dir_path.path_join(folder))


func available_modes() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_catalog.keys())
	out.sort()
	return out


func has_required_modes() -> bool:
	for mode in REQUIRED_MODES:
		if not _catalog.has(mode):
			return false
	return true


func display_name(mode: StringName) -> String:
	return _catalog[mode]["display_name"] if _catalog.has(mode) else ""


func default_settings(mode: StringName) -> RuleSettings:
	if not _catalog.has(mode):
		return null
	return RuleSettings.from_dictionary(_catalog[mode]["defaults"])


## Nueva instancia de la regla para una partida. `settings` nulo = valores del plug-in.
func resolve(mode: StringName, settings: RuleSettings = null) -> GameRule:
	if not _catalog.has(mode):
		return null
	var rule: GameRule = _catalog[mode]["script"].new()
	rule.configure(mode, settings if settings != null else default_settings(mode), _evaluator)
	return rule


## Plug-ins rechazados y su motivo (log de auditoría, RNF 5).
func rejections() -> Array[String]:
	return _rejections.duplicate()


# ======================================================================= carga
func _load_one(folder: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(folder.path_join("plugin.cfg")) != OK:
		return
	var problem := _problem_with(cfg)
	if problem != "":
		_rejections.append("%s: %s" % [folder, problem])
		return
	var id := StringName(cfg.get_value("plugin", "id"))
	_catalog[id] = {
		"script": load(cfg.get_value("plugin", "script")),
		"display_name": str(cfg.get_value("plugin", "display_name", id)),
		"defaults": _section(cfg, "defaults"),
	}


func _problem_with(cfg: ConfigFile) -> String:
	var id := StringName(cfg.get_value("plugin", "id", ""))
	if id == &"":
		return "plugin.cfg sin id"
	if _catalog.has(id):
		return "id duplicado '%s'" % id
	if int(cfg.get_value("plugin", "contract_version", -1)) != GameRule.CONTRACT_VERSION:
		return "versión de contrato distinta de %d" % GameRule.CONTRACT_VERSION
	var path := str(cfg.get_value("plugin", "script", ""))
	if not ResourceLoader.exists(path):
		return "script inexistente '%s'" % path
	if not _extends_game_rule(load(path)):
		return "el script no hereda de GameRule"
	return ""


func _extends_game_rule(script: Script) -> bool:
	var base := script
	while base != null:
		if base == GameRule:
			return true
		base = base.get_base_script()
	return false


func _section(cfg: ConfigFile, section: String) -> Dictionary:
	var out := {}
	if cfg.has_section(section):
		for key in cfg.get_section_keys(section):
			out[key] = cfg.get_value(section, key)
	return out
