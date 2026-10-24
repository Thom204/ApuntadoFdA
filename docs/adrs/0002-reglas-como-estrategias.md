# ADR-02: Implementar las reglas de victoria como estrategias intercambiables dentro del monolito modular

- **Estado:** Proposed
- **Fecha:** [2026-09-28]
- **Autor(es):** [Daniel Restrepo]
- **Revisores:** [docente / equipo]
- **Relacionado con:** [ADR-01](./0001-particionamiento-por-dominio.md), secciones 4.4 y 4.5, RNF 1 y RNF 6

## Contexto

Las modalidades Clásica (1 cuarta + 2 ternas + 1 descarte) y Apuntado (3 ternas con sobrante menor a 5 puntos y eliminación en 101) tienen condiciones de victoria distintas, y el cliente anticipa nuevas variantes (comodín, reingreso, apuestas).

Los drivers de **Extensibilidad** y **Testability** exigen agregar reglas sin modificar el núcleo y probarlas de forma automatizada, y el RNF 1 fija un máximo de 2 archivos existentes modificados por regla nueva. La variación de parámetros (umbral, comodín, valor de cartas) se resuelve con configuración; esta decisión trata la variación de **comportamiento**.

Se evaluaron tres alternativas:

1. **Condicionales por modalidad en el núcleo.** Descartada: convierte al orquestador en un *GameManager*.
2. **Strategy dentro del monolito modular.** Adoptada.
3. **Microkernel con plug-ins cargados en ejecución** (Richards & Ford, cap. 13). Descartada por su complejidad y por ejecutar código externo, en conflicto con el RNF 6.

## Decisión

Las reglas de victoria se implementarán con el patrón **Strategy** dentro del módulo de reglas.

- La clase abstracta `GameRule` (`@abstract`, `extends Resource`) define el contrato `validate_closing(cards: Array[Card], discard: Card)`, que recibe una copia de las cartas de la mano (nunca la entidad `Hand`) y devuelve un `ValidationResult`.
- `ClassicRule` y `ApuntadoRule` son las estrategias concretas, ubicadas en `res://rules/modes/` y apoyadas en Hand Evaluation.
- `RuleRegistry` selecciona la estrategia según la modalidad de la partida y es el único punto que conoce las implementaciones concretas.
- Turn Orchestration depende solo de `GameRule`.
- Los parámetros de regla residen en `RuleSettings`, que `MatchConfig` compone.

**Justificación:** una modalidad nueva equivale a un archivo en `res://rules/modes/`, un valor en el catálogo `GameMode` y una línea en el registro, sin tocar el núcleo, la interfaz ni la persistencia. Las reglas se prueban sin árbol de escena. Un Microkernel en ejecución solo se justifica si se agregan reglas sin volver a exportar el juego o si las desarrollan terceros, y esas necesidades no existen en el MVP.

## Consecuencias

### Positivas

- Modalidades agregables sin modificar el núcleo.
- Reglas probadas de forma aislada.
- Eliminación de la ramificación por modalidad.
- Polimorfismo explícito en el diagrama de clases.

### Negativas

- Cada modalidad nueva requiere volver a exportar el juego.
- Se agrega una capa de abstracción.
- Se requiere Godot 4.5 o superior para `@abstract`.
- Las variantes que alteren el flujo del turno (apuestas) necesitarán un contrato propio en lugar de ampliar `GameRule`.
- Agregar una modalidad modifica dos archivos existentes (`GameMode` y `RuleRegistry`), el máximo que permite el RNF 1.

## Cumplimiento (Compliance)

### Automatizado

- Pruebas de contrato con GUT, en modo headless, que aplican una batería común de casos a todas las reglas registradas.
- Un script de dependencias en CI falla si un archivo fuera de `res://rules/` referencia una regla concreta, si una regla depende de otra o si aparecen condicionales por modalidad en el núcleo.

### Manual

En la revisión de cada regla nueva se verifica el límite del RNF 1 (máximo 2 archivos existentes modificados).

## Notas

[Daniel, fecha de aprobación, revisores]
