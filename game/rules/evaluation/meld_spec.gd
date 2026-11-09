class_name MeldSpec
extends RefCounted
## Una casilla del patrón de cierre: qué tipo de combinación y de cuántas cartas.
## Clásica = [ANY 4, ANY 3, ANY 3]; Apuntado = [ANY 3, ANY 3, ANY 3].

enum Type { SET, RUN, ANY }

var type: int:
	get:
		return _type
var size: int:
	get:
		return _size

var _type: int
var _size: int


func _init(p_type: int, p_size: int) -> void:
	_type = p_type
	_size = p_size


func allows_sets() -> bool:
	return _type != Type.RUN


func allows_runs() -> bool:
	return _type != Type.SET
