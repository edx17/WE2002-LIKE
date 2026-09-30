"""PLAYER_MASTER generator: recipe JSON -> rigged, animated GLB.

    blender -b -P tools/asset_pipeline/player_generator.py -- player_001 [player_002 ...]
    python  tools/asset_pipeline/player_generator.py player_001        (with the `bpy` module)
    ... -- --all                                                        (every recipe in data/appearance)

One master body is assembled from parametric components (body type, face,
hair, boots, skin) and a shared skeleton, so a small library produces many
different players. Every part is rigidly bound to one bone, the way players
of that era were built: robust, cheap and readable from the gameplay camera.

The kit is NOT baked into the player. Shirt, shorts and socks get the
KIT_SHIRT / KIT_SHORTS / KIT_SOCKS materials and Godot swaps in the team's
kit texture at runtime (kit_generator.py): one model, every team.

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
from mathutils import Euler, Matrix, Quaternion, Vector

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


# --- mesh building -----------------------------------------------------------------

MATERIALS = ["SKIN", "KIT_SHIRT", "KIT_SHORTS", "KIT_SOCKS", "BOOTS", "HAIR", "EYES"]


class BodyBuilder:
    """Accumulates primitive parts into one skinned mesh."""

    def __init__(self, scale):
        self.s = scale
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()
        self.deform = self.bm.verts.layers.deform.verify()
        self.groups = list(SKELETON.keys())

    def _finish(self, verts, bone, mat, matrix, smooth):
        bmesh.ops.transform(self.bm, matrix=matrix, verts=verts)
        gi = self.groups.index(bone)
        vset = set(verts)
        for v in verts:
            v[self.deform][gi] = 1.0
        for f in {f for v in verts for f in v.link_faces}:
            if all(v in vset for v in f.verts):
                f.material_index = MATERIALS.index(mat)
                f.smooth = smooth

    def _place(self, loc, size, rot):
        s = self.s
        return (Matrix.Translation(Vector(loc) * s)
                @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4()
                @ Matrix.Diagonal((size[0] * s, size[1] * s, size[2] * s, 1.0)))

    def sphere(self, bone, mat, loc, size, rot=(0, 0, 0), segs=(16, 10), smooth=True):
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=segs[0], v_segments=segs[1], radius=1.0, calc_uvs=True)
        self._finish(res["verts"], bone, mat, self._place(loc, size, rot), smooth)

    def tube(self, bone, mat, a, b, r1, r2, sx=1.0, sy=1.0, segs=12, smooth=True):
        """Tapered cylinder from point a to point b (radii r1 at a, r2 at b)."""
        a, b = Vector(a), Vector(b)
        axis = b - a
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs,
                                    radius1=r1, radius2=r2, depth=axis.length, calc_uvs=True)
        rot = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
        m = (Matrix.Translation((a + b) * 0.5 * self.s) @ rot
             @ Matrix.Diagonal((sx * self.s, sy * self.s, self.s, 1.0)))
        self._finish(res["verts"], bone, mat, m, smooth)

    def box(self, bone, mat, loc, size, rot=(0, 0, 0)):
        res = bmesh.ops.create_cube(self.bm, size=1.0, calc_uvs=True)
        self._finish(res["verts"], bone, mat, self._place(loc, size, rot), False)

    def unwrap_kit(self):
        """Kit UV contract (see kit_generator.py): cylindrical projection around
        the torso. u = angle around the body (0.5 = chest, 0/1 = back),
        v = height from the hem (0) to the collar (1)."""
        shirt = MATERIALS.index("KIT_SHIRT")
        z0, z1 = 1.0 * self.s, 1.5 * self.s
        for f in self.bm.faces:
            if f.material_index != shirt:
                continue
            uvs = []
            for loop in f.loops:
                co = loop.vert.co
                u = math.atan2(co.x, -co.y) / (2 * math.pi) + 0.5
                v = (co.z - z0) / (z1 - z0)
                uvs.append([u, min(max(v, 0.0), 1.0)])
            # Faces crossing the back seam: keep them continuous (texture repeats).
            if max(uv[0] for uv in uvs) - min(uv[0] for uv in uvs) > 0.5:
                for uv in uvs:
                    if uv[0] < 0.5:
                        uv[0] += 1.0
            for loop, uv in zip(f.loops, uvs):
                loop[self.uv].uv = uv

    def build(self, name):
        self.unwrap_kit()
        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.new(name, mesh)
        for g in self.groups:
            obj.vertex_groups.new(name=g)
        return obj


def build_body(b, recipe, lib):
    body = lib["body_types"][recipe["body"]]
    face = lib["faces"][recipe["face"]]
    boot = lib["boots"][recipe["boot"]]
    # Weight shapes the girth relative to a 23 BMI athlete.
    bmi = recipe["weight"] / (recipe["height"] ** 2)
    girth = max(0.85, min(1.2, (bmi / 23.0) ** 0.5))
    sh, ch, wa, li = (body["shoulders"] * girth, body["chest"] * girth, body["waist"] * girth, body["limbs"] * girth)

    # Torso: shirt, two segments so the spine can bend.
    b.tube("Spine", "KIT_SHIRT", (0, 0, 1.0), (0, 0, 1.26), 0.16 * wa, 0.17 * ch, sx=1.15, sy=0.72)
    b.tube("Chest", "KIT_SHIRT", (0, 0, 1.24), (0, 0, 1.46), 0.17 * ch, 0.15 * sh, sx=1.28 * sh, sy=0.7)
    b.sphere("Chest", "KIT_SHIRT", (0, 0, 1.43), (0.2 * sh, 0.1, 0.06))  # shoulder line
    # Neck + head.
    b.tube("Neck", "SKIN", (0, 0, 1.44), (0, 0, 1.58), 0.055, 0.05)
    b.sphere("Head", "SKIN", (0, -0.005, 1.67), (0.098 * face["cheeks"], 0.112, 0.125))
    b.sphere("Head", "SKIN", (0, -0.035, 1.6), (0.075 * face["jaw"], 0.08, 0.06))  # jaw
    b.box("Head", "SKIN", (0, -0.118, 1.655), (0.024, 0.03 * face["nose"], 0.045 * face["nose"]), rot=(12, 0, 0))
    for x in (-0.042, 0.042):
        b.sphere("Head", "EYES", (x, -0.098, 1.69), (0.013, 0.008, 0.009), segs=(8, 5))
        b.box("Head", "HAIR", (x, -0.103, 1.713), (0.036 * face["brow"], 0.012, 0.009), rot=(0, 0, 8 if x > 0 else -8))
        b.sphere("Head", "SKIN", (x * 2.35, 0.0, 1.665), (0.016, 0.03, 0.035), segs=(8, 6))  # ears
    build_hair(b, recipe["hair"])

    for side, sx in (("L", 1), ("R", -1)):
        # Arms: short sleeve, skin forearm, hand.
        b.sphere(f"UpperArm.{side}", "KIT_SHIRT", (0.2 * sx * sh, 0, 1.415), (0.075 * li, 0.075 * li, 0.07))
        b.tube(f"UpperArm.{side}", "KIT_SHIRT", (0.21 * sx * sh, 0, 1.43), (0.225 * sx * sh, 0, 1.25), 0.07 * li, 0.06 * li)
        b.tube(f"UpperArm.{side}", "SKIN", (0.225 * sx * sh, 0, 1.26), (0.24 * sx * sh, 0, 1.14), 0.047 * li, 0.042 * li)
        b.tube(f"LowerArm.{side}", "SKIN", (0.24 * sx * sh, 0, 1.15), (0.25 * sx * sh, 0, 0.9), 0.042 * li, 0.032 * li)
        b.sphere(f"Hand.{side}", "SKIN", (0.252 * sx * sh, -0.005, 0.85), (0.03, 0.045, 0.06))
        # Legs: shorts, thigh, sock-covered shin, boot.
        x = 0.1 * sx
        b.tube(f"UpperLeg.{side}", "KIT_SHORTS", (x, 0, 0.98), (x, 0, 0.72), 0.095 * li, 0.085 * li)
        b.tube(f"UpperLeg.{side}", "SKIN", (x, 0, 0.73), (x, 0, 0.52), 0.07 * li, 0.055 * li)
        b.tube(f"LowerLeg.{side}", "SKIN", (x, 0, 0.53), (x, 0, 0.44), 0.052 * li, 0.055 * li)
        b.tube(f"LowerLeg.{side}", "KIT_SOCKS", (x, 0.005, 0.45), (x, 0, 0.1), 0.057 * li, 0.036)
        blen, bh = 0.26 * boot["length"], 0.07 * boot["height"]
        b.sphere(f"Foot.{side}", "BOOTS", (x, -0.06, bh * 0.62), (0.045, blen * 0.5, bh * 0.55), segs=(12, 8))
        b.sphere(f"Foot.{side}", "BOOTS", (x, 0.005, bh * 0.9), (0.042, 0.06, bh * 0.6), segs=(10, 6))  # heel/ankle
        b.box(f"Foot.{side}", "BOOTS", (x, -0.06, 0.008), (0.08, blen * 0.97, 0.016))  # sole
    # Shorts waist.
    b.tube("Hips", "KIT_SHORTS", (0, 0, 0.84), (0, 0, 1.03), 0.18 * wa, 0.165 * wa, sx=1.12, sy=0.8)


def build_hair(b, style):
    """Stylised hair volumes, no strands: closer to the era and to the camera."""
    if style == 0:
        return
    if style == 1:    # short
        b.sphere("Head", "HAIR", (0, 0.008, 1.705), (0.104, 0.118, 0.105))
    elif style == 2:  # buzz
        b.sphere("Head", "HAIR", (0, 0.004, 1.695), (0.1, 0.115, 0.108))
    elif style == 3:  # long
        b.sphere("Head", "HAIR", (0, 0.008, 1.705), (0.108, 0.122, 0.11))
        b.sphere("Head", "HAIR", (0, 0.055, 1.6), (0.1, 0.07, 0.12))
    elif style == 4:  # afro
        b.sphere("Head", "HAIR", (0, 0.015, 1.73), (0.135, 0.145, 0.125))
    elif style == 5:  # mohawk
        b.sphere("Head", "HAIR", (0, 0.004, 1.69), (0.099, 0.114, 0.104))
        b.box("Head", "HAIR", (0, 0.0, 1.8), (0.03, 0.2, 0.06))


def make_materials(recipe, lib):
    """The 'look' recipe: flat-ish base color, high roughness, moderate specular."""
    colors = {
        "SKIN": hex_color(lib["skin_tones"][recipe["skin"]]),
        "KIT_SHIRT": hex_color("#bbbbbb"),
        "KIT_SHORTS": hex_color("#eeeeee"),
        "KIT_SOCKS": hex_color("#bbbbbb"),
        "BOOTS": hex_color(recipe.get("boot_color", "#111111")),
        "HAIR": hex_color(lib["hair_colors"][recipe["hair_color"]]),
        "EYES": hex_color("#1a1a1a"),
    }
    roughness = {"SKIN": 0.65, "KIT_SHIRT": 0.8, "KIT_SHORTS": 0.8, "KIT_SOCKS": 0.85, "BOOTS": 0.35, "HAIR": 0.75, "EYES": 0.3}
    mats = []
    for name in MATERIALS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = colors[name]
        bsdf.inputs["Roughness"].default_value = roughness[name]
        bsdf.inputs["Specular IOR Level"].default_value = 0.35
        mats.append(m)
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

    arm = build_armature(scale)
    builder = BodyBuilder(scale)
    build_body(builder, recipe, lib)
    body = builder.build("Body")
    for m in make_materials(recipe, lib):
        body.data.materials.append(m)
    bpy.context.scene.collection.objects.link(body)
    body.parent = arm
    mod = body.modifiers.new("Skeleton", "ARMATURE")
    mod.object = arm

    build_actions(arm, scale, clips)

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f"{recipe_id}.glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_animations=True,
        export_animation_mode="ACTIONS", export_force_sampling=True,
        export_apply=False, export_yup=True)
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print(f"[player_generator] {recipe_id}: {tris} tris, {len(clips['clips'])} clips -> {os.path.relpath(path, ROOT)}")
    return path


def main(argv):
    ids = [a for a in argv if not a.startswith("--")]
    if "--all" in argv or not ids:
        ids = sorted(f[:-5] for f in os.listdir(os.path.join(DATA, "appearance"))
                     if f.startswith("player_") and f.endswith(".json"))
    for rid in ids:
        generate(rid)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:])
