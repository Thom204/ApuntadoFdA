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
var _dragged_card: Control


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
		if card == _dragged_card:
			continue
		card.rotation = deg_to_rad(t * degrees)
		card.position = Vector2(size.x / 2 + t * step - card_size.x / 2, top + t * t * arc_drop)
		card.z_index=i

## Saca visualmente la carta del abanico mientras se arrastra.
func begin_drag(card: Control, global_position: Vector2) -> void:
	if not is_ancestor_of(card):
		return
	_dragged_card = card
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = 0
	card.rotation = 0.0
	update_drag(card, global_position)


func update_drag(card: Control, global_position: Vector2) -> void:
	if not is_instance_valid(_dragged_card) or card != _dragged_card:
		return
	_dragged_card.position = get_global_transform().affine_inverse() * global_position - card_size / 2
	var local_x := (get_global_transform().affine_inverse() * global_position).x
	_dragged_card.z_index = 0
	var idx = 0
	for child in get_children():
		var other := child as Control
		if other == null or other == card:
			continue
		if local_x >= other.position.x:
			_dragged_card.z_index += 1
			other.z_index = idx 
		else:
			other.z_index = idx + 1
		idx +=1
		
## Inserta la carta en la posición horizontal bajo el puntero y vuelve a formar el abanico.
func finish_drag(global_position: Vector2) -> void:
	if not is_instance_valid(_dragged_card):
		_dragged_card = null
		return
	var card := _dragged_card
	var local_x := (get_global_transform().affine_inverse() * global_position).x
	var target_index := 0
	for child in get_children():
		var other := child as Control
		if other == null or other == card:
			continue
		if local_x >= other.position.x + other.size.x / 2:
			target_index += 1
	remove_child(card)
	add_child(card)
	move_child(card, mini(target_index, get_child_count() - 1))
	card.z_index = 0
	_dragged_card = null
	relayout()


## Ancho que ocupa el abanico con `n` cartas sin apretarlas.
func natural_width(n: int) -> float:
	return card_size.x * (1.0 + max_step * maxf(0.0, n - 1))
