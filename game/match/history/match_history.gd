class_name MatchHistory
extends RefCounted
## Bitácora de solo inserción con los movimientos de la partida (RNF 5, D-14).

var _moves: Array[MoveRecord] = []


func record(move: MoveRecord) -> void:
	_moves.append(move)


func all() -> Array[MoveRecord]:
	return _moves.duplicate()


func moves_of_round(round_number: int) -> Array[MoveRecord]:
	return _moves.filter(func(m: MoveRecord) -> bool: return m.round_number == round_number)


func last() -> MoveRecord:
	return null if _moves.is_empty() else _moves.back()


func size() -> int:
	return _moves.size()
