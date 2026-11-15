class_name TableMarkings
extends Control
## Lo que está impreso en el paño, como en una mesa de casino: los espacios del mazo y
## del pozo (rectángulos punteados con su nombre debajo) y el nombre del juego en arco.
## Cuando puedes robar, los dos espacios se iluminan para indicar dónde hacer clic.

const SLOT_PADDING := 10.0
const DASH := 7.0

var deck_slot := Rect2()
var discard_slot := Rect2()
var deck_caption := "MAZO"
var discard_caption := "POZO"
## Si se puede robar ahora (resalta los espacios).
var drawable := false
## Nombre del juego impreso en arco y dónde va (centro del arco y radio).
var print_text := ""
var print_center := Vector2.ZERO
var print_radius := 420.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var color := TableTheme.GOLD if drawable else TableTheme.GOLD_SOFT
	for pair in [[deck_slot, deck_caption], [discard_slot, discard_caption]]:
		var slot: Rect2 = pair[0]
		if slot.size == Vector2.ZERO:
			continue
		var outline := slot.grow(SLOT_PADDING)
		if drawable:
			_rounded_rect(outline.grow(3), Color(TableTheme.GOLD, 0.25), 6.0, false)
		_rounded_rect(outline, color, 2.0 if drawable else 1.5, true)
		_caption(str(pair[1]), Vector2(outline.get_center().x, outline.end.y + 24), color)
	if print_text != "":
		_arc_text(print_text, print_center, print_radius, 30, TableTheme.FELT_PRINT)


func _caption(text: String, center: Vector2, color: Color) -> void:
	var font := TableTheme.serif()
	var size := TableTheme.FONT_SMALL
	var spaced := " ".join(text.split(""))  # letras separadas, como impresas en el paño
	var width := font.get_string_size(spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string_outline(font, center - Vector2(width / 2, 0), spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, TableTheme.OUTLINE)
	draw_string(font, center - Vector2(width / 2, 0), spaced, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Rectángulo redondeado: punteado (espacio de carta) o continuo (resplandor).
func _rounded_rect(r: Rect2, color: Color, width: float, dashed: bool) -> void:
	var radius := 10.0
	var p := r.position
	var e := r.end
	var edges := [
		[Vector2(p.x + radius, p.y), Vector2(e.x - radius, p.y)],
		[Vector2(e.x, p.y + radius), Vector2(e.x, e.y - radius)],
		[Vector2(e.x - radius, e.y), Vector2(p.x + radius, e.y)],
		[Vector2(p.x, e.y - radius), Vector2(p.x, p.y + radius)],
	]
	for edge in edges:
		if dashed:
			draw_dashed_line(edge[0], edge[1], color, width, DASH, true, true)
		else:
			draw_line(edge[0], edge[1], color, width, true)
	var corners := [
		[Vector2(p.x + radius, p.y + radius), PI],
		[Vector2(e.x - radius, p.y + radius), PI * 1.5],
		[Vector2(e.x - radius, e.y - radius), 0.0],
		[Vector2(p.x + radius, e.y - radius), PI * 0.5],
	]
	for corner in corners:
		draw_arc(corner[0], radius, corner[1], corner[1] + PI / 2, 10, color, width, true)


## Texto curvado en la parte de abajo de un círculo (sonrisa), letra por letra.
func _arc_text(text: String, center: Vector2, radius: float, font_size: int, color: Color) -> void:
	var font := TableTheme.serif()
	var advances: Array[float] = []
	var total := 0.0
	for ch in text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 3.0
		advances.append(w)
		total += w
	var angle := PI / 2 + (total / radius) / 2
	for i in text.length():
		var step := advances[i] / radius
		var mid := angle - step / 2
		draw_set_transform(center + Vector2(cos(mid), sin(mid)) * radius, mid - PI / 2)
		draw_char(font, Vector2(-advances[i] / 2 + 1.5, 0), text[i], font_size, color)
		angle -= step
	draw_set_transform(Vector2.ZERO)
