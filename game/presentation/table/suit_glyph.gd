class_name SuitGlyph
extends RefCounted
## Palos de la baraja francesa como contornos vectoriales, sin depender de que la fuente
## tenga ♥♦♣♠ (en el export Web no la tiene).
##
## Cada palo se define en una caja de 100 × 100 (y hacia abajo) con curvas Bézier
## cúbicas que solo describen la MITAD DERECHA; la izquierda es su reflejo exacto, así
## que la simetría está garantizada por construcción. Las curvas se muestrean finas y el
## contorno se repasa con una línea antialiasada para que los bordes queden lisos.
##
## Estructura de cada palo (la de las barajas de póker actuales):
##   - Corazón: dos lóbulos redondos que se juntan en una hendidura arriba y bajan en
##     curvas convexas hasta una punta inferior. Un poco más ancho que alto.
##   - Diamante (carreau, "baldosa"): rombo más alto que ancho (≈ 0,72), con lados
##     levemente cóncavos y cuatro puntas afiladas.
##   - Pica (pique, "punta de lanza"): punta arriba, hombros que se abren en dos lóbulos
##     redondos abajo, y un tallo que se ensancha en un pie de lados cóncavos.
##   - Trébol (trèfle): tres hojas circulares iguales (arriba, izquierda y derecha) que
##     apenas se tocan, y el mismo tallo con pie que la pica.
##
## Las pintas de una carta miden de 8 a 11 px, así que la hendidura del corazón es una V
## abierta y las hojas del trébol casi no se solapan: si no, a ese tamaño el corazón
## parece una pica y el trébol una sola hoja.
##
## Los contornos quedan centrados en su caja y con la dimensión mayor igual a 1, y se
## calculan una sola vez.

const HEARTS := 0
const DIAMONDS := 1
const CLUBS := 2
const SPADES := 3

## Puntos por cada curva Bézier. Con 32 los bordes no muestran facetas ni a 200 px.
const CURVE_STEPS := 32
const CIRCLE_STEPS := 128
## Cuánto se encoge el relleno para que el borde antialiasado no engorde la forma.
const EDGE_INSET_PX := 0.5

static var _outlines: Dictionary = {}


## Dibuja el palo centrado en `center`, con su dimensión mayor igual a `size` px.
## `flipped` lo gira 180°, como las pintas de la mitad inferior de una carta.
## Respeta el draw_set_transform del lienzo (sirve para la esquina rotada).
static func draw(canvas: CanvasItem, suit: int, center: Vector2, size: float, color: Color, flipped := false) -> void:
	var shape := outline(suit)
	if shape.is_empty():
		return
	var points := Transform2D(PI if flipped else 0.0, Vector2(size, size), 0.0, center) * shape
	# El borde antialiasado de 1 px se centra sobre el contorno: si se dibuja sobre la
	# forma original la engorda medio píxel y, en pintas de 8 a 11 px, tapa la hendidura
	# del corazón y las muescas del trébol. Por eso se encoge antes medio píxel.
	var pieces := Geometry2D.offset_polygon(points, -EDGE_INSET_PX, Geometry2D.JOIN_ROUND)
	if pieces.is_empty():
		pieces = [points]
	for piece: PackedVector2Array in pieces:
		if Geometry2D.is_polygon_clockwise(piece) != Geometry2D.is_polygon_clockwise(points):
			continue  # un agujero, no una parte de la forma
		canvas.draw_colored_polygon(piece, color)
		var edge := piece.duplicate()
		edge.append(piece[0])
		canvas.draw_polyline(edge, color, 1.0, true)


## Contorno del palo en coordenadas unitarias (centrado, dimensión mayor = 1).
static func outline(suit: int) -> PackedVector2Array:
	if not _outlines.has(suit):
		_outlines[suit] = _normalized(_build(suit))
	return _outlines[suit]


## Estrella de cinco puntas (comodín).
static func draw_star(canvas: CanvasItem, center: Vector2, radius: float, fill: Color, outline_color: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI / 2 + i * PI / 5
		var r := radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	canvas.draw_colored_polygon(points, fill)
	points.append(points[0])
	canvas.draw_polyline(points, outline_color, maxf(1.0, radius * 0.06), true)


# ======================================================================= formas
static func _build(suit: int) -> PackedVector2Array:
	match suit:
		HEARTS:
			return _heart()
		DIAMONDS:
			return _diamond()
		SPADES:
			return _spade()
		CLUBS:
			return _club()
	return PackedVector2Array()


static func _heart() -> PackedVector2Array:
	return _symmetric(Vector2(50, 30), [
		[Vector2(57, 18), Vector2(63, 4), Vector2(77, 4)],      # hendidura en V abierta hasta el lóbulo
		[Vector2(91, 4), Vector2(101, 16), Vector2(101, 31)],   # lóbulo hasta el costado
		[Vector2(101, 54), Vector2(76, 70), Vector2(50, 92)],   # costado convexo hasta la punta
	])


static func _diamond() -> PackedVector2Array:
	return _symmetric(Vector2(50, 0), [
		[Vector2(58, 18), Vector2(72, 36), Vector2(86, 50)],    # lado superior, levemente cóncavo
		[Vector2(72, 64), Vector2(58, 82), Vector2(50, 100)],   # lado inferior
	])


static func _spade() -> PackedVector2Array:
	return _symmetric(Vector2(50, 0), [
		[Vector2(56, 13), Vector2(71, 25), Vector2(85, 37)],    # punta de lanza hasta el hombro
		[Vector2(99, 49), Vector2(102, 68), Vector2(89, 77)],   # lóbulo redondo
		[Vector2(78, 85), Vector2(61, 83), Vector2(53, 71)],    # vuelta interior hasta el tallo
		[Vector2(54, 85), Vector2(60, 95), Vector2(71, 100)],   # tallo que se abre en el pie
		[Vector2(50, 100)],                                      # base del pie
	])


## Tres hojas circulares iguales más el tallo con pie; se unen en un solo contorno.
static func _club() -> PackedVector2Array:
	# La hoja de arriba y las de los lados apenas se solapan: cada muesca es una punta
	# nítida y profunda, que se lee aun en pintas chicas.
	const R := 22.0
	var top := Vector2(50, 23)
	var left := Vector2(24, 58)
	var right := Vector2(76, 58)
	# Se empieza por el relleno central, que toca las tres hojas: así cada unión agrega
	# una pieza conectada y nunca se descarta una hoja.
	var shape := PackedVector2Array([top, left, right])
	for part in [
		_circle(top, R),
		_circle(left, R),
		_circle(right, R),
		# El tallo nace ancho, se funde con las hojas de abajo sin escalón, se angosta en
		# una cintura y se abre en el pie de lados cóncavos.
		_symmetric(Vector2(50, 50), [
			[Vector2(56, 50)],
			[Vector2(56, 60), Vector2(53, 68), Vector2(52.6, 74)],
			[Vector2(53.2, 88), Vector2(59, 96), Vector2(70, 100)],
			[Vector2(50, 100)],
		]),
	]:
		shape = _union(shape, part)
	return shape


# ======================================================================= construcción
## Arma un contorno cerrado y simétrico a partir de la mitad derecha. `start` y el final
## del último tramo están sobre el eje (x = 50). Cada tramo es [c1, c2, fin] (Bézier
## cúbica) o [fin] (recta).
static func _symmetric(start: Vector2, segments: Array) -> PackedVector2Array:
	var right := PackedVector2Array([start])
	var at := start
	for segment: Array in segments:
		if segment.size() == 1:
			right.append(segment[0])
		else:
			for i in range(1, CURVE_STEPS + 1):
				right.append(at.bezier_interpolate(segment[0], segment[1], segment[2], float(i) / CURVE_STEPS))
		at = segment[-1]
	var out := right.duplicate()
	for i in range(right.size() - 2, 0, -1):  # sin repetir los dos puntos del eje
		out.append(Vector2(100.0 - right[i].x, right[i].y))
	return out


static func _circle(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in CIRCLE_STEPS:
		var angle := TAU * i / CIRCLE_STEPS
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _union(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var best := a
	var best_area := -1.0
	for piece: PackedVector2Array in Geometry2D.merge_polygons(a, b):
		var area := absf(_area(piece))
		if area > best_area:
			best = piece
			best_area = area
	return best


static func _area(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size():
		var p := points[i]
		var q := points[(i + 1) % points.size()]
		total += p.x * q.y - q.x * p.y
	return total / 2.0


## Centra el contorno en (0, 0) y lo escala para que su dimensión mayor sea 1.
static func _normalized(points: PackedVector2Array) -> PackedVector2Array:
	if points.is_empty():
		return points
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	var scale := 1.0 / maxf(box.size.x, box.size.y)
	var out := PackedVector2Array()
	for p in points:
		out.append((p - box.get_center()) * scale)
	return out
