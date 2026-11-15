class_name TableTheme
extends RefCounted
## Estilo de la mesa estilo casino: colores, tipografía y fábricas de estilos para que
## todos los componentes compartan el mismo lenguaje visual.
##
## Reglas que sigue (guía de UI de juegos):
##   - Texto de 14 px o más, con contorno oscuro para leerse sobre cualquier fondo.
##   - Nada se comunica solo con color: el turno, los errores y los estados llevan texto.
##   - Botones de 44 px de alto como mínimo y con foco visible para jugar con teclado.

const GOLD := Color("d4af37")
const GOLD_SOFT := Color(0.83, 0.69, 0.22, 0.7)
const PANEL := Color(0.02, 0.07, 0.04, 0.72)
const PANEL_STRONG := Color(0.02, 0.06, 0.035, 0.92)
const TEXT := Color("f4efe1")
const TEXT_DIM := Color(0.96, 0.94, 0.88, 0.72)
const OUTLINE := Color(0, 0, 0, 0.8)
const ERROR_BG := Color(0.42, 0.05, 0.08, 0.94)
const OK_BG := Color(0.05, 0.32, 0.15, 0.94)
const FELT_PRINT := Color(0.95, 0.9, 0.7, 0.16)

const FONT_SMALL := 14
const FONT_BODY := 16
const FONT_TITLE := 22
const FONT_HERO := 28
const MIN_BUTTON_HEIGHT := 44

static var _serif: SystemFont


## Serif clásica del sistema (Georgia, Times...). Sin archivos de fuente en el repo.
static func serif() -> Font:
	if _serif == null:
		_serif = SystemFont.new()
		_serif.font_names = PackedStringArray(["Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif", "serif"])
		_serif.font_weight = 700
	return _serif


## Etiqueta con contorno oscuro, legible sobre el paño, la madera o un panel.
static func label(text: String, font_size := FONT_BODY, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", 4)
	return l


static func panel_style(border := GOLD_SOFT, background := PANEL, radius := 10, border_width := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	box.anti_aliasing = true
	return box


static func panel(border := GOLD_SOFT, background := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(border, background))
	return p


## Botón de mesa: verde oscuro con filete dorado; dorado al pasar el mouse o tener foco.
static func style_button(button: Button, primary := false) -> void:
	var base := Color(0.05, 0.2, 0.11, 0.95) if not primary else Color(0.55, 0.42, 0.1, 0.97)
	var states := {
		"normal": panel_style(GOLD_SOFT, base, 22),
		"hover": panel_style(GOLD, base.lightened(0.12), 22, 2),
		"pressed": panel_style(GOLD, base.darkened(0.2), 22, 2),
		"disabled": panel_style(Color(1, 1, 1, 0.12), Color(0.05, 0.12, 0.08, 0.6), 22),
		"focus": panel_style(GOLD, Color.TRANSPARENT, 22, 2),
	}
	for state: String in states:
		var box: StyleBoxFlat = states[state]
		box.content_margin_left = 18
		box.content_margin_right = 18
		button.add_theme_stylebox_override(state, box)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	button.add_theme_font_size_override("font_size", FONT_BODY)
	button.custom_minimum_size.y = MIN_BUTTON_HEIGHT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
