# Protocolo entre el núcleo y la red

Contrato entre el núcleo del juego (`res://orchestration/`, `res://notification/`) y el adaptador de red (`res://infrastructure/network/`, Network Session de ADR-05). El núcleo decide todo; la red solo autentica, transporta y entrega.

Todo lo que cruza esta frontera es **nativo de JSON**: `String`, `int`/`float`, `bool`, `null`, `Array` y `Dictionary` con claves `String`. Las pruebas lo verifican (`test_lobby.gd`, `test_game_notification.gd`).

## 1. Lo que arma el servidor

La implementación server-side está en `res://infrastructure/network/network_session.gd`,
instanciada por `res://app/server.tscn`. Arranca el listener WebSocket, inicializa el
registro de reglas, SQLite, el lobby, las notificaciones y la auditoría. El único punto
que recibe comandos es `Lobby.handle`; este adaptador no contiene reglas del juego.

El servidor acepta estas variables de entorno (si se omiten usa los valores indicados):

| Variable | Valor por defecto | Uso |
|---|---|---|
| `APUNTADO_PORT` | `7777` | Puerto TCP del WebSocket server |
| `APUNTADO_BIND_ADDRESS` | `*` | Dirección de escucha; en producción puede quedar detrás de un proxy TLS |
| `APUNTADO_DB` | `user://apuntado_server.db` | Archivo SQLite local del proceso servidor |
| `APUNTADO_AUDIT_LOG` | `user://apuntado_server.jsonl` | Archivo JSONL de auditoría |

Arranque local desde la raíz del repositorio: `godot --headless --path game res://app/server.tscn`.
En producción se exporta esa misma escena con la plantilla de servidor dedicado. Si TLS
termina en un proxy, el proxy debe aceptar WSS desde el navegador y reenviar WebSocket
sin TLS a la dirección privada del proceso.

### Sesión y reconexión

Antes de enviar solicitudes, el cliente invoca `hello(resume_token)` por RPC. En una
sesión nueva envía una cadena vacía; el servidor responde con `welcome`:

```json
{ "player_id": "p-…", "resume_token": "…", "resumed": false }
```

El token es una credencial aleatoria de portador. `ClientNetworkEndpoint` lo conserva
en `user://apuntado_session.cfg` y lo vuelve a presentar en `hello` tras una desconexión
o al abrir de nuevo la aplicación; no almacena la sala, la mano ni el marcador. La sala
y la vista que mantiene `ClientSession` son una caché temporal de presentación, nunca
estado autoritativo. En Web, la persistencia de `user://` depende de IndexedDB y de que
el navegador permita ese almacenamiento; si no es persistente, una recarga puede perder
el token y crear una identidad nueva.
El servidor mantiene el mapeo token/jugador únicamente en memoria. Un reinicio invalida
los tokens y las salas en curso, porque el Lobby aún no restaura salas desde SQLite.
Un token solo puede tener una conexión activa; al reanudarlo se cierra la conexión
anterior. `player_id` nunca se acepta desde `request(data)`.

El cliente implementa esos RPC en `ClientNetworkEndpoint`, cuyo nodo raíz se llama
`NetworkSession` en `res://app/network_client.tscn`; así coincide con la ruta
`/root/NetworkSession` del servidor. `hello` y `request` son llamadas del cliente al
servidor, y `welcome`, `response` y `event` son llamadas de autoridad del servidor al
cliente. `ClientNetworkTransport` adapta esas señales al puerto `IClientTransport` que
consume `ClientSession`.

El cliente de demo está en `res://app/online_client.tscn` y es la escena principal. La
pantalla permite configurar la URL WebSocket, conectarse, crear una sala y unirse con el
código compartido. En Web, el token se guarda en el sistema `user://` de Godot, respaldado
por IndexedDB; el navegador debe permitir almacenamiento del sitio. En navegación privada
o con ese almacenamiento bloqueado, se puede perder al cerrar o recargar la página.

```gdscript
# infrastructure/network/network_session.gd (lo implementa la red; aquí sí se permite @rpc)
var _registry := RuleRegistry.new(HandEvaluator.new())
var _repository: SqlMatchRepository
var _lobby: Lobby
var _notifications: LobbyNotification   # conservar estas referencias mientras viva el servidor
var _audit: AuditTrail

func _ready() -> void:
	_registry.load_plugins(RuleRegistry.DEFAULT_PLUGIN_DIR)
	assert(_registry.has_required_modes())   # fail fast (ADR-03)
	# Rutas por configuración externa (D-19), fuera de res://.
	_repository = SqlMatchRepository.open(OS.get_environment("APUNTADO_DB"))
	assert(_repository != null, SqlMatchRepository.open_error)   # fail fast (ADR-04, C-8)
	_lobby = Lobby.new(_registry, _repository)
	_lobby.turn_timeout_ms = 45000            # opcional: por defecto 45 s y 10 s (D-12)
	_notifications = LobbyNotification.new(_lobby, NetworkChannel.new(self))
	_audit = AuditTrail.new(_lobby, JsonlAuditSink.open(OS.get_environment("APUNTADO_AUDIT_LOG")))
	var timer := Timer.new()                  # el núcleo no tiene reloj: lo mueve el servidor
	timer.wait_time = 1.0
	timer.timeout.connect(func() -> void: _lobby.tick(Time.get_ticks_msec()))
	add_child(timer)
	timer.start()
	multiplayer.peer_disconnected.connect(func(peer: int) -> void: _lobby.set_connected(_player_of(peer), false))

@rpc("any_peer", "call_remote", "reliable")
func request(data: Dictionary) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var player_id := _player_of(peer)             # autenticación: responsabilidad de la red
	response.rpc_id(peer, _lobby.handle(player_id, data))
```

- **Al reconectarse**, la red llama `_lobby.set_connected(player_id, true)` y el cliente pide `get_view` (D-11).
- **`tick(now_ms)`** recibe cualquier reloj que avance en milisegundos (`Time.get_ticks_msec()` sirve). Devuelve los jugadores por los que jugó el servidor.
- **La base y el log de auditoría** se pasan por variables de entorno en el ejemplo; la forma concreta (argumentos, archivo de configuración) la decide la red. Al exportar el servidor hay que incluir `*.sql` en los filtros de exportación, porque las migraciones se leen de `res://infrastructure/persistence/migrations/`.

```gdscript
class NetworkChannel extends IPlayerChannel:
	func send(player_id: StringName, message: Dictionary) -> void:
		_session.event.rpc_id(_session.peer_of(player_id), message)
```

- **`player_id` lo pone la red**, a partir del peer autenticado. Nunca se toma del mensaje, para que nadie pueda jugar haciéndose pasar por otro.
- **`IPlayerChannel.send`** no devuelve nada. Si un envío falla, el comando ya está guardado y no se deshace.
- **Momento de la entrega:** las notificaciones llegan al final del frame (`CONNECT_DEFERRED`), después de la respuesta del comando.

## 2. Solicitud y respuesta

```json
{ "type": "discard", "action_id": "c1-0042", "expected_version": 7, "card_id": 31 }
```

```json
{ "ok": true, "request": "discard", "action_id": "c1-0042",
  "error": "", "message": "", "data": { "view": { ... }, "card": { ... } } }
```

- **`action_id`:** obligatorio en toda solicitud que cambia algo. Un texto único por acción del cliente. Si llega repetido (un reintento), se devuelve **la misma respuesta** sin ejecutar otra vez. Solo se recuerdan las respuestas exitosas: un fallo se puede reintentar con el mismo id.
- **`expected_version`:** obligatorio en los comandos de juego. Es el `view.version` que el cliente vio por última vez. Si no coincide, la respuesta es `STALE_STATE` y `data.view` trae la mesa actual para resincronizar; no se ejecuta nada.
- **Errores:** si `ok` es `false`, `error` trae un código de `ErrorCatalog` (sección 6) y `message`, el texto para el jugador.

### Solicitudes

| `type` | Campos | Cambia estado | `data` si sale bien | Errores propios |
|---|---|---|---|---|
| `create_room` | `nickname`, `mode` | sí | `room` | `INVALID_REQUEST`, `ALREADY_IN_ROOM`, `UNKNOWN_MODE` |
| `join_room` | `room_code`, `nickname` | sí | `room` | `NO_ROOM`, `ALREADY_IN_ROOM`, `ROOM_ALREADY_STARTED`, `ROOM_FULL` |
| `leave_room` | — | sí | — | `NOT_IN_ROOM`, `ROOM_ALREADY_STARTED` |
| `start_match` | — | sí | `view` | `NOT_HOST`, `NOT_ENOUGH_PLAYERS`, `ROOM_ALREADY_STARTED` |
| `draw_from_deck` | `expected_version` | sí | `view`, `card` (la robada, solo para quien roba) | de juego |
| `draw_from_discard` | `expected_version` | sí | `view`, `card` | de juego |
| `discard` | `expected_version`, `card_id` | sí | `view`, `card` | de juego |
| `declare_closing` | `expected_version`, `card_id` | sí | `view`, `validation` | de juego, `INVALID_CLOSING` (con `validation`) |
| `start_next_round` | `expected_version` | sí | `view` | `ROUND_IN_PROGRESS` |
| `get_view` | — | no | `room`, `view` | `NOT_IN_ROOM` |
| `check_meld` | `card_ids: [int]` | no | `check` | `NOT_IN_ROOM`, `INVALID_REQUEST` |

- **Errores de juego:** `NOT_IN_ROOM`, `NO_MATCH` (la sala aún no empieza), `STALE_STATE`, `MATCH_FINISHED`, `NOT_PLAYER_TURN`, `ACTION_NOT_ALLOWED`, `CARD_NOT_IN_HAND`, `DISCARD_EMPTY`, `DECK_EMPTY`, `PERSISTENCE_FAILED`.
- **Errores de cualquier solicitud:** `INVALID_REQUEST` (sin `type`, sin `action_id`, campos faltantes) y `UNKNOWN_REQUEST`.
- **Salas:** quien crea la sala es el anfitrión. La respuesta de `create_room` incluye `room.room_code`, un código de invitación de seis caracteres para compartir en la LAN. `join_room` busca por ese código; mantiene compatibilidad con clientes antiguos que envían `room_id`. Un jugador está en una sola sala a la vez, por eso los comandos de juego no llevan identificador de sala. La sala admite de 2 a 5 jugadores y empieza cuando el anfitrión envía `start_match`. Si el anfitrión sale antes de empezar, lo reemplaza el siguiente en llegar. Una sala vacía desaparece.
- **Partida iniciada:** el código no permite añadir jugadores una vez iniciada; devuelve `ROOM_ALREADY_STARTED`. Un miembro vuelve presentando el token de sesión existente: el servidor asocia ese token al mismo `player_id` y el cliente solicita `get_view`. Una sesión nueva no puede reclamar un asiento con el código.
- **Reconexión e inactividad:** el miembro reconectado recibe su mesa con `get_view`. Mientras permanece desconectado, la política vigente ejecuta turnos automáticos según los plazos configurados.
- **Turnos automáticos (D-12):** si un turno no avanza en 45 s (10 s si el jugador está desconectado), el servidor juega por él: roba del mazo y descarta lo que robó. Llega como un `move_performed` normal con `"automatic": true`. Con 3 turnos automáticos seguidos, el jugador queda eliminado al liquidarse la ronda (`player_eliminated`). Si nadie de la sala está conectado, la partida espera.

## 3. Notificaciones (núcleo → cada jugador)

```json
{ "event": "move_performed", "data": { ... }, "view": { ...vista de ESE jugador... } }
```

| `event` | `data` |
|---|---|
| `room_updated` | la sala (`room`); en este caso `view` va vacío |
| `round_started` | `{ "round_number" }` |
| `turn_changed` | `{ "player_id" }` |
| `move_performed` | movimiento (sección 5) |
| `round_closed` | `{ "settlement", "closing" }` (liquidación y validación del cierre) |
| `player_eliminated` | `{ "player_id" }` |
| `match_finished` | `{ "winner_id" }` |

Cada mensaje trae la vista de quien lo recibe: el cliente puede redibujar con `view` sin pedir nada más.

## 4. Vista de un jugador (`view`)

```json
{ "match_id": "m-1a2b3c4d", "mode": "apuntado", "mode_name": "Apuntado (101)",
  "status": "IN_PROGRESS", "version": 7, "round_number": 2, "round_closed": false,
  "current_player": "b", "phase": "DRAW", "top_discard": { ...carta... },
  "deck_size": 23, "discard_size": 4, "winner": "",
  "players": [ { "id": "a", "nickname": "Ana", "seat": 0, "active": true,
                 "total": 10, "hand_size": 10, "is_current": false } ],
  "you": "a", "is_your_turn": false, "hand": [ ...cartas propias... ] }
```

- **`hand`** solo trae las cartas de quien recibe la vista. De los demás solo se envía `hand_size` (RNF 3).
- **`phase`** puede ser `DRAW` (robar), `DISCARD` (descartar o cerrar) o `END`. Quien empieza la ronda arranca en `DISCARD` con 11 cartas.
- **`total`** es el puntaje con signo: +10 al cerrar, +25 al irse a pintas, menos las cartas sueltas al perder. Se gana en +51 y se sale en −101.

## 5. Formatos

- **Carta:** `{ "id": 31, "rank": 7, "suit": 1, "label": "7♥" }`. `id` es lo que se envía en `card_id`.
- **Movimiento:** `{ "sequence", "round_number", "player_id", "action", "card", "automatic" }`. `action` es `DRAW_FROM_DECK`, `DRAW_FROM_DISCARD`, `DISCARD` o `DECLARE_CLOSING`. `card` es `null` al robar del mazo, porque esa carta es secreta. `automatic` es `true` si la jugó el servidor por turno vencido.
- **Liquidación:** `{ "round_number", "closer_id", "deltas": { "a": 10, "b": -65 } }`.
- **Validación de cierre:** `{ "valid", "reason", "message", "leftover_points", "leftover": [cartas], "melds": [[cartas]] }`.
- **Organizar la mano (`check`):** `{ "result": "SET" | "RUN" | "INVALID" | "CARD_NOT_IN_HAND", "valid", "points", "message" }`.
- **Sala (`room`):** `{ "room_id", "room_code", "host_id", "mode", "mode_name", "status": "WAITING" | "IN_PROGRESS" | "FINISHED", "max_players": 5, "players": [ { "id", "nickname", "connected" } ] }`. `room_code` es el código para encontrar una sala en espera; `connected` es `false` mientras la red tenga al jugador como desconectado.

## 6. Códigos de error

Los códigos están en `res://shared/error_catalog.gd`, junto con el mensaje de cada uno. La prueba `test_error_catalog.gd` fija la lista: **cambiar un código rompe al cliente; agregar uno es compatible.**

## 7. Fuera de alcance por ahora

- **Salir de la sala con la partida en curso:** `leave_room` lo rechaza; quien se va queda desconectado y lo cubren los turnos automáticos.
- **Empezar la ronda siguiente sin nadie que la pida:** `start_next_round` lo envía un jugador; el servidor no lo hace solo.
- **Recuperar las salas tras reiniciar el servidor:** las partidas se pueden recuperar con `MatchOrchestrator.resume_match`, pero el `Lobby` aún no reconstruye sus salas.

## 8. Auditoría

`AuditTrail` escribe una línea JSON por cada solicitud (aceptada o rechazada) y por cada evento de juego en el archivo de `JsonlAuditSink`. Nunca guarda manos ni vistas (D-10). Sirve de evidencia para las pruebas con usuarios: con `ts_ms` se mide el tiempo por turno, y las solicitudes con `ok: false` muestran los errores de regla.

```json
{"kind":"request","ts_ms":1794617973695,"player_id":"a","room_id":"r-1","type":"declare_closing","action_id":"c1-0042","ok":false,"error":"INVALID_CLOSING","fields":{"expected_version":7,"card_id":31},"detail":{"validation":{"valid":false,"reason":"LEFTOVER_TOO_HIGH","leftover_points":5}}}
{"kind":"event","ts_ms":1794617973701,"room_id":"r-1","match_id":"m-1a2b3c4d","version":8,"event":"move_performed","data":{"sequence":12,"round_number":2,"player_id":"b","action":"DISCARD","card":{"id":7,"rank":9,"suit":2,"label":"9♣"},"automatic":true}}
```

Las jugadas también quedan en la tabla `turn_move` de SQLite (D-14), que solo acepta inserciones.

## 9. Lado del cliente

La interfaz no conoce el Lobby ni la red. Habla con el servidor solo a través de `ClientSession` (`presentation/session/`), que arma las solicitudes (`action_id` nuevo, `expected_version` de la última vista), guarda la última sala y la última vista, y descarta las vistas más viejas que la que ya tiene. Las fitness functions prohíben que `presentation` dependa de `infrastructure.network`.

`ClientSession` recibe un `IClientTransport`, el puerto del cliente:

- `send(request)` envía una solicitud.
- La señal `response_received(response)` entrega la respuesta.
- La señal `message_received(message)` entrega lo que el servidor empuja (`{ event, data, view }`).

Hay dos adaptadores:

| Adaptador | Dónde | Uso |
|---|---|---|
| `LocalTransport` + `LocalServer` | `infrastructure/network/local/` | El Lobby real en el mismo proceso: mesa local (hot seat) y desarrollo de la interfaz sin red. |
| Transporte de red | `infrastructure/network/` | `NetworkSession` y `NetworkChannel` implementan el servidor; `ClientNetworkEndpoint` y `ClientNetworkTransport` implementan el cliente. Este último conecta `ClientSession` con las RPC del endpoint. En navegador se usa `WebSocketMultiplayerPeer` (el export Web no tiene ENet). |

Los puntos de armado viven en `app/` y nadie depende de ellos. `app/local_playground.tscn` es la escena principal por ahora: elige la modalidad y la cantidad de jugadores, y abre una pestaña por jugador con su `TableView`. Guarda las partidas en `user://apuntado_local.db` y la auditoría en `user://auditoria_local.jsonl`.
