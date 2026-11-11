extends RefCounted
## ¿Un valor solo contiene tipos nativos de JSON? (nada de objetos, StringName ni
## Vector; claves de diccionario String). Es la condición para que la red lo envíe tal cual.


static func is_json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_ARRAY:
			return value.all(is_json_safe)
		TYPE_DICTIONARY:
			return value.keys().all(func(k: Variant) -> bool: return typeof(k) == TYPE_STRING) \
				and value.values().all(is_json_safe)
	return false
