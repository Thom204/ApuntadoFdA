extends Control
## Punto de entrada mínimo para jugar en red. El endpoint es hijo directo de la raíz
## para conservar la ruta RPC /root/NetworkSession que espera el servidor.

const SERVER_URL_DEFAULT := "ws://127.0.0.1:7777"

var _endpoint: ClientNetworkEndpoint
var _transport: ClientNetworkTransport
var _session: ClientSession
var _url: LineEdit
var _nickname: LineEdit
var _room_code: LineEdit
var _mode: OptionButton
var _status: Label
var _room_status: Label
var _table: TableView
var _connect_button: Button
var _create_button: Button
var _join_button: Button
var _start_button: Button
var _room_lookup_pending := false


func _ready() -> void:
	_build()
	_endpoint = get_parent() as ClientNetworkEndpoint
	_transport = ClientNetworkTransport.new(_endpoint)
	_session = ClientSession.new(_transport)
	_session.room_changed.connect(_on_room_changed)
	_session.view_changed.connect(func(_view: Dictionary) -> void: _refresh_actions())
	_session.request_failed.connect(_on_request_failed)
	_transport.connection_established.connect(_on_connection_established)
	_transport.connection_failed.connect(_on_connection_failed)
	_transport.connection_closed.connect(_on_connection_closed)
	_table.bind(_session)
	_refresh_actions()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	column.add_theme_constant_override("margin_left", 12)
	column.add_theme_constant_override("margin_right", 12)
	column.add_theme_constant_override("margin_top", 12)
	column.add_theme_constant_override("margin_bottom", 12)
	add_child(column)

	var connection_row := HBoxContainer.new()
	column.add_child(connection_row)
	_url = LineEdit.new()
	_url.placeholder_text = "URL del servidor (ws://IP:7777)"
	_url.text = SERVER_URL_DEFAULT
	_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connection_row.add_child(_url)
	_connect_button = Button.new()
	_connect_button.text = "Conectar"
	_connect_button.pressed.connect(_connect_to_server)
	connection_row.add_child(_connect_button)
	_status = Label.new()
	_status.text = "Desconectado"
	column.add_child(_status)

	var player_row := HBoxContainer.new()
	column.add_child(player_row)
	_nickname = LineEdit.new()
	_nickname.placeholder_text = "Tu nombre"
	_nickname.text = "Jugador"
	_nickname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_row.add_child(_nickname)
	_mode = OptionButton.new()
	_mode.add_item("Apuntado (101)")
	_mode.set_item_metadata(0, "apuntado")
	_mode.add_item("Clásica 4-3-3")
	_mode.set_item_metadata(1, "classic")
	player_row.add_child(_mode)
	_create_button = Button.new()
	_create_button.text = "Crear sala"
	_create_button.pressed.connect(_create_room)
	player_row.add_child(_create_button)

	var join_row := HBoxContainer.new()
	column.add_child(join_row)
	_room_code = LineEdit.new()
	_room_code.placeholder_text = "Código de sala"
	_room_code.max_length = 6
	_room_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_code.text_submitted.connect(func(_text: String) -> void: _join_room())
	join_row.add_child(_room_code)
	_join_button = Button.new()
	_join_button.text = "Buscar / unirse"
	_join_button.pressed.connect(_join_room)
	join_row.add_child(_join_button)
	_start_button = Button.new()
	_start_button.text = "Iniciar partida"
	_start_button.pressed.connect(func() -> void: _session.start_match())
	join_row.add_child(_start_button)
	_room_status = Label.new()
	_room_status.text = "Sin sala"
	column.add_child(_room_status)

	_table = TableView.new()
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_table)


func _connect_to_server() -> void:
	_status.text = "Conectando…"
	var error := _transport.connect_to_server(_url.text.strip_edges())
	if error != OK:
		_status.text = "No se pudo iniciar la conexión (código %d)" % error


func _create_room() -> void:
	if _session == null or not _transport.is_connected_and_ready():
		return
	_session.create_room(_nickname.text.strip_edges(), StringName(str(_mode.get_item_metadata(_mode.selected))))


func _join_room() -> void:
	if _session == null or not _transport.is_connected_and_ready():
		return
	_session.join_room(_room_code.text.strip_edges().to_upper(), _nickname.text.strip_edges())


func _on_connection_established(info: Dictionary) -> void:
	var resumed := bool(info.get("resumed", false))
	_room_lookup_pending = resumed and _session.room.is_empty()
	_status.text = "Conectado · recuperando sala…" if _room_lookup_pending else ("Conectado · sesión restaurada" if resumed else "Conectado")
	_refresh_actions()


func _on_connection_failed(error: int) -> void:
	_room_lookup_pending = false
	_status.text = "Falló la conexión (código %d)" % error
	_refresh_actions()


func _on_connection_closed() -> void:
	_room_lookup_pending = false
	_status.text = "Conexión cerrada · reconecta para volver a la sala"
	_refresh_actions()


func _on_request_failed(response: Dictionary) -> void:
	if _room_lookup_pending and str(response.get("request", "")) == "get_view":
		_room_lookup_pending = false
	_status.text = str(response.get("message", "La solicitud fue rechazada"))
	_refresh_actions()


func _on_room_changed(room: Dictionary) -> void:
	_room_lookup_pending = false
	if room.is_empty():
		_room_status.text = "Sin sala"
	else:
		_room_status.text = "Código %s · %d/%d jugadores · %s" % [
			str(room.get("room_code", "")), room.get("players", []).size(),
			int(room.get("max_players", 0)), str(room.get("status", "")),
		]
		_room_code.text = str(room.get("room_code", _room_code.text))
	_refresh_actions()


func _refresh_actions() -> void:
	if _connect_button == null:
		return
	var connected := _transport != null and _transport.is_connected_and_ready()
	var in_room := _session != null and not _session.room.is_empty()
	_connect_button.disabled = connected
	_create_button.disabled = not connected or in_room or _room_lookup_pending
	_join_button.disabled = not connected or in_room or _room_lookup_pending
	_start_button.disabled = not connected or not in_room or str(_session.room.get("status", "")) != "WAITING"
