# Guía de Blender para WE2002-LIKE

Esta guía está pensada para alguien que **nunca abrió Blender**. No intenta enseñarte todo
Blender: solo lo necesario para hacer jugadores y animaciones que el juego entienda, en el orden
en que lo vas a necesitar.

> Regla de oro: el juego no sabe nada de cómo modelaste. Solo le importan los **contratos**
> (nombres de huesos, nombres de materiales, tamaño, orientación, nombres y duración de las
> animaciones). Si los respetás, podés modelar como quieras.

---

## 0. Instalar y preparar

1. Bajá **Blender 4.2 LTS** de blender.org (es gratis). LTS = versión estable, la misma que usa
   el pipeline del proyecto.
2. Abrí `assets/source/players/player_001.blend`. Es el jugador actual del juego, ya armado con
   el esqueleto, los materiales y las animaciones correctas. **Siempre empezá desde este archivo**
   (Archivo → Guardar como… con otro nombre), nunca desde una escena vacía.
3. Si querés otro jugador como base: `python tools/asset_pipeline/player_generator.py player_005 --save-blend`.

### El panel WE2002 (hace lo difícil por vos)
1. Pestaña **Scripting** (arriba) → Texto → Abrir → `tools/asset_pipeline/blender_panel.py` → botón ▶ (Run Script).
2. Volvé a la vista 3D y apretá **N**: aparece la pestaña **WE2002** a la derecha, con cuatro botones:
   - **UV de camiseta:** aplica la regla de la camiseta a lo que tengas seleccionado.
   - **Crear animaciones:** crea las que falten, con el nombre y la cantidad de cuadros correctos.
   - **Revisar:** te dice qué falta o qué está mal (huesos, materiales, animaciones).
   - **Exportar al juego:** guarda el `.glb` en la carpeta correcta con la configuración correcta.

### Lo mínimo para moverse

| Acción | Cómo |
|---|---|
| Girar la vista | botón del medio del mouse y arrastrar |
| Desplazar la vista | Shift + botón del medio |
| Zoom | rueda del mouse |
| Vistas fijas | teclado numérico: 1 frente, 3 costado, 7 arriba (Ctrl+1 = detrás) |
| Ver solo lo seleccionado | `/` del teclado numérico |
| Modo objeto ↔ modo edición | Tab |
| Mover / rotar / escalar | G / R / S (después X, Y o Z para un solo eje) |
| Deshacer | Ctrl+Z |

Sin teclado numérico: Editar → Preferencias → Entrada → "Emular teclado numérico".

---

## 1. Los contratos (lo que no se puede romper)

| Qué | Regla |
|---|---|
| Unidades | metros (1 unidad = 1 m). Altura del jugador: 1,65–1,95 m |
| Orientación | Z hacia arriba, el jugador **mira hacia −Y** (vista frontal = tecla 1 del numérico te muestra su cara) |
| Posición | pies en el piso (z = 0), centrado en x = 0, y = 0 |
| Esqueleto | un solo Armature con estos huesos, **con estos nombres exactos**: `Hips, Spine, Chest, Neck, Head, UpperArm.L, LowerArm.L, Hand.L, UpperArm.R, LowerArm.R, Hand.R, UpperLeg.L, LowerLeg.L, Foot.L, UpperLeg.R, LowerLeg.R, Foot.R` (.L = izquierda del jugador = +X) |
| Materiales | `SKIN` (piel), `FACE` (cara pintada), `KIT_SHIRT` (camiseta), `KIT_SHORTS` (short), `KIT_SOCKS` (medias), `BOOTS`, `HAIR`, `EYES` |
| Camisetas | dos objetos: `Shirt_Short` (manga corta) y `Shirt_Long` (manga larga). El juego muestra uno u otro según el equipo |
| Triángulos | estilo clásico WE2002: 1.000–3.000 por jugador. Máximo razonable: 40.000 |
| Animaciones | nombres y duraciones de la tabla de la sección 5, a 30 cuadros por segundo |

Los colores de `KIT_SHIRT`, `KIT_SHORTS` y `KIT_SOCKS` **no importan**: el juego los reemplaza
por los de cada equipo. Por eso un mismo modelo sirve para todos los equipos.

---

## 2. Modelar (estilo WE2002)

El estilo del original es **cuadrado y de pocos polígonos**: el torso es un trapecio, el short
una caja ancha, las piernas prismas, la cara está pintada. Eso juega a tu favor: es el tipo de
modelado más fácil para empezar.

Técnica recomendada, **modelado por cajas** (box modeling):

1. Seleccioná una parte del jugador existente (por ejemplo la camiseta) y entrá en modo edición
   (Tab).
2. Herramientas básicas:
   - **Extruir** (E): sacar caras hacia afuera, para brazos o cuello.
   - **Corte en bucle** (Ctrl+R): agregar un anillo de geometría, para codo o rodilla.
   - **Escalar** (S): hacer más ancho o angosto un anillo.
   - **Unir** (M → At Center): juntar vértices.
3. Activá el **espejo**: modificador *Mirror* en X. Modelás un lado y el otro se copia solo.
4. Poné tus capturas de referencia de fondo: Agregar → Imagen → Referencia, en vista frontal y
   lateral. Las capturas son solo para mirar, **nunca uses texturas o modelos del juego original**.
5. Cada tanto apretá Tab para volver a modo objeto y mirá cómo queda de lejos (la cámara del
   juego está lejos: lo que importa es la silueta).

Consejos:
- Menos es más: si una parte no se ve desde la cámara de juego, no la detalles.
- Trabajá la silueta de frente (1) y de costado (3), no en perspectiva.
- Guardá seguido con números: `jugador_v01.blend`, `jugador_v02.blend`…

---

## 3. Camiseta y cara (texturas)

### Camiseta: la regla del UV
El juego pinta la camiseta con una textura de 256×256 que sigue esta regla:

```
u (horizontal):  0 = espalda · 0.25 = costado derecho · 0.5 = PECHO · 0.75 = costado izquierdo · 1 = espalda
v (vertical):    0 = ruedo (abajo) … 0.95 = hombros · 0.955–1.0 = SOLO el cuello
```

Cómo lograrlo en Blender:
1. Seleccioná la camiseta, entrá en modo edición y seleccioná todo (A).
2. Vista frontal (1), menú UV → **Proyección cilíndrica** (Cylinder Projection), con "Align to
   Object" y radio 1.
3. En el editor UV, mové y escalá para que el pecho quede en el centro horizontal y el ruedo abajo.
4. Para revisarlo, cargá `assets/kits/team_a_home.png` como textura de prueba: los bastones tienen
   que quedar verticales y el número de la espalda centrado.

### Cara
La cara es una textura chica (64×64) pintada: ojos, cejas, boca, barba. Podés pintarla en Blender
(modo Texture Paint) o en cualquier programa de dibujo (GIMP, Krita, Aseprite) y asignarla al
material `FACE`. Pixelada está bien: es el estilo.

---

## 4. Esqueleto y pesos (que el modelo se mueva)

El esqueleto **ya está hecho** en el archivo base. Solo tenés que conectar tu malla:

1. En modo objeto, seleccioná tu malla, después con Shift seleccioná el esqueleto (el último
   seleccionado es el "activo").
2. Ctrl+P → **Con pesos automáticos** (With Automatic Weights).
3. Probalo: seleccioná el esqueleto, Ctrl+Tab (modo pose), elegí un hueso y rotalo (R). La malla
   tiene que seguirlo. Alt+R vuelve a la pose de reposo.
4. Si alguna zona se deforma mal (típico: la axila o la entrepierna), usá **Weight Paint**:
   seleccioná la malla, modo Weight Paint, elegí el grupo del hueso a la izquierda y pintá
   (rojo = 100 % de ese hueso, azul = 0 %).

**No renombres ni borres huesos.** Podés moverlos un poco (modo edición del esqueleto) para que
coincidan con tus proporciones.

---

## 5. Animar

Cada animación es una **Acción** (Action) con un nombre exacto. Las que usa el juego:

| Nombre | Qué es | Cuadros (a 30 fps) | Loop | Momento de contacto |
|---|---|---|---|---|
| `IDLE` | parado, respirando (loop) | 48 | sí |  |
| `WALK` | caminando (loop) | 30 | sí |  |
| `RUN` | trotando (loop) | 19 | sí |  |
| `SPRINT` | corriendo a fondo (loop) | 16 | sí |  |
| `PASS` | pase con el pie derecho | 9 | no | cuadro 3 |
| `SHOOT` | remate | 12 | no | cuadro 4 |
| `HEAD` | cabezazo | 14 | no | cuadro 4 |
| `TACKLE` | quite parado | 14 | no | cuadro 4 |
| `SLIDE` | barrida | 24 | no |  |
| `FALL` | caída hacia adelante | 21 | no |  |
| `GET_UP` | levantarse | 14 | no |  |
| `TURN_180` | giro brusco | 8 | no |  |
| `CELEBRATE` | festejo (loop) | 30 | sí |  |
| `DIVE_LEFT` | arquero vuela a su izquierda | 16 | no |  |
| `DIVE_RIGHT` | arquero vuela a su derecha | 16 | no |  |
| `THROW_HOLD` | lateral: pelota sobre la cabeza (loop) | 30 | sí |  |
| `THROW_IN` | lateral: el tiro | 14 | no | cuadro 6 |

El **momento de contacto** importa: es el cuadro en que el pie (o la cabeza) toca la pelota. El
juego patea en ese instante, así que la animación y la pelota quedan sincronizadas.

Cómo hacer una animación:
1. Arriba elegí la pestaña **Animation**. Abajo cambiá el editor a **Dope Sheet → Action Editor**.
2. Seleccioná el esqueleto, modo pose (Ctrl+Tab).
3. Botón **New** en el Action Editor, ponele el nombre exacto (por ejemplo `RUN`) y activá el
   escudo (Fake User) para que no se borre.
4. Cuadro 1: poné la pose inicial, seleccioná los huesos (A) y apretá **I → Rotación** para
   guardar una clave. Avanzá cuadros (flechas), cambiá la pose y volvé a apretar I.
5. En las animaciones en loop, la última pose tiene que ser igual a la primera.
6. Revisala con la barra espaciadora.

El estilo WE es de **animaciones cortas y marcadas**: poses claras y transiciones rápidas, nada de
movimientos lentos de cine.

---

## 6. Exportar al juego

1. Archivo → Exportar → **glTF 2.0 (.glb)**.
2. Opciones:
   - Formato: **glTF Binary (.glb)**
   - Incluir: *Selected Objects* desactivado (exporta todo)
   - Transformar: **+Y Up** activado
   - Datos → Malla: *Apply Modifiers* activado
   - Animación: activada, modo **Actions**
3. Guardalo en `assets/players/custom/<nombre>.glb`, con el mismo nombre que el aspecto que querés
   reemplazar (por ejemplo `player_001.glb`). El juego usa automáticamente tu modelo en lugar del
   generado.
4. **Validá** (detecta el 90 % de los problemas):
   ```
   python tools/asset_pipeline/validate_glb.py assets/players/custom/player_001.glb
   ```
   o, sin Python: `blender -b -P tools/asset_pipeline/validate_glb.py -- assets/players/custom/player_001.glb`
5. Miralo en el juego: abrí Godot, ejecutá `scenes/tools/ModelPreview.tscn` (F6). Con ←/→ ves cada
   animación, con ↑/↓ cambiás de jugador y con K la camiseta.

---

## 7. Errores comunes

| Síntoma | Causa | Solución |
|---|---|---|
| El jugador aparece gigante o diminuto | Escala en centímetros o sin aplicar | Seleccionar → Ctrl+A → *All Transforms*, escala 1 |
| Corre de espaldas | Modelado mirando a +Y | Rotalo 180° en Z y aplicá (Ctrl+A) |
| La camiseta no cambia de color | El material no se llama `KIT_SHIRT` | Renombrá el material (sin ".001") |
| Se queda quieto en una acción | La acción tiene otro nombre o no tiene Fake User | Nombre exacto y escudo activado |
| La malla se "despega" al moverse | Faltan pesos en esa zona | Weight Paint |
| El número aparece torcido | El UV de la camiseta no sigue la regla | Repetí la proyección cilíndrica |

---

## 8. Cómo te ayudo

- Mandame **capturas** (vista frontal, lateral y la cámara del juego) y te digo qué ajustar.
- Si subís tu `.blend` o `.glb` al repo (`assets/source/players/` o `assets/players/custom/`),
  lo reviso, corro el validador y te propongo los cambios concretos.
- Puedo escribirte **scripts para Blender** que automaticen lo repetitivo: renombrar materiales,
  crear las acciones vacías con la duración correcta, copiar una animación de izquierda a derecha.
- Orden sugerido para aprender: (1) cambiar proporciones del jugador base, (2) remodelar la
  cabeza y el pelo, (3) pintar una cara, (4) rehacer `IDLE` y `RUN`, (5) el resto de las
  animaciones.
