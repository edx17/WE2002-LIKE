# Pipeline de assets

No copiamos modelos: reconstruimos la **receta**. Un PLAYER_MASTER más una biblioteca chica de
componentes produce muchos jugadores, y la camiseta es una textura sobre el mismo modelo.

```
data/appearance/player_XXX.json ─┐
data/appearance/components.json ─┼─► tools/asset_pipeline/player_generator.py (Blender)
data/animation/clips.json ───────┘              │
                                                ▼
                               assets/players/generated/player_XXX.glb
                               (Body, Head, Shirt_Short, Shirt_Long, Shorts,
                                Boots, Hair, Face + esqueleto + 13 clips)
data/kits/*.json ──► tools/asset_pipeline/kit_generator.py ──► assets/kits/*.png
                                                │
                                                ▼
                        Godot: PlayerModel → kit + dorsal (KitTexture) → AnimationTree
```

## Generar

```bash
# Con Blender instalado
blender -b -P tools/asset_pipeline/player_generator.py -- --all
# o con el módulo de Python (pip install bpy==4.2.0, Python 3.11)
python tools/asset_pipeline/player_generator.py --all

python3 tools/asset_pipeline/kit_generator.py          # sin dependencias
godot --headless --import --path .                     # reimportar
godot --path . res://scenes/tools/ModelPreview.tscn    # visor (←/→ clip, ↑/↓ jugador, K camiseta)
```

Los `.glb` y `.png` generados se versionan: el juego funciona sin tener Blender.

## Receta de un jugador

```json
{ "id": "player_001", "body": 1, "face": 0, "hair": 1, "hair_color": 1,
  "boot": 0, "boot_color": "#111111", "skin": 1, "height": 1.80, "weight": 76 }
```

Los índices apuntan a `components.json` (3 tipos de cuerpo, 3 caras, 6 peinados, 3 botines,
6 tonos de piel, 6 colores de pelo). La altura escala el esqueleto; el peso (IMC) ajusta el
volumen. Cada jugador en `data/players/*.json` elige su receta con `"appearance"`.

## Contratos (lo que no se puede romper)

- **Orientación.** Blender Z arriba, el personaje mira a −Y, pies en el origen. Godot lo gira 180°.
- **Esqueleto.** `Hips, Spine, Chest, Neck, Head`, y `UpperArm/LowerArm/Hand/UpperLeg/LowerLeg/Foot`
  `.L/.R`.
- **Materiales por nombre.** `SKIN, KIT_SHIRT, KIT_SHORTS, KIT_SOCKS, BOOTS, HAIR, EYES`. Godot
  reemplaza los `KIT_*` con el kit del equipo.
- **UV de camiseta.** Proyección cilíndrica alrededor del torso: `u` 0.5 = pecho, 0/1 = espalda,
  `v` 0 = ruedo, 0.95 = hombros; la franja `v > 0.955` es solo para el anillo del cuello. Cualquier textura de 1024² que respete eso sirve para todos los
  jugadores, sea generada (`plain, stripes, hoops, halves, sash`) o pintada a mano.
- **Clips.** Nombres y duraciones en `data/animation/clips.json`, el mismo archivo del que el
  gameplay lee las ventanas de patada. `contact` = frame de contacto con la pelota.
- **Look.** Material de pocas capas: color base, rugosidad alta y especular moderado. La luz, el
  SSAO, el grading y la **cámara** viven en `data/look/we2002_hd.json`.

## Cómo se esculpe (sculpt.py)

La referencia visual es la de los remasters actuales de WE2002: proporciones modernas,
cuerpo continuo, ropa con volumen y dorsal grande en la espalda. La receta:

1. **Anatomía como primitivas.** Unas 50 elipsoides y cápsulas cónicas (pelvis, glúteos,
   costillas, pectorales, trapecios, deltoides, bíceps, cuádriceps, gemelos, cráneo, mandíbula,
   nariz, arco superciliar, orejas…), cada una asignada a un hueso.
2. **Fusión por voxel remesh.** Se unen en una sola superficie continua, sin costuras en las
   articulaciones, y se suaviza. El tamaño de voxel sale del presupuesto de triángulos (nunca se
   decima: el decimado deja triángulos largos que se rompen al animar).
3. **Ropa como cáscaras.** La camiseta (torso más una manga por brazo), el short y los botines
   son copias infladas de la anatomía, cortadas en el ruedo, el cuello, los puños y las piernas.
   Los bordes se proyectan sobre la superficie de corte, así quedan rectos como costuras.
4. **Skinning.** El cuerpo recibe pesos suaves de sus primitivas y la ropa copia los pesos del
   vértice de piel más cercano, así nunca se rompe.
5. **Cabeza aparte**, con voxel más fino, para que nariz, cejas, mandíbula y orejas no se pierdan.

| Malla | Triángulos |
|---|---|
| Body | ~29k |
| Head | ~7k |
| Shirt_Short / Shirt_Long | ~6k / ~7k (se ve una sola) |
| Shorts, Boots, Hair | ~3k, ~3k, ~4k |
| Face (ojos, cejas) | ~2.5k |

El kit decide manga corta o larga (`"sleeves": "long"`, por ejemplo para arqueros). El número
del jugador se imprime en tiempo de ejecución, grande en la espalda y chico en el pecho, con
borde, en los colores `number` / `number_outline` del kit.

## Próximos pasos

1. Un `PLAYER_MASTER.blend` esculpido a mano puede reemplazar las primitivas manteniendo los
   contratos. El generador ya resuelve la ropa, el skinning, el UV y la exportación.
2. Animaciones hechas a mano o capturadas, con los mismos nombres y tiempos.
3. Nombre en la espalda (hoy solo número) y escudo en el pecho.
4. Editor de jugadores in-game a partir de `ModelPreview`, que escribe recetas JSON.
