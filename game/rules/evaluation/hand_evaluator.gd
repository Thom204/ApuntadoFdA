class_name HandEvaluator
extends RefCounted
## Servicio de dominio sin estado: reconoce combinaciones y busca la mejor
## descomposición de una mano. No conoce la modalidad: recibe el patrón y la tabla
## de valores (sección 4.2.1 del E1).
##
## Supuestos de reglas (RD11):
## - Terna/cuarta por valor: mismo rango, palos repetidos permitidos (baraja doble).
## - Escalera: mismo palo y rangos consecutivos; el As va bajo (A-2-3) o alto
##   (Q-K-A), sin dar la vuelta (K-A-2).
## - Los comodines no forman combinaciones en el MVP (jokers_enabled = false).

const MIN_MELD := 3
const MAX_SET := 4
const ACE_HIGH := 14


# ======================================================================= consultas
func points_of(cards: Array[Card], values: CardValueTable) -> int:
	var total := 0
	for c in cards:
		total += values.value_of(c)
	return total


func is_valid_meld(cards: Array[Card]) -> bool:
	if cards.size() < MIN_MELD or _has_joker(cards):
		return false
	return _is_set(cards) or _is_run(cards)


## Combinaciones que cumplen `pattern` (una por casilla) dejando el sobrante de menor
## valor. Devuelve un arreglo vacío si el patrón no se puede cumplir.
func best_melds(cards: Array[Card], pattern: Array[MeldSpec], values: CardValueTable) -> Array[Meld]:
	var state := {"best": [], "best_points": -1}
	_search_pattern(cards.duplicate(), pattern, 0, [], values, state)
	var out: Array[Meld] = []
	out.assign(state["best"])
	return out


## Valor mínimo de las cartas que quedan sin combinar, con combinaciones libres
## (sin patrón). Es la penalización de un perdedor (RD07).
func min_leftover_points(cards: Array[Card], values: CardValueTable) -> int:
	return _min_leftover(cards.duplicate(), values)


# ======================================================================= búsqueda con patrón
func _search_pattern(remaining: Array[Card], pattern: Array[MeldSpec], idx: int,
		chosen: Array, values: CardValueTable, state: Dictionary) -> void:
	if state["best_points"] == 0:
		return
	if idx == pattern.size():
		_offer(remaining, chosen, values, state)
		return
	for meld_cards in _candidates(remaining, pattern[idx]):
		chosen.append(Meld.new(_type_of(meld_cards), meld_cards))
		_search_pattern(_without(remaining, meld_cards), pattern, idx + 1, chosen, values, state)
		chosen.pop_back()


func _offer(leftover: Array[Card], chosen: Array, values: CardValueTable, state: Dictionary) -> void:
	var points := points_of(leftover, values)
	if state["best_points"] < 0 or points < state["best_points"]:
		state["best_points"] = points
		state["best"] = chosen.duplicate()


func _candidates(cards: Array[Card], spec: MeldSpec) -> Array:
	var out := []
	if spec.allows_sets():
		out.append_array(_sets_of_size(cards, spec.size))
	if spec.allows_runs():
		out.append_array(_runs_of_size(cards, spec.size))
	return out


# ======================================================================= búsqueda libre
func _min_leftover(remaining: Array[Card], values: CardValueTable) -> int:
	if remaining.is_empty():
		return 0
	var first: Card = remaining[0]
	var rest: Array[Card] = remaining.slice(1)
	var best := values.value_of(first) + _min_leftover(rest, values)
	for meld_cards in _melds_containing(first, remaining):
		best = mini(best, _min_leftover(_without(remaining, meld_cards), values))
	return best


func _melds_containing(card: Card, cards: Array[Card]) -> Array:
	if card.is_joker():
		return []
	var out := []
	var others: Array[Card] = _without(cards, [card])
	for n in range(MIN_MELD, MAX_SET + 1):
		for combo in _combinations(_same_rank(others, card.rank), n - 1):
			combo.append(card)
			out.append(combo)
	out.append_array(_runs_containing(card, others))
	return out


func _runs_containing(card: Card, others: Array[Card]) -> Array:
	var out := []
	var by_rank := _by_rank_of_suit(others, card.suit)
	by_rank[card.rank] = [card]
	if card.rank == Card.Rank.ACE:
		by_rank[ACE_HIGH] = [card]
	for pos in _rank_positions(card.rank):
		for start in range(maxi(1, pos - 12), pos + 1):
			_collect_runs_from(start, pos, by_rank, out)
	return out


func _collect_runs_from(start: int, must_include: int, by_rank: Dictionary, out: Array) -> void:
	var run: Array[Card] = []
	for rank in range(start, ACE_HIGH + 1):
		if not by_rank.has(rank) or _contains_id(run, by_rank[rank][0]):
			return
		run.append(by_rank[rank][0])
		if rank >= must_include and run.size() >= MIN_MELD:
			out.append(run.duplicate())


# ======================================================================= generadores
func _sets_of_size(cards: Array[Card], n: int) -> Array:
	if n > MAX_SET:
		return []
	var out := []
	var groups := {}
	for c in cards:
		if not c.is_joker():
			groups[c.rank] = groups.get(c.rank, []) + [c]
	for rank in groups:
		out.append_array(_combinations(_typed(groups[rank]), n))
	return out


func _runs_of_size(cards: Array[Card], n: int) -> Array:
	var out := []
	for suit in [Card.Suit.HEARTS, Card.Suit.DIAMONDS, Card.Suit.CLUBS, Card.Suit.SPADES]:
		var by_rank := _by_rank_of_suit(cards, suit)
		for start in range(1, ACE_HIGH - n + 2):
			var run := _run_from(start, n, by_rank)
			if not run.is_empty():
				out.append(run)
	return out


func _run_from(start: int, n: int, by_rank: Dictionary) -> Array[Card]:
	var run: Array[Card] = []
	for rank in range(start, start + n):
		if not by_rank.has(rank):
			return []
		run.append(by_rank[rank][0])
	return run


func _combinations(pool: Array[Card], k: int) -> Array:
	var out := []
	_combine(pool, k, 0, [], out)
	return out


func _combine(pool: Array[Card], k: int, from: int, current: Array[Card], out: Array) -> void:
	if current.size() == k:
		out.append(current.duplicate())
		return
	for i in range(from, pool.size()):
		current.append(pool[i])
		_combine(pool, k, i + 1, current, out)
		current.pop_back()


# ======================================================================= validación
func _is_set(cards: Array[Card]) -> bool:
	if cards.size() > MAX_SET:
		return false
	for c in cards:
		if not c.same_rank_as(cards[0]):
			return false
	return true


func _is_run(cards: Array[Card]) -> bool:
	for c in cards:
		if not c.same_suit_as(cards[0]):
			return false
	var ranks: Array[int] = []
	for c in cards:
		ranks.append(c.rank)
	ranks.sort()
	if _consecutive(ranks):
		return true
	if ranks[0] != Card.Rank.ACE:
		return false
	ranks.remove_at(0)
	ranks.append(ACE_HIGH)
	return _consecutive(ranks)


func _consecutive(sorted_ranks: Array[int]) -> bool:
	for i in range(1, sorted_ranks.size()):
		if sorted_ranks[i] != sorted_ranks[i - 1] + 1:
			return false
	return true


func _type_of(cards: Array[Card]) -> int:
	return MeldSpec.Type.SET if _is_set(cards) else MeldSpec.Type.RUN


# ======================================================================= utilidades
func _has_joker(cards: Array[Card]) -> bool:
	for c in cards:
		if c.is_joker():
			return true
	return false


func _same_rank(cards: Array[Card], rank: int) -> Array[Card]:
	var out: Array[Card] = []
	for c in cards:
		if c.rank == rank:
			out.append(c)
	return out


## { rango: [cartas] } de un palo; el As aparece también como rango 14 (As alto).
func _by_rank_of_suit(cards: Array[Card], suit: int) -> Dictionary:
	var by_rank := {}
	for c in cards:
		if c.suit == suit and not c.is_joker():
			by_rank[c.rank] = by_rank.get(c.rank, []) + [c]
	if by_rank.has(Card.Rank.ACE):
		by_rank[ACE_HIGH] = by_rank[Card.Rank.ACE]
	return by_rank


func _rank_positions(rank: int) -> Array[int]:
	if rank == Card.Rank.ACE:
		return [Card.Rank.ACE, ACE_HIGH]
	return [rank]


func _without(cards: Array[Card], removed: Array) -> Array[Card]:
	var out: Array[Card] = []
	for c in cards:
		if not _contains_id(removed, c):
			out.append(c)
	return out


func _contains_id(cards: Array, card: Card) -> bool:
	for c in cards:
		if c.instance_id == card.instance_id:
			return true
	return false


func _typed(cards: Array) -> Array[Card]:
	var out: Array[Card] = []
	out.assign(cards)
	return out
