class_name CardView
extends Control
## Carta de póker dibujada por código, sin imágenes, con la proporción real de una carta
## de póker: 63,5 × 88,9 mm (5:7), esquinas de 1/8" y papel cálido.
##   - Frente: índice (valor + palo) arriba a la izquierda y girado abajo a la derecha;
##     pintas en la disposición clásica del 2 al 10 (las de abajo, invertidas); as con
##     una pinta grande; J, Q y K en un marco dorado partido en diagonal; comodín con
##     estrella.
##   - Reverso: borde blanco, celosía dorada sobre vino tinto y medallón central.
##   - Seleccionada: sube y se marca en dorado. Al pasar el mouse sube un poco si es
##     interactiva. Solo se mueve el dibujo, no el layout (la mano no salta).
##
## La mesa solo usa show_card, show_back, selected, interactive, stack y la señal pressed:
## para cambiar a texturas basta con reescribir _draw.

signal pressed(card_id: int)

## 5:7, como 63,5 × 88,9 mm.
const CARD_SIZE := Vector2(75, 105)
const CORNER_RADIUS := 5  # 1/8" sobre 2,5" de ancho ≈ 5 % del ancho

const PAPER := Color("fbf8f0")
const EDGE := Color("cfc8b8")
const INK := Color("1b1b1f")
const RED := Color("c8102e")
const GOLD := Color("c9a227")
const COURT_TINT := Color("f5ead0")
const BACK := Color("7a1f2b")
const BACK_DARK := Color("561520")
const SELECTED_BORDER_COLOR := Color("f2c14e")
const SHADOW := Color(0, 0, 0, 0.35)

const SELECTED_LIFT := 14.0
const HOVER_LIFT := 5.0
const LIFT_SECONDS := 0.12
## Máximo de cantos que se dibujan detrás para simular un mazo con grosor.
const MAX_STACK := 4

## Id de la carta del protocolo; -1 si es un reverso.
var card_id := -1
## Si responde a clics (cursor de mano, sube al pasar el mouse y emite pressed).
var interactive := false:
	set(value):
		interactive = value
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if value else Control.CURSOR_ARROW
		_animate_lift()
var selected := false:
	set(value):
		selected = value
		_animate_lift()
## Cuántos cantos dibujar detrás (mazo o pozo con varias cartas), de 0 a MAX_STACK.
var stack := 0:
	set(value):
		stack = clampi(value, 0, MAX_STACK)
		queue_redraw()

var _card: Dictionary = {}
var _face_up := false
var _empty := false
var _hovered := false
var _lift := 0.0:
	set(value):
		_lift = value
		queue_redraw()
var _tween: Tween


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))


func show_card(card: Dictionary) -> void:
	_empty = false
	_card = card.duplicate()
	card_id = int(card.get("id", -1))
	_face_up = true
	tooltip_text = CardFace.spoken_name(card)
	queue_redraw()


## Reverso: cartas del mazo y de los rivales.
func show_back() -> void:
	_empty = false
	_card = {}
	card_id = -1
	_face_up = false
	tooltip_text = ""
	queue_redraw()


## Espacio vacío marcado en el paño (mazo o pozo sin cartas).
func show_empty() -> void:
	_empty = true
	_card = {}
	card_id = -1
	_face_up = false
	tooltip_text = "Vacío"
	queue_redraw()


func is_face_up() -> bool:
	return _face_up


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(card_id)
		accept_event()


# ======================================================================= movimiento
func _on_hover(inside: bool) -> void:
	_hovered = inside
	_animate_lift()


func _target_lift() -> float:
	if selected:
		return SELECTED_LIFT
	return HOVER_LIFT if interactive and _hovered else 0.0


func _animate_lift() -> void:
	var target := _target_lift()
	if _tween != null:
		_tween.kill()
	if not is_inside_tree():
		_lift = target
		return
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "_lift", target, LIFT_SECONDS)


# ======================================================================= dibujo
func _draw() -> void:
	var rect := Rect2(Vector2(0, -_lift), size)
	if _empty:
		draw_style_box(_box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.35), 2, false), rect)
		return
	for i in range(stack, 0, -1):
		draw_style_box(_box(PAPER, EDGE, 1, false), Rect2(rect.position + Vector2(i, i) * 1.5, rect.size))
	draw_style_box(_box(PAPER, EDGE, 1, true), rect)
	if not _face_up:
		_draw_back(rect)
	elif CardFace.is_joker(_card):
		_draw_joker(rect)
	else:
		_draw_face(rect)
	if selected:
		var outline := _box(Color.TRANSPARENT, SELECTED_BORDER_COLOR, 3, false)
		outline.draw_center = false
		draw_style_box(outline, rect.grow(2))


func _draw_face(rect: Rect2) -> void:
	var color := RED if CardFace.is_red(_card) else INK
	_mirrored(rect, func(r: Rect2) -> void: _draw_index(r, color))
	var rank := int(_card.get("rank", 0))
	if rank == 1:
		_draw_ace(rect, color)
	elif rank >= 11:
		_draw_court(rect, color)
	else:
		_draw_pips(rect, rank, color)


## Valor y palo pequeños en la esquina superior izquierda de `r`.
func _draw_index(r: Rect2, color: Color) -> void:
	var w := r.size.x
	var text := CardFace.rank_text(_card)
	var font_size := int(w * (0.16 if text.length() > 1 else 0.19))  # el "10" va más angosto
	var column := w * 0.21
	var baseline := r.position.y + int(w * 0.19) * 1.05
	draw_string(_serif(), Vector2(r.position.x + 1, baseline), text,
		HORIZONTAL_ALIGNMENT_CENTER, column, font_size, color)
	SuitGlyph.draw(self, int(_card["suit"]), Vector2(r.position.x + 1 + column / 2, baseline + w * 0.09), w * 0.11, color)


## Las pintas van dentro del área central, sin tocar la columna de los índices.
func _draw_pips(rect: Rect2, rank: int, color: Color) -> void:
	var area := Rect2(rect.position + rect.size * Vector2(0.31, 0.2), rect.size * Vector2(0.38, 0.6))
	var pip := rect.size.x * 0.15
	for at: Vector2 in CardFace.pip_positions(rank):
		SuitGlyph.draw(self, int(_card["suit"]), area.position + area.size * at, pip, color, at.y > 0.5)


func _draw_ace(rect: Rect2, color: Color) -> void:
	var center := rect.get_center()
	var suit := int(_card["suit"])
	if suit == SuitGlyph.SPADES:
		draw_arc(center, rect.size.x * 0.3, 0, TAU, 48, GOLD, 1.5, true)
	SuitGlyph.draw(self, suit, center, rect.size.x * (0.42 if suit == SuitGlyph.SPADES else 0.38), color)


## J, Q y K: marco dorado partido en diagonal, con la letra y el palo en cada mitad
## (la de abajo girada), como las figuras de dos cabezas de una baraja real.
func _draw_court(rect: Rect2, color: Color) -> void:
	var frame := Rect2(rect.position + rect.size * Vector2(0.25, 0.13), rect.size * Vector2(0.5, 0.74))
	draw_rect(frame, COURT_TINT)
	draw_line(frame.position + Vector2(0, frame.size.y), frame.position + Vector2(frame.size.x, 0), GOLD, 1.0, true)
	draw_rect(frame.grow(-2.5), GOLD, false, 1.0)
	draw_rect(frame, color, false, 1.2)
	var half := func(f: Rect2) -> void:
		var letter_size := int(rect.size.x * 0.3)
		draw_string(_serif(), Vector2(f.position.x, f.position.y + f.size.y * 0.37), CardFace.rank_text(_card),
			HORIZONTAL_ALIGNMENT_CENTER, f.size.x * 0.62, letter_size, color)
		SuitGlyph.draw(self, int(_card["suit"]), f.position + f.size * Vector2(0.76, 0.24), rect.size.x * 0.15, color)
	_mirrored(frame, half)


func _draw_joker(rect: Rect2) -> void:
	_mirrored(rect, _draw_joker_index)
	SuitGlyph.draw_star(self, rect.get_center(), rect.size.x * 0.3, GOLD, RED)


## "JOKER" en vertical, letra por letra, en la esquina superior izquierda de `r`.
func _draw_joker_index(r: Rect2) -> void:
	var word := "JOKER"
	var font_size := int(r.size.x * 0.12)
	for i in word.length():
		draw_string(_serif(), r.position + Vector2(2, font_size * (i + 1.1)), word[i],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x * 0.18, font_size, RED)


func _draw_back(rect: Rect2) -> void:
	var inner := rect.grow(-4)
	draw_style_box(_box(BACK, BACK_DARK, 1, false, 3), inner)
	var lattice := inner.grow(-3)
	_draw_lattice(lattice, 7.0, Color(GOLD, 0.45))
	draw_rect(lattice, GOLD, false, 1.0)
	var center := rect.get_center()
	var radius := rect.size.x * 0.17
	draw_circle(center, radius, BACK_DARK, true, -1.0, true)
	draw_arc(center, radius, 0, TAU, 40, GOLD, 1.5, true)
	var font_size := int(radius * 1.2)
	draw_string(_serif(), Vector2(center.x - radius, center.y + font_size * 0.36), "A",
		HORIZONTAL_ALIGNMENT_CENTER, radius * 2, font_size, GOLD)


## Líneas diagonales en los dos sentidos, recortadas a `r` (rombos de `step` px).
func _draw_lattice(r: Rect2, step: float, color: Color) -> void:
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	var c := x0 - y1
	while c <= x1 - y0:  # x - y = c
		var a := maxf(x0, y0 + c)
		var b := minf(x1, y1 + c)
		if a < b:
			draw_line(Vector2(a, a - c), Vector2(b, b - c), color, 1.0, true)
		c += step
	c = x0 + y0
	while c <= x1 + y1:  # x + y = c
		var a := maxf(x0, c - y1)
		var b := minf(x1, c - y0)
		if a < b:
			draw_line(Vector2(a, c - a), Vector2(b, c - b), color, 1.0, true)
		c += step


# ======================================================================= ayudas
## Dibuja `content` en `r` y otra vez girado 180° alrededor del centro de `r`.
func _mirrored(r: Rect2, content: Callable) -> void:
	content.call(r)
	draw_set_transform(r.get_center() * 2, PI)
	content.call(r)
	draw_set_transform(Vector2.ZERO)


func _box(fill: Color, border: Color, border_width: int, shadow: bool, radius := CORNER_RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	if shadow:
		box.shadow_color = SHADOW
		box.shadow_size = 4 if selected else 2
		box.shadow_offset = Vector2(0, 3 if selected else 1)
	return box


static func _serif() -> Font:
	return TableTheme.serif()
