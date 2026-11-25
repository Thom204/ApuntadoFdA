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

**Varios jugadores en el mismo equipo:** cada cliente guarda un token de sesión, y dos
clientes con el mismo token son el mismo jugador.

- Navegador: cada pestaña es un jugador distinto; recargar la pestaña conserva al jugador.
- Escritorio: abre cada ventana con su perfil, `-- --perfil=2`, `-- --perfil=3`… (el
  mismo perfil vuelve a ser el mismo jugador). Desde el editor:
  `godot --path game res://app/online_client.tscn -- --perfil=2`.
- Sin servidor: el modo local (`res://app/local_playground.tscn`) pone a todos en un
  equipo, una pestaña por jugador.

## Exportar

Presets en `game/export_presets.cfg` (Proyecto → Exportar, o
`godot --headless --path game --export-release "<preset>" <salida>`). Hacen falta las
plantillas de exportación de Godot 4.5.1 (Editor → Administrar plantillas de exportación).
Todo sale a `exports/`, que no se versiona.

| Preset | Salida | Uso |
|---|---|---|
| `Windows` | `exports/windows/ApuntadoFdA.exe` | Cliente, servidor y modo local. Copia al lado los `.bat` de `tools/windows/`: `servidor.bat`, `jugador-extra.bat` (pide un número y abre otro jugador), `modo-local.bat` |
| `Linux` | `exports/_server/server.x86_64` | Servidor dedicado: `./server.sh` (no necesita `--headless`) |
| `Web` | `exports/_client/index.html` | Cliente para navegador. Sin SQLite ni servidor: se conecta a un servidor aparte |

El build Web se sirve por HTTP, por ejemplo `python -m http.server 8060` dentro de
`exports/_client`, y se abre en `http://<IP>:8060`. Si la página se sirve por HTTPS, el
navegador exige `wss://` para el servidor.

Los filtros `*.sql, *.cfg` de los presets no se pueden quitar: las migraciones y el
`plugin.cfg` de cada modalidad no son recursos de Godot, y sin ellos el servidor no
encuentra los modos de juego.
