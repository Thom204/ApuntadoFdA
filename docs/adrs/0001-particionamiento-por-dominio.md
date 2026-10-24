# ADR-01: Particionar el sistema por dominio del juego mediante un monolito modular

- **Estado:** Proposed
- **Fecha:** [2026-09-28]
- **Autor(es):** [Daniel Restrepo]
- **Revisores:** [docente / equipo]
- **Relacionado con:** [ADR-02](./0002-reglas-como-estrategias.md), secciones 4.1, 4.3 y 4.5

## Contexto

El sistema debe soportar dos modalidades de juego (Clásica 4-3-3 y Apuntado 101) y evolucionar con variantes que el cliente ya anticipó: comodín, apuestas dinámicas, reingreso de eliminados y variaciones visuales. El driver principal es la **Extensibilidad/Configurabilidad**, seguido de **Testability** y **Responsiveness**.

Se evaluaron dos alternativas de particionamiento superior (Richards & Ford, cap. 9):

1. **Particionamiento técnico** (capas de presentación, negocio y persistencia). Es simple y conocido, pero un cambio de regla atraviesa todas las capas. Por ejemplo, agregar el comodín tocaría la capa de negocio, la de persistencia y la de presentación, y la lógica del juego queda dispersa en una capa de servicios genérica.
2. **Particionamiento por dominio** (módulos alineados con las responsabilidades del juego). Cada módulo agrupa todo lo necesario para una parte del juego, y los componentes identificados ya siguen esta forma.

## Decisión

Usaremos **particionamiento por dominio** como estructura superior, implementado como un **monolito modular**.

- Cada módulo corresponde a un área del juego (partida, turno, reglas, puntaje, baraja, notificación, historial) y se organiza como una carpeta de nivel superior del proyecto (`res://match/`, `res://turn/`, `res://rules/`, etc.), replicando el namespace lógico del inventario de 4.1.
- Los módulos exponen su funcionalidad a los demás solo mediante clases con `class_name` y señales (`signal`). Ningún módulo accede a nodos internos de otro por ruta directa.
- La coordinación entre módulos se centraliza en un único autoload orquestador (`MatchOrchestrator`), cuyo rol se limita a invocar funciones de los módulos, sin contener lógica de negocio propia.
- La interfaz de usuario (escenas y nodos de UI) se mantiene desacoplada de la lógica del juego y se comunica con ella únicamente mediante señales, de modo que la lógica no depende de la presentación.

**Justificación:** los cambios que el cliente anticipa son cambios de dominio, no de tecnología. Con particionamiento por dominio, un cambio de regla queda contenido en el módulo de reglas. Se elige un monolito y no servicios distribuidos porque ninguna característica prioritaria exige despliegue independiente o escalabilidad por partes; distribuir el sistema añadiría latencia de red, complejidad operativa y costo.

## Consecuencias

### Positivas

- Los cambios de reglas quedan localizados en un módulo.
- Los módulos se pueden probar de forma aislada.
- Si en el futuro se necesita distribuir, los módulos ya tienen fronteras claras para extraerse como servicios.

### Negativas

- Las funciones transversales (notificación, historial) son usadas por varios módulos y deben diseñarse con cuidado para no acoplarlos entre sí.
- Las fronteras entre módulos dependen de la disciplina del equipo: en un monolito nada impide técnicamente que un módulo acceda a las clases internas de otro.
- Todo el sistema se despliega y escala como una unidad.

## Cumplimiento (Compliance)

### Automatizado

Un script de dependencias ejecutado en CI (GUT, modo headless) construye el grafo de referencias entre carpetas `res://` a partir de `class_name`, `extends`, `preload` y anotaciones de tipo. Falla si:

- aparece un ciclo entre módulos;
- un archivo del núcleo referencia `res://presentation/` o `res://infrastructure/`;
- un módulo accede a otro por ruta de nodo en lugar de su API pública (`class_name` y señales).

### Manual

En la revisión de código se rechazan las cadenas de llamadas sobre objetos de otro módulo (Ley de Deméter) y cualquier lógica de negocio agregada a `MatchOrchestrator`.

## Notas

[Daniel, fecha de aprobación, revisores]
