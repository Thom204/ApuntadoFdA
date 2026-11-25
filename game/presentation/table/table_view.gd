class_name TableView
extends Control
## Mesa de un jugador, distribuida como una mesa real vista desde tu asiento:
##
##   ┌──────────────── baranda de madera ────────────────┐
##   │  modo · ronda            rivales en el borde       │
##   │                 ┌─────┐   ┌─────┐                  │
##   │                 │MAZO │   │POZO │                  │
##   │                 └─────┘   └─────┘                  │
##   │               ~ APUNTADO · 101 ~                   │
##   │                [ tu turno: roba ]                  │
##   │  historial      ╲ tu mano en abanico ╱   acciones  │
##   │  tus puntos                                        │
##   └────────────────────────────────────────────────────┘
##
## Dibuja la última vista de su ClientSession y traduce clics y teclas en solicitudes.
## No valida reglas (RNF 6): habilita las acciones según el turno y la fase, y muestra el
## mensaje del servidor si rechaza algo. Atajos: M mazo, P pozo, D descartar, C cerrar,
## V ¿combinan?, O ordenar, N siguiente ronda, Esc quitar selección.
##
## Animaciones: cada vez que llega una vista nueva se compara con la anterior para saber
## qué carta se movió (plan_moves) y se la hace volar en arco de su origen a su destino:
## del mazo o el pozo a una mano, y de una mano al pozo. Las cartas robadas del mazo se
## voltean en el camino. Como se deducen de las vistas, funcionan igual para tus jugadas,
## las de los rivales y los turnos automáticos, y no dependen del orden en que lleguen
## respuestas y avisos. Nunca bloquean: se puede seguir jugando mientras vuelan.
##
## Uso: var table := TableView.new(); add_child(table); table.bind(session)

const CardViewScene := preload("res://presentation/table/card_view.tscn")
const FeltShader := preload("res://presentation/theme/felt_table.gdshader")

const PILE_CARD := Vector2(76, 106)
const HAND_CARD := Vector2(88, 123)
const CARDS_PER_EDGE := 8
const SIDE_PANEL_WIDTH := 250.0
const EDGE := 34.0  # baranda + aire
const TOAST_SECONDS := 3.5
const LOG_LINES := 6
## Duración del vuelo de una carta y cuánto sube el arco en el punto medio.
const FLY_SECONDS := 0.42
const FLY_ARC := 70.0
const ACTION_TEXT := {
	"DRAW_FROM_DECK": "robó del mazo",
	"DRAW_FROM_DISCARD": "robó del pozo",
	"DISCARD": "descartó",
	"DECLARE_CLOSING": "cerró la ronda descartando",
}

var _session: ClientSession
var _selected: Array[int] = []
## Orden visual de la mano, local al cliente y separado de los ids de carta.
var _hand_order: Array[int] = []
var _hand_order_round := -1
var _sort_by_suit := true
var _last_settlement: Dictionary = {}
## En false, las cartas cambian de lugar sin volar (movimiento reducido).
static var animations_enabled := true
var _prev_view: Dictionary = {}
## Cartas robadas que todavía vuelan hacia tu mano: se ocultan hasta que aterrizan.
var _landing_ids: Array[int] = []
## Mientras una carta vuela al pozo, el pozo sigue mostrando la carta anterior.
var _discard_holds := 0
var _discard_held_card: Variant = null
var _fx_layer: Control

var _felt: ColorRect
var _markings: TableMarkings
var _title: Label
var _seats: Array[OpponentSeat] = []
var _deck_card: CardView
var _discard_card: CardView
var _banner: PanelContainer
var _banner_text: Label
var _hand: HandFan
var _actions: VBoxContainer
var _discard_button: Button
var _close_button: Button
var _check_button: Button
var _sort_button: Button
var _me_plate: PanelContainer
var _me_text: Label
var _log_panel: PanelContainer
var _log_lines: VBoxContainer
var _toast: PanelContainer
var _toast_text: Label
var _toast_tween: Tween
var _overlay: Control
var _overlay_title: Label
var _overlay_body: Label
var _next_round_button: Button
var _leave_button: Button


func _init() -> void:
	clip_contents = true
	_build()
	resized.connect(_layout)


func bind(session: ClientSession) -> void:
	_session = session
	session.view_changed.connect(func(_view: Dictionary) -> void: _render())
	session.room_changed.connect(func(_room: Dictionary) -> void: _render())
	session.event_received.connect(_on_event)
	session.request_failed.connect(_on_failed)
	session.meld_checked.connect(_on_meld_checked)
	_render()


# ======================================================================= dibujo
func _render() -> void:
	if _session == null:
		return
	if not _session.has_match():
		_render_waiting()
		return
	var view := _session.view
	# Una mesa que no está en pantalla (otra pestaña) no anima: no tiene posiciones
	# válidas y nadie la ve. Solo actualiza su estado.
	var animate := animations_enabled and is_visible_in_tree() and size.x > 0
	var moves: Array[Dictionary] = []
	if animate:
		moves = plan_moves(_prev_view, view)
	var origins := _hand_card_visuals()  # dónde estaban tus cartas antes de redibujar
	_prepare_flights(moves)
	_title.text = "%s · Ronda %d" % [view["mode_name"], int(view["round_number"])]
	_markings.print_text = str(view["mode_name"]).to_upper().replace("(", "· ").replace(")", "")
	_render_seats(view)
	_render_piles(view)
	_render_hand(view)
	_render_banner(view)
	_render_actions(view)
	_render_me(view)
	_render_overlay(view)
	_layout()
	for move in moves:
		_fly(move, origins)
	_prev_view = view


func _render_waiting() -> void:
	var room := _session.room
	_title.text = "Sin sala" if room.is_empty() else "Sala %s · %s" % [room.get("room_code", room.get("room_id", "")), room.get("mode_name", "")]
	_banner.visible = true
	_banner_text.text = "Esperando jugadores (%d/%d)" % [room.get("players", []).size(), int(room.get("max_players", 0))]
	for button: Button in [_discard_button, _close_button, _check_button]:
		button.disabled = true
	# Sin partida (al salir de una terminada): la mesa queda vacía.
	_overlay.visible = false
	_prev_view = {}
	_last_settlement = {}
	for seat in _seats:
		seat.visible = false
	for child in _hand.get_children():
		_hand.remove_child(child)
		child.queue_free()
	_deck_card.show_empty()
	_discard_card.show_empty()
	_me_text.text = ""
	_layout()


func _render_seats(view: Dictionary) -> void:
	var opponents := _opponents_in_turn_order(view)
	while _seats.size() < opponents.size():
		var seat := OpponentSeat.new()
		add_child(seat)
		move_child(seat, _markings.get_index() + 1)
		_seats.append(seat)
	for i in _seats.size():
		_seats[i].visible = i < opponents.size()
		if i < opponents.size():
			_seats[i].show_player(opponents[i])


## Rivales empezando por el que juega después de ti: en la mesa real, el turno pasa a tu
## izquierda y sigue por el borde de enfrente hasta tu derecha.
func _opponents_in_turn_order(view: Dictionary) -> Array[Dictionary]:
	var players: Array = view["players"].duplicate()
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["seat"]) < int(b["seat"]))
	var mine := players.find_custom(func(p: Dictionary) -> bool: return p["id"] == view["you"])
	var out: Array[Dictionary] = []
	for i in range(1, players.size()):
		out.append(players[(mine + i) % players.size()])
	return out


func _render_piles(view: Dictionary) -> void:
	var can_draw := _can_act(view, "DRAW")
	var deck_size := int(view["deck_size"])
	if deck_size > 0:
		_deck_card.show_back()
	else:
		_deck_card.show_empty()
	_deck_card.stack = deck_size / CARDS_PER_EDGE
	_deck_card.interactive = can_draw and deck_size > 0
	var top: Variant = _discard_held_card if _discard_holds > 0 else view["top_discard"]
	if top != null:
		_discard_card.show_card(top)
	else:
		_discard_card.show_empty()
	_discard_card.stack = maxi(0, int(view["discard_size"]) - 1) / CARDS_PER_EDGE
	_discard_card.interactive = can_draw and top != null
	_markings.deck_caption = "MAZO · %d" % deck_size
	_markings.discard_caption = "POZO · %d" % int(view["discard_size"])
	_markings.drawable = can_draw
	_markings.queue_redraw()


func _render_hand(view: Dictionary) -> void:
	var round_number := int(view["round_number"])
	if round_number != _hand_order_round:
		_hand_order.clear()
		_hand_order_round = round_number
	for child in _hand.get_children():
		_hand.remove_child(child)
		child.queue_free()
	var sorted_cards: Array = CardFace.sorted(view["hand"], _sort_by_suit)
	var cards_by_id := {}
	var ids: Array[int] = []
	for card: Dictionary in sorted_cards:
		var id := int(card["id"])
		cards_by_id[id] = card
		ids.append(id)
	_hand_order.assign(_hand_order.filter(func(id: int) -> bool: return ids.has(id)))
	for id in ids:
		if not _hand_order.has(id):
			_hand_order.append(id)
	var ordered_cards: Array[Dictionary] = []
	for id in _hand_order:
		ordered_cards.append(cards_by_id[id])
	for card: Dictionary in ordered_cards:
		var card_view: CardView = CardViewScene.instantiate()
		_hand.add_child(card_view)
		card_view.show_card(card)
		card_view.interactive = true
		card_view.selected = card_view.card_id in _selected
		card_view.modulate.a = 0.0 if card_view.card_id in _landing_ids else 1.0
		card_view.pressed.connect(_toggle_selected)
		card_view.drag_started.connect(_hand.begin_drag)
		card_view.drag_moved.connect(_hand.update_drag)
		card_view.drag_finished.connect(_on_hand_drag_finished)
	_selected.assign(_selected.filter(func(id: int) -> bool: return id in ids))


func _render_banner(view: Dictionary) -> void:
	var text := ""
	var mine := false
	if view["status"] == "FINISHED" or view["round_closed"]:
		text = ""
	elif view["is_your_turn"] and view["phase"] == "DRAW":
		text = "Tu turno · Roba del mazo [M] o del pozo [P]"
		mine = true
	elif view["is_your_turn"]:
		text = "Tu turno · Elige una carta y descártala [D] o cierra la ronda [C]"
		mine = true
	else:
		text = "Turno de %s" % _nickname(view, str(view["current_player"]))
	_banner.visible = text != ""
	_banner_text.text = text
	_banner_text.add_theme_color_override("font_color", TableTheme.GOLD if mine else TableTheme.TEXT)
	_banner.add_theme_stylebox_override("panel", TableTheme.panel_style(
		TableTheme.GOLD if mine else TableTheme.GOLD_SOFT, TableTheme.PANEL_STRONG if mine else TableTheme.PANEL, 20, 2 if mine else 1))


func _render_actions(view: Dictionary) -> void:
	var can_discard := _can_act(view, "DISCARD") and _selected.size() == 1
	_discard_button.disabled = not can_discard
	_close_button.disabled = not can_discard
	_check_button.disabled = _selected.size() < 3
	_sort_button.text = "Ordenar por valor  [O]" if _sort_by_suit else "Ordenar por palo  [O]"


func _render_me(view: Dictionary) -> void:
	var me := _player(view, str(view["you"]))
	_me_text.text = "%s (tú)\n%d puntos" % [me.get("nickname", ""), int(me.get("total", 0))]


func _render_overlay(view: Dictionary) -> void:
	var finished: bool = view["status"] == "FINISHED"
	_overlay.visible = finished or view["round_closed"]
	if not _overlay.visible:
		return
	var lines: Array[String] = []
	var deltas: Dictionary = _last_settlement.get("deltas", {})
	for p: Dictionary in view["players"]:
		var delta := ("  (%+d)" % int(deltas[p["id"]])) if deltas.has(p["id"]) else ""
		var state := "" if p["active"] else "  · eliminado"
		lines.append("%s:  %d pts%s%s" % [p["nickname"], int(p["total"]), delta, state])
	if finished:
		_overlay_title.text = "¡Gana %s!" % _nickname(view, str(view["winner"]))
	elif not _last_settlement.is_empty():
		_overlay_title.text = "%s cerró la ronda %d" % [
			_nickname(view, str(_last_settlement["closer_id"])), int(_last_settlement["round_number"])]
	else:
		_overlay_title.text = "Ronda %d cerrada" % int(view["round_number"])
	_overlay_body.text = "\n".join(lines)
	_next_round_button.visible = not finished
	_leave_button.visible = finished


func _can_act(view: Dictionary, phase: String) -> bool:
	return view["is_your_turn"] and view["phase"] == phase and not view["round_closed"] and view["status"] == "IN_PROGRESS"


# ======================================================================= animaciones
## Qué cartas se movieron entre dos vistas de la misma ronda. Cada movimiento es:
##   { kind: "draw_me", card, from: "deck"|"discard" }   robaste
##   { kind: "discard_me", card }                         descartaste (o cerraste)
##   { kind: "draw_other", player, from, card }           un rival robó (card: la del pozo)
##   { kind: "discard_other", player, card }              un rival descartó
## Vacío si no hay vista anterior o cambió la partida o la ronda (se reparte de nuevo).
static func plan_moves(before: Dictionary, view: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if before.is_empty() or view.is_empty() or before.get("match_id") != view.get("match_id") \
			or before.get("round_number") != view.get("round_number"):
		return out
	var from := "deck" if int(view["deck_size"]) < int(before["deck_size"]) else "discard"
	var discarded := int(view["discard_size"]) > int(before["discard_size"])
	var old_ids := _ids(before["hand"])
	var new_ids := _ids(view["hand"])
	for card: Dictionary in view["hand"]:
		if not int(card["id"]) in old_ids:
			out.append({"kind": "draw_me", "card": card, "from": from})
	for card: Dictionary in before["hand"]:
		if not int(card["id"]) in new_ids:
			out.append({"kind": "discard_me", "card": card})
	var old_sizes := {}
	for p: Dictionary in before["players"]:
		old_sizes[p["id"]] = int(p["hand_size"])
	for p: Dictionary in view["players"]:
		if p["id"] == view["you"]:
			continue
		var change := int(p["hand_size"]) - int(old_sizes.get(p["id"], p["hand_size"]))
		if change > 0:
			out.append({"kind": "draw_other", "player": p["id"], "from": from, "card": before["top_discard"]})
		elif change < 0 and discarded:
			out.append({"kind": "discard_other", "player": p["id"], "card": view["top_discard"]})
	return out


static func _ids(cards: Array) -> Array[int]:
	var out: Array[int] = []
	for card: Dictionary in cards:
		out.append(int(card["id"]))
	return out


## Antes de redibujar: oculta las cartas que van a aterrizar en tu mano y congela el pozo
## mientras le llega una carta.
func _prepare_flights(moves: Array[Dictionary]) -> void:
	for move in moves:
		if move["kind"] == "draw_me":
			_landing_ids.append(int(move["card"]["id"]))
		elif move["kind"] in ["discard_me", "discard_other"]:
			if _discard_holds == 0:
				_discard_held_card = _prev_view.get("top_discard")
			_discard_holds += 1


func _fly(move: Dictionary, origins: Dictionary) -> void:
	var card: Variant = move.get("card")
	match move["kind"]:
		"draw_me":
			var id := int(card["id"])
			var target := _hand_card(id)
			if target == null:
				_landed(id)
				return
			var source := _visual(_deck_card if move["from"] == "deck" else _discard_card)
			_launch(source, _visual(target), card, move["from"] == "discard", true, _landed.bind(id))
		"discard_me":
			var source: Dictionary = origins.get(int(card["id"]), _visual(_hand))
			_launch(source, _visual(_discard_card), card, true, true, _release_discard)
		"draw_other":
			var seat := _seat_of(str(move["player"]))
			if seat == null:
				return
			var source := _visual(_deck_card if move["from"] == "deck" else _discard_card)
			_launch(source, _seat_visual(seat), card, move["from"] == "discard" and card != null, false, Callable())
		"discard_other":
			var seat := _seat_of(str(move["player"]))
			if seat == null:
				_release_discard()
				return
			_launch(_seat_visual(seat), _visual(_discard_card), card, false, true, _release_discard)


## Hace volar una carta en arco de `from` a `to` ({ center, size, rotation }), con su
## tamaño y giro interpolados; si cambia de cara, se voltea a mitad de camino.
func _launch(from: Dictionary, to: Dictionary, card: Variant, face_up_at_start: bool, face_up_at_end: bool, done: Callable) -> void:
	var flyer: CardView = CardViewScene.instantiate()
	flyer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flyer.custom_minimum_size = Vector2.ZERO
	_fx_layer.add_child(flyer)
	_show_face(flyer, card, face_up_at_start)
	var flips := face_up_at_start != face_up_at_end
	var state := {"flipped": false}  # diccionario: la lambda lo modifica por referencia
	var start: Vector2 = from["center"]
	var end: Vector2 = to["center"]
	var control := (start + end) / 2 - Vector2(0, FLY_ARC)
	var step := func(t: float) -> void:
		var e := 1.0 - pow(1.0 - t, 3)  # sale rápido y frena al llegar
		var center := start.lerp(control, e).lerp(control.lerp(end, e), e)
		var card_size: Vector2 = from["size"].lerp(to["size"], e)
		flyer.size = card_size
		flyer.pivot_offset = card_size / 2
		flyer.position = center - card_size / 2
		flyer.rotation = lerp_angle(from["rotation"], to["rotation"], e)
		if flips:
			flyer.scale = Vector2(maxf(absf(1.0 - 2.0 * e), 0.03), 1.0)
			if e >= 0.5 and not state["flipped"]:
				state["flipped"] = true
				_show_face(flyer, card, face_up_at_end)
	step.call(0.0)
	var tween := create_tween()
	tween.tween_method(step, 0.0, 1.0, FLY_SECONDS)
	tween.tween_callback(_finish_flight.bind(flyer, done))


func _finish_flight(flyer: CardView, done: Callable) -> void:
	flyer.queue_free()
	if done.is_valid():
		done.call()


func _show_face(flyer: CardView, card: Variant, face_up: bool) -> void:
	if face_up and card != null:
		flyer.show_card(card)
	else:
		flyer.show_back()


func _landed(card_id: int) -> void:
	_landing_ids.erase(card_id)
	var card := _hand_card(card_id)
	if card != null:
		card.modulate.a = 1.0


func _release_discard() -> void:
	_discard_holds = maxi(0, _discard_holds - 1)
	if _discard_holds == 0:
		_discard_held_card = null
		if _session != null and _session.has_match():
			_render_piles(_session.view)


## Centro, tamaño y giro de un control en coordenadas de la mesa.
func _visual(control: Control) -> Dictionary:
	var xf := get_global_transform().affine_inverse() * control.get_global_transform()
	return {"center": xf * (control.size / 2), "size": control.size * xf.get_scale(), "rotation": xf.get_rotation()}


func _seat_visual(seat: OpponentSeat) -> Dictionary:
	return {"center": seat.position + seat.cards_center(), "size": OpponentSeat.BACK_SIZE, "rotation": 0.0}


func _hand_card_visuals() -> Dictionary:
	var out := {}
	for child in _hand.get_children():
		var card := child as CardView
		if card != null and card.card_id >= 0:
			out[card.card_id] = _visual(card)
	return out


func _hand_card(card_id: int) -> CardView:
	for child in _hand.get_children():
		var card := child as CardView
		if card != null and card.card_id == card_id and not card.is_queued_for_deletion():
			return card
	return null


func _seat_of(player_id: String) -> OpponentSeat:
	for seat in _seats:
		if seat.visible and seat.player_id == player_id:
			return seat
	return null

# ======================================================================= distribución
## Ubica todo según el tamaño de la mesa: la mano centrada en la mitad inferior, el mazo y
## el pozo al centro, y los rivales en el arco superior del borde.
func _layout() -> void:
	var s := size
	if s.x <= 0 or s.y <= 0:
		return
	_felt.size = s
	(_felt.material as ShaderMaterial).set_shader_parameter("rect_size", s)
	_markings.size = s
	_title.position = Vector2(EDGE + 30, EDGE + 12)

	# Mazo y pozo: al centro, un poco por encima de la mitad.
	# Justo debajo del asiento de enfrente, para dejarle aire a la mano y al cartel de turno.
	var piles_center := Vector2(s.x / 2, maxf(s.y * 0.36, EDGE + OpponentSeat.SIZE.y + 24 + PILE_CARD.y / 2))
	var gap := 44.0
	_deck_card.position = piles_center + Vector2(-gap / 2 - PILE_CARD.x, -PILE_CARD.y / 2)
	_discard_card.position = piles_center + Vector2(gap / 2, -PILE_CARD.y / 2)
	_markings.deck_slot = Rect2(_deck_card.position, PILE_CARD)
	_markings.discard_slot = Rect2(_discard_card.position, PILE_CARD)

	# Tu mano: centrada en la mitad inferior, entre los paneles laterales.
	var hand_height := HAND_CARD.y + 60
	var available := s.x - 2 * (SIDE_PANEL_WIDTH + EDGE)
	var hand_width := clampf(_hand.natural_width(_hand.get_child_count()), HAND_CARD.x, maxf(HAND_CARD.x, available))
	_hand.size = Vector2(hand_width, hand_height)
	# Las cartas sobresalen un poco sobre la baranda, como cuando se sostienen en la mano.
	_hand.position = Vector2((s.x - hand_width) / 2, s.y - hand_height - 18)
	_hand.relayout()

	_banner.reset_size()
	_banner.position = Vector2((s.x - _banner.size.x) / 2, _hand.position.y - _banner.size.y + 8)
	# Nombre del juego impreso en arco, entre los espacios de cartas y el cartel de turno.
	var piles_bottom := piles_center.y + PILE_CARD.y / 2 + TableMarkings.SLOT_PADDING
	_markings.print_radius = 520.0
	_markings.print_center = Vector2(s.x / 2, piles_bottom + 62 - _markings.print_radius)
	_markings.queue_redraw()

	# Rivales: sobre una elipse, de tu izquierda (siguiente en jugar) a tu derecha.
	var visible_seats := _seats.filter(func(seat: OpponentSeat) -> bool: return seat.visible)
	var count := visible_seats.size()
	var seat_center_y := s.y * 0.46
	var seat_radius_y := seat_center_y - (EDGE + OpponentSeat.SIZE.y / 2 + 2)
	for i in count:
		var angle := deg_to_rad(270.0) if count == 1 else deg_to_rad(lerpf(192.0, 348.0, float(i) / (count - 1)))
		var at := Vector2(s.x / 2 + cos(angle) * s.x * 0.36, seat_center_y + sin(angle) * seat_radius_y)
		visible_seats[i].position = at - OpponentSeat.SIZE / 2

	# Paneles laterales: historial y tus puntos a la izquierda, acciones a la derecha.
	_me_plate.reset_size()
	_me_plate.position = Vector2(EDGE + 10, s.y - EDGE - _me_plate.size.y - 4)
	_log_panel.size = Vector2(SIDE_PANEL_WIDTH, 0)
	_log_panel.reset_size()
	_log_panel.visible = _log_lines.get_child_count() > 0
	_log_panel.position = Vector2(EDGE + 10, _me_plate.position.y - _log_panel.size.y - 10)
	_actions.reset_size()
	_actions.position = Vector2(s.x - EDGE - 10 - _actions.size.x, s.y - EDGE - _actions.size.y - 4)
	# El aviso aparece justo encima del cartel de turno, sin taparlo.
	_toast.reset_size()
	var above := _banner.position.y if _banner.visible else _hand.position.y + 30
	_toast.position = Vector2((s.x - _toast.size.x) / 2, above - _toast.size.y - 8)
	_overlay.size = s


# ======================================================================= acciones
func _toggle_selected(card_id: int) -> void:
	if card_id in _selected:
		return
	else:
		_selected.clear()
		_selected.append(card_id)

	_render()


func _discard_selected() -> void:
	if not _discard_button.disabled:
		_session.discard(_selected[0])
		_selected.clear()


func _close_with_selected() -> void:
	if not _close_button.disabled:
		_session.declare_closing(_selected[0])
		_selected.clear()


func _check_selected() -> void:
	if not _check_button.disabled:
		_session.check_meld(_selected.duplicate())


func _toggle_sort() -> void:
	_sort_by_suit = not _sort_by_suit
	if _session != null and _session.has_match():
		_hand_order.clear()
		for card: Dictionary in CardFace.sorted(_session.view["hand"], _sort_by_suit):
			_hand_order.append(int(card["id"]))
	_render()


func _on_hand_drag_finished(_card: CardView, global_position: Vector2) -> void:
	_hand.finish_drag(global_position)
	_hand_order.clear()
	for child in _hand.get_children():
		var hand_card := child as CardView
		if hand_card != null:
			_hand_order.append(hand_card.card_id)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not is_visible_in_tree() or _session == null or not _session.has_match():
		return
	match key.keycode:
		KEY_M:
			if _deck_card.interactive:
				_session.draw_from_deck()
		KEY_P:
			if _discard_card.interactive:
				_session.draw_from_discard()
		KEY_D:
			_discard_selected()
		KEY_C:
			_close_with_selected()
		KEY_V:
			_check_selected()
		KEY_O:
			_toggle_sort()
		KEY_N:
			if _overlay.visible and _next_round_button.visible:
				_session.start_next_round()
		KEY_ESCAPE:
			_selected.clear()
			_render()
		_:
			return
	get_viewport().set_input_as_handled()


# ======================================================================= mensajes
func _on_event(event: String, data: Dictionary) -> void:
	var view := _session.view
	match event:
		"round_started":
			_last_settlement = {}
			_note("Empieza la ronda %d." % int(data["round_number"]))
			_render()
		"move_performed":
			_note(_move_text(view, data))
		"round_closed":
			_last_settlement = data["settlement"]
			_note(_settlement_text(view, data["settlement"]))
			_render()
		"player_eliminated":
			_note("%s quedó eliminado." % _nickname(view, str(data["player_id"])))
		"match_finished":
			_note("Fin de la partida: gana %s." % _nickname(view, str(data["winner_id"])))


func _move_text(view: Dictionary, move: Dictionary) -> String:
	var text := "%s %s" % [_nickname(view, str(move["player_id"])), ACTION_TEXT.get(move["action"], move["action"])]
	if move["card"] != null:
		text += " " + CardFace.spoken_name(move["card"]).to_lower()
	if move.get("automatic", false):
		text += " (automático)"
	return text + "."


func _settlement_text(view: Dictionary, settlement: Dictionary) -> String:
	var parts: Array[String] = []
	for player_id: String in settlement["deltas"]:
		parts.append("%s %+d" % [_nickname(view, player_id), int(settlement["deltas"][player_id])])
	return "%s cerró la ronda: %s." % [_nickname(view, str(settlement["closer_id"])), ", ".join(parts)]


func _on_failed(response: Dictionary) -> void:
	_show_toast(str(response.get("message", response.get("error", ""))), false)


func _on_meld_checked(check: Dictionary) -> void:
	var verdict := "Combinan" if check["valid"] else "No combinan"
	_show_toast("%s: %s (%d pts)" % [verdict, check["message"], int(check["points"])], check["valid"])


## Aviso temporal sobre el paño: aparece al instante y se desvanece solo (no hay que
## cerrarlo). El texto dice si es error o no; el color solo lo refuerza.
func _show_toast(text: String, ok: bool) -> void:
	_toast_text.text = text
	_toast.add_theme_stylebox_override("panel", TableTheme.panel_style(
		TableTheme.GOLD_SOFT, TableTheme.OK_BG if ok else TableTheme.ERROR_BG, 18))
	_toast.visible = true
	_toast.modulate.a = 1.0
	_layout()
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


func _note(text: String) -> void:
	var line := TableTheme.label(text, TableTheme.FONT_SMALL, TableTheme.TEXT_DIM)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = SIDE_PANEL_WIDTH - 28
	_log_lines.add_child(line)
	while _log_lines.get_child_count() > LOG_LINES:
		var old := _log_lines.get_child(0)
		_log_lines.remove_child(old)
		old.queue_free()
	_layout()


# ======================================================================= ayudas
func _player(view: Dictionary, player_id: String) -> Dictionary:
	for p: Dictionary in view.get("players", []):
		if p["id"] == player_id:
			return p
	return {}


func _nickname(view: Dictionary, player_id: String) -> String:
	return str(_player(view, player_id).get("nickname", player_id))


# ======================================================================= armado
func _build() -> void:
	_felt = ColorRect.new()
	_felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var felt_material := ShaderMaterial.new()
	felt_material.shader = FeltShader
	_felt.material = felt_material
	add_child(_felt)

	_markings = TableMarkings.new()
	add_child(_markings)

	_title = TableTheme.label("", TableTheme.FONT_TITLE, TableTheme.GOLD)
	add_child(_title)

	_deck_card = _pile_card()
	_deck_card.pressed.connect(func(_id: int) -> void: _session.draw_from_deck())
	_discard_card = _pile_card()
	_discard_card.pressed.connect(func(_id: int) -> void: _session.draw_from_discard())

	_hand = HandFan.new()
	_hand.card_size = HAND_CARD
	add_child(_hand)

	_banner = TableTheme.panel()
	_banner_text = TableTheme.label("", TableTheme.FONT_TITLE)
	_banner.add_child(_banner_text)
	add_child(_banner)

	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	add_child(_actions)
	_discard_button = _action_button("Descartar  [D]", _discard_selected, true)
	_close_button = _action_button("Cerrar ronda  [C]", _close_with_selected, true)
	_check_button = _action_button("¿Combinan?  [V]", _check_selected)
	_sort_button = _action_button("Ordenar por valor  [O]", _toggle_sort)

	_log_panel = TableTheme.panel()
	_log_lines = VBoxContainer.new()
	_log_lines.add_theme_constant_override("separation", 2)
	_log_panel.add_child(_log_lines)
	add_child(_log_panel)

	_me_plate = TableTheme.panel(TableTheme.GOLD)
	_me_text = TableTheme.label("", TableTheme.FONT_BODY)
	_me_plate.add_child(_me_text)
	add_child(_me_plate)

	_fx_layer = Control.new()
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)

	_toast = TableTheme.panel()
	_toast_text = TableTheme.label("", TableTheme.FONT_BODY)
	_toast.add_child(_toast_text)
	_toast.visible = false
	add_child(_toast)

	_build_overlay()


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.visible = false
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var card := TableTheme.panel(TableTheme.GOLD, TableTheme.PANEL_STRONG)
	card.custom_minimum_size.x = 380
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	_overlay_title = TableTheme.label("", TableTheme.FONT_HERO, TableTheme.GOLD)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_overlay_title)
	_overlay_body = TableTheme.label("", TableTheme.FONT_BODY)
	column.add_child(_overlay_body)
	_next_round_button = Button.new()
	_next_round_button.text = "Siguiente ronda  [N]"
	TableTheme.style_button(_next_round_button, true)
	_next_round_button.pressed.connect(func() -> void: _session.start_next_round())
	column.add_child(_next_round_button)
	_leave_button = Button.new()
	_leave_button.text = "Volver al inicio"
	TableTheme.style_button(_leave_button, true)
	_leave_button.pressed.connect(func() -> void: _session.leave_room())
	column.add_child(_leave_button)


func _pile_card() -> CardView:
	var card: CardView = CardViewScene.instantiate()
	card.custom_minimum_size = PILE_CARD
	card.size = PILE_CARD
	add_child(card)
	return card


func _action_button(text: String, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.x = 210
	TableTheme.style_button(button, primary)
	button.pressed.connect(action)
	_actions.add_child(button)
	return button
