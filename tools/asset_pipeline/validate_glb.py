"""Checks a player GLB against the game's contracts, in plain Spanish.

    python tools/asset_pipeline/validate_glb.py assets/players/custom/player_001.glb
    blender -b -P tools/asset_pipeline/validate_glb.py -- assets/players/custom/player_001.glb

Run it after every export from Blender. It tells you what will break in the
game and why, so you can fix it without guessing.
"""

import json
import os
import sys

import bpy  # noqa: I001
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from player_generator import SKELETON  # noqa: E402

MATERIALS_REQUIRED = {"KIT_SHIRT", "KIT_SHORTS", "KIT_SOCKS"}
MATERIALS_KNOWN = {"SKIN", "FACE", "KIT_SHIRT", "KIT_SHORTS", "KIT_SOCKS", "BOOTS", "HAIR", "EYES"}
TRIS_WARN = 40000


def main(path):
    errors, warnings, info = [], [], []
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)

    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.data.vertices and o.name != "Icosphere"]
    if len(arms) != 1:
        errors.append(f"Tiene que haber exactamente un esqueleto (Armature); hay {len(arms)}.")
    else:
        bones = {b.name for b in arms[0].data.bones}
        missing = [b for b in SKELETON if b not in bones]
        if missing:
            errors.append("Faltan huesos (o tienen otro nombre): " + ", ".join(missing)
                          + ". Los nombres tienen que ser exactamente iguales, con .L / .R.")
        extra = sorted(bones - set(SKELETON))
        if extra:
            info.append("Huesos extra (se ignoran, no molestan): " + ", ".join(extra[:10]))

    # Size and orientation (rest pose).
    pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    if pts:
        zmin, zmax = min(p.z for p in pts), max(p.z for p in pts)
        height = zmax - zmin
        info.append(f"Altura: {height:.2f} m (pies en z={zmin:.2f})")
        if not 1.5 < height < 2.2:
            errors.append(f"La altura es {height:.2f} m: tiene que estar entre 1,5 y 2,2 m. "
                          "¿Escalaste en centímetros? En Blender, escala 1 = 1 metro.")
        if abs(zmin) > 0.05:
            warnings.append(f"Los pies no están en el piso (z mínima {zmin:.2f}). Bajá el modelo a z=0.")
        if arms:
            nose = [p for p in pts if p.z > zmin + height * 0.85]
            if nose:
                front = sum(p.y for p in nose) / len(nose)
                info.append("Orientación: mira hacia -Y (correcto)" if front < 0.02 else "")
        cx = sum(p.x for p in pts) / len(pts)
        if abs(cx) > 0.05:
            warnings.append(f"El modelo no está centrado en X (centro {cx:.2f}).")

    # Materials.
    mats = {m.name.split(".")[0] for o in meshes for m in o.data.materials if m}
    for m in sorted(MATERIALS_REQUIRED - mats):
        errors.append(f"Falta el material '{m}': sin él no se puede poner la camiseta del equipo.")
    unknown = sorted(mats - MATERIALS_KNOWN)
    if unknown:
        warnings.append("Materiales con nombres que el juego no conoce (se verán con su color fijo): " + ", ".join(unknown))
    for o in meshes:
        if any(m and m.name.startswith("KIT_SHIRT") for m in o.data.materials) and not o.data.uv_layers:
            errors.append(f"'{o.name}' usa KIT_SHIRT pero no tiene UV: la camiseta no se va a ver.")
        if not o.vertex_groups:
            errors.append(f"'{o.name}' no tiene pesos (vertex groups): no se va a mover con el esqueleto.")

    # Shirt variants.
    names = {o.name for o in meshes}
    if not ({"Shirt_Short", "Shirt_Long"} & names):
        warnings.append("No hay objetos 'Shirt_Short' / 'Shirt_Long': las mangas no van a cambiar según la camiseta.")

    # Triangles.
    tris = sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)
    info.append(f"Triángulos: {tris}")
    if tris > TRIS_WARN:
        warnings.append(f"{tris} triángulos es mucho para 22 jugadores en cancha (sugerido < {TRIS_WARN}).")

    # Animations vs data/animation/clips.json.
    with open(os.path.join(ROOT, "data", "animation", "clips.json"), encoding="utf-8") as f:
        clips = json.load(f)
    fps = clips["fps"]
    actions = {a.name: a for a in bpy.data.actions}
    for name, spec in clips["clips"].items():
        found = next((a for n, a in actions.items() if n == name or n.startswith(name + "_") or n.endswith("|" + name)), None)
        if found is None:
            warnings.append(f"Falta la animación '{name}' ({spec['length']} s): se va a ver quieto en ese momento.")
            continue
        # The importer converts seconds to frames at the scene's frame rate.
        length = (found.frame_range[1] - found.frame_range[0]) / bpy.context.scene.render.fps
        if abs(length - spec["length"]) > 0.08:
            warnings.append(f"'{name}' dura {length:.2f} s y el juego espera {spec['length']} s "
                            f"({round(spec['length'] * fps)} cuadros a {fps} fps).")
    info.append(f"Animaciones encontradas: {len(actions)}")

    print("\n=== " + os.path.basename(path) + " ===")
    for line in info:
        if line:
            print("  ·", line)
    for w in warnings:
        print("  ⚠ ", w)
    for e in errors:
        print("  ✗ ", e)
    print("\nRESULTADO:", "LISTO PARA EL JUEGO ✓" if not errors else f"{len(errors)} PROBLEMA(S) A CORREGIR")
    return 0 if not errors else 1


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    sys.exit(main(os.path.abspath(args[0])))
