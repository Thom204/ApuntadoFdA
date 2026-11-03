# ADR-04: Selección del motor y modelo de persistencia: relacional con SQLite en el servidor

- **ESTADO:** Accepted .
- **Fecha:** 2026-11-03
- **Autor(es):** Thomas Monnier Granda. 
- **Revisores:** Daniel, Angelika.
- **Relacionado con:** [ADR-01](./0001-particionamiento-por-dominio.md), [ADR-03](./0003-reglas-como-plugins-en-tiempo-de-ejecucion.md), ADR-05, secciones 2.1 a 2.4, 3.4 y 5.1 a 5.3
---

**CONTEXTO**

El sistema debe guardar de forma confiable el historial de partidas, las manos privadas de los jugadores y el acumulado multironda de penalizaciones hasta el umbral de eliminación de −101 puntos. Esa persistencia exige trazabilidad transaccional estricta: cada ronda se liquida calculando las penalizaciones de los jugadores que no cerraron, actualizando el marcador y verificando el umbral como una sola operación indivisible.

Las fuerzas que condicionan la decisión son:

1. **Servidor autoritativo único (D-03, D-04).** Un proceso dedicado de Godot, desplegado en una VPS, es la única autoridad sobre el estado de cada partida. Los clientes (navegadores) nunca acceden a la base de datos ni comparten estado mutable de partida.
2. **Hilo principal compartido (ADR-05).** Los comandos de todas las salas se ejecutan en serie en el hilo principal del servidor, de modo que una escritura lenta retrasa a las demás.
3. **Persistir antes de anunciar (D-15).** Cada acción aceptada termina en una escritura antes de emitir eventos, y debe responderse en ≤ 200 ms (DA-03).
4. **Recuperación tras un reinicio (D-15)**, sin replicación, alta disponibilidad ni respaldo redundante en el MVP.
5. **Alcance del MVP.** Salas de exactamente 5 jugadores y una sola instancia del servidor. Varias instancias (por balance de carga o redundancia) quedan fuera de esta entrega.
6. **Reglas variables (ADR-03).** Agregar una variante de juego no debe obligar a cambiar el esquema.

La sección 2.1 del documento compara cuatro topologías de almacenamiento. Este ADR registra la decisión final y precisa un matiz: **SQLite embebida en cada cliente** se descarta, pero **SQLite embebida solo en el servidor** se selecciona. Responde a tres preguntas: (1) qué modelo de datos usar (relacional o documental), (2) dónde vive la base de datos respecto de los clientes y (3) qué tipo de motor se usa y cómo se aloja.

---

**ALTERNATIVAS**

| Alternativa | Integridad transaccional | Costo operativo | Escalabilidad futura | Resultado |
|---|---|---|---|---|
| A. Base documental (NoSQL) | La atomicidad entre partida, rondas y puntajes depende de transacciones entre documentos, más limitadas o más complejas de operar en estos motores | Un servicio adicional | Alta | Descartada: el dominio es naturalmente relacional (partida → rondas → puntajes) y la liquidación necesita atomicidad simple |
| B. SQLite embebida en cada cliente | Ninguna entre clientes: cada navegador tendría su propia copia y los estados divergirían | Nulo | No aplica | Descartada: viola D-03 (única autoridad), D-10 (visibilidad restringida) y RNF 6 |
| C. SGBD relacional como servicio aparte (p. ej., PostgreSQL)¹ | Muy alta; admite varios escritores | Un servicio más que desplegar, asegurar y respaldar en la VPS | Alta: varias instancias y replicación | Descartada para el MVP: con un único proceso escritor y sin alta disponibilidad (D-15) no aporta; queda como ruta de escalada |
| **D. Relacional con SQLite embebida solo en el servidor (único escritor)** | **ACID local; una transacción por liquidación** | **Un archivo en la VPS, sin servicio adicional** | **Limitada: una sola instancia de servidor** | **Seleccionada** |


---

**DECISIÓN**

Adoptamos un **modelo relacional (SQL) normalizado en Tercera Forma Normal (3FN)**, implementado con **SQLite embebida en el proceso servidor**. La arquitectura sigue siendo la de una base de datos **centralizada**: "embebida" describe cómo se aloja el motor (como biblioteca dentro del proceso), no quién puede escribir. El único proceso con permiso para hacerlo es el servidor, el archivo de datos vive solo en la VPS y los procesos cliente, que existen en el navegador de los jugadores, solo hacen transacciones comunicándose con el servidor.

La decisión tiene cinco elementos, más unas directrices de implementación:

**1. Modelo relacional en 3FN.** El esquema consta de seis tablas y una vista (Figura 2.2 del Entregable 2):

| Objeto | Rol |
|---|---|
| `player` | Jugador registrado |
| `match_session` | Partida y su sala: modalidad, estado del ciclo de vida, umbral de eliminación y versión |
| `match_participant` | Participación de un jugador en una partida (tabla asociativa N:M) |
| `round` | Ronda de una partida: estado y participante que la cerró (anulable) |
| `player_hand_and_state` | Mano privada de un jugador en una ronda |
| `round_score` | Variación de puntaje de cada participante en una ronda liquidada (clave compuesta ronda + participante) |
| `v_cumulative_score` (vista) | Puntaje acumulado por participante: `SUM(score_delta)` |

Los principios del modelo son:

- **El acumulado es un dato derivado.** Se calcula con la vista y no se almacena: guardarlo duplicaría información de `round_score` y violaría la 3FN.
- **`mode` almacena el identificador del plug-in de reglas (ADR-03)**, no una enumeración cerrada. Por eso no lleva una restricción `CHECK` con valores fijos: la validación contra `RuleRegistry` ocurre en el servidor y agregar una variante no requiere cambiar el esquema.
- **`match_session.version`** cuenta las modificaciones aceptadas de la partida y sostiene el control de concurrencia optimista (D-07).
- **Las relaciones previstas son:** un jugador participa en muchas partidas; una partida reúne exactamente 5 participantes y tiene una o más rondas; cada ronda guarda una mano por jugador y hasta 5 filas de puntaje.

**2. Un único proceso escritor.** Todas las operaciones sobre la base de datos las realiza el servidor, que además es responsable de aplicar las validaciones y políticas para transacciones **duplicadas, inválidas u obsoletas**: identificador único de acción para reconocer reintentos, versión de la partida para rechazar estados obsoletos (`STALE_STATE`) y reglas del dominio para el resto (D-07, D-09). El archivo de datos no vive dentro de `res://` y su ruta se suministra por configuración externa (D-19).

**3. Acceso encapsulado tras un puerto (Repository + Data Mapper).** El núcleo solo conoce el puerto `IMatchRepository`, que expone tres operaciones:

| Operación | Propósito |
|---|---|
| `load(match_id)` | Reconstruir el agregado `Match` desde la base de datos (inicio y recuperación tras reinicio) |
| `save_snapshot(match)` | Persistir el estado actual de la partida (D-13) |
| `save_settlement(match, settlement)` | Persistir de forma atómica la liquidación de una ronda |

El adaptador `SqlMatchRepository` delega en un `SqlGateway` (acceso a SQL) y en un `MatchMapper` (traducción entre dominio y entidades). Solo `infrastructure/persistence` conoce SQL y el binding del motor. Esta encapsulación es la mitigación del límite de escalabilidad: cambiar de motor o pasar a varias instancias implica reemplazar el adaptador, no el núcleo.

**4. Reglas transaccionales.**

- **Persistir antes de anunciar (D-15, ADR-05):** el orden es validar → ejecutar en el dominio → persistir en una transacción → emitir eventos. Si la persistencia falla, no se emite nada y el estado en memoria no avanza respecto del persistido.
- **Liquidación atómica de una ronda (sección 2.4.2):** en una sola transacción se insertan las filas de `round_score`, se marca la ronda como liquidada, se consulta `v_cumulative_score` para identificar a los participantes que alcanzaron el umbral y se registran sus eliminaciones, y se incrementa `version`. Ante cualquier fallo se hace *rollback* completo: nunca existen marcadores parciales.
- **Dos barreras contra la concurrencia:** el servidor serializa las modificaciones de cada partida (ADR-05) y la escritura se condiciona a la versión leída. Ilustrativo:

```sql
PRAGMA foreign_keys = ON;  -- por conexión, antes de cualquier transacción

UPDATE match_session
   SET version = version + 1, status = :status
 WHERE session_id = :session_id AND version = :expected_version;
-- 0 filas afectadas => STALE_STATE: el servidor rechaza la acción
```

**5. Alcance de lo persistido (D-13, D-14, D-16).** La base conserva el estado necesario para recuperar una partida en curso y, de forma complementaria, un historial de acciones y eventos para depuración y análisis. No se implementa *event sourcing* ni se reconstruye una partida reproduciendo eventos. El ciclo de vida de salas y partidas (sala esperando jugadores, partida en curso, partida finalizada, sala cerrada) se registra en `status`. Tras un reinicio, el servidor restaura las partidas en curso con `load()`. No hay replicación, alta disponibilidad ni respaldo redundante.

**Directrices de implementación sobre SQLite (propuestas; a validar con pruebas).**

- **Claves foráneas:** SQLite las trae desactivadas por defecto y hay que activarlas en cada conexión (`PRAGMA foreign_keys = ON`). Activarlas dentro de una transacción no tiene efecto, así que se hace justo al abrir la conexión. Sin este paso, la restricción de claves foráneas que verifica el cumplimiento de este ADR no se aplica.
- **Tipos:** SQLite tipa de forma dinámica (por afinidad). Los tipos lógicos del modelo se protegen con restricciones `NOT NULL` y `CHECK` (excepto en `mode`, ver elemento 1) y se evaluarán tablas `STRICT`.
- **Conexión y transacciones:** una sola conexión de escritura abierta por el servidor y transacciones cortas, porque todas las salas comparten el hilo principal (ADR-05).
- **Durabilidad frente a latencia:** el modo de *journal* (p. ej., WAL) y el nivel de sincronización se fijan midiendo en la VPS real. "Persistir antes de anunciar" convierte cada acción en una escritura que cuenta contra los 200 ms de DA-03.
- **Migraciones:** scripts SQL versionados en el repositorio, aplicados al arrancar y con la versión del esquema registrada en la base (p. ej., `PRAGMA user_version`). Si la versión no coincide con la esperada, el servidor no acepta salas (*fail fast*).

**Lo que este ADR no decide:** el binding de SQLite para Godot (cuestión abierta 1), los valores de *journal* y sincronización, los tipos físicos de las columnas, la estrategia de respaldo y el proveedor o tamaño de la VPS.

---

**CONSECUENCIAS**

*Positivas:*

- **Integridad ACID en la liquidación:** el cálculo simultáneo de puntajes de los 5 jugadores es atómico, sin divergencias aritméticas en el marcador.
- **Una única fuente de verdad:** con un solo proceso escritor y serialización por partida no hay condiciones de carrera a nivel de partida, y el estado no necesita validarse constantemente contra la base.
- **Operación simple:** un archivo en la VPS y ningún servicio de base de datos que desplegar, asegurar ni respaldar (D-19).
- **Recuperación tras reinicio:** el estado persistido permite restaurar las partidas en curso (D-15).
- **Núcleo probable sin base de datos:** el puerto `IMatchRepository` permite probar el núcleo con un doble de pruebas y probar el adaptador por separado.
- **Sin inconsistencias de acumulado:** al derivarse con una vista, el total nunca puede desincronizarse de las filas de `round_score`.

*Negativas y riesgos aceptados:*

- **Escalabilidad limitada:** una sola instancia del servidor. Balance de carga o redundancia exigirán cambiar el adaptador (y probablemente el motor), y quedan fuera del alcance de esta entrega.
- **Las escrituras comparten el hilo principal:** una escritura lenta retrasa a todas las salas (ADR-05). Mitigación: transacciones pequeñas y medición en integración continua. Si no basta, una cola de persistencia por partida requerirá un ADR nuevo.
- **Latencia por acción:** persistir antes de anunciar añade el costo de escritura en disco a cada acción; debe medirse contra DA-03.
- **Sin alta disponibilidad ni respaldo:** la pérdida o corrupción del archivo implica perder las partidas guardadas (D-15). Un respaldo manual correcto debe usar los mecanismos de copia del propio motor, no copiar el archivo mientras se escribe.
- **Esquema y migraciones estrictos:** el DDL es rígido y cada cambio exige una migración versionada.
- **Integridad dependiente de la configuración:** si se omite `PRAGMA foreign_keys = ON` o se relajan los tipos, la base acepta datos inválidos sin avisar.
- **Dependencia de un binding externo:** Godot no incluye SQLite en su núcleo, así que el acceso depende de una extensión. Esto acopla la actualización del motor a la compatibilidad de esa extensión.
- **"Único escritor" es una política, no una garantía del motor:** se sostiene con el diseño (solo el servidor accede) y con los permisos del sistema operativo sobre el archivo.

---

**CUMPLIMIENTO (COMPLIANCE)**

*Automatizado (GUT en modo headless, ejecutado en CI; ver secciones 5.1 a 5.3):*

1. **FF-01: aislamiento de capas.** Ni el núcleo ni la presentación dependen de `res://infrastructure/persistence/`. Solo ese módulo usa SQL.
2. **Uso exclusivo del binding.** Una vez elegido el binding, su clase se añade a `FORBIDDEN_IN_CORE_IDENTIFIERS` de `arch_config.gd`, de modo que FF-04 falle si aparece fuera de `infrastructure/persistence/`.
3. **Pruebas de esquema** (integración, con un archivo SQLite temporal o en memoria): crear el esquema desde las migraciones y verificar que las claves foráneas rechazan filas huérfanas, que se respeta la unicidad de (`session_id`, `player_id`) y la clave compuesta de `round_score`, y que `v_cumulative_score` suma los `score_delta`.
4. **Atomicidad.** Con un fallo simulado a mitad de `save_settlement`, no quedan filas parciales y `version` no avanza.
5. **Concurrencia optimista.** Dos escrituras con la misma versión: la segunda se rechaza con `STALE_STATE`.
6. **Persistir antes de anunciar.** Con un doble de `IMatchRepository` cuyo `save_snapshot()` falla, no se emite ningún evento (ADR-05).
7. **Recuperación.** Guardar un estado, reconstruirlo con `load()` y comparar: el estado recuperado es equivalente (D-15).
8. **Migraciones.** El servidor no arranca si la versión del esquema no coincide con la esperada.
9. **Latencia.** `save_snapshot()` y `save_settlement()` se miden en CI con transacciones de tamaño realista, y la medición se repite en la VPS para fijar los parámetros de durabilidad.

Las pruebas 3 a 8 se ubican en `tests/integration/persistence/` (carpeta nueva: añadirla a `dirs` de `.gutconfig.json` y a un paso del flujo de CI).

*Manual:*

- Revisión de los scripts DDL en cada *pull request*: claves foráneas, unicidad por sala y ausencia de columnas derivadas almacenadas (3FN).
- El código del módulo que gestiona las transacciones se audita a fondo en la fase de testeo.
- Verificar que el archivo de datos en la VPS solo es accesible por el usuario del servicio.

---

**CUESTIONES ABIERTAS**

1. **Binding de SQLite para Godot.** Hay que elegir la extensión que implemente `SqlGateway`. Candidato a evaluar: *godot-sqlite* (GDExtension de la comunidad, licencia MIT), cuya última versión conocida al redactar este ADR se publica para Godot 4.5 con SQLite 3.51.0 y soporta Linux, Windows y HTML5. Criterios: soporte de Linux x86_64 para el servidor dedicado, compatibilidad con la versión fijada de Godot y mantenimiento. Según su documentación, Godot abre el archivo en modo no compartido: la base no puede abrirse con otra herramienta mientras el servidor esté en ejecución.
2. **Parámetros de durabilidad** (modo de *journal* y sincronización), según la medición en la VPS.
3. **Persistencia completa de `RuleSettings`.** ADR-03 indica que `match_session` persiste `elimination_threshold`, `max_leftover_points`, `jokers_enabled` y `card_values`, pero el esquema actual solo refleja el umbral de eliminación.
4. **Elementos de D-12, D-13, D-14 y D-08 sin ubicación en el modelo:** mazo y pila de descarte, turno actual, contador de turnos automáticos consecutivos, rol de espectador e historial de acciones.
5. **Estrategia de respaldo,** fuera del alcance del MVP (D-15), y proveedor y tamaño de la VPS.

---

**NOTAS**

- **Autor:** Thomas Monnier
- **Fecha:** 2026-11-03
- **Aprobado por:** Daniel F, Angelika M.
- **Reemplaza a:** ninguno.
- **Relacionado con:** ADR-01 (particionamiento por dominio), ADR-03 (la columna `mode` almacena el identificador del plug-in y `match_session` persiste los parámetros de la regla), ADR-05 (hilo principal compartido y orden persistir → emitir), secciones 2.1 a 2.4, 3.4 (D-03, D-04, D-07, D-09, D-13 a D-17, D-19) y 5.1 a 5.3 (FF-01 y FF-04), DA-03, RNF 5 y RNF 6.
- **Referencias:** documentación de SQLite sobre claves foráneas (`sqlite.org/foreignkeys.html`), tipos de datos (`sqlite.org/datatype3.html`) y tablas `STRICT` (`sqlite.org/stricttables.html`); repositorio de *godot-sqlite* (`github.com/2shady4u/godot-sqlite`).
- **Archivo en el repositorio:** `docs/adrs/0004-persistencia-relacional-sqlite-en-el-servidor.md`
