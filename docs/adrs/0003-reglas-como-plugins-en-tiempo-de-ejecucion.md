# ADR-03: Monolito modular con módulo de reglas extensible por plug-ins en tiempo de ejecución

- **ESTADO:** Accepted. Reemplaza a ADR-02 (ADR-02 pasa a *Superseded by ADR-03*).
- **Fecha:** 2026-10-24
- **Autor(es):** Daniel Restrepo
- **Revisores:** Thomas, Angelika
- **Relacionado con:** [ADR-01](./0001-particionamiento-por-dominio.md), secciones 1.1, 1.3, 2.3 y 5.2
---

**CONTEXTO**

El sistema debe soportar las modalidades Clásica (1 cuarta + 2 ternas + 1 descarte) y Apuntado (3 ternas + sobrante < 5 puntos, eliminación al llegar a −101 puntos o menos, RF09), y el cliente ya anticipó variantes nuevas como Continental. El driver principal es la extensibilidad (DA-01): agregar una variante debe crear o modificar como máximo 2 archivos y no puede alterar el orquestador. Le siguen la testabilidad (DA-02) y la responsividad (DA-03, ≤ 200 ms por cierre o descarte). La restricción DA-04 exige un monolito sin llamadas de red internas.

ADR-01 fijó el particionamiento por dominio en un monolito modular, y ADR-02 encapsuló las reglas con el patrón Strategy. Ese diseño cumple la extensibilidad en el código, pero no en la operación, y tiene tres límites que este ADR resuelve:

1. **Exige recompilar.** Las estrategias se registran en tiempo de compilación: una modalidad nueva modifica el enum `GameMode` y `RuleRegistry`, y obliga a re-exportar y redesplegar el servidor. Richards y Ford llaman a este caso *compile-based plug-ins*: son más simples de gestionar, pero agregar uno exige redesplegar toda la aplicación monolítica (cap. 13).
2. **El contrato solo sirve para las dos modalidades actuales.** `GameRule` no conoce el número de ronda, así que no puede expresar una variante cuyo patrón de cierre cambie en cada ronda, como Continental. Tampoco recibe el marcador, así que `is_match_over()` no puede evaluar la victoria por 51 puntos (RD08).
3. **El catálogo es cerrado.** `GameMode` es un enum, de modo que el núcleo debe conocer de antemano todas las modalidades.

La guía pide justificar el estilo y explicar cómo se agrega una variante "sin recompilar ni alterar el orquestador principal".

---

**ALTERNATIVAS**

| Alternativa | Extensibilidad (DA-01) | Testabilidad (DA-02) | Responsividad (DA-03) | Simplicidad | Resultado |
|---|---|---|---|---|---|
| A. Condicionales por modalidad en el núcleo | Cada variante modifica el orquestador (viola OCP) | Baja: casos acoplados | Alta | Alta al inicio | Descartada desde el E1 |
| B. Monolito modular + Strategy en compilación (ADR-02) | Media: ≤ 2 archivos existentes, pero exige re-exportar | Alta | Alta | Alta | Insuficiente: no cumple "sin recompilar" |
| C. Microkernel puro (turnos, mazo y puntaje también como plug-ins) | Muy alta | Alta | Alta | Baja: el núcleo queda casi vacío y todo pasa por contratos | Descartada: turnos, mazo y liquidación son estables y compartidos por toda la familia de juegos; volverlos plug-ins agrega costo sin beneficio |
| D. Reglas como servicio remoto (REST) | Muy alta | Media | Baja: latencia de red en cada validación | Baja | Descartada: rompe DA-04 y pone en riesgo los 200 ms. Richards y Ford advierten que el acceso remoto convierte el microkernel en una arquitectura distribuida |
| E. Reglas declarativas (JSON o DSL interpretado) | Alta para variaciones de parámetros | Media: el intérprete es otro motor que probar | Alta | Media | Adoptada solo en parte: los parámetros ya son datos (`RuleSettings`), pero el comportamiento no cabe en un DSL simple sin elevar la complejidad ciclomática |
| **F. Monolito modular + módulo de reglas con microkernel interno (plug-ins en tiempo de ejecución)** | **Muy alta: 2 archivos nuevos, 0 existentes, sin recompilar** | **Alta: pruebas de contrato por plug-in** | **Alta: llamada en proceso** | **Media-alta** | **Seleccionada** |

---

**DECISIÓN**

Mantendremos el **monolito modular particionado por dominio** de ADR-01 y convertiremos el módulo `rules` en un **microkernel interno**. Los módulos `orchestration`, `match`, `turn`, `deck`, `scoring` y `notification` forman el *core system*; cada modalidad de juego es un ***plug-in* de reglas en tiempo de ejecución** que implementa el contrato `GameRule` (patrón Strategy) y que `RuleRegistry` descubre al arrancar el servidor.

Esto corresponde a la hibridación que describen Richards y Ford: el *core system* de un microkernel puede implementarse como un monolito modular (cap. 13, fig. 13-2). En su espectro de "microkern-ality", el sistema queda del lado de los que *soportan plug-ins* pero son funcionales por sí mismos: el núcleo concentra el flujo del juego y los plug-ins solo deciden *qué* gana y *cómo* se puntúa.

*Justificación:* según la tabla comparativa de la sección 1.1, el microkernel es superior en extensibilidad y el monolito modular en simplicidad. Esta decisión aplica cada estilo donde aporta: el mecanismo de plug-ins se limita al único punto que cambia con frecuencia (las reglas), y el resto conserva la simplicidad del monolito.

La decisión tiene cinco elementos:

**1. Contrato versionado para la familia de juegos de combinaciones (contrato v1).** `GameRule` deja de modelar solo dos modalidades y pasa a modelar la familia de juegos de cartas por combinaciones (rummy). Los métodos reciben contexto:

```gdscript
# res://rules/game_rule.gd  (núcleo; estable)
class_name GameRule extends Resource
const CONTRACT_VERSION := 1

func cards_to_deal(ctx: RoundContext) -> int                                   # abstract
func validate_closing(cards: Array[Card], discard: Card, ctx: RoundContext) -> ValidationResult  # Template Method
func penalty_for(cards: Array[Card]) -> int
func is_eliminated(total_score: int) -> bool                                   # abstract
func is_match_over(ctx: MatchContext) -> bool                                  # abstract
func select_winner(ctx: MatchContext) -> StringName                            # abstract
func _closing_pattern(ctx: RoundContext) -> Array[MeldSpec]                    # hook
func _accepts_leftover(leftover: Array[Card], points: int) -> bool             # hook
```

`RoundContext` (número de ronda, jugadores activos), `MatchContext` (jugadores activos, `Scoreboard`, rondas jugadas) y `MeldSpec` (tipo SET/RUN/ANY y tamaño mínimo) son *value objects* inmutables: la regla recibe datos y devuelve datos, nunca entidades (ajuste H4 del E1).

**2. Catálogo abierto.** El enum `GameMode` se reemplaza por un identificador `StringName` (por ejemplo `&"apuntado"`). El núcleo ya no enumera las modalidades: las obtiene de `RuleRegistry.available_modes()`.

**3. Empaquetado y descubrimiento.** Cada plug-in es un paquete de recursos de Godot (`.pck`) que contiene exactamente 2 archivos:

```ini
; res://rules/modes/continental/plugin.cfg
[plugin]
id="continental"
display_name="Continental"
version="1.0.0"
contract_version=1
script="res://rules/modes/continental/continental_rule.gd"

[defaults]
elimination_threshold=0
max_leftover_points=0
```

Se distinguen dos ubicaciones. `rule_plugins/` es una carpeta **en disco**, junto al ejecutable del servidor, donde el administrador copia los `.pck`; no forma parte de `res://`. Al montarse, los archivos de cada paquete aparecen en la ruta virtual `res://rules/modes/<id>/`, que es el punto de montaje del componente *Game Modes* (sección 1.3).

Al arrancar, `RuleRegistry` recorre la carpeta `rule_plugins/` del servidor y, por cada paquete:

1. Calcula el SHA-256 del archivo (`FileAccess.get_sha256(path)`) y lo rechaza si no está en la lista de hashes aprobados. La verificación ocurre **antes** de montar, porque un paquete ya montado no se puede desmontar de forma fiable mientras el proceso sigue vivo.
2. Lo monta con `ProjectSettings.load_resource_pack(path, false)`. El argumento `replace_files = false` impide que un plug-in sobrescriba archivos del núcleo.
3. Lee el `plugin.cfg` y rechaza el paquete si `contract_version` no coincide con `GameRule.CONTRACT_VERSION`, si el script no hereda de `GameRule` o si el `id` ya existe.
4. Registra `id → (script, defaults)` en su catálogo, que es un mapa interno como el *registry* simple que describen Richards y Ford.

Si al terminar el recorrido `available_modes()` no incluye `classic` y `apuntado`, el servidor no arranca (*fail fast*), en lugar de aceptar salas sin reglas.

*Regla de empaquetado:* el script de un plug-in **no declara `class_name`**. Hereda de `GameRule`, que sí es global porque pertenece al núcleo, y se carga por ruta desde `plugin.cfg`. El registro de clases globales (`class_name`) lo genera el editor para el proyecto principal, y con `replace_files = false` un paquete no lo actualiza. Así se evitan colisiones de nombres entre plug-ins. Este comportamiento se verifica con la prueba de integración de carga (Cumplimiento, punto 7).

Las reglas Clásica y Apuntado se migran al mismo formato, de modo que el núcleo no distingue reglas "de fábrica" de reglas agregadas. Su código fuente vive en `res://rules/modes/classic/` y `res://rules/modes/apuntado/`; el *preset* de exportación del núcleo excluye `rules/modes/*` y cada carpeta se exporta como su propio `.pck`.

**Tipo de plug-in según Richards y Ford.** Los plug-ins son *runtime-based*: se agregan sin recompilar ni redesplegar el núcleo. La carga ocurre al arrancar, y la recarga en caliente durante la ejecución queda fuera de alcance. Es un punto intermedio deliberado: evita la complejidad de un *framework* de módulos como OSGi y conserva la simplicidad del monolito.

**4. Comunicación punto a punto y en proceso.** El núcleo invoca al plug-in con una llamada de método a través de `IGameRule` (puerto `pGameRule`, sección 1.3), no por red. Así se conservan DA-03 y DA-04 (detalle en ADR-05).

**5. Plug-ins sin dependencias entre sí ni con la persistencia.** Un plug-in solo depende del contrato y de `HandEvaluation`. Nunca referencia otro plug-in, la red ni la base de datos: el núcleo le pasa los datos que necesita, como recomiendan Richards y Ford para la topología de datos del microkernel. También evita la gestión de dependencias transitivas (*plug-in dependencies*, cap. 13).

**6. Parámetros cerrados en v1.** Un plug-in solo puede configurarse con los campos de `RuleSettings` (`elimination_threshold`, `max_leftover_points`, `jokers_enabled`, `card_values`), que son los que persiste `match_session`. Un parámetro nuevo implica cambiar el contrato (v2) y el esquema, y por lo tanto un ADR nuevo. Así la promesa "sin cambio de esquema" de ADR-04 se mantiene verdadera para toda variante dentro de v1.

**Cómo se agrega una variante nueva, por ejemplo Continental:**

1. Se escribe `continental_rule.gd`, que hereda de `GameRule`: `_closing_pattern(ctx)` devuelve el patrón exigido según `ctx.round_number`; `cards_to_deal(ctx)` devuelve las cartas de esa ronda; `is_match_over(ctx)` termina tras la última ronda; y `select_winner(ctx)` elige al de menor puntaje.
2. Se escribe su `plugin.cfg` con los parámetros por defecto.
3. Se ejecuta la batería de pruebas de contrato (ver Cumplimiento).
4. Se empaqueta como `continental.pck` y se copia en `rule_plugins/` del servidor.
5. Se reinicia el proceso del servidor. "Continental" aparece en `available_modes()` y el anfitrión puede elegirlo al crear una sala.

No se recompila ni se re-exporta el núcleo, y no se modifica ningún archivo existente: Match Orchestration, Turn Orchestration, Match Outcome, la UI y el esquema de base de datos quedan intactos. El cliente web no necesita el plug-in, porque la validación ocurre en el servidor (RNF 6) y el cliente solo recibe el nombre de la modalidad y los resultados.

**Alcance del contrato: Póker no es un plug-in de este contrato.** Póker no tiene combinaciones de cierre, cambia la estructura del turno (apuestas en lugar de robar y descartar) y requiere otra interfaz de usuario. Incorporarlo exigiría una máquina de estados de turno distinta, es decir, cambiar el núcleo, lo que sería un contrato nuevo (v2) con su propio ADR. Se deja fuera de forma explícita: un contrato que pretendiera cubrir cualquier juego de cartas sería tan genérico que el núcleo perdería su valor y se volvería volátil, el primer riesgo común del microkernel según Richards y Ford (*volatile core*).

Por la misma razón, las **apuestas dinámicas** y el **reingreso de jugadores eliminados** que el cliente anticipó en el E1 tampoco caben en v1. Las apuestas agregan una fase al turno, y el reingreso cambia el ciclo de vida del participante, que pertenece a `match`. Ninguno de los dos se resuelve solo con un plug-in de reglas.

---

**CONSECUENCIAS**

*Positivas:*

- **DA-01 se cumple con margen:** una variante nueva = 2 archivos creados y 0 existentes modificados (antes eran 2 existentes), sin recompilar ni redesplegar el núcleo.
- **El orquestador y la persistencia no se enteran de las variantes:** solo conocen `IGameRule` y un identificador de modalidad.
- **Se resuelve la victoria por 51 puntos:** `MatchContext` incluye el marcador, así que la condición de RD08 queda expresable en `is_match_over()`.
- **Mejora la testabilidad:** cada plug-in se prueba de forma aislada y *headless* contra la misma batería de contrato (DA-02).
- **Las reglas Clásica y Apuntado dejan de ser casos especiales:** el núcleo no tiene código específico de ninguna modalidad.

*Negativas y riesgos aceptados:*

- **El contrato pasa a ser la decisión más costosa de cambiar.** Una versión v2 rompe todos los plug-ins existentes. Por eso es versionado y su alcance está limitado a la familia de juegos de combinaciones.
- **Los plug-ins son código de confianza.** GDScript no ofrece aislamiento (*sandbox*): un plug-in se ejecuta con los mismos permisos que el servidor. Mitigación: solo el administrador del servidor instala plug-ins, y la carga se restringe a una lista de hashes aprobados.
- **Agregar una modalidad exige reiniciar el servidor.** No requiere recompilar, pero las partidas en curso conservan la instancia de regla con la que empezaron, y la recarga en caliente queda fuera de alcance.
- **Riesgo de partidas huérfanas o con reglas cambiadas.** Si se retira o se actualiza un plug-in con partidas guardadas en esa modalidad, al recuperarlas tras un reinicio (D-15) no podrían reanudarse o seguirían con reglas distintas. `RuleRegistry` rechaza retirar o reemplazar un plug-in mientras existan partidas activas en esa modalidad.
- **La UI solo admite variantes que reutilicen sus interacciones** (robar, descartar, cerrar). Una variante que requiera interacciones nuevas también requiere cambios en la capa de presentación.
- **Cambio único en el núcleo ahora.** Hay que migrar `GameMode` a identificador, ampliar el contrato con los objetos de contexto y migrar las dos reglas actuales al formato de plug-in. Se acepta porque estabiliza el núcleo antes de abrirlo a extensiones.

---

**CUMPLIMIENTO (COMPLIANCE)**

*Automatizado (GUT en modo headless, ejecutado en CI; se implementa en la sección 5.2):*

1. **Pruebas de contrato.** Una batería común de manos válidas e inválidas se ejecuta contra cada plug-in registrado. Verifica que `validate_closing()` devuelva un `ValidationResult` coherente, que `penalty_for()` sea determinista, que `cards_to_deal()` respete el tamaño del mazo y que `contract_version` coincida. Richards y Ford recomiendan las pruebas de contrato como control de gobernanza del microkernel.
2. **Aislamiento del núcleo.** Ningún archivo en `res://orchestration/`, `res://match/`, `res://turn/`, `res://scoring/`, `res://deck/` ni `res://rules/selection/` puede referenciar de forma estática `res://rules/modes/` ni el nombre de una regla concreta: solo `GameRule`. `RuleRegistry` llega a los plug-ins únicamente leyendo `plugin.cfg` en tiempo de ejecución.
3. **Independencia entre plug-ins.** Ningún script de un plug-in puede referenciar la carpeta de otro plug-in, `res://infrastructure/` ni `res://presentation/`. El grafo de dependencias entre plug-ins debe tener 0 aristas.
4. **Volatilidad del núcleo.** Un script de CI compara los archivos cambiados (`git diff --name-only`) en todo *pull request* que agregue o modifique un plug-in, y falla si también cambian archivos del núcleo. Es el *volatility check* sobre el historial de versiones que proponen Richards y Ford.
5. **Validación en la carga.** `RuleRegistry` rechaza y registra en el log de auditoría (RNF 5) todo paquete con una versión de contrato distinta, un script que no herede de `GameRule`, un `id` duplicado o un hash fuera de la lista aprobada.
6. **Desempeño por plug-in.** La batería de contrato mide `validate_closing()` con manos de 10 cartas y falla si el p95 supera 150 ms (RNF 2). Como todas las salas comparten el hilo principal (ADR-05), un plug-in lento afectaría a todas.
7. **Prueba de integración de carga.** En CI se exporta un plug-in de prueba como `.pck` (`godot --headless --export-pack`) y se monta en un servidor *headless*. Se verifica que aparece en `available_modes()`, que con `replace_files = false` no puede reemplazar un archivo del núcleo y que un hash no aprobado se rechaza antes de montar.

*Manual:*

- En la revisión de cada plug-in nuevo se verifica que use solo el contrato y `HandEvaluation`, y que no exceda 2 archivos.
- Todo cambio a `GameRule` exige incrementar `CONTRACT_VERSION` y escribir un ADR nuevo.

---

**NOTAS**

- **Autor:** Daniel Restrepo Faciolince
- **Fecha:** 2026-10-24
- **Aprobado por:** Angelika M y Thomas M
- **Reemplaza a:** ADR-02 (Strategy en tiempo de compilación). Se conservan su patrón Strategy y su Template Method.
- **Relacionado con:** ADR-01 (particionamiento por dominio), ADR-04 (la columna `mode` almacena el identificador del plug-in), ADR-05 (comunicación síncrona en proceso), secciones 1.1, 1.3, 2.3 y 5.2, DA-01 a DA-04, RD08, RNF 5 y RNF 6.
- **Referencias:** Richards y Ford (2025), caps. 11 (*Modular Monolith*), 13 (*Microkernel*: *Plug-In Components*, *Registry*, *Contracts*, *Common Risks*, *Governance*) y 21 (*Architectural Decisions*).
- **Archivo en el repositorio:** `docs/adrs/0003-reglas-como-plugins-en-tiempo-de-ejecucion.md`
