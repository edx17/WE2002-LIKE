"""PLAYER_MASTER generator: recipe JSON -> rigged, animated GLB.

    blender -b -P tools/asset_pipeline/player_generator.py -- player_001 [player_002 ...]
    python  tools/asset_pipeline/player_generator.py player_001        (with the `bpy` module)
    ... -- --all                                                        (every recipe in data/appearance)

Two styles, chosen per recipe ("style") with a default in components.json:

  classic (default)  the original WE2002 design: boxy low-poly lofts (~2k
                     tris), trapezoid shirt, very wide shorts, painted face,
                     matte materials, unfiltered low-res textures
                     (classic_builder.py)
  modern             the sculpted look described below (sculpt.py)

Modern: one master body is sculpted from parametric anatomy (body type, face, hair,
boots, skin) over a shared skeleton, so a small library produces many
different players (see sculpt.py):

    Body         one continuous organic surface, neck to toe (voxel-fused)
    Head         finer voxel so nose, brow, jaw and ears survive
    Shirt_Short  loose shell with hem, collar and short sleeves
    Shirt_Long   same with long sleeves (goalkeepers / winter kits)
    Shorts       loose shell, open at the waist and legs
    Boots        low-cut shells
    Hair         stylised volume cut along a hairline
    Face         eyes and brows

The kit is NOT baked into the player. Shirt, shorts and socks get the
KIT_SHIRT / KIT_SHORTS / KIT_SOCKS materials and Godot swaps in the team's
kit texture (with the player's number) at runtime: one model, every team.

Animation timings come from data/animation/clips.json, the same file the
gameplay reads for kick windows and state durations.

Conventions: Blender Z-up, character faces -Y, feet at the origin.
"""

import json
import math
import os
import sys

import bpy  # noqa: I001 - must come first: it provides bmesh/mathutils
import bmesh
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sculpt import (Capsule, Ellipsoid, cut, cylindrical_uv, fuse, join, nearest,  # noqa: E402
                    planar_uv, skin, transfer_weights, tris)
import classic_builder  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "data")
OUT_DIR = os.path.join(ROOT, "assets", "players", "generated")

BASE_HEIGHT = 1.80


def load_json(*parts):
    with open(os.path.join(DATA, *parts), encoding="utf-8") as f:
        return json.load(f)


def hex_color(h, alpha=1.0):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    # Blender material colors are linear.
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, alpha)


# --- skeleton ------------------------------------------------------------------

# name: (head, tail, parent) at the 1.80 m reference. L = +X (character's left).
SKELETON = {
    "Hips":       ((0, 0, 0.95), (0, 0, 1.05), None),
    "Spine":      ((0, 0, 1.05), (0, 0, 1.25), "Hips"),
    "Chest":      ((0, 0, 1.25), (0, 0, 1.45), "Spine"),
    "Neck":       ((0, 0, 1.45), (0, 0, 1.55), "Chest"),
    "Head":       ((0, 0, 1.55), (0, 0, 1.80), "Neck"),
    "UpperArm.L": ((0.21, 0, 1.42), (0.24, 0, 1.15), "Chest"),
    "LowerArm.L": ((0.24, 0, 1.15), (0.25, 0, 0.90), "UpperArm.L"),
    "Hand.L":     ((0.25, 0, 0.90), (0.25, 0, 0.80), "LowerArm.L"),
    "UpperLeg.L": ((0.10, 0, 0.93), (0.10, 0, 0.52), "Hips"),
    "LowerLeg.L": ((0.10, 0, 0.52), (0.10, 0, 0.10), "UpperLeg.L"),
    "Foot.L":     ((0.10, 0, 0.10), (0.10, -0.16, 0.03), "LowerLeg.L"),
}
for _name in [n for n in SKELETON if n.endswith(".L")]:
    _h, _t, _p = SKELETON[_name]
    SKELETON[_name.replace(".L", ".R")] = (
        (-_h[0], _h[1], _h[2]), (-_t[0], _t[1], _t[2]), _p.replace(".L", ".R") if _p and _p.endswith(".L") else _p)


# --- anatomy -------------------------------------------------------------------------
#
# Reference: modern-proportioned footballer (~7.5 heads), broad shoulders,
# athletic legs, as seen from the broadcast camera. All values at 1.80 m;
# body type / weight scale girth, the recipe height scales everything.

MATERIALS = ["SKIN", "KIT_SHIRT", "KIT_SHORTS", "KIT_SOCKS", "BOOTS", "HAIR", "EYES"]

SOCK_TOP = 0.47
SHIRT_HEM = 0.96
SHORTS_TOP = 1.02
SHORTS_HEM = 0.66
BOOT_TOP = 0.115


def anatomy(recipe, lib):
    body = lib["body_types"][recipe["body"]]
    face = lib["faces"][recipe["face"]]
    boot = lib["boots"][recipe["boot"]]
    bmi = recipe["weight"] / (recipe["height"] ** 2)
    girth = max(0.88, min(1.18, (bmi / 23.0) ** 0.5))
    sh, ch, wa, li = (body["shoulders"] * girth, body["chest"] * girth, body["waist"] * girth, body["limbs"] * girth)

    P = {}  # region -> primitives
    P["torso"] = [
        Ellipsoid((0, 0.012, 0.95), (0.158 * wa, 0.105, 0.11), "Hips", "pelvis"),
        Ellipsoid((0, 0, 1.09), (0.142 * wa, 0.092, 0.13), "Spine", "waist"),
        Ellipsoid((0, -0.004, 1.27), (0.163 * ch, 0.104, 0.15), "Chest", "ribs"),
        Ellipsoid((0.062, -0.058, 1.33), (0.072 * ch, 0.042, 0.062), "Chest", "pec"),
        Ellipsoid((-0.062, -0.058, 1.33), (0.072 * ch, 0.042, 0.062), "Chest", "pec"),
        Capsule((-0.17 * sh, 0.012, 1.428), (0.17 * sh, 0.012, 1.428), 0.066, 0.066, "Chest", "traps"),
    ]
    P["glutes"] = [Ellipsoid((x, 0.05, 0.9), (0.082 * wa, 0.075, 0.09), "Hips", "glute") for x in (-0.074, 0.074)]
    P["neck"] = [Capsule((0, 0.008, 1.43), (0, 0.0, 1.585), 0.062, 0.054, "Neck", "neck")]
    P["head"] = [
        Ellipsoid((0, 0.014, 1.69), (0.087 * face["cheeks"], 0.102, 0.112), "Head", "cranium"),
        Ellipsoid((0, -0.028, 1.632), (0.07 * face["jaw"], 0.074, 0.07), "Head", "jaw"),
        Ellipsoid((0, -0.07, 1.585), (0.034 * face["jaw"], 0.03, 0.03), "Head", "chin"),
        Ellipsoid((0, -0.097, 1.652), (0.015, 0.024 * face["nose"], 0.03 * face["nose"]), "Head", "nose", rot=(18, 0, 0)),
        Ellipsoid((0, -0.082, 1.706), (0.068 * face["brow"], 0.026, 0.018), "Head", "brow"),
        Ellipsoid((0.046, -0.07, 1.655), (0.03, 0.026, 0.024), "Head", "cheek"),
        Ellipsoid((-0.046, -0.07, 1.655), (0.03, 0.026, 0.024), "Head", "cheek"),
        Ellipsoid((0.087, 0.01, 1.665), (0.013, 0.026, 0.033), "Head", "ear"),
        Ellipsoid((-0.087, 0.01, 1.665), (0.013, 0.026, 0.033), "Head", "ear"),
    ]
    for side, sx in (("L", 1), ("R", -1)):
        P["delt." + side] = [Ellipsoid((0.202 * sx * sh, 0, 1.39), (0.068 * li, 0.072, 0.082), f"UpperArm.{side}", "delt")]
        P["upperarm." + side] = [
            Capsule((0.208 * sx * sh, 0, 1.39), (0.232 * sx * sh, 0.004, 1.16), 0.057 * li, 0.046 * li, f"UpperArm.{side}", "upperarm"),
            Ellipsoid((0.222 * sx * sh, -0.018, 1.285), (0.046 * li, 0.05 * li, 0.085), f"UpperArm.{side}", "biceps"),
        ]
        P["forearm." + side] = [
            Capsule((0.234 * sx * sh, 0.004, 1.15), (0.246 * sx * sh, -0.004, 0.925), 0.047 * li, 0.032, f"LowerArm.{side}", "forearm"),
        ]
        P["hand." + side] = [
            Ellipsoid((0.25 * sx * sh, -0.004, 0.858), (0.021, 0.04, 0.058), f"Hand.{side}", "hand"),
            Ellipsoid((0.244 * sx * sh, -0.034, 0.878), (0.012, 0.014, 0.03), f"Hand.{side}", "thumb", rot=(-20, 0, 0)),
        ]
        P["thigh." + side] = [
            Capsule((0.094 * sx, 0.004, 0.93), (0.1 * sx, -0.004, 0.53), 0.09 * li, 0.06 * li, f"UpperLeg.{side}", "thigh"),
            Ellipsoid((0.102 * sx, -0.03, 0.72), (0.072 * li, 0.062 * li, 0.15), f"UpperLeg.{side}", "quad"),
        ]
        P["shin." + side] = [
            Ellipsoid((0.1 * sx, -0.018, 0.515), (0.05, 0.05, 0.05), f"LowerLeg.{side}", "knee"),
            Ellipsoid((0.1 * sx, 0.028, 0.37), (0.058 * li, 0.06 * li, 0.115), f"LowerLeg.{side}", "calf"),
            Capsule((0.1 * sx, 0.0, 0.5), (0.1 * sx, 0.006, 0.09), 0.048 * li, 0.031, f"LowerLeg.{side}", "shin"),
        ]
        blen = boot["length"]
        P["foot." + side] = [
            Ellipsoid((0.1 * sx, -0.062 * blen, 0.042), (0.043, 0.118 * blen, 0.042), f"Foot.{side}", "foot"),
            Ellipsoid((0.1 * sx, 0.018, 0.052), (0.037, 0.04, 0.048), f"Foot.{side}", "heel"),
        ]
    return P


def group(P, *keys):
    out = []
    for k in keys:
        out += P[k + ".L"] + P[k + ".R"] if k + ".L" in P else P[k]
    return out


def build_meshes(recipe, lib, scale):
    """Returns [(name, mesh, prims_for_skinning, material_names, rigid_bone)].
    "Body" must come first: clothes copy their skin weights from it."""
    s = scale
    A = {k: [p.scaled(s) for p in v] for k, v in anatomy(recipe, lib).items()}
    all_prims = [p for v in A.values() for p in v]
    body_prims = [p for k, v in A.items() if k != "head" for p in v]
    out = []

    # Body (neck down): one continuous organic surface.
    body = fuse("Body", body_prims, voxel=0.009 * s, max_tris=30000)
    _assign_body_materials(body, body_prims, s)
    out.append(("Body", body, body_prims, ["SKIN", "KIT_SOCKS", "BOOTS"], None))

    # Head: finer voxel so the face keeps its features. Its neck sleeve sits
    # 1.5 mm outside the body's neck to hide the joint.
    head_prims = A["head"] + [p.inflated(0.0015 * s) for p in A["neck"]]
    head = fuse("Head", head_prims, voxel=0.004 * s, smooth=(0.5, 3), max_tris=9000)
    cut(head, lambda co: 1.485 * s - co.z)
    out.append(("Head", head, head_prims + A["torso"], ["SKIN"], None))

    # Shirt: torso shell + one tube per sleeve (separate shells, so no web
    # between arm and torso), cut open at hem, collar and cuffs.
    torso = fuse("Shirt_Torso", [p.inflated(0.02 * s) for p in A["torso"] + A["glutes"]]
                 + [p.inflated(0.016 * s) for p in group(A, "delt")], voxel=0.011 * s, smooth=(0.6, 10), max_tris=6000)

    def torso_sdf(co):
        f = SHIRT_HEM * s - co.z
        if co.z > 1.43 * s:
            f = max(f, 0.075 * s - math.hypot(co.x, co.y + 0.005 * s))
        return f
    cut(torso, torso_sdf)
    for sleeves, parts, cut_t in (("Short", ("upperarm",), 0.55), ("Long", ("upperarm", "forearm"), 0.93)):
        meshes = [torso.copy()]
        for side in ("L", "R"):
            arm = []
            for part in parts:
                arm += [p.inflated(0.014 * s, 0.02 * s) if isinstance(p, Capsule) else p.inflated(0.012 * s)
                        for p in A[f"{part}.{side}"]]
            tube = fuse(f"Sleeve_{side}", arm, voxel=0.009 * s, smooth=(0.6, 8), max_tris=1800)
            cap = [p for p in arm if isinstance(p, Capsule)][-1]
            axis = cap.b - cap.a
            end = cap.a + axis * (cut_t if len(parts) == 1 or cap.region == parts[-1] else 1.0)
            cut(tube, lambda co, end=end, n=axis.normalized(): (co - end).dot(n))
            meshes.append(tube)
        shirt = join(f"Shirt_{sleeves}", meshes)
        cylindrical_uv(shirt, SHIRT_HEM * s, 1.5 * s,
                       collar=lambda co: co.z > 1.44 * s and math.hypot(co.x, co.y + 0.005 * s) < 0.092 * s)
        out.append((f"Shirt_{sleeves}", shirt, all_prims, ["KIT_SHIRT"], None))
    bpy.data.meshes.remove(torso)

    # Shorts: loose around pelvis and thighs, open at waist and legs.
    shorts_prims = [A["torso"][0].inflated(0.022 * s), A["torso"][1].inflated(0.016 * s)]
    shorts_prims += [p.inflated(0.022 * s) for p in A["glutes"]]
    shorts_prims += [p.inflated(0.02 * s, 0.034 * s) if isinstance(p, Capsule) else p.inflated(0.024 * s)
                     for p in group(A, "thigh")]
    shorts = fuse("Shorts", shorts_prims, voxel=0.01 * s, smooth=(0.6, 10), max_tris=7000)
    cut(shorts, lambda co: max(co.z - SHORTS_TOP * s, SHORTS_HEM * s - co.z))
    planar_uv(shorts)
    out.append(("Shorts", shorts, all_prims, ["KIT_SHORTS"], None))

    # Boots: low-cut shells over the feet.
    boots = fuse("Boots", [p.inflated(0.009 * s) for p in group(A, "foot")], voxel=0.006 * s, max_tris=3000)
    cut(boots, lambda co: co.z - BOOT_TOP * s)
    planar_uv(boots)
    out.append(("Boots", boots, all_prims, ["BOOTS"], None))

    hair = build_hair(recipe["hair"], A["head"], s)
    if hair is not None:
        out.append(("Hair", hair, all_prims, ["HAIR"], "Head"))
    out.append(("Face", build_face(lib["faces"][recipe["face"]], s), all_prims, ["EYES", "HAIR"], "Head"))
    return out


def _assign_body_materials(mesh, prims, s):
    """Socks are painted on the shins (tight fabric); feet are hidden by boots."""
    socks, boots = MATERIALS_BODY.index("KIT_SOCKS"), MATERIALS_BODY.index("BOOTS")
    for poly in mesh.polygons:
        c = poly.center
        bone = nearest(prims, c).bone
        if bone.startswith("Foot") or c.z < BOOT_TOP * 0.8 * s:
            poly.material_index = boots
        elif bone.startswith("LowerLeg") and c.z < SOCK_TOP * s:
            poly.material_index = socks
        poly.use_smooth = True


MATERIALS_BODY = ["SKIN", "KIT_SOCKS", "BOOTS"]


def build_hair(style, head, s):
    """Stylised hair volumes (no strands) cut along a hairline."""
    if style == 0:
        return None
    cranium = head[0]
    thick = {1: 0.011, 2: 0.006, 3: 0.014, 4: 0.04, 5: 0.008}[style] * s
    prims = [cranium.inflated(thick)]
    if style == 3:  # long: volume down the back of the neck
        prims.append(Ellipsoid(cranium.c + Vector((0, 0.05, -0.085)) * s, Vector((0.085, 0.06, 0.1)) * s, "Head"))
    if style == 4:  # afro: a round volume sitting high on the head
        prims = [cranium.inflated(0.02 * s),
                 Ellipsoid(cranium.c + Vector((0, 0.018, 0.05)) * s, Vector((0.122, 0.13, 0.105)) * s, "Head")]
    mesh = fuse("Hair", prims, voxel=0.006 * s, smooth=(0.5, 3), max_tris=7000)
    cz, cy = cranium.c.z, cranium.c.y

    def hairline_sdf(co):
        rel_z, rel_y = (co.z - cz) / s, (co.y - cy) / s
        # Hairline: high on the forehead, lower at the back, above the ears.
        front = min(1.0, max(0.0, -rel_y) / 0.1)
        line = 0.035 * front - 0.06 * (1 - front)
        if abs(co.x) > 0.072 * s and rel_y < 0.03:
            line = max(line, -0.005)  # sideburns stop above the ears
        if style == 3:
            line -= 0.06 * max(0.0, rel_y / 0.1)
        if style == 4:
            line = 0.03 * front - 0.02 * (1 - front)
        f = (line - rel_z) * s
        if style == 5:
            f = max(f, abs(co.x) - 0.026 * s)  # mohawk strip
        return f
    cut(mesh, hairline_sdf)
    planar_uv(mesh)
    return mesh


def build_face(face, s):
    """Eyes and brows: tiny separate pieces so they stay crisp."""
    bm = bmesh.new()
    for x in (-0.034, 0.034):
        e = Ellipsoid((x, -0.083, 1.678), (0.012, 0.007, 0.0085), "Head")
        e.scaled(s).add_to(bm)
    eyes_count = len(bm.faces)
    for x in (-0.035, 0.035):
        b = Ellipsoid((x, -0.095, 1.703), (0.024 * face["brow"], 0.007, 0.0055), "Head", rot=(0, 0, -7 if x > 0 else 7))
        b.scaled(s).add_to(bm)
    bm.faces.ensure_lookup_table()
    for i, f in enumerate(bm.faces):
        f.material_index = 0 if i < eyes_count else 1
        f.smooth = True
    mesh = bpy.data.meshes.new("Face")
    bm.to_mesh(mesh)
    bm.free()
    planar_uv(mesh)
    return mesh


def make_materials(recipe, lib, classic=False):
    """The 'look' recipe. Modern: flat-ish colour, high roughness, moderate
    specular. Classic (WE2002): fully matte, no specular, painted face."""
    colors = {
        "SKIN": hex_color(lib["skin_tones"][recipe["skin"]]),
        "KIT_SHIRT": hex_color("#bbbbbb"),
        "KIT_SHORTS": hex_color("#eeeeee"),
        "KIT_SOCKS": hex_color("#bbbbbb"),
        "BOOTS": hex_color(recipe.get("boot_color", "#111111")),
        "HAIR": hex_color(lib["hair_colors"][recipe["hair_color"]]),
        "EYES": hex_color("#161210"),
        "FACE": hex_color("#ffffff"),
    }
    roughness = {"SKIN": 0.62, "KIT_SHIRT": 0.82, "KIT_SHORTS": 0.8, "KIT_SOCKS": 0.88, "BOOTS": 0.32,
                 "HAIR": 0.8, "EYES": 0.25, "FACE": 0.62}
    mats = {}
    for name in MATERIALS + ["FACE"]:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = colors[name]
        bsdf.inputs["Roughness"].default_value = 1.0 if classic else roughness[name]
        bsdf.inputs["Specular IOR Level"].default_value = 0.0 if classic else 0.35
        if name == "FACE":
            face = lib["faces"][recipe["face"]]
            img = classic_builder.face_image(
                f"face_{recipe['id']}", lib["skin_tones"][recipe["skin"]],
                lib["hair_colors"][recipe["hair_color"]], face, recipe.get("facial_hair", 0))
            tex = m.node_tree.nodes.new("ShaderNodeTexImage")
            tex.image = img
            tex.interpolation = "Closest"
            m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        mats[name] = m
    return mats


def build_armature(scale):
    arm_data = bpy.data.armatures.new("Skeleton")
    arm = bpy.data.objects.new("Skeleton", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (head, tail, parent) in SKELETON.items():
        eb = arm_data.edit_bones.new(name)
        eb.head = Vector(head) * scale
        eb.tail = Vector(tail) * scale
        eb.roll = 0.0
        if parent:
            eb.parent = arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# --- animation -----------------------------------------------------------------------
#
# Poses are authored in armature space with intuitive signs, then converted to
# each bone's local frame:
#   X rotation: legs/arms  -  = swing forward,  + = swing back
#               spine/head +  = lean forward
#               lower leg  +  = knee bend,  lower arm - = elbow bend
#   Y rotation: side lean.  Z rotation: twist.
#   Hips offset: armature-space metres (z = up, -y = forward).

def to_local(pbone, rot_deg):
    b = pbone.bone.matrix_local.to_3x3()
    r = Euler([math.radians(a) for a in rot_deg], "XYZ").to_matrix()
    return (b.inverted() @ r @ b).to_quaternion()


def locomotion(t, stride, knee, arm, elbow, lean, bounce):
    p = 2 * math.pi * t
    s, c = math.sin(p), math.cos(p)
    pose = {
        "UpperLeg.L": (-stride * s, 0, 0),
        "UpperLeg.R": (stride * s, 0, 0),
        "LowerLeg.L": (knee * (0.25 + 0.75 * max(0.0, c)), 0, 0),
        "LowerLeg.R": (knee * (0.25 + 0.75 * max(0.0, -c)), 0, 0),
        "Foot.L": (-0.3 * stride * s, 0, 0),
        "Foot.R": (0.3 * stride * s, 0, 0),
        "UpperArm.L": (arm * s, -8, 0),
        "UpperArm.R": (-arm * s, 8, 0),
        "LowerArm.L": (-elbow, 0, 0),
        "LowerArm.R": (-elbow, 0, 0),
        "Spine": (lean, 0, 4 * s),
        "Chest": (lean * 0.3, 0, -8 * s),
        "Neck": (-lean * 0.8, 0, 0),
        "Hips": (0, 0, -5 * s),
    }
    return pose, (0, 0, -bounce * (0.5 + 0.5 * math.cos(2 * p)))


def kick(t, contact, power, header=False):
    """Right-foot strike: back-swing, snap through the ball at `contact`, follow through."""
    if header:
        u = min(t / contact, 1.0)
        after = max(0.0, (t - contact) / (1 - contact))
        nod = 25 * u - 45 * min(after * 3, 1.0) * (1 - after)
        return {"Spine": (-10 * u + 20 * after, 0, 0), "Neck": (nod, 0, 0), "Head": (nod * 0.5, 0, 0),
                "UpperArm.L": (-30, -35, 0), "UpperArm.R": (-30, 35, 0),
                "UpperLeg.L": (-20 * u, 0, 0), "LowerLeg.L": (40 * u, 0, 0),
                "UpperLeg.R": (10 * u, 0, 0), "LowerLeg.R": (60 * u, 0, 0)}, \
            (0, 0, 0.25 * math.sin(math.pi * min(t / (contact + 0.25), 1.0)))
    if t < contact:
        u = t / contact
        thigh, knee_b = 35 * power * u, 95 * u
    else:
        u = (t - contact) / (1 - contact)
        thigh = 35 * power - (35 * power + 75 * power) * min(u * 2.5, 1.0) + 60 * power * max(0.0, u - 0.4)
        knee_b = 95 * (1 - min(u * 4, 1.0)) + 20 * max(0.0, u - 0.5)
    lean_back = -12 * power * math.sin(math.pi * min(t / (contact * 2), 1.0))
    pose = {
        "UpperLeg.R": (thigh, 0, 0), "LowerLeg.R": (knee_b, 0, 0), "Foot.R": (15, 0, 0),
        "UpperLeg.L": (-12, 0, 0), "LowerLeg.L": (25, 0, 0),
        "UpperArm.L": (-25, -40 * power, 0), "UpperArm.R": (25, 30 * power, 0),
        "LowerArm.L": (-30, 0, 0), "LowerArm.R": (-30, 0, 0),
        "Spine": (lean_back + 8, 0, -15 * power * (1 - t)), "Chest": (0, 0, -10 * power * (1 - t)),
    }
    return pose, (0, 0, -0.04 * math.sin(math.pi * t))


def clip_pose(name, t, spec):
    if name == "IDLE":
        b = math.sin(2 * math.pi * t)
        return {"Chest": (2 * b, 0, 0), "Spine": (3, 1.5 * b, 0), "UpperArm.L": (0, -6, 0), "UpperArm.R": (0, 6, 0),
                "LowerArm.L": (-15, 0, 0), "LowerArm.R": (-15, 0, 0), "LowerLeg.L": (8, 0, 0), "LowerLeg.R": (8, 0, 0),
                "UpperLeg.L": (-4, 0, 0), "UpperLeg.R": (-4, 0, 0)}, (0, 0, -0.02 + 0.006 * b)
    if name == "WALK":
        return locomotion(t, 22, 30, 15, 15, 3, 0.02)
    if name == "RUN":
        return locomotion(t, 42, 75, 38, 70, 10, 0.05)
    if name == "SPRINT":
        return locomotion(t, 55, 95, 55, 85, 17, 0.06)
    if name in ("PASS", "SHOOT"):
        return kick(t, spec["contact"] / spec["length"], 0.6 if name == "PASS" else 1.0)
    if name == "HEAD":
        return kick(t, spec["contact"] / spec["length"], 1.0, header=True)
    if name == "TACKLE":
        u = math.sin(math.pi * min(t / 0.6, 1.0))
        return {"UpperLeg.R": (-55 * u, 0, -20 * u), "LowerLeg.R": (10, 0, 0), "UpperLeg.L": (20 * u, 0, 0),
                "LowerLeg.L": (70 * u, 0, 0), "Spine": (25 * u, 0, 0), "UpperArm.L": (-20, -40 * u, 0),
                "UpperArm.R": (10, 40 * u, 0)}, (0, -0.15 * u, -0.22 * u)
    if name == "SLIDE":
        u = min(t / 0.15, 1.0)
        return {"Hips": (-60 * u, 0, 0), "Spine": (20 * u, 0, 0), "UpperLeg.R": (-35 * u, 0, 0),
                "UpperLeg.L": (10 * u, 0, 0), "LowerLeg.L": (110 * u, 0, 0), "UpperArm.L": (-10, -60 * u, 0),
                "UpperArm.R": (-10, 60 * u, 0), "Neck": (20 * u, 0, 0)}, (0, 0.1 * u, -0.72 * u)
    if name == "FALL":
        u = min(t / 0.55, 1.0) ** 2
        return {"Hips": (85 * u, 0, 0), "UpperArm.L": (-120 * u, -20, 0), "UpperArm.R": (-120 * u, 20, 0),
                "LowerLeg.L": (30 * u, 0, 0), "LowerLeg.R": (20 * u, 0, 0), "Neck": (-40 * u, 0, 0)}, \
            (0, -0.35 * u, -0.8 * u)
    if name == "GET_UP":
        u = 1 - t
        return {"Hips": (60 * u, 0, 0), "UpperLeg.L": (-80 * u, 0, 0), "LowerLeg.L": (120 * u, 0, 0),
                "UpperLeg.R": (-20 * u, 0, 0), "LowerLeg.R": (90 * u, 0, 0), "UpperArm.L": (-60 * u, -15, 0),
                "UpperArm.R": (-60 * u, 15, 0)}, (0, -0.2 * u, -0.6 * u)
    if name == "TURN_180":
        u = math.sin(math.pi * t)
        return {"Hips": (0, 0, 60 * u), "Spine": (10, 0, 30 * u), "UpperLeg.L": (-30 * u, 0, 0),
                "LowerLeg.L": (50 * u, 0, 0), "LowerLeg.R": (30 * u, 0, 0),
                "UpperArm.L": (-20 * u, -30 * u, 0), "UpperArm.R": (20 * u, 30 * u, 0)}, (0, 0, -0.08 * u)
    if name in ("DIVE_LEFT", "DIVE_RIGHT"):
        # Goalkeeper dive: body lays out sideways, arms stretched over the head.
        sx = 1 if name == "DIVE_LEFT" else -1
        u = math.sin(math.pi * 0.5 * min(t / 0.45, 1.0))
        return {"Hips": (0, 78 * u * sx, 0), "UpperArm.L": (-170 * u, -10 * sx, 0), "UpperArm.R": (-170 * u, -10 * sx, 0),
                "LowerArm.L": (-10, 0, 0), "LowerArm.R": (-10, 0, 0), "UpperLeg.L": (-15 * u, 0, 10 * sx * u),
                "UpperLeg.R": (10 * u, 0, 10 * sx * u), "LowerLeg.L": (25 * u, 0, 0), "Neck": (0, -20 * sx * u, 0)}, \
            (0.45 * u * sx, 0, -0.62 * u)
    if name == "CELEBRATE":
        j = abs(math.sin(2 * math.pi * t))
        return {"UpperArm.L": (-165, -25, 0), "UpperArm.R": (-165, 25, 0), "LowerArm.L": (-20, 0, 0),
                "LowerArm.R": (-20, 0, 0), "Neck": (-15, 0, 0), "LowerLeg.L": (30 * j, 0, 0),
                "LowerLeg.R": (30 * j, 0, 0)}, (0, 0, 0.18 * j)
    raise KeyError(name)


def build_actions(arm, scale, clips):
    fps = clips["fps"]
    bpy.context.scene.render.fps = fps
    arm.animation_data_create()
    hips_rest = arm.pose.bones["Hips"].bone.matrix_local.to_3x3()
    for name, spec in clips["clips"].items():
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        arm.animation_data.action = action
        frames = max(2, round(spec["length"] * fps))
        for f in range(frames + 1):
            t = f / frames
            pose, hips_offset = clip_pose(name, t, spec)
            for pb in arm.pose.bones:
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = to_local(pb, pose.get(pb.name, (0, 0, 0)))
                pb.keyframe_insert("rotation_quaternion", frame=f + 1)
            hips = arm.pose.bones["Hips"]
            hips.location = hips_rest.inverted() @ (Vector(hips_offset) * scale)
            hips.keyframe_insert("location", frame=f + 1)
    arm.animation_data.action = bpy.data.actions["IDLE"]


# --- entry point ------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def generate(recipe_id):
    reset_scene()
    recipe = load_json("appearance", f"{recipe_id}.json")
    lib = load_json("appearance", "components.json")
    clips = load_json("animation", "clips.json")
    scale = recipe["height"] / BASE_HEIGHT

    style = recipe.get("style", lib.get("default_style", "classic"))
    arm = build_armature(scale)
    skeleton = {n: (Vector(h) * scale, Vector(t) * scale, p) for n, (h, t, p) in SKELETON.items()}
    mats = make_materials(recipe, lib, classic=style == "classic")
    report = []
    if style == "classic":
        _add_classic(recipe, lib, scale, arm, mats, report)
    else:
        _add_modern(recipe, lib, scale, arm, skeleton, mats, report)

    build_actions(arm, scale, clips)

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f"{recipe_id}.glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_animations=True,
        export_animation_mode="ACTIONS", export_force_sampling=True,
        export_apply=False, export_yup=True)
    print(f"[player_generator] {recipe_id} ({style}): {', '.join(report)} tris; {len(clips['clips'])} clips -> "
          f"{os.path.relpath(path, ROOT)}")
    return path


def _link(name, mesh, arm):
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = arm
    obj.modifiers.new("Skeleton", "ARMATURE").object = arm
    return obj


def _add_classic(recipe, lib, scale, arm, mats, report):
    """WE2002 look: boxy low-poly lofts, weights per ring, painted face."""
    for name, mesh, mat_names, trim in classic_builder.build(recipe, lib, scale, list(SKELETON)):
        for m in mat_names:
            mesh.materials.append(mats[m])
        if name.startswith("Shirt"):
            cylindrical_uv(mesh, 0.93 * scale, 1.5 * scale,
                           collar=lambda co, trim=trim: any((co - t).length < 1e-4 for t in trim))
        elif name == "Head":
            classic_builder.face_uv(mesh, scale)
        else:
            planar_uv(mesh)
        obj = _link(name, mesh, arm)
        for bone in SKELETON:  # same order as the deform layer indices
            obj.vertex_groups.new(name=bone)
        report.append(f"{name} {tris(mesh)}")


def _add_modern(recipe, lib, scale, arm, skeleton, mats, report):
    """Sculpted look: continuous voxel-fused body, cloth shells."""
    body_obj = None
    for name, mesh, prims, mat_names, rigid in build_meshes(recipe, lib, scale):
        for m in mat_names:
            mesh.materials.append(mats[m])
        for poly in mesh.polygons:
            poly.use_smooth = True
        obj = _link(name, mesh, arm)
        if name in ("Body", "Head"):
            skin(obj, prims, skeleton)
            if name == "Body":
                body_obj = obj
        elif rigid:
            skin(obj, prims, skeleton, rigid=rigid)
        else:
            transfer_weights(obj, body_obj, skeleton)
        report.append(f"{name} {tris(mesh)}")


def main(argv):
    ids = [a for a in argv if not a.startswith("--")]
    if "--all" in argv or not ids:
        ids = sorted(f[:-5] for f in os.listdir(os.path.join(DATA, "appearance"))
                     if f.startswith("player_") and f.endswith(".json"))
    for rid in ids:
        generate(rid)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
