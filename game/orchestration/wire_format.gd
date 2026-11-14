class_name WireFormat
extends RefCounted
## Traducción del dominio a datos del protocolo con la red. Es el único lugar donde se
## decide cómo viaja una carta, un movimiento o una liquidación. Todo lo que devuelve
## es nativo de JSON: String, int, float, bool, null, Array y Dictionary con claves String.


static func card(c: Card) -> Variant:
	if c == null:
		return null
	return {"id": c.instance_id, "rank": c.rank, "suit": c.suit, "label": str(c)}


static func cards(list: Array[Card]) -> Array:
	return list.map(func(c: Card) -> Variant: return card(c))


## `card` es null cuando la carta es secreta (robo del mazo).
static func move(m: MoveRecord) -> Dictionary:
	return {
		"sequence": m.sequence,
		"round_number": m.round_number,
		"player_id": String(m.player_id),
		"action": m.action_name(),
		"card": card(m.card),
		"automatic": m.automatic,
	}


static func settlement(s: RoundSettlement) -> Dictionary:
	var deltas := {}
	for player_id in s.deltas:
		deltas[String(player_id)] = int(s.deltas[player_id])
	return {"round_number": s.round_number, "closer_id": String(s.closer_id), "deltas": deltas}


static func validation(v: ValidationResult) -> Variant:
	if v == null:
		return null
	return {
		"valid": v.is_valid,
		"reason": ValidationResult.Reason.keys()[v.reason],
		"message": v.message,
		"leftover_points": v.leftover_points,
		"leftover": cards(v.leftover),
		"melds": v.melds.map(func(m: Meld) -> Array: return cards(m.cards)),
	}


static func meld_check(c: MeldCheck) -> Dictionary:
	return {
		"result": MeldCheck.Result.keys()[c.result],
		"valid": c.is_valid,
		"points": c.points,
		"message": c.message,
	}
