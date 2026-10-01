# Hoja de ruta

Estado y decisiones del proyecto. Se actualiza en cada fase.

## Hecho

| Fase | Contenido |
|---|---|
| 0–4 | Juego completo: controles WE (8/16 direcciones), pelota física, IA de equipo, 11v11 con tácticas, fuera de juego, pelota parada, dos tiempos, energía, faltas y tarjetas, penales, laterales con la mano, árbitro, cambios |
| Cimientos | **Dos jugadores locales** (versus y cooperativo), **Master League** (mundo ficticio, temporadas, ascensos y descensos, copa, puntos, fichajes, crecimiento y declive, guardado), **motor de competiciones** (liga todos contra todos y eliminación directa), **grabación del partido** (base de repeticiones y VAR), pantalla de título y de Master League provisorias |
| Assets | Pipeline receta → Blender → GLB → Godot, estilo clásico WE2002 y estilo moderno, kits con dorsal y escudo, guía de Blender, panel de Blender y validador |

## Próximas fases, en orden

1. **Calibración** (con pruebas del usuario y mediciones del WE2002 original): sensación de control,
   IA (pases, remates, goles), arqueros, cantidad de faltas, cámara.
2. **Dificultad de la IA** (1 a 5 estrellas) y **sonido** con un sistema de eventos.
3. **Menús e interfaz** con estética WE: selección de equipos y camisetas, opciones, la Master League
   completa (alineación manual, negociaciones, renovaciones, juveniles).
4. **Estadio** modular, **público**, **iluminación y clima** (lluvia que afecta a la pelota).
5. **Repeticiones** (usan la grabación del partido): automáticas de goles, manual desde la pausa,
   varias cámaras, cámara lenta.
6. **VAR** (ver abajo).
7. **Competiciones** sobre el motor de la Master League: ligas con ascensos y descensos de varias
   divisiones, copas nacionales, copas internacionales de clubes (formato tipo Libertadores y
   Sudamericana), torneos de selecciones (tipo Copa América, Mundial, Mundial Sub-20), ligas y copas
   personalizadas. Todo con nombres, escudos y camisetas ficticios y editables.
8. **Editor** de jugadores, equipos, camisetas, formaciones, competiciones y aspecto (usa el pipeline
   de assets), con exportación como mod.
9. **Animaciones y modelos hechos a mano** (los hace el usuario con la guía `docs/BLENDER_GUIA.md`)
   y **comentarios**.

## VAR (especificación)

Tiene que funcionar **como en la vida real**, con su animación:

- **Qué revisa** (protocolo IFAB): goles (fuera de juego, falta o mano en la jugada previa), penales
  (cobrados o no), rojas directas y confusión de identidad. Nunca amarillas ni faltas en el medio.
- **Flujo:**
  1. El juego sigue hasta la próxima pelota parada, salvo un gol, que se revisa antes del saque.
  2. El VAR "chequea" en silencio (en pantalla: *VAR · CHEQUEANDO GOL*). Si no hay error claro, sigue.
  3. Si hay un posible error claro, el árbitro se lleva la mano al oído, detiene el juego y dibuja
     el rectángulo de TV con las manos: **revisión en el campo** (OFR).
  4. El árbitro corre al monitor al costado de la cancha y mira la repetición (animación propia).
  5. Decisión: vuelve, hace la señal y se anula o convalida el gol, se cobra o se cancela el penal, se
     cambia la tarjeta.
- **Fuera de juego por VAR:** usa las marcas de la grabación para volver al cuadro exacto del pase,
  congela la imagen, dibuja la línea del penúltimo defensor y la del atacante (líneas calibradas
  sobre el césped) y decide con la tolerancia del reglamento.
- **Animaciones nuevas:** dedo en el oído, rectángulo de TV, árbitro mirando el monitor, señal de
  gol anulado. Se agregan a `data/animation/clips.json` (y a la guía de Blender).
- **Opciones:** VAR activado o desactivado por competición (como en la vida real: no todas lo usan).

## Decisiones tomadas

- Dos jugadores locales: sí, ya implementado.
- La Master League es el cimiento de todos los modos de competición.
- Modelos y animaciones: los hace el usuario, con la guía, el panel de Blender y el validador como apoyo.
- Sin licencias: todo es ficticio y editable.
- Juego online: fuera del alcance por ahora.
