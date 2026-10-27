# ADR-05: Comandos síncronos por interfaz y notificaciones por eventos post-commit

- **ESTADO:** Accepted.
- **Fecha:** 2026-10-27
- **Autor(es):** Daniel Restrepo
- **Revisores:** Thomas, Angelika
- **Relacionado con:** [ADR-01](./0001-particionamiento-por-dominio.md), secciones 1.1, 1.3, 2.3 y 5.2
---

**CONTEXTO**

Los componentes del núcleo se comunican en dos tipos de situación con necesidades distintas:

- **Comandos:** robar, descartar y declarar cierre. El jugador que los envía espera una respuesta inmediata y propia: si un cierre se rechaza, solo él recibe la notificación y su mano, su turno y el marcador no cambian (RD16), en ≤ 200 ms (DA-03). Un cierre válido debe bloquear la ronda de inmediato (RD17) y liquidarse sin marcadores parciales (CU3-A5, sección 2.4).
- **Notificaciones de cambio de estado:** descarte, cambio de turno, cierre, eliminación y fin de partida. Cada uno de los 5 clientes recibe solo su vista (mano privada + estado público, RNF 3), y el historial registra cada movimiento (RNF 5). Quien produce el cambio no debería conocer a quienes lo consumen.

Hay además tres restricciones técnicas:

1. **DA-04:** monolito sin llamadas de red internas.
2. **Godot 4.5:** el servidor procesa las RPC entrantes en el hilo principal, en cada iteración del bucle. Las señales de Godot son síncronas por defecto: `emit()` ejecuta a los suscriptores dentro de la misma llamada, salvo que se conecten con `CONNECT_DEFERRED`.
3. **La red es asíncrona por naturaleza.** Si esa asincronía se filtra al coordinador de turnos (`await`, RPC o lógica dependiente del *peer*), el núcleo deja de ser determinista y de poder probarse en modo *headless* (DA-02).

Richards y Ford recomiendan usar comunicación síncrona por defecto y asíncrona solo cuando sea necesaria (cap. 19), y proponen el enfoque *mediator* para comunicar los módulos de un monolito modular (cap. 11). ADR-01 ya fijó a Match Orchestration como ese mediador.

---

**ALTERNATIVAS**

| Alternativa | Ventaja | Por qué se descarta |
|---|---|---|
| A. Todo síncrono: el orquestador llama directamente a notificación, historial y UI | Flujo lineal y fácil de seguir | Acopla el orquestador a cada consumidor: un consumidor nuevo exige modificarlo (viola OCP) y aumenta su acoplamiento eferente (Ce) |
| B. Todo por eventos (coreografía: un `DiscardEvent` dispara turnos, puntaje, etc.) | Máximo desacoplamiento | No hay un punto que devuelva el `ValidationResult` al solicitante; el orden de ejecución queda implícito, y aparecen las condiciones de carrera y la dificultad de depuración que el libro asocia con la comunicación asíncrona |
| C. Bus de eventos global (*autoload* `EventBus`, patrón común en Godot) | Muy fácil de usar | Cualquier módulo emite o escucha cualquier evento: el acoplamiento queda oculto y las fitness functions no pueden verificarlo |
| D. Validación en hilos (`WorkerThreadPool`) | No bloquea el bucle | Innecesario: la evaluación cabe en ≤ 150 ms (RNF 2). Introduce concurrencia sobre el estado compartido de la ronda y obliga a usar bloqueos |
| **E. Híbrido: comandos síncronos vía mediador + notificaciones por eventos post-commit** | Respuesta inmediata, orden determinista y consumidores desacoplados | **Seleccionada** |

---

**DECISIÓN**

**1. Los comandos y las consultas son llamadas síncronas en memoria a través de interfaces.** Match Orchestration (Mediator + Facade) recibe cada comando por el puerto `IMatchCommands` y lo resuelve en una sola pila de llamadas: `IRoundPlay`, `IGameRule`, `IRoundScoring`, `IMatchOutcome` y, al final, `IMatchRepository`. Ningún módulo del núcleo llama a otro sin pasar por el mediador, salvo las dependencias de dominio documentadas en 1.3 (por ejemplo, Turn Orchestration → `IGameRule`). El resultado, como `ValidationResult`, vuelve por la misma pila al solicitante.

**2. El orden de cada comando es fijo:**

```
validar sesión (Network Session) → Turn.can(acción) → ejecutar en el dominio
→ persistir (save_snapshot / save_settlement, una transacción) → emitir IGameEvents
```

Si `Turn.can()` rechaza la acción, no se persiste ni se emite nada (RD16). Si la persistencia falla, el orquestador recarga el último snapshot y tampoco emite: los clientes nunca ven un estado no guardado.

**3. Las notificaciones son eventos de dominio (Observer con señales) emitidos solo después del commit.** La interfaz `IGameEvents` define `turn_changed`, `move_performed`, `round_closed`, `player_eliminated` y `match_finished`. Solo Match Orchestration la emite. Game Notification se suscribe con `CONNECT_DEFERRED`: el envío por red se ejecuta al final de la iteración, fuera de la pila del comando, así que un fallo al notificar no puede abortar ni dejar a medias un comando ya confirmado. Los eventos internos del dominio que deben formar parte de la misma transacción, como `Round.move_performed` → `MatchHistory.record` (ajuste H2 del E1), se mantienen síncronos.

**4. Sincronización de turnos con servidor autoritativo y un solo hilo.** El servidor es la única fuente de verdad. Como las RPC se procesan en el hilo principal, los comandos de una partida se ejecutan uno tras otro, sin bloqueos en memoria. El turno lo decide `Turn` (patrón State); el cliente solo habilita botones según `turn_changed`, y el servidor revalida cada acción (RNF 6). La columna `version` de `match_session` (ADR-04, sección 2.4) es la segunda barrera contra escrituras concurrentes.

**5. La asincronía de la red queda encerrada en el adaptador.** Network Session es el único componente que usa `@rpc`, `multiplayer` o `MultiplayerPeer`: convierte cada RPC en una llamada síncrona a `IMatchCommands` y cada envío en una llamada a `IPlayerChannel`. El núcleo no usa `await`, hilos ni APIs de red, y no distingue si un jugador es local o remoto.

---

**CONSECUENCIAS**

*Positivas:*

- **Respuesta inmediata y dirigida:** el rechazo de un cierre vuelve por la pila de llamadas solo al solicitante.
- **Latencia dominada por la evaluación y la escritura en BD:** las llamadas entre módulos ocurren en memoria y su costo es despreciable frente al presupuesto de 200 ms.
- **Orden determinista y sin bloqueos en memoria:** el cierre simultáneo es imposible dentro de un proceso, lo que simplifica la sección 2.4.
- **Consumidores desacoplados:** agregar uno (por ejemplo, estadísticas o un espectador) significa suscribirse a `IGameEvents`, sin modificar el orquestador.
- **Núcleo 100 % probable en modo *headless*:** las pruebas llaman métodos y verifican señales con `watch_signals`, sin red ni árbol de escena (DA-02).

*Negativas y riesgos aceptados:*

- **Todas las salas comparten el hilo principal del servidor.** Una escritura lenta en la BD retrasa a las demás partidas. Mitigación: transacciones pequeñas (una por comando) y medición en CI. Si se supera el presupuesto, mover la persistencia a un hilo de trabajo con una cola por partida requerirá un ADR nuevo.
- **El orquestador sigue siendo el punto de mayor acoplamiento** (Ce = 6, E1). Se acepta como costo del enfoque *mediator*, según el cap. 11.
- **Las notificaciones diferidas llegan al final de la iteración del bucle,** decenas de milisegundos después del commit. Es aceptable dentro de los 200 ms.
- **Escalar a varias salas por encima de un proceso exigiría otra estrategia** (afinidad de sala por proceso). Queda fuera del alcance del monolito (ADR-01).

---

**CUMPLIMIENTO (COMPLIANCE)**

*Automatizado (GUT headless en CI; se implementa en la sección 5.2):*

1. **Núcleo sin red ni asincronía.** Ningún archivo en `res://orchestration/`, `match/`, `turn/`, `scoring/`, `rules/`, `deck/` o `notification/` contiene `@rpc`, `multiplayer`, `MultiplayerPeer`, `await`, `Thread` ni `WorkerThreadPool`.
2. **Un único emisor de `IGameEvents`.** Solo `res://orchestration/` emite eventos de `IGameEvents`, y `project.godot` no declara ningún *autoload* de bus de eventos global.
3. **Sin ciclos por eventos.** Los suscriptores de `IGameEvents` no referencian `IMatchCommands`: un evento no puede disparar un comando.
4. **Orden emitir-después-de-guardar.** Prueba con un repositorio simulado: si `save_snapshot()` falla, `assert_signal_not_emitted(orchestrator, "turn_changed")`; si tiene éxito, la señal se emite exactamente una vez y después de la escritura.
5. **Presupuesto de latencia.** Prueba de rendimiento de `declare_closing()` de punta a punta con un repositorio en memoria: p95 ≤ 200 ms.

*Manual:*

- En la revisión de código se rechaza cualquier `connect()` entre módulos del núcleo fuera del cableado del orquestador.

---

**NOTAS**

- **Autor:** Daniel Restrepo Faciolince
- **Fecha:** 2026-10-27
- **Aprobado por:** Angelika M y Thomas M
- **Relacionado con:** ADR-01 (Match Orchestration como mediador), ADR-03 (la llamada al plug-in de reglas es síncrona y en proceso), ADR-04 y sección 2.4 (transacción y `version`), sección 1.3 (puertos `pCommands` y `pPlayerChannel`, interfaz `IGameEvents`), DA-02, DA-03, DA-04, RD03, RD16, RD17, RNF 3, RNF 5, RNF 6 y CU2/CU3.
- **Referencias:** Richards y Ford (2025), caps. 11 (*Module Communication*: *mediator approach*), 19 (*use synchronous communication by default, asynchronous when necessary*) y 21 (*Architectural Decisions*).
- **Archivo en el repositorio:** `docs/adrs/0005-comandos-sincronos-y-eventos-post-commit.md`