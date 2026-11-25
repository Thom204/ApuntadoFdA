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

## Cómo jugar en red

**1. Levantar el servidor** (en el equipo que hace de anfitrión, desde la raíz del repo):

```bash
godot --headless --path game res://app/server.tscn
```

`godot` es el ejecutable de Godot 4.5.1 (en Windows, el `_console.exe` para ver los
mensajes). Cuando aparece `Apuntado server listening on *:7777` ya está listo; deja esa
terminal abierta y ciérralo con Ctrl+C. Desde el editor: abre `app/server.tscn` y pulsa F6.
Opcional: `APUNTADO_PORT`, `APUNTADO_DB` y `APUNTADO_AUDIT_LOG` (ver `docs/protocolo-red.md`).

**2. Abrir el cliente** (F5 en el editor, o el export Web) y conectarse:

- En el mismo equipo del servidor: `ws://127.0.0.1:7777`.
- Desde otro equipo de la misma red: `ws://<IP del anfitrión>:7777` (la IP sale con
  `ipconfig`). En Windows el anfitrión debe permitir el puerto 7777 en el firewall o tener
  la red marcada como privada.

**3. Sala:** un jugador elige la modalidad y pulsa **Crear sala**; los demás escriben el
código de 6 caracteres y pulsan **Buscar / unirse**. El creador pulsa **Iniciar partida**.

> Cada cliente guarda su sesión en `user://`. Dos ventanas en el mismo equipo comparten
> esa carpeta y entran como el mismo jugador; para probar con varias, usa equipos
> distintos o el modo local (`res://app/local_playground.tscn`, un equipo con pestañas).
