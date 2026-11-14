@abstract class_name IAuditSink extends RefCounted
## Puerto de salida de la auditoría (D-20): dónde quedan las entradas que arma
## AuditTrail. El adaptador de producción escribe un archivo JSONL
## (infrastructure/persistence/JsonlAuditSink). `entry` es un diccionario JSON-nativo.
## Un fallo al escribir no deshace nada: la jugada ya está guardada (ADR-05).

@abstract func write(entry: Dictionary) -> void
