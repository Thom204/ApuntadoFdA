class_name CardFace
extends RefCounted
## Cómo se lee una carta del protocolo ({ id, rank, suit, label }) en pantalla.
## Trabaja solo con los datos que llegan del servidor: el cliente no necesita el mazo.

const JOKER_RANK := 0
const SUIT_SYMBOLS := {0: "♥", 1: "♦", 2: "♣", 3: "♠"}
const RANK_LABELS := {1: "A", 11: "J", 12: "Q", 13: "K"}
const RED_SUITS := [0, 1]


static func is_joker(card: Dictionary) -> bool:
	return int(card.get("rank", -1)) == JOKER_RANK


static func rank_text(card: Dictionary) -> String:
	if is_joker(card):
		return "★"
	var rank := int(card.get("rank", 0))
	return RANK_LABELS.get(rank, str(rank))


static func suit_text(card: Dictionary) -> String:
	return "" if is_joker(card) else SUIT_SYMBOLS.get(int(card.get("suit", -1)), "?")


## Esquina de la carta: "7♥", "K♠", "★" para el comodín.
static func corner_text(card: Dictionary) -> String:
	return rank_text(card) + suit_text(card)


## Centro de la carta: el palo grande, o la estrella del comodín.
static func center_text(card: Dictionary) -> String:
	return "★" if is_joker(card) else suit_text(card)


static func is_red(card: Dictionary) -> bool:
	return int(card.get("suit", -1)) in RED_SUITS


const SUIT_NAMES := {0: "corazones", 1: "diamantes", 2: "tréboles", 3: "picas"}
const RANK_NAMES := {1: "As", 11: "J", 12: "Q", 13: "K"}

## Nombre para el tooltip: "7 de corazones", "As de picas", "Comodín".
static func spoken_name(card: Dictionary) -> String:
	if is_joker(card):
		return "Comodín"
	var rank := int(card.get("rank", 0))
	return "%s de %s" % [RANK_NAMES.get(rank, str(rank)), SUIT_NAMES.get(int(card.get("suit", -1)), "?")]


## Dónde va cada pinta en las cartas del 1 al 10, en la disposición clásica de la
## baraja francesa. Coordenadas de 0 a 1 dentro del área central (x: izquierda, centro,
## derecha; y: de arriba a abajo). Las de y > 0.5 se dibujan invertidas. Vacío si el
## valor no lleva pintas (figuras y comodín).
static func pip_positions(rank: int) -> Array[Vector2]:
	const L := 0.0
	const C := 0.5
	const R := 1.0
	var sides_3 := [0.0, 0.5, 1.0]
	var sides_4 := [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]
	var out: Array[Vector2] = []
	match rank:
		1:
			out = [Vector2(C, 0.5)]
		2:
			out = [Vector2(C, 0), Vector2(C, 1)]
		3:
			out = [Vector2(C, 0), Vector2(C, 0.5), Vector2(C, 1)]
		4, 5:
			out = [Vector2(L, 0), Vector2(R, 0), Vector2(L, 1), Vector2(R, 1)]
			if rank == 5:
				out.append(Vector2(C, 0.5))
		6, 7, 8:
			for y: float in sides_3:
				out.append_array([Vector2(L, y), Vector2(R, y)])
			if rank >= 7:
				out.append(Vector2(C, 0.25))
			if rank == 8:
				out.append(Vector2(C, 0.75))
		9, 10:
			for y: float in sides_4:
				out.append_array([Vector2(L, y), Vector2(R, y)])
			if rank == 9:
				out.append(Vector2(C, 0.5))
			else:
				out.append_array([Vector2(C, 1.0 / 6.0), Vector2(C, 5.0 / 6.0)])
	return out


## Orden para mostrar la mano: por palo y luego por valor, o por valor y luego por palo.
## Es solo visual; el servidor no depende del orden de la mano.
static func sorted(cards: Array, by_suit: bool) -> Array:
	var out := cards.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _sort_key(a, by_suit) < _sort_key(b, by_suit))
	return out


## Clave entera: criterio principal, secundario y el id para desempatar (comodines al final).
static func _sort_key(card: Dictionary, by_suit: bool) -> int:
	var id := int(card.get("id", 0))
	if is_joker(card):
		return 99 * 1_000_000 + id
	var rank := int(card.get("rank", 0))
	var suit := int(card.get("suit", 0))
	var major := suit if by_suit else rank
	var minor := rank if by_suit else suit
	return major * 1_000_000 + minor * 10_000 + id
