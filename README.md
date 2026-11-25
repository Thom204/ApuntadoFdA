# ApuntadoFdA
Digital card game (Classic 4-3-3 & Apuntado to 101).
Godot 4.5+ / GDScript · Modular monolith + ports & adapters.

- `game/` Godot project (res://)
- `tests/` GUT tests (unit, contract, architecture)
- `docs/` ADRs, UML/BPMN diagrams, deliverables

The main scene is the network demo client (`res://app/online_client.tscn`). It accepts a
WebSocket server URL, connects with the saved session token, and lets players create or
join a room using its invitation code. The local hot-seat playground remains available
at `res://app/local_playground.tscn`.
