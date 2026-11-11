extends RefCounted
## Análisis estático de código GDScript para las fitness functions.
##
## Solo usa APIs del motor (sin Python ni herramientas externas), por lo que corre igual
## en el equipo del desarrollador y en integración continua.
## Limitaciones conocidas: detecta dependencias por (a) rutas "res://" y "uid://" literales,
## (b) nombres de `class_name` y (c) autoloads. No ve dependencias dinámicas
## (rutas construidas por concatenación) ni `get_node()` por nombre.

static var _re_cache: Dictionary = {}

static func _re(pattern: String) -> RegEx:
	if not _re_cache.has(pattern):
		var regex := RegEx.new()
		var err := regex.compile(pattern)
		assert(err == OK, "Expresión regular inválida: " + pattern)
		_re_cache[pattern] = regex
	return _re_cache[pattern]

# ======================================================================= archivos
static func list_files(root: String, extensions: Array, excluded: Array) -> PackedStringArray:
	var out := PackedStringArray()
	_walk(root, extensions, excluded, out)
	out.sort()
	return out

static func _walk(dir_path: String, extensions: Array, excluded: Array, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				if not _is_excluded(full + "/", excluded):
					_walk(full, extensions, excluded, out)
			elif full.get_extension() in extensions and not _is_excluded(full, excluded):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()

static func _is_excluded(path: String, excluded: Array) -> bool:
	for prefix: String in excluded:
		if path.begins_with(prefix):
			return true
	return false

static func module_of(path: String, modules: Dictionary) -> String:
	var best := ""
	var best_len := -1
	for prefix: String in modules.keys():
		if path.begins_with(prefix) and prefix.length() > best_len:
			best = modules[prefix]
			best_len = prefix.length()
	return best

# ======================================================================= limpieza de código
## Quita comentarios y, si `keep_strings` es falso, también el contenido de los textos.
## Conserva los saltos de línea para que los números de línea sigan siendo válidos.
static func sanitize(src: String, keep_strings: bool) -> String:
	var out := ""
	var n := src.length()
	var i := 0
	var plain_start := 0
	while i < n:
		var c := src[i]
		if c == "#":
			out += src.substr(plain_start, i - plain_start)
			while i < n and src[i] != "\n":
				i += 1
			plain_start = i
		elif c == "\"" or c == "'":
			out += src.substr(plain_start, i - plain_start)
			var start := i
			var triple := src.substr(i, 3) == c.repeat(3)
			var delim := c.repeat(3) if triple else c
			i += delim.length()
			while i < n:
				var d := src[i]
				if d == "\\":
					i += 2
					continue
				if src.substr(i, delim.length()) == delim:
					i += delim.length()
					break
				if d == "\n" and not triple:
					break
				i += 1
			var literal := src.substr(start, i - start)
			if keep_strings:
				out += literal
			else:
				out += c + c + "\n".repeat(literal.count("\n"))
			plain_start = i
		else:
			i += 1
	out += src.substr(plain_start, n - plain_start)
	return out

# ======================================================================= dependencias
## Nombres globales -> archivo: `class_name` de cada script y autoloads de project.godot.
static func global_names(files: PackedStringArray) -> Dictionary:
	var names := {}
	var regex := _re("(?m)^\\s*class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	for f in files:
		if f.get_extension() != "gd":
			continue
		var found := regex.search(sanitize(FileAccess.get_file_as_string(f), false))
		if found != null:
			names[found.get_string(1)] = f
	var cfg := ConfigFile.new()
	if cfg.load("res://project.godot") == OK and cfg.has_section("autoload"):
		for autoload_name in cfg.get_section_keys("autoload"):
			var target := str(cfg.get_value("autoload", autoload_name)).trim_prefix("*")
			names[autoload_name] = target
	return names

## Rutas de archivo de las que depende el código fuente `src`.
static func dependencies_in_source(src: String, own_path: String, names: Dictionary) -> PackedStringArray:
	var deps := {}
	var is_resource := own_path.get_extension() in ["tscn", "tres"]
	var literal_code := src if is_resource else sanitize(src, true)
	for m in _re("res://[^\"'\\s,)\\]]+").search_all(literal_code):
		deps[m.get_string()] = true
	for m in _re("uid://[a-z0-9]+").search_all(literal_code):
		var id := ResourceUID.text_to_id(m.get_string())
		if ResourceUID.has_id(id):
			deps[ResourceUID.get_id_path(id)] = true
	if not is_resource:
		var code := sanitize(src, false)
		for m in _re("[A-Za-z_][A-Za-z0-9_]*").search_all(code):
			var ident := m.get_string()
			if names.has(ident):
				deps[names[ident]] = true
	deps.erase(own_path)
	return PackedStringArray(deps.keys())

## Construye el grafo de dependencias de todo el proyecto.
## Devuelve { files, file_deps, module_deps, names }.
static func build_graph(modules: Dictionary, excluded: Array) -> Dictionary:
	var files := list_files("res://", ["gd", "tscn", "tres"], excluded)
	var names := global_names(files)
	var file_deps := {}
	var module_deps := {}
	for f in files:
		var deps := dependencies_in_source(FileAccess.get_file_as_string(f), f, names)
		file_deps[f] = deps
		var from_mod := module_of(f, modules)
		if from_mod == "":
			continue
		for d in deps:
			var to_mod := module_of(d, modules)
			if to_mod == "" or to_mod == from_mod:
				continue
			if not module_deps.has(from_mod):
				module_deps[from_mod] = {}
			var edges: Dictionary = module_deps[from_mod]
			if not edges.has(to_mod):
				edges[to_mod] = []
			edges[to_mod].append("%s -> %s" % [f, d])
	return {"files": files, "file_deps": file_deps, "module_deps": module_deps, "names": names}

static var _graph_cache: Dictionary = {}

## Igual que build_graph pero lo calcula una sola vez por ejecución de GUT.
static func cached_graph(modules: Dictionary, excluded: Array) -> Dictionary:
	if _graph_cache.is_empty():
		_graph_cache = build_graph(modules, excluded)
	return _graph_cache

# ======================================================================= reglas
## FF-01. Devuelve una línea por cada dependencia prohibida encontrada.
static func forbidden_dependencies(graph: Dictionary, rules: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var module_deps: Dictionary = graph["module_deps"]
	for from_mod: String in rules.keys():
		if not module_deps.has(from_mod):
			continue
		var edges: Dictionary = module_deps[from_mod]
		for to_mod: String in rules[from_mod]:
			if edges.has(to_mod):
				for evidence: String in edges[to_mod]:
					out.append("[%s] no debe depender de [%s]:  %s" % [from_mod, to_mod, evidence])
	return out

## FF-02. Dependencias entre archivos de grupos de modalidades distintos.
static func variant_cross_dependencies(graph: Dictionary, groups: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var file_deps: Dictionary = graph["file_deps"]
	for f: String in file_deps.keys():
		var from_group := _group_of(f, groups)
		if from_group == "":
			continue
		for d: String in file_deps[f]:
			var to_group := _group_of(d, groups)
			if to_group != "" and to_group != from_group:
				out.append("%s depende de %s  (%s -> %s)" % [f, d, from_group, to_group])
	return out

## FF-06. Archivos de fuera de `plugin_prefix` que dependen de un archivo de dentro:
## el núcleo del microkernel no puede conocer ningún plug-in (ADR-03). Una ruta de
## carpeta (sin extensión) no cuenta: es dónde buscar plug-ins, no un plug-in.
static func plugin_dependencies(graph: Dictionary, plugin_prefix: String) -> Array[String]:
	var out: Array[String] = []
	var file_deps: Dictionary = graph["file_deps"]
	for f: String in file_deps.keys():
		if f.begins_with(plugin_prefix):
			continue
		for d: String in file_deps[f]:
			if d.begins_with(plugin_prefix) and d.get_extension() != "":
				out.append("%s depende del plug-in %s" % [f, d])
	return out


static func _group_of(path: String, groups: Dictionary) -> String:
	for group_name: String in groups.keys():
		for prefix: String in groups[group_name]:
			if path.begins_with(prefix):
				return group_name
	return ""

## FF-03. Primer ciclo encontrado entre módulos (vacío si el grafo es acíclico).
static func find_cycle(module_deps: Dictionary) -> Array[String]:
	var state := {}
	var stack: Array[String] = []
	for start: String in module_deps.keys():
		if state.get(start, 0) == 0:
			var cycle := _dfs(start, module_deps, state, stack)
			if not cycle.is_empty():
				return cycle
	return []

static func _dfs(node: String, module_deps: Dictionary, state: Dictionary, stack: Array[String]) -> Array[String]:
	state[node] = 1
	stack.append(node)
	var edges: Dictionary = module_deps.get(node, {})
	for next: String in edges.keys():
		var status: int = state.get(next, 0)
		if status == 1:
			var cycle: Array[String] = []
			cycle.assign(stack.slice(stack.find(next)))
			cycle.append(next)
			return cycle
		if status == 0:
			var found := _dfs(next, module_deps, state, stack)
			if not found.is_empty():
				return found
	stack.pop_back()
	state[node] = 2
	return []

## FF-04. Usos de identificadores/patrones prohibidos, con archivo y línea.
static func forbidden_usages(paths: Array, identifiers: Array, patterns: Array) -> Array[String]:
	var out: Array[String] = []
	for path: String in paths:
		var lines := sanitize(FileAccess.get_file_as_string(path), false).split("\n")
		for idx in lines.size():
			var line := lines[idx]
			for m in _re("[A-Za-z_][A-Za-z0-9_]*").search_all(line):
				if m.get_string() in identifiers:
					out.append("%s:%d usa `%s`" % [path, idx + 1, m.get_string()])
			for pattern: String in patterns:
				if _re(pattern).search(line) != null:
					out.append("%s:%d usa `%s`" % [path, idx + 1, pattern])
	return out

# ======================================================================= métricas de modularidad
## ¿El script declara algo abstracto (`@abstract class_name` o `@abstract func`)?
static func is_abstract_source(src: String) -> bool:
	return sanitize(src, false).contains("@abstract")


## Métricas de Martin por módulo (Richards y Ford, cap. 3), contando archivos como clases:
##   ca = archivos de OTROS módulos que dependen de alguno del módulo (acoplamiento aferente)
##   ce = archivos de OTROS módulos de los que depende alguno del módulo (eferente)
##   i  = ce / (ca + ce)              inestabilidad (0 si no hay acoplamiento)
##   a  = abstractos / archivos .gd   abstracción
##   d  = |a + i - 1|                 distancia a la secuencia principal
## Las dependencias a archivos sin módulo (addons) no cuentan.
static func module_metrics(file_deps: Dictionary, modules: Dictionary, abstract_files: Array) -> Dictionary:
	var afferent := {}
	var efferent := {}
	var files := {}
	var abstracts := {}
	for f: String in file_deps.keys():
		var from_mod := module_of(f, modules)
		if from_mod == "" or f.get_extension() != "gd":
			continue
		_add_to_set(files, from_mod, f)
		if f in abstract_files:
			_add_to_set(abstracts, from_mod, f)
		for d: String in file_deps[f]:
			var to_mod := module_of(d, modules)
			if to_mod != "" and to_mod != from_mod:
				_add_to_set(efferent, from_mod, d)
				_add_to_set(afferent, to_mod, f)
	var out := {}
	for module_name: String in files.keys():
		out[module_name] = _metrics_row(
			_set_size(afferent, module_name), _set_size(efferent, module_name),
			_set_size(abstracts, module_name), _set_size(files, module_name))
	return out


static func _metrics_row(ca: int, ce: int, abstract_count: int, file_count: int) -> Dictionary:
	var instability := 0.0 if ca + ce == 0 else float(ce) / float(ca + ce)
	var abstractness := float(abstract_count) / float(file_count)
	return {
		"ca": ca, "ce": ce, "files": file_count, "abstract": abstract_count,
		"i": instability, "a": abstractness, "d": absf(abstractness + instability - 1.0),
	}


static func _add_to_set(sets: Dictionary, key: String, value: String) -> void:
	if not sets.has(key):
		sets[key] = {}
	sets[key][value] = true


static func _set_size(sets: Dictionary, key: String) -> int:
	return sets[key].size() if sets.has(key) else 0


# ======================================================================= Ley de Deméter
## Métodos de tipos del motor (Array, Dictionary, String, Signal...) que se aceptan
## sobre el resultado de una llamada: encadenarlos no expone la estructura del dominio.
const BUILTIN_METHODS := [
	"size", "is_empty", "duplicate", "keys", "values", "has", "get", "append", "append_array",
	"erase", "find", "count", "slice", "sort", "back", "front", "map", "filter", "reduce",
	"any", "all", "pop_back", "pop_front", "join", "split", "strip_edges", "to_upper",
	"to_lower", "begins_with", "ends_with", "contains", "substr", "length", "repeat",
	"get_extension", "get_file", "get_base_dir", "path_join", "trim_prefix", "trim_suffix",
	"replace", "get_string", "emit", "is_valid", "call", "bind", "to_int", "to_float", "assign",
	"hash", "abs", "floor", "round", "max", "min",
]


## Cadenas `x.a().b(` donde `b` es un método del dominio invocado sobre lo que devolvió
## `a`: el llamador conoce la estructura interna de lo que recibe (Ley de Deméter).
## No cuentan `X.new().b()` (construcción), las conversiones `Tipo(x).b()` ni los
## métodos de tipos del motor. Limitación: no ve `a(f(x)).b()` (paréntesis anidados).
static func demeter_chains_in_source(src: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var chain_re := _re("\\b([A-Za-z_][A-Za-z0-9_]*)\\([^()]*\\)\\.([A-Za-z_][A-Za-z0-9_]*)\\(")
	var lines := sanitize(src, true).split("\n")
	var code_lines := sanitize(src, false).split("\n")
	for idx in code_lines.size():
		for m in chain_re.search_all(code_lines[idx]):
			var first := m.get_string(1)
			var second := m.get_string(2)
			var is_type_conversion := first[0] >= "A" and first[0] <= "Z"
			if first == "new" or is_type_conversion or second in BUILTIN_METHODS:
				continue
			out.append({"line": idx + 1, "chain": m.get_string(), "text": lines[idx].strip_edges()})
	return out


# ======================================================================= reporte
## Reporte Markdown de métricas (sección 4.2 del E3). `chains`: { módulo: [cadena] }, cada
## cadena con file, line y text.
static func metrics_report(metrics: Dictionary, chains: Dictionary) -> String:
	var modules: Array = metrics.keys()
	modules.sort()
	var out := "# Métricas de modularidad\n\n"
	out += "Ca/Ce cuentan archivos (clases); I = Ce/(Ca+Ce); A = abstractos/archivos; D = |A + I - 1|.\n\n"
	out += "| Módulo | Archivos | Ca | Ce | I | A | D | Cadenas Deméter |\n"
	out += "|---|---|---|---|---|---|---|---|\n"
	for module_name: String in modules:
		var row: Dictionary = metrics[module_name]
		out += "| %s | %d | %d | %d | %.2f | %.2f | %.2f | %d |\n" % [
			module_name, row["files"], row["ca"], row["ce"], row["i"], row["a"], row["d"],
			chains.get(module_name, []).size()]
	out += "\n## Cadenas que van contra la Ley de Deméter\n\n"
	var any := false
	for module_name: String in modules:
		for chain: Dictionary in chains.get(module_name, []):
			out += "- `%s:%d`  `%s`\n" % [chain["file"], chain["line"], chain["text"]]
			any = true
	if not any:
		out += "Ninguna.\n"
	return out


# ======================================================================= complejidad ciclomática
## CC de cada función de `src`: 1 + if/elif/for/while + and/or (&&, ||) + ramas de match.
static func function_complexities(src: String) -> Array[Dictionary]:
	var lines := sanitize(src, false).split("\n")
	var out: Array[Dictionary] = []
	var header_re := _re("^(?:@[A-Za-z_]+(?:\\([^)]*\\))?\\s+)*(?:static\\s+)?func\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var i := 0
	while i < lines.size():
		var found := header_re.search(lines[i].strip_edges())
		if found == null:
			i += 1
			continue
		var indent := _indent_of(lines[i])
		var start_line := i + 1
		# El encabezado puede ocupar varias líneas (parámetros entre paréntesis).
		var body: Array[String] = [lines[i]]
		var depth := _paren_balance(lines[i])
		var j := i + 1
		while depth > 0 and j < lines.size():
			body.append(lines[j])
			depth += _paren_balance(lines[j])
			j += 1
		while j < lines.size():
			var text := lines[j]
			if text.strip_edges() != "" and _indent_of(text) <= indent:
				break
			body.append(text)
			j += 1
		out.append({"name": found.get_string(1), "line": start_line, "cc": 1 + _decision_points(body)})
		i = j
	return out

static func _indent_of(line: String) -> int:
	var count := 0
	while count < line.length() and (line[count] == "\t" or line[count] == " "):
		count += 1
	return count

static func _paren_balance(line: String) -> int:
	return line.count("(") + line.count("[") + line.count("{") - line.count(")") - line.count("]") - line.count("}")

static func _decision_points(body: Array[String]) -> int:
	var points := 0
	var keywords := _re("\\b(if|elif|for|while|and|or)\\b|&&|\\|\\|")
	var k := 0
	while k < body.size():
		var text := body[k]
		var trimmed := text.strip_edges()
		if trimmed.begins_with("match ") or trimmed == "match":
			points += _match_branches(body, k)
		points += keywords.search_all(text).size()
		k += 1
	return points

## Ramas (distintas de la comodín `_:`) del `match` que empieza en la línea `at`.
static func _match_branches(body: Array[String], at: int) -> int:
	var match_indent := _indent_of(body[at])
	var branch_indent := -1
	var branches := 0
	var k := at + 1
	while k < body.size():
		var text := body[k]
		var trimmed := text.strip_edges()
		if trimmed == "":
			k += 1
			continue
		var indent := _indent_of(text)
		if indent <= match_indent:
			break
		if branch_indent == -1:
			branch_indent = indent
		if indent == branch_indent and _is_match_branch(trimmed):
			branches += 1
		k += 1
	return branches

## ¿La línea es el encabezado de una rama de `match` que no sea la comodín `_`?
## Admite `patrón:` y también `patrón: sentencia` en una sola línea.
static func _is_match_branch(trimmed: String) -> bool:
	var depth := 0
	for pos in trimmed.length():
		var c := trimmed[pos]
		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth -= 1
		elif c == ":" and depth == 0:
			return trimmed.substr(0, pos).strip_edges() != "_"
	return false

## FF-05. Funciones de las carpetas de `scope` cuya CC supera `limit`.
static func complexity_violations(files: PackedStringArray, scope: Array, limit: int) -> Array[String]:
	var out: Array[String] = []
	for f in files:
		if f.get_extension() != "gd":
			continue
		var in_scope := false
		for prefix: String in scope:
			if f.begins_with(prefix):
				in_scope = true
		if not in_scope:
			continue
		for fn in function_complexities(FileAccess.get_file_as_string(f)):
			if int(fn["cc"]) > limit:
				out.append("%s:%d  %s()  CC=%d  (límite %d)" % [f, fn["line"], fn["name"], fn["cc"], limit])
	return out
