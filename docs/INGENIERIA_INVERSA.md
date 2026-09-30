# Ingeniería inversa de comportamiento

Objetivo: recrear **cómo se comporta** WE2002 midiendo, no copiando código ni archivos.

```
WE2002 ──► observar ──► medir ──► registrar ──► data/reference/we2002_behavior.json
                                                          │
nuestro motor ◄── ajustar datos/fórmulas ◄── comparar ◄── tests/behavior_probe.gd
```

## Qué es verde, amarillo y rojo

| | Qué | Cómo lo tratamos |
|---|---|---|
| 🟢 Replicable | proporciones, cámara, composición, estilo, comportamiento, paleta aproximada, estructura de menús, diseño de gameplay, lógica física | Se mide y se reproduce con código y datos propios. |
| 🟡 Estudiar y reconstruir | modelos, animaciones, texturas, estadios | Se usan como **referencia visual**; los assets se hacen desde cero en el pipeline (`docs/PIPELINE_ASSETS.md`). |
| 🔴 No se distribuye | archivos del juego, modelos/texturas/animaciones extraídos, audio, caras reales, logos y marcas sin licencia | Nunca entran al repositorio ni al build. |

## Protocolo de medición

1. **Captura.** Grabar una copia propia del juego a 60 fps (emulador o capturadora), sin
   filtros ni frame blending. Anotar versión, región y configuración de cámara.
2. **Escala.** Las líneas del campo son la regla: área grande 16.5 m × 40.32 m, área chica
   5.5 m, arco 7.32 m × 2.44 m, círculo central de 9.15 m de radio, punto penal a 11 m.
   Medir siempre cerca de una marca conocida y lo más perpendicular posible a la cámara.
3. **Tiempo.** Contar frames (1 frame = 16.7 ms a 60 fps). Para cada métrica, al menos
   **5 muestras**; registrar el promedio y anotar la dispersión en `source`.
4. **Herramientas.** Cualquier visor cuadro a cuadro sirve (Kinovea, Tracker, un editor de
   video). Para velocidades: posición en el frame A y en el frame B, dividido por el tiempo.
5. **Registro.** En `data/reference/we2002_behavior.json`, completar `target`, `samples` y
   `source` (ej. `"captura_03.mp4 f1200-f1260, escala con área grande, 6 muestras, σ=0.2"`).
   Un `target` en `null` significa **pendiente**: nunca se completa a ojo.
6. **Comparar.**
   ```bash
   godot --headless --path . -s tests/behavior_probe.gd -- --out=behavior_report.json
   ```
   Cada métrica sale como `PENDIENTE`, `OK` o `FUERA`. El comando falla si alguna medida queda
   fuera de tolerancia, así CI evita que el juego se aleje de la referencia.
7. **Ajustar** datos, no parches: velocidades en `PlayerController` / atributos, tiempos en
   `data/animation/clips.json`, cámara en `data/look/*.json`, balón en `Ball` / `KickSolver`.

## Métricas actuales

Movimiento (velocidad de trote/sprint, aceleración, frenada, giros de 45° y 180°), conducción
(distancia pie-pelota, velocidad con pelota), patadas (ventana de pase/remate, velocidad de
salida, tiempo de recorrido, vuelo del globo) y cámara (ángulo, metros visibles, reacción al
cambio de posesión). La lista completa, con el método de cada una, está en el JSON.

Próximas a agregar con el mismo formato: radio de giro con pelota, distancia de control según
la zona del cuerpo, rebote de la pelota en el césped y el palo, duración de caída y
levantada, distancias entre líneas y reacción de la IA a la pérdida.
