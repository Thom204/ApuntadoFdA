extends Control
## Mesa local (hot seat): arma el servidor real en el mismo proceso (Lobby, reglas,
## SQLite y auditoría) y abre una pestaña por jugador, cada una con su propia
## ClientSession. Es el punto de armado (composition root) del modo local; la versión
## en red tendrá el suyo, con el adaptador de red en lugar de LocalTransport.
##
## Archivos que deja (fuera de res://, en la carpeta de datos del usuario):
##   apuntado_local.db        partidas (ADR-04)
##   auditoria_local.jsonl    solicitudes y eventos, evidencia para las pruebas (D-20)

const DB_PATH := "user://apuntado_local.db"
const AUDIT_PATH := "user://auditoria_local.jsonl"
const MIN_PLAYERS := 2
const MAX_PLAYERS := 5
## Espera antes de pasar a la pestaña del siguiente jugador: lo que dura el vuelo de la
## carta jugada más un respiro.
const TAB_SWITCH_DELAY := TableView.FLY_SECONDS + 0.35

var _registry: RuleRegistry
var _repository: SqlMatchRepository
var _audit_sink: JsonlAuditSink
var _server: LocalServer
var _audit: AuditTrail
var _sessions: Array[ClientSession] = []
var _switch_request := 0  # solo el último cambio de turno pendiente salta de pestaña

var _mode: OptionButton
var _players: SpinBox
var _tabs: TabContainer
var _message: Label


func _ready() -> void:
	_build()
	_registry = RuleRegistry.new(HandEvaluator.new())
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	for mode in _registry.available_modes():
		_mode.add_item(_registry.display_name(mode))
		_mode.set_item_metadata(_mode.item_count - 1, mode)
	_repository = SqlMatchRepository.open(ProjectSettings.globalize_path(DB_PATH))
	if _repository == null:
		_message.text = "No se pudo abrir la base de datos: %s" % SqlMatchRepository.open_error
		return
	_audit_sink = JsonlAuditSink.open(ProjectSettings.globalize_path(AUDIT_PATH))
	_message.text = "Partidas y auditoría en user://"
	_message.tooltip_text = ProjectSettings.globalize_path("user://")
	_message.mouse_filter = Control.MOUSE_FILTER_PASS
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(func() -> void:
		if _server != null:
			_server.tick(Time.get_ticks_msec()))
	add_child(timer)
	timer.start()


func _exit_tree() -> void:
	if _repository != null:
		_repository.close()
	if _audit_sink != null:
		_audit_sink.close()


func _new_game() -> void:
	if _repository == null:
		return
	for tab in _tabs.get_children():
		_tabs.remove_child(tab)
		tab.queue_free()
	_sessions.clear()
	_server = LocalServer.new(Lobby.new(_registry, _repository))
	_audit = AuditTrail.new(_server.lobby, _audit_sink) if _audit_sink != null else null
	for i in int(_players.value):
		_add_player(i + 1)
	var host := _sessions[0]
	host.create_room("Jugador 1", _mode.get_item_metadata(_mode.selected))
	var room_id := str(host.room.get("room_id", ""))
	for i in range(1, _sessions.size()):
		_sessions[i].join_room(room_id, "Jugador %d" % (i + 1))
	host.start_match()


func _add_player(number: int) -> void:
	var session := ClientSession.new(_server.connect_player(StringName("p%d" % number)), "p%d" % number)
	_sessions.append(session)
	var table := TableView.new()
	table.name = "Jugador %d" % number
	_tabs.add_child(table)
	table.bind(session)
	session.view_changed.connect(func(_view: Dictionary) -> void: _mark_turn())


## Marca en las pestañas a quién le toca y, cuando la carta que se acaba de jugar termina
## de volar, salta a la pestaña de ese jugador (si saltara al instante no verías tu
## propio descarte).
func _mark_turn() -> void:
	var next := -1
	for i in _sessions.size():
		var mine := _sessions[i].is_my_turn()
		_tabs.set_tab_title(i, ("▶ " if mine else "") + "Jugador %d" % (i + 1))
		if mine:
			next = i
	if next < 0 or _tabs.current_tab == next:
		return
	_switch_request += 1
	var request := _switch_request
	get_tree().create_timer(TAB_SWITCH_DELAY).timeout.connect(func() -> void:
		if request == _switch_request and next < _tabs.get_tab_count():
			_tabs.current_tab = next)


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	column.add_child(bar)
	var mode_label := Label.new()
	mode_label.text = "Modalidad:"
	bar.add_child(mode_label)
	_mode = OptionButton.new()
	bar.add_child(_mode)
	var players_label := Label.new()
	players_label.text = "Jugadores:"
	bar.add_child(players_label)
	_players = SpinBox.new()
	_players.min_value = MIN_PLAYERS
	_players.max_value = MAX_PLAYERS
	_players.value = 3
	bar.add_child(_players)
	var start := Button.new()
	start.text = "Nueva partida"
	start.pressed.connect(_new_game)
	bar.add_child(start)
	_message = Label.new()
	bar.add_child(_message)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)
