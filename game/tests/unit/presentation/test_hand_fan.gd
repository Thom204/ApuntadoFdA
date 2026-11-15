extends GutTest
## Abanico de la mano: simétrico, dentro del ancho disponible y con las cartas de los
## extremos más bajas y más giradas que las del centro.

const CardViewScene := preload("res://presentation/table/card_view.tscn")


func _fan(cards: int, width: float) -> HandFan:
	var fan := HandFan.new()
	fan.card_size = Vector2(88, 123)
	fan.size = Vector2(width, 190)
	add_child_autofree(fan)
	for i in cards:
		fan.add_child(CardViewScene.instantiate())
	fan.relayout()
	return fan


func _card(fan: HandFan, i: int) -> Control:
	return fan.get_child(i)


func test_el_abanico_es_simetrico() -> void:
	var fan := _fan(7, 700)
	var center := fan.size.x / 2
	for i in 3:
		var left := _card(fan, i)
		var right := _card(fan, 6 - i)
		var left_mid := left.position.x + left.size.x / 2
		var right_mid := right.position.x + right.size.x / 2
		assert_almost_eq(center - left_mid, right_mid - center, 0.01, "carta %d y su espejo a la misma distancia" % i)
		assert_almost_eq(left.position.y, right.position.y, 0.01)
		assert_almost_eq(left.rotation, -right.rotation, 0.0001)


func test_los_extremos_bajan_y_giran_mas_que_el_centro() -> void:
	var fan := _fan(7, 700)
	assert_gt(_card(fan, 0).position.y, _card(fan, 3).position.y)
	assert_lt(_card(fan, 0).rotation, 0.0)
	assert_almost_eq(_card(fan, 3).rotation, 0.0, 0.0001)


func test_con_poco_espacio_las_cartas_se_solapan_mas_sin_salirse() -> void:
	var fan := _fan(11, 400)
	var first := _card(fan, 0)
	var last := _card(fan, 10)
	assert_gte(first.position.x, -0.01)
	assert_lte(last.position.x + last.size.x, fan.size.x + 0.01)


func test_cada_carta_toma_el_tamano_del_abanico() -> void:
	var fan := _fan(3, 500)
	assert_true(_card(fan, 1).size.is_equal_approx(Vector2(88, 123)), "tamaño %s" % _card(fan, 1).size)
