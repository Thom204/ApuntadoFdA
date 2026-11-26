# ApuntadoFdA

Juego de cartas digital con dos modalidades: **Clásica 4-3-3** y **Apuntado (101)**.
Proyecto del curso Fundamentos de Arquitectura de Software (UNAL).

Godot 4.5.1 · GDScript · monolito modular con puertos y adaptadores · servidor autoritativo
por WebSocket · SQLite en el servidor.

## Jugar ya (versión desplegada)

El servidor y el cliente Web están desplegados en un VPS de Linode, con HTTPS y dominio propio:

**<https://apuntadito.thom2msdev.click/>**

1. Abre el enlace. El campo de servidor ya trae `wss://apuntadito.thom2msdev.click/ws/`;
   pulsa **Conectar** y espera a que diga "Conectado".
2. Un jugador escribe su nombre, elige la modalidad y pulsa **Crear sala**. Aparece un
   código de 6 caracteres.
3. Los demás escriben ese código y pulsan **Buscar / unirse**.
4. El creador pulsa **Iniciar partida** (mínimo 2 jugadores, máximo 5).

Cada pestaña del navegador es un jugador distinto, así que se puede probar solo con dos o
tres pestañas. Recargar una pestaña conserva al jugador y lo devuelve a su sala.

## Requisitos (para desarrollo)

| Herramienta | Versión | Para qué |
|---|---|---|
| [Godot](https://godotengine.org/download/archive/4.5.1-stable/) | **4.5.1 exacto** (estándar, no .NET) | Editor, servidor y pruebas. GUT 9.5.0 (en `game/addons/gut`) solo funciona con 4.5.x |
| Plantillas de exportación de Godot 4.5.1 | las mismas | Solo para exportar (Editor → Administrar plantillas de exportación) |
| Git | cualquiera | Clonar el repositorio |
| Bash (Git Bash en Windows) | cualquiera | `tools/run_tests.sh` |
| Python 3 | opcional | Servir el export Web en local |

En Windows conviene usar el ejecutable `Godot_v4.5.1-stable_win64_console.exe` para ver
los mensajes en la terminal. En los comandos de abajo, `godot` es ese ejecutable.

## Instalación

```bash
git clone https://github.com/Thom204/ApuntadoFdA.git
cd ApuntadoFdA
godot --headless --path game --import   # genera .godot/ (no se versiona); tarda la primera vez
```

El proyecto de Godot vive en `game/` (es `res://`), no en la raíz. Para abrirlo en el
editor, importa `game/project.godot`.

## Ejecutar en local

### 1. Levantar el servidor

Desde la raíz del repositorio:

```bash
godot --headless --path game res://app/server.tscn
```

Cuando aparece `Apuntado server listening on *:7777` ya está listo. Deja esa terminal
abierta y ciérralo con Ctrl+C. Desde el editor: abre `app/server.tscn` y pulsa F6.

Variables de entorno opcionales (detalle en [`docs/protocolo-red.md`](docs/protocolo-red.md)):

| Variable | Por defecto | Uso |
|---|---|---|
| `APUNTADO_PORT` | `7777` | Puerto del WebSocket |
| `APUNTADO_BIND_ADDRESS` | `*` | Dirección de escucha |
| `APUNTADO_DB` | `user://apuntado_server.db` | Archivo SQLite |
| `APUNTADO_AUDIT_LOG` | `user://apuntado_server.jsonl` | Bitácora de auditoría (JSONL) |

### 2. Abrir el cliente y conectarse

Abre el cliente (F5 en el editor, el export de Windows o el export Web) y **cambia la URL
del servidor**, porque por defecto apunta al servidor desplegado:

- En el mismo equipo del servidor: `ws://127.0.0.1:7777`.
- Desde otro equipo de la misma red: `ws://<IP del anfitrión>:7777` (la IP sale con
  `ipconfig` o `ip a`). En Windows el anfitrión debe permitir el puerto 7777 en el firewall
  o tener la red marcada como privada.

Luego se crea la sala igual que en la versión desplegada (ver arriba).

Si nadie escucha en esa dirección, el cliente muestra **"Falló la conexión (código 25)"**
(`ERR_CANT_CONNECT`). Se corrige la URL y se vuelve a pulsar Conectar.

### Varios jugadores en el mismo equipo

Cada cliente guarda un token de sesión, y dos clientes con el mismo token son el mismo
jugador.

- **Navegador:** cada pestaña es un jugador distinto.
- **Escritorio:** abre cada ventana con su perfil, `-- --perfil=2`, `-- --perfil=3`… (el
  mismo perfil vuelve a ser el mismo jugador). Desde el editor:
  `godot --path game res://app/online_client.tscn -- --perfil=2`.
- **Sin servidor:** el modo local (`res://app/local_playground.tscn`) pone a todos en un
  mismo proceso, con SQLite en `user://apuntado_local.db`.

## Reglas en resumen

Baraja de 52 cartas sin comodines (dos barajas con 5 jugadores). Se reparten 10 cartas;
quien abre la ronda recibe 11 y empieza descartando. En cada turno se roba del mazo o del
descarte y se descarta una carta. Combinaciones válidas: **ternas o cuartas** del mismo
valor, o **escaleras** de la misma pinta (3 a 5 cartas). Valores: A, J, Q y K = 10; del 2
al 10, su número.

**Clásica 4-3-3.** Se cierra con 1 cuarta + 2 ternas y el descarte final, sin cartas
sobrantes. La partida termina con el primer cierre válido y gana quien cerró.

**Apuntado (101).** El puntaje se acumula entre rondas:

- *Tocar:* 3 ternas + 1 carta suelta que valga **menos de 5** puntos.
- *Ganar completo:* 1 cuarta + 2 ternas, sin sobrante.
- *Irse a pintas:* las 10 cartas de una misma pinta; suma +25.
- Quien cierra suma +10; cada perdedor resta el valor de sus cartas sueltas.
- Queda eliminado quien llega a **−101**. Gana quien llega a **+51** o el último activo.

Turnos: 45 s por defecto. Si se agota, el servidor juega un turno automático (roba del
mazo y descarta); tras 3 turnos automáticos seguidos el jugador queda eliminado.

**Atajos de teclado en la mesa:** `M` robar del mazo · `P` robar del descarte · `D`
descartar · `V` verificar combinación · `C` cerrar · `O` ordenar la mano · `N` siguiente
ronda · `Esc` deseleccionar.

## Arquitectura

```
Navegador / escritorio (cliente Godot)      Servidor Godot headless
  presentation/  TableView, ClientSession     infrastructure/network/  NetworkSession
  infrastructure/network/  ClientEndpoint ──WSS──▶ orchestration/  Lobby → MatchOrchestrator
                                                  match/ turn/ rules/ scoring/ deck/
                                                  notification/  vistas por jugador, auditoría
                                                  infrastructure/persistence/  SQLite
```

El servidor decide todo; el cliente solo envía comandos y dibuja la vista que recibe. En
producción, nginx termina TLS y reenvía `/ws/` al WebSocket del servidor.

| Carpeta (`game/`) | Responsabilidad |
|---|---|
| `deck/` | Cartas, barajas y reparto |
| `rules/` | Contrato `GameRule` y evaluador de manos. Las modalidades son plug-ins en `rules/modes/{classic,apuntado}`, cargados por su `plugin.cfg` |
| `turn/` | Ronda y fases del turno (patrón State) |
| `scoring/` | Liquidación, eliminación y fin de partida |
| `match/` | Agregado `Match`, único punto de entrada de los comandos de juego |
| `orchestration/` | `Lobby` (salas, entrada única de la red) y `MatchOrchestrator` (persiste y luego notifica) |
| `notification/` | Vista privada de cada jugador, eventos y auditoría |
| `infrastructure/` | Adaptadores: WebSocket, SQLite, bitácora JSONL |
| `presentation/` | Mesa, cartas, tema y sesión del cliente |
| `app/` | Raíces de composición: `server.tscn`, `online_client.tscn` (escena principal), `local_playground.tscn` |
| `shared/` | Catálogo de errores y utilidades comunes |

Documentación:

- Decisiones: [`docs/adrs/`](docs/adrs/) (ADR-01 a ADR-05).
- Protocolo cliente-servidor: [`docs/protocolo-red.md`](docs/protocolo-red.md).
- Diagramas del Entregable 3 (despliegue, secuencia de cierre, clases):
  [`docs/deliverables/Entregable 3/Diagramas/`](docs/deliverables/Entregable%203/Diagramas/).
- Componentes, dominio y modelo ER: [`docs/diagrams/`](docs/diagrams/).
- Gobernanza y métricas: [`docs/deliverables/Entregable 3/seccion-4-gobernanza.md`](docs/deliverables/Entregable%203/seccion-4-gobernanza.md).

## Pruebas y fitness functions

Las pruebas usan GUT y están en `game/tests/`:

| Carpeta | Qué prueba |
|---|---|
| `unit/` | Cada módulo del dominio, la sesión del cliente y la red |
| `contract/` | Que cada modalidad cumpla el contrato `GameRule` |
| `integration/` | Persistencia con SQLite real |
| `architecture/` | Fitness functions: capas, dependencias, complejidad, eventos y métricas |

```bash
GODOT=/ruta/a/godot tools/run_tests.sh                    # toda la suite
GODOT=/ruta/a/godot tools/run_tests.sh res://tests/unit/  # una carpeta
```

El CI ([`.github/workflows/tests.yml`](.github/workflows/tests.yml)) corre las cuatro
carpetas en cada push a `main` y en cada pull request, con Godot 4.5.1. Publica los
reportes JUnit y `tests/results/metricas.md` (acoplamiento, inestabilidad, abstracción)
como artefacto `resultados-gut`.

## Exportar

Presets en `game/export_presets.cfg` (Proyecto → Exportar, o
`godot --headless --path game --export-release "<preset>" <salida>`). Todo sale a
`exports/`, que no se versiona.

| Preset | Salida | Uso |
|---|---|---|
| `Windows` | `exports/windows/ApuntadoFdA.exe` | Cliente, servidor y modo local. Copia al lado los `.bat` de `tools/windows/`: `servidor.bat`, `jugador-extra.bat` (pide un número y abre otro jugador), `modo-local.bat` |
| `Linux` | `exports/_server/server.x86_64` | Servidor dedicado: `./server.sh` (no necesita `--headless`) |
| `Web` | `exports/_client/index.html` | Cliente para navegador. Sin SQLite ni servidor: se conecta a un servidor aparte |

El build Web se sirve por HTTP, por ejemplo `python -m http.server 8060` dentro de
`exports/_client`, y se abre en `http://<IP>:8060`.

Los filtros `*.sql, *.cfg` de los presets no se pueden quitar: las migraciones y el
`plugin.cfg` de cada modalidad no son recursos de Godot, y sin ellos el servidor no
encuentra los modos de juego.

## Problemas frecuentes

| Síntoma | Causa y solución |
|---|---|
| "Falló la conexión (código 25)" | No hay servidor en esa URL. Revisa que el servidor esté corriendo y que la URL tenga el puerto (`:7777`) |
| "No se pudo iniciar la conexión (código 31)" | La URL no empieza por `ws://` o `wss://` |
| Desde otro PC no conecta | Firewall de Windows bloqueando el puerto 7777, o red marcada como pública |
| La página HTTPS no conecta a `ws://…` | Un navegador en HTTPS exige `wss://`. Usa el servidor desplegado, o sirve el export Web por `http://` |
| Errores de `class_name` o GUT no arranca | Falta importar (`godot --headless --path game --import`) o la versión de Godot no es 4.5.1 |
| El servidor no encuentra las modalidades | El export perdió los filtros `*.sql, *.cfg` |
| Dos ventanas de escritorio son el mismo jugador | Abre cada una con un `--perfil` distinto |

## Equipo

Angelika Moya Bolaños · Daniel Restrepo Faciolince · Thomas Monnier Granda
