class_name HandFan
extends Control
## Abanico de cartas, como se sostienen en la mano: cada carta gira un poco alrededor de
## su borde inferior y las de los extremos bajan, formando un arco. Las cartas se
## solapan lo necesario para caber en el ancho disponible.
##
## Ubica a sus hijos (CardView) por código; no es un Container para poder rotarlos.

## Tamaño de cada carta (5:7).
var card_size := Vector2(90, 126):
	set(value):
		card_size = value
		relayout()
## Cuánto avanza cada carta respecto de la anterior, como fracción de su ancho.
var max_step := 0.62
## Giro por carta y giro total máximo del abanico, en grados.
var degrees_per_card := 2.4
var max_total_degrees := 22.0
## Cuánto bajan las cartas de los extremos (px por carta desde el centro, al cuadrado).
var arc_drop := 1.4


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(relayout)
	child_order_changed.connect(relayout)


func relayout() -> void:
	var cards: Array[Control] = []
	for child in get_children():
		if child is Control:
			cards.append(child)
	var n := cards.size()
	if n == 0:
		return
	var step := card_size.x * max_step
	if n > 1:
		step = minf(step, maxf(0.0, size.x - card_size.x) / (n - 1))
	var degrees := minf(degrees_per_card, max_total_degrees / maxf(1.0, n - 1))
	var mid := (n - 1) / 2.0
	var top := size.y - card_size.y - mid * mid * arc_drop
	for i in n:
		var t := i - mid
		var card := cards[i]
		card.custom_minimum_size = card_size
		card.size = card_size
		card.pivot_offset = Vector2(card_size.x / 2, card_size.y)
		card.rotation = deg_to_rad(t * degrees)
		card.position = Vector2(size.x / 2 + t * step - card_size.x / 2, top + t * t * arc_drop)


## Ancho que ocupa el abanico con `n` cartas sin apretarlas.
func natural_width(n: int) -> float:
	return card_size.x * (1.0 + max_step * maxf(0.0, n - 1))
