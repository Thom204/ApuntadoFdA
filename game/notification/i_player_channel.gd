@abstract class_name IPlayerChannel
extends RefCounted
## Puerto de salida hacia un jugador (ADR-05, decisión 5). El adaptador de red
## (Network Session) lo implementa con RPC; las pruebas, con un canal que graba.
## El núcleo no distingue si el jugador es local o remoto.


## Entrega `message` (solo tipos JSON) a `player_id`. No devuelve nada: un fallo al
## notificar no puede deshacer un comando ya guardado.
@abstract func send(player_id: StringName, message: Dictionary) -> void
