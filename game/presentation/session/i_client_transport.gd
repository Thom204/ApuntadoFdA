@abstract class_name IClientTransport
extends RefCounted
## Puerto del cliente hacia el servidor. La interfaz solo conoce este puerto (a través
## de ClientSession), nunca el Lobby ni la red. Hay dos adaptadores:
##   - LocalTransport: el servidor corre en el mismo proceso (hot seat, desarrollo).
##   - el de red (RPC sobre WebSocketMultiplayerPeer), que entrega la red.
##
## Todo lo que viaja es nativo de JSON (docs/protocolo-red.md).

## Respuesta a una solicitud: { ok, request, action_id, error, message, data }.
signal response_received(response: Dictionary)
## Mensaje que el servidor empuja sin que se pida: { event, data, view }.
signal message_received(message: Dictionary)


## Envía una solicitud { type, action_id?, ...campos }. La respuesta llega por
## response_received (de inmediato en local, más tarde por red).
@abstract func send(request: Dictionary) -> void
