# Pipeline de assets

No copiamos modelos: reconstruimos la **receta**. Un PLAYER_MASTER más una biblioteca chica de
componentes produce muchos jugadores, y la camiseta es una textura sobre el mismo modelo.

```
data/appearance/player_XXX.json ─┐
data/appearance/components.json ─┼─► tools/asset_pipeline/player_generator.py (Blender)
data/animation/clips.json ───────┘              │
                                                ▼
                               assets/players/generated/player_XXX.glb
                               (malla + esqueleto + 13 clips)
data/kits/*.json ──► tools/asset_pipeline/kit_generator.py ──► assets/kits/*.png
                                                │
                                                ▼
                        Godot: PlayerModel → kit por material → AnimationTree
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
  `.L/.R`. Skinning rígido por pieza, que es robusto, barato y fiel a la época.
- **Materiales por nombre.** `SKIN, KIT_SHIRT, KIT_SHORTS, KIT_SOCKS, BOOTS, HAIR, EYES`. Godot
  reemplaza los `KIT_*` con el kit del equipo.
- **UV de camiseta.** Proyección cilíndrica alrededor del torso: `u` 0.5 = pecho, 0/1 = espalda,
  `v` 0 = ruedo, 1 = cuello. Cualquier textura de 1024² que respete eso sirve para todos los
  jugadores, sea generada (`plain, stripes, hoops, halves, sash`) o pintada a mano.
- **Clips.** Nombres y duraciones en `data/animation/clips.json`, el mismo archivo del que el
  gameplay lee las ventanas de patada. `contact` = frame de contacto con la pelota.
- **Look.** Material de pocas capas: color base, rugosidad alta y especular moderado. La luz, el
  SSAO, el grading y la **cámara** viven en `data/look/we2002_hd.json`.

## Estado y próximos pasos

PLAYER_001 hoy tiene unos 4k triángulos de primitivas paramétricas. Es un sustituto con el
esqueleto, la animación y los contratos finales. El objetivo artístico sigue siendo
cuerpo 20k–35k, cabeza 5k–10k, pelo 2k–8k y botines 1k–3k. El camino:

1. Esculpir en Blender un `PLAYER_MASTER.blend` real con el mismo esqueleto, los mismos
   nombres de material y el UV de camiseta respetando el contrato. El generador pasa a
   ensamblar variantes (cuerpo/cara/pelo/botín) de ese archivo en lugar de primitivas.
2. Reemplazar las animaciones procedurales por clips hechos a mano o capturados, con los mismos
   nombres y tiempos. El gameplay no cambia.
3. Números y nombres en la espalda: una textura por jugador, derivada del kit.
4. Editor de jugadores in-game a partir de `ModelPreview`, que escribe recetas JSON.
