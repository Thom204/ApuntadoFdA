@abstract class_name IMatchRepository extends RefCounted
## Puerto de salida de persistencia (ADR-04). El núcleo solo conoce este contrato;
## los adaptadores viven en res://infrastructure/persistence/.
##
## Lo que cruza el seam es el snapshot de Match.to_snapshot(): datos planos y
## JSON-compatibles, nunca el objeto vivo. El adaptador no necesita conocer Match.
## Cada método devuelve false si la escritura falla: el orquestador entonces
## restaura el estado previo y no emite eventos (persistir antes de anunciar, ADR-05).

@abstract func save_snapshot(snapshot: Dictionary) -> bool
## Debe ser atómica: liquidación, eliminaciones y estado de la partida, o nada.
## `settlement` es la liquidación nueva (ya incluida en el snapshot).
@abstract func save_settlement(snapshot: Dictionary, settlement: RoundSettlement) -> bool
## Snapshot guardado; vacío si no existe.
@abstract func load(match_id: StringName) -> Dictionary
