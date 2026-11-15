class_name OpponentSeat
extends Control
## Asiento de un rival en el borde de la mesa: sus cartas boca abajo en abanico (tantas
## como tiene en la mano) y una placa con nombre y puntos. Si le toca jugar, la placa se
## marca en dorado y dice "en turno" (no solo color). Si quedó eliminado, se atenúa.

const SIZE := Vector2(210, 128)
const BACK_SIZE := Vector2(40, 56)
const MAX_BACKS := 11
const CardViewScene := preload("res://presentation/table/card_view.tscn")

## Jugador sentado aquí (para saber a dónde vuelan sus cartas).
var player_id := ""

var _fan: HandFan
var _plate: PanelContainer
var _name: Label
var _detail: Label
var _shown_backs := -1


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fan = HandFan.new()
	_fan.card_size = BACK_SIZE
	_fan.max_step = 0.38
	_fan.degrees_per_card = 4.0
	_fan.max_total_degrees = 34.0
	_fan.arc_drop = 0.8
	_fan.position = Vector2(0, 0)
	_fan.size = Vector2(SIZE.x, 66)
	add_child(_fan)
	_plate = TableTheme.panel()
	_plate.position = Vector2(20, 70)
	_plate.custom_minimum_size = Vector2(SIZE.x - 40, 0)
	add_child(_plate)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	_plate.add_child(lines)
	_name = TableTheme.label("", TableTheme.FONT_BODY)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(_name)
	_detail = TableTheme.label("", TableTheme.FONT_SMALL, TableTheme.TEXT_DIM)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lines.add_child(_detail)


## `player` es una entrada de view.players: { nickname, hand_size, total, active, is_current }.
func show_player(player: Dictionary) -> void:
	player_id = str(player.get("id", ""))
	var backs := mini(int(player.get("hand_size", 0)), MAX_BACKS)
	if backs != _shown_backs:
		_set_backs(backs)
	var current := bool(player.get("is_current", false))
	var active := bool(player.get("active", true))
	_name.text = str(player.get("nickname", ""))
	var status := "en turno · " if current else ("eliminado · " if not active else "")
	_detail.text = "%s%d cartas · %d pts" % [status, int(player.get("hand_size", 0)), int(player.get("total", 0))]
	_name.add_theme_color_override("font_color", TableTheme.GOLD if current else TableTheme.TEXT)
	_plate.add_theme_stylebox_override("panel", TableTheme.panel_style(
		TableTheme.GOLD if current else TableTheme.GOLD_SOFT, TableTheme.PANEL, 10, 2 if current else 1))
	modulate.a = 1.0 if active else 0.5


## Centro del abanico de cartas, en coordenadas del asiento.
func cards_center() -> Vector2:
	return _fan.position + Vector2(_fan.size.x / 2, _fan.size.y - BACK_SIZE.y / 2)


func _set_backs(count: int) -> void:
	_shown_backs = count
	for child in _fan.get_children():
		_fan.remove_child(child)
		child.queue_free()
	for i in count:
		var back: CardView = CardViewScene.instantiate()
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fan.add_child(back)
		back.show_back()
