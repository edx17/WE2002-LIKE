# WE2002-LIKE

Un Winning Eleven espiritual hecho desde cero en **Godot 4**: gráficos modernos
más adelante, pero primero **controles clásicos, pelota física, animaciones
rápidas, movimiento en 8/16 direcciones, IA sencilla pero con criterio y cámara WE**.

> Visualmente feo. Mecánicamente obsesivo.
> El objetivo del vertical slice: jugar 30 segundos y decir *"esto se siente como WE2002"*.

## Estado

| Etapa | Contenido | Estado |
|---|---|---|
| **0** Dos muñecos y una pelota | campo, jugador, pelota, cámara: correr → controlar → girar → patear | ✅ jugable (`--match=stage0_solo`) |
| **1** 1 vs 1 | control, pase, remate, recuperación, choque, quite, barrida, cambio de dirección, balón dividido | ✅ jugable (por defecto) |
| **2** 5 vs 5 | IA de posicionamiento, marcaje, apoyo, transiciones | ⏳ la IA ya tiene los modos, falta formación |
| **3** 11 vs 11 | formación, roles, táctica, presión, línea defensiva, offside, pelota parada | ⏳ |
| **4** El monstruo | faltas completas, penales, tiros libres, córners, laterales, tarjetas, árbitro… | 🟡 ya hay lateral, córner, saque de arco y falta simplificados |
| Assets | pipeline receta JSON → Blender → GLB → Godot, PLAYER_001 con esqueleto y 13 clips, kits como textura | 🟡 sustituto funcional; falta el PLAYER_MASTER esculpido |
| Ingeniería inversa | 20 métricas de comportamiento, sonda que mide nuestro motor, protocolo de medición | 🟡 falta medir WE2002 |
| Después | estadios, caras, público, menús, repeticiones, Master League-like, editor | — |

## Cómo correrlo

1. Abrir la carpeta con **Godot 4.3+** y darle Play (escena `scenes/match/Match.tscn`).
2. O por línea de comandos:

```bash
godot --path .                          # 1v1 contra la IA
godot --path . -- --match=stage0_solo   # etapa 0: solo vos y la pelota
godot --path . -- --attract             # IA contra IA
```

### Controles

| Acción | Teclado | Pad (layout Xbox) |
|---|---|---|
| Mover (8/16 direcciones) | WASD / flechas | stick izq. / cruceta |
| Sprint | Shift / Espacio | RB |
| Pase a ras | J | A |
| Remate | K | X |
| Pase filtrado | I | Y |
| Globo / centro | L | B |
| **Sin pelota, rival la tiene:** mantener PASE = presionar · tocar PASE = quite · REMATE = barrida | | |
| **Sin pelota, pelota suelta:** soltar cualquier botón = acción **de primera** al llegar la pelota | | |
| 8 ↔ 16 direcciones | F2 | click stick izq. |
| Zoom de cámara | C | Back |
| Debug / Ayuda / Reiniciar | F3 / F1 / R | — / — / Start |

Los botones de patada funcionan como la barra clásica: **mantener = cargar, soltar = patear**.
En el remate, más carga = más fuerte **y más alto**; pasado el ~88 % se va por arriba.

## Arquitectura

El orden de prioridad es el del diseño: **el gameplay manda sobre la animación**.

```
INPUT (HumanInput / PlayerAI)  →  PlayerIntent
   ↓
PLAYER CONTROL      scripts/players/player_controller.gd   DirectionResolver (8/16), aceleración, giro, estados
   ↓
FOOTBALL GAMEPLAY   scripts/gameplay/possession_referee.gd posesión, divididas, quites, barridas
                    scripts/players/ball_interaction.gd    zonas de contacto, primer toque, conducción
   ↓
BALL PHYSICS        scripts/physics/ball.gd               RigidBody3D + drag + Magnus + rodadura
                    scripts/gameplay/kick_solver.gd        pedido de patada → velocidad + efecto
   ↓
ANIMATION           scripts/animation/animation_selector.gd  estado → "SPRINT_FORWARD + TURN_RIGHT + BALL_CONTROL"
   ↓
AI                  scripts/ai/player_ai.gd               DEFEND / PRESS / COVER / RECOVER / ATTACK…
   ↓
CAMERA              scripts/camera/we_camera.gd           cámara de transmisión WE
   ↓
GRAPHICS            scripts/match/pitch_builder.gd        (placeholder a propósito)
```

```
scenes/   match/ players/ ball/ tools/
scripts/  gameplay/ physics/ players/ ai/ animation/ camera/ match/ tools/
data/     players/ teams/ matches/ appearance/ kits/ animation/ look/ reference/   ← JSON
assets/   players/generated/*.glb  kits/*.png                                    ← generados
tools/    asset_pipeline/ (Blender + kits)
tests/    test_runner.gd  behavior_probe.gd
docs/     INGENIERIA_INVERSA.md  PIPELINE_ASSETS.md
```

### Decisiones clave

- **Movimiento digital.** `DirectionResolver.quantize()` lleva la entrada a 8 o 16
  direcciones. El jugador **corre hacia donde mira**; girar cuesta velocidad, y un giro de
  más de 110° a velocidad pasa por el estado `TURN` (frena y pivotea). La velocidad de giro
  sale de `agility`.
- **La pelota nunca está pegada.** Al conducir, el jugador le pide a la pelota una
  *velocidad deseada* con una fuerza de control (`ball_control_strength` ≈ 0.55–0.92
  según `control`, menos al sprintar). En sprint los toques son más largos.
- **Contacto por zonas.** Pie, muslo, pecho, cabeza, cuerpo: cada una tiene alcance y
  facilidad de control distintos. Si la calidad de recepción no alcanza, la pelota **rebota**.
- **La patada es un pedido, no una orden.** `KickSolver`:
  ```
  final_power = base_power × player_power × balance_modifier × contact_modifier
  accuracy    = player_accuracy × pressure_modifier × movement_modifier × weak_foot_modifier
  ```
  El contacto sale de dónde está realmente la pelota respecto del pie; el balance, de
  cuánto venías girando; el pie malo, de qué lado quedó la pelota. Resultado: *"le pegué mal"*
  en lugar de *"el numerito decidió que erraba"*.
- **Los pases llegan donde prometen.** La velocidad de salida del pase a ras se calcula con
  la solución cerrada de rodadura + drag cuadrático; los tests verifican en el motor real que
  un pase de 25 m llega a la velocidad pedida.
- **La IA usa el mismo `PlayerIntent` que el humano.** Mismas 8 direcciones, misma
  aceleración, misma imprecisión. Decide cada 0.1–0.32 s según `reaction`, y nunca
  "persigue la pelota": primero elige un modo táctico (defender del lado del arco, cubrir,
  presionar, recuperar).
- **La animación solo refleja.** `AnimationSelector` produce un descriptor
  (`SPRINT_FORWARD + TURN_RIGHT + BALL_CONTROL`). Con un jugador generado, `PlayerModel` arma un
  `AnimationTree` en código (Locomotion por velocidad más un estado por acción, con fundidos de
  0.05–0.1 s) y `AnimationTreeDriver` lo conduce. Sin modelo, un animador procedural mueve la
  cápsula.
- **Cámara WE.** Lateral y alta, sigue la pelota a lo largo del campo con *dead zone* y un
  *lead* hacia donde ataca el poseedor. `lead_speed` controla cuánto tarda en girar al
  cambiar la posesión: ahí se juega buena parte de la sensación.

## Ingeniería inversa y assets

Dos objetivos separados:

1. **Comportamiento.** Se mide WE2002 (velocidades, giros, patadas, cámara) con el protocolo de
   [`docs/INGENIERIA_INVERSA.md`](docs/INGENIERIA_INVERSA.md). Los valores se cargan en
   `data/reference/we2002_behavior.json` y `tests/behavior_probe.gd` mide lo mismo en nuestro motor.
2. **Assets.** Se reconstruye la receta visual con assets 100 % propios:
   [`docs/PIPELINE_ASSETS.md`](docs/PIPELINE_ASSETS.md). Una receta JSON pasa por Blender, sale un GLB
   y Godot lo carga. La camiseta es una textura sobre el mismo modelo, y los tiempos de los clips
   son los mismos que usa el gameplay.

```bash
godot --path . res://scenes/tools/ModelPreview.tscn    # visor de jugadores generados
```

## Datos y modding

Jugadores, equipos y partidos son JSON en `data/`. Cualquier archivo con la misma ruta
dentro de `user://mods/data/` pisa al original, sin recompilar nada.

```json
{ "name": "Jugador 01", "speed": 83, "acceleration": 87, "control": 91,
  "passing": 84, "shooting": 79, "strength": 72, "stamina": 88 }
```

Atributos: `speed acceleration agility balance strength stamina passing shooting
shot_power heading tackling control technique aggression reaction`, más
`preferred_foot` y `weak_foot` (1–4).

## Tests

```bash
godot --headless --import --path .
godot --headless --path . -s tests/test_runner.gd
```

52 comprobaciones: cuantización, zonas de contacto y fórmulas de patada, más simulaciones
en el motor real. Distancia de pase y de globo, remate que entra, remate pasado de potencia
que se va por arriba, conducción en sprint sin perder la pelota, giro de 180°, un remate
completo con la misma entrada que un humano, el modelo generado con su AnimationTree
siguiendo al gameplay, y 90 s de IA contra IA. `tests/behavior_probe.gd` compara contra la
referencia de WE2002. Corren en CI con
GitHub Actions.

## Legal

La idea es copiar la **filosofía de diseño**, no los assets. Nada de modelos, escudos,
nombres, caras, audio ni ningún otro material de Konami o de Forever Eleven. Todo lo que
entre al proyecto tiene que ser propio o tener licencia compatible.
