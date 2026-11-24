# Orden visual de la mano

## Comportamiento

- Cada cliente puede ordenar visualmente sus cartas sin cambiar el estado de la partida ni el orden que conoce el servidor.
- La vista mantiene una secuencia local de `card_id`; este identificador no se usa como posición porque el orden puede cambiar.
- Una carta robada se añade al final de esa secuencia. Las cartas que salen de la mano se eliminan al reconstruirla.
- El orden se reinicia al cambiar de ronda y no se guarda entre partidas.
- Un clic selecciona la carta al soltar el botón. Mantenerlo presionado durante 0,9 segundos inicia el arrastre; una vez iniciado, al soltar se inserta la carta según la posición horizontal del puntero.
- Un movimiento de más de 10 píxeles antes de completar la espera cancela el gesto, para no confundir un movimiento accidental con un clic o un hold.

## Implementación

- `CardView` distingue el clic del arrastre y emite señales de inicio, movimiento y fin.
- `HandFan` sigue el puntero y calcula la posición de inserción al terminar el arrastre.
- `TableView` conserva el orden visual por `card_id` entre reconstrucciones de la mano. Las cartas nuevas se anexan al final.
- El estado persistido y las reglas del juego no cambian.

## Pendientes

- Revisar cómo debe interactuar el botón **Ordenar por valor** con el orden manual. Por ahora, al alternar el orden existente, la mano vuelve al orden indicado por ese botón.
- Evaluar el umbral de 0,9 segundos y la tolerancia de 10 píxeles con uso real.
- Considerar soporte táctil si se añade una interfaz para pantallas táctiles.
