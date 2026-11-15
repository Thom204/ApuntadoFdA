extends GutTest
## Contornos de los palos: simétricos, lisos y rellenables. Se miden las formas, no
## píxeles: así la prueba no depende de la tarjeta de video.

const SUITS := {
	"corazón": SuitGlyph.HEARTS,
	"diamante": SuitGlyph.DIAMONDS,
	"trébol": SuitGlyph.CLUBS,
	"pica": SuitGlyph.SPADES,
}
## Esquinas que el diseño SÍ tiene (puntas y uniones), donde el contorno puede quebrar.
##   corazón: hendidura y punta; diamante: 4 puntas; pica: punta, 2 uniones lóbulo-tallo,
##   2 esquinas del pie; trébol: 2 uniones entre hojas, 2 uniones hoja-tallo, 2 del pie.
const MAX_CORNERS := {"corazón": 2, "diamante": 4, "pica": 5, "trébol": 6}
## Un giro mayor que este entre dos tramos seguidos cuenta como esquina.
const CORNER_DEGREES := 20.0


func _closest_distance(point: Vector2, shape: PackedVector2Array) -> float:
	var best := INF
	for i in shape.size():
		var on_edge := Geometry2D.get_closest_point_to_segment(point, shape[i], shape[(i + 1) % shape.size()])
		best = minf(best, point.distance_to(on_edge))
	return best


func _turn_degrees(a: Vector2, b: Vector2, c: Vector2) -> float:
	return rad_to_deg(absf((b - a).angle_to(c - b)))


func test_cada_palo_es_simetrico_respecto_del_eje_vertical() -> void:
	for suit_name in SUITS:
		var shape := SuitGlyph.outline(SUITS[suit_name])
		var worst := 0.0
		for p in shape:
			worst = maxf(worst, _closest_distance(Vector2(-p.x, p.y), shape))
		assert_lt(worst, 0.002, "%s: el reflejo de cada punto cae sobre el contorno (desvío %.4f)" % [suit_name, worst])


func test_cada_palo_ocupa_la_caja_unitaria_centrado() -> void:
	for suit_name in SUITS:
		var shape := SuitGlyph.outline(SUITS[suit_name])
		var box := Rect2(shape[0], Vector2.ZERO)
		for p in shape:
			box = box.expand(p)
		assert_almost_eq(maxf(box.size.x, box.size.y), 1.0, 0.001, "%s: dimensión mayor = 1" % suit_name)
		assert_true(box.get_center().is_zero_approx(), "%s: centrado en (0, 0)" % suit_name)


func test_los_bordes_son_curvas_lisas_salvo_las_puntas_del_diseno() -> void:
	for suit_name in SUITS:
		var shape := SuitGlyph.outline(SUITS[suit_name])
		var corners := 0
		var n := shape.size()
		for i in n:
			if _turn_degrees(shape[(i - 1 + n) % n], shape[i], shape[(i + 1) % n]) > CORNER_DEGREES:
				corners += 1
		assert_lte(corners, MAX_CORNERS[suit_name], "%s: esquinas inesperadas en el contorno" % suit_name)


func test_las_curvas_estan_muestreadas_finas() -> void:
	# Ningún tramo curvo puede medir más del 4 % del palo: así no se ven facetas.
	# (Las rectas del diseño, como la base del pie, sí pueden ser largas.)
	for suit_name in ["corazón", "diamante"]:
		var shape := SuitGlyph.outline(SUITS[suit_name])
		var longest := 0.0
		for i in shape.size():
			longest = maxf(longest, shape[i].distance_to(shape[(i + 1) % shape.size()]))
		assert_lt(longest, 0.04, "%s: tramo más largo %.3f" % [suit_name, longest])


func test_cada_palo_se_puede_rellenar() -> void:
	for suit_name in SUITS:
		var shape := SuitGlyph.outline(SUITS[suit_name])
		assert_false(Geometry2D.triangulate_polygon(shape).is_empty(), "%s: el polígono es simple y se triangula" % suit_name)


func test_proporciones_de_cada_palo() -> void:
	var ratio := func(suit: int) -> float:
		var shape := SuitGlyph.outline(suit)
		var box := Rect2(shape[0], Vector2.ZERO)
		for p in shape:
			box = box.expand(p)
		return box.size.x / box.size.y
	assert_between(ratio.call(SuitGlyph.DIAMONDS), 0.68, 0.76, "el diamante es más alto que ancho")
	assert_between(ratio.call(SuitGlyph.HEARTS), 1.0, 1.25, "el corazón es un poco más ancho que alto")
	assert_between(ratio.call(SuitGlyph.SPADES), 0.9, 1.1)
	assert_between(ratio.call(SuitGlyph.CLUBS), 0.9, 1.1)
