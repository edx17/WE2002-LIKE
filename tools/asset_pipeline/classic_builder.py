"""Classic (WE2002 / PS1-era) player: boxy low-poly lofts, painted face.

What defines the original look, and what this builder reproduces:
  * few polygons (~2k tris), chamfered-box cross sections: trapezoid shirt
    with broad square shoulders, very wide boxy shorts, square calves
  * a box-like head whose eyes, brows and mouth are TEXTURE, not geometry;
    blocky hair caps
  * mitten hands, simple wedge boots, long socks under a bare knee
  * low-res textures shown without filtering, matte materials

Every part is a loft: a chain of rings (8-sided chamfered rectangles), each
ring with its own bone weights. That keeps the silhouette angular while the
joints bend without gaps.
"""

import math

import bpy  # noqa: F401 - provides bmesh/mathutils when running as a module
import bmesh
from mathutils import Vector


class Ring:
    """Cross-section: centre, half-width a (frame X), half-depth b (frame Y)."""

    def __init__(self, c, a, b, weights, chamfer=0.3, tilt=0.0, trim=False):
        self.c, self.a, self.b = Vector(c), a, b
        self.weights, self.chamfer, self.tilt, self.trim = weights, chamfer, tilt, trim


def _profile(a, b, k):
    ka, kb = a * k, b * k
    return [(a, -b + kb), (a, b - kb), (a - ka, b), (-a + ka, b),
            (-a, b - kb), (-a, -b + kb), (-a + ka, -b), (a - ka, -b)]


class LoftBuilder:
    """Accumulates lofts into one bmesh with per-vertex bone weights."""

    def __init__(self, bone_names, materials, scale):
        self.bm = bmesh.new()
        self.deform = self.bm.verts.layers.deform.verify()
        self.bones = list(bone_names)
        self.materials = list(materials)
        self.s = scale
        self.trim_coords = []

    def loft(self, rings, material, cap_start=True, cap_end=True):
        s = self.s
        loops = []
        for i, ring in enumerate(rings):
            prev_c = rings[max(i - 1, 0)].c
            next_c = rings[min(i + 1, len(rings) - 1)].c
            d = (next_c - prev_c).normalized()
            ref = Vector((1, 0, 0)) if abs(d.x) < 0.9 else Vector((0, 1, 0))
            xa = (ref - d * ref.dot(d)).normalized()
            ya = d.cross(xa)
            loop = []
            for px, py in _profile(ring.a, ring.b, ring.chamfer):
                p = ring.c + xa * px + ya * py
                p.z += ring.tilt * (p.y - ring.c.y)
                v = self.bm.verts.new(p * s)
                for bone, w in ring.weights.items():
                    v[self.deform][self.bones.index(bone)] = w
                loop.append(v)
                if ring.trim:
                    self.trim_coords.append((p * s).copy())
            loops.append(loop)
        mi = self.materials.index(material)
        faces = []
        for l0, l1 in zip(loops, loops[1:]):
            n = len(l0)
            for j in range(n):
                faces.append(self.bm.faces.new((l0[j], l0[(j + 1) % n], l1[(j + 1) % n], l1[j])))
        if cap_start:
            faces.append(self.bm.faces.new(list(reversed(loops[0]))))
        if cap_end:
            faces.append(self.bm.faces.new(loops[-1]))
        for f in faces:
            f.material_index = mi
            f.smooth = True
        return faces

    def build(self, name, sharp_angle=40.0):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        for e in self.bm.edges:
            if e.is_manifold and math.degrees(e.calc_face_angle(0.0)) > sharp_angle:
                e.smooth = False
        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        return mesh


def R(c, a, b, w, **kw):
    return Ring(c, a, b, w, **kw)


# --- the classic player ---------------------------------------------------------------

def build(recipe, lib, scale, bone_names):
    """Returns [(name, mesh, material_names, trim_coords)]. Body first."""
    body = lib["body_types"][recipe["body"]]
    bmi = recipe["weight"] / (recipe["height"] ** 2)
    girth = max(0.9, min(1.15, (bmi / 23.0) ** 0.5))
    sh, ch, wa, li = (body["shoulders"] * girth, body["chest"] * girth, body["waist"] * girth, body["limbs"] * girth)
    out = []

    # Body: arms, hands, neck, thighs, socks, boots.
    b = LoftBuilder(bone_names, ["SKIN", "KIT_SOCKS", "BOOTS"], scale)
    for side, sx in (("L", 1), ("R", -1)):
        ua, la, hand = f"UpperArm.{side}", f"LowerArm.{side}", f"Hand.{side}"
        b.loft([R((0.2 * sx * sh, 0, 1.375), 0.046 * li, 0.048 * li, {ua: 1}),  # starts inside the sleeve
                R((0.214 * sx * sh, 0, 1.3), 0.052 * li, 0.054 * li, {ua: 1}),
                R((0.235 * sx * sh, 0, 1.16), 0.043 * li, 0.045 * li, {ua: 0.5, la: 0.5}),
                R((0.243 * sx * sh, 0, 1.03), 0.04 * li, 0.043 * li, {la: 1}),
                R((0.248 * sx * sh, -0.004, 0.925), 0.03, 0.033, {la: 0.5, hand: 0.5})], "SKIN")
        b.loft([R((0.25 * sx * sh, -0.004, 0.93), 0.024, 0.036, {hand: 1}, chamfer=0.45),
                R((0.252 * sx * sh, -0.006, 0.865), 0.027, 0.043, {hand: 1}, chamfer=0.45),
                R((0.252 * sx * sh, -0.008, 0.8), 0.018, 0.03, {hand: 1}, chamfer=0.45)], "SKIN")
        ul, ll, ft = f"UpperLeg.{side}", f"LowerLeg.{side}", f"Foot.{side}"
        x = 0.1 * sx
        b.loft([R((x, 0, 0.8), 0.072 * li, 0.074 * li, {ul: 1}),
                R((x, -0.01, 0.6), 0.063 * li, 0.066 * li, {ul: 1}),
                R((x, -0.016, 0.515), 0.051, 0.055, {ul: 0.5, ll: 0.5})], "SKIN")
        b.loft([R((x, -0.012, 0.5), 0.053, 0.056, {ll: 1}),
                R((x, 0.012, 0.37), 0.058 * li, 0.064 * li, {ll: 1}),
                R((x, 0.004, 0.2), 0.04, 0.043, {ll: 1}),
                R((x, 0.0, 0.1), 0.035, 0.038, {ll: 0.5, ft: 0.5})], "KIT_SOCKS")
        # Boot: wedge lofted heel -> toe (frame Y = up).
        b.loft([R((x, 0.05, 0.045), 0.04, 0.045, {ft: 1}, chamfer=0.25),
                R((x, -0.04, 0.046), 0.05, 0.046, {ft: 1}, chamfer=0.25),
                R((x, -0.13, 0.034), 0.046, 0.034, {ft: 1}, chamfer=0.3),
                R((x, -0.178, 0.026), 0.028, 0.022, {ft: 1}, chamfer=0.4)], "BOOTS")
    b.loft([R((0, 0.005, 1.42), 0.05, 0.05, {"Neck": 1}),
            R((0, 0.005, 1.58), 0.046, 0.048, {"Neck": 0.5, "Head": 0.5})], "SKIN")
    out.append(("Body", b.build("Body"), ["SKIN", "KIT_SOCKS", "BOOTS"], []))

    # Head: rounded box + low-poly nose and ears; the face is painted.
    h = LoftBuilder(bone_names, ["FACE"], scale)
    hw = {"Head": 1}
    h.loft([R((0, -0.03, 1.545), 0.045, 0.05, hw, chamfer=0.4),
            R((0, -0.006, 1.6), 0.072, 0.085, hw, chamfer=0.38),
            R((0, 0.004, 1.66), 0.083, 0.098, hw, chamfer=0.38),
            R((0, 0.01, 1.72), 0.082, 0.1, hw, chamfer=0.38),
            R((0, 0.012, 1.78), 0.07, 0.09, hw, chamfer=0.4),
            R((0, 0.012, 1.815), 0.04, 0.055, hw, chamfer=0.4)], "FACE")
    h.loft([R((0, -0.088, 1.66), 0.015, 0.024, hw, chamfer=0.3),
            R((0, -0.112, 1.646), 0.011, 0.014, hw, chamfer=0.3)], "FACE")
    for sx in (1, -1):
        h.loft([R((0.075 * sx, 0.01, 1.665), 0.026, 0.034, hw, chamfer=0.4),
                R((0.093 * sx, 0.014, 1.665), 0.02, 0.03, hw, chamfer=0.4)], "FACE")
    out.append(("Head", h.build("Head", sharp_angle=55.0), ["FACE"], []))

    # Shirt: trapezoid torso (square shoulders) + sleeves; collar/cuffs are trim.
    torso = [R((0, 0, 0.93), 0.172 * wa, 0.108, {"Hips": 0.5, "Spine": 0.5}),
             R((0, 0, 1.06), 0.158 * wa, 0.1, {"Spine": 1}),
             R((0, -0.005, 1.22), 0.175 * ch, 0.11, {"Spine": 0.5, "Chest": 0.5}),
             R((0, -0.005, 1.35), 0.21 * sh, 0.114, {"Chest": 1}, chamfer=0.25),
             R((0, 0.005, 1.448), 0.192 * sh, 0.094, {"Chest": 1}, chamfer=0.35),
             R((0, 0.005, 1.492), 0.07, 0.06, {"Chest": 0.6, "Neck": 0.4}, trim=True)]
    for sleeves in ("Short", "Long"):
        sb = LoftBuilder(bone_names, ["KIT_SHIRT"], scale)
        sb.loft(torso, "KIT_SHIRT")
        for side, sx in (("L", 1), ("R", -1)):
            ua, la, hand = f"UpperArm.{side}", f"LowerArm.{side}", f"Hand.{side}"
            rings = [R((0.176 * sx * sh, 0, 1.425), 0.064, 0.07, {"Chest": 0.4, ua: 0.6}),
                     R((0.212 * sx * sh, 0, 1.33), 0.066 * li, 0.066 * li, {ua: 1})]
            if sleeves == "Short":
                rings.append(R((0.227 * sx * sh, 0.002, 1.215), 0.064 * li, 0.062 * li, {ua: 1}, trim=True))
            else:
                rings += [R((0.237 * sx * sh, 0, 1.15), 0.058 * li, 0.059 * li, {ua: 0.5, la: 0.5}),
                          R((0.245 * sx * sh, -0.004, 0.96), 0.047, 0.05, {la: 1}),
                          R((0.248 * sx * sh, -0.004, 0.93), 0.045, 0.048, {la: 0.6, hand: 0.4}, trim=True)]
            sb.loft(rings, "KIT_SHIRT")
        out.append((f"Shirt_{sleeves}", sb.build(f"Shirt_{sleeves}"), ["KIT_SHIRT"], sb.trim_coords))

    # Shorts: wide box at the hips + flared legs, the WE silhouette.
    st = LoftBuilder(bone_names, ["KIT_SHORTS"], scale)
    st.loft([R((0, 0.005, 1.03), 0.168 * wa, 0.105, {"Hips": 1}),
             R((0, 0.008, 0.88), 0.185 * wa, 0.118, {"Hips": 1}, chamfer=0.25),
             R((0, 0.008, 0.85), 0.05, 0.1, {"Hips": 1}, chamfer=0.25)], "KIT_SHORTS")
    for side, sx in (("L", 1), ("R", -1)):
        ul = f"UpperLeg.{side}"
        st.loft([R((0.092 * sx, 0.008, 0.93), 0.094 * wa, 0.112, {"Hips": 0.6, ul: 0.4}, chamfer=0.25),
                 R((0.112 * sx, 0.0, 0.67), 0.1 * li, 0.112 * li, {ul: 1}, chamfer=0.25)], "KIT_SHORTS")
    out.append(("Shorts", st.build("Shorts"), ["KIT_SHORTS"], []))

    hair = _hair(recipe["hair"], bone_names, scale)
    if hair is not None:
        out.append(("Hair", hair, ["HAIR"], []))
    return out


def _hair(style, bone_names, scale):
    """Blocky caps; the bottom ring is tilted: high hairline in front, low at the back."""
    if style == 0:
        return None
    hb = LoftBuilder(bone_names, ["HAIR"], scale)
    w = {"Head": 1}
    grow = {1: 0.009, 2: 0.004, 3: 0.011, 4: 0.035, 5: 0.004}[style]
    tilt = -0.45 if style != 3 else -0.9
    top = 1.835 + (0.04 if style == 4 else 0.0)
    rings = [R((0, 0.012, 1.69), 0.083 + grow, 0.1 + grow, w, chamfer=0.38, tilt=tilt),
             R((0, 0.012, 1.75), 0.083 + grow, 0.102 + grow, w, chamfer=0.38),
             R((0, 0.014, 1.795 + (0.02 if style == 4 else 0.0)), 0.072 + grow, 0.093 + grow, w, chamfer=0.4),
             R((0, 0.014, top), 0.04 + grow * 0.6, 0.058 + grow * 0.6, w, chamfer=0.4)]
    hb.loft(rings, "HAIR")
    if style == 3:  # long: block down the back of the head
        hb.loft([R((0, 0.085, 1.72), 0.08, 0.03, w, chamfer=0.3),
                 R((0, 0.09, 1.57), 0.075, 0.028, w, chamfer=0.3)], "HAIR")
    if style == 5:  # mohawk ridge, front to back
        hb.loft([R((0, -0.07, 1.8), 0.018, 0.03, w), R((0, 0.0, 1.86), 0.02, 0.035, w),
                 R((0, 0.09, 1.79), 0.018, 0.03, w)], "HAIR")
    return hb.build("Hair", sharp_angle=50.0)


# --- painted face ------------------------------------------------------------------------

FACE_TEX = 64


def face_image(name, skin_hex, hair_hex, face, facial_hair=0):
    """64x64 face texture: skin, eyes, brows, nose shade and mouth, pixel-art style.
    Mapped with face_uv(): front-facing polygons get a planar projection, the
    rest sample plain skin."""
    import numpy as np

    def rgb(h):
        h = h.lstrip("#")
        return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)] + [1.0])

    skin, hair = rgb(skin_hex), rgb(hair_hex)
    shade = skin * np.array([0.78, 0.7, 0.68, 1.0])
    px = np.tile(skin, (FACE_TEX, FACE_TEX, 1))

    def rect(u0, v0, u1, v1, color):
        x0, x1 = int(u0 * FACE_TEX), max(int(u0 * FACE_TEX) + 1, int(u1 * FACE_TEX))
        y0, y1 = int(v0 * FACE_TEX), max(int(v0 * FACE_TEX) + 1, int(v1 * FACE_TEX))
        px[y0:y1, x0:x1] = color

    brow = face.get("brow", 1.0)
    for sx in (-1, 1):
        cu = 0.5 + sx * 0.17
        rect(cu - 0.09 * brow, 0.59, cu + 0.08 * brow, 0.65, hair)                  # brow
        rect(cu - 0.08, 0.47, cu + 0.08, 0.57, shade)                               # eye socket
        rect(cu - 0.065, 0.49, cu + 0.065, 0.55, np.array([0.93, 0.92, 0.9, 1.0]))  # eye white
        rect(cu - 0.035, 0.49, cu + 0.035, 0.55, np.array([0.1, 0.07, 0.05, 1.0]))  # iris
        rect(cu - 0.08, 0.36, cu + 0.08, 0.4, shade * 0.98 + skin * 0.02)            # cheekbone shade
    rect(0.47, 0.38, 0.53, 0.5, shade)                                              # nose shade
    rect(0.42, 0.25, 0.58, 0.28, np.array([0.45, 0.22, 0.2, 1.0]) * 0.6 + shade * 0.4)  # mouth
    rect(0.4, 0.06, 0.6, 0.12, shade)                                               # chin shade
    if facial_hair in (1, 3):                                                       # goatee / beard
        rect(0.42, 0.04, 0.58, 0.22, hair)
    if facial_hair in (2, 1, 3):                                                    # moustache
        rect(0.41, 0.29, 0.59, 0.33, hair)
    if facial_hair == 3:                                                            # full beard
        rect(0.24, 0.1, 0.33, 0.36, hair)
        rect(0.67, 0.1, 0.76, 0.36, hair)
        rect(0.3, 0.02, 0.7, 0.14, hair)
    rect(0.42, 0.25, 0.58, 0.28, np.array([0.45, 0.22, 0.2, 1.0]) * 0.6 + shade * 0.4)  # mouth on top

    img = bpy.data.images.new(name, FACE_TEX, FACE_TEX, alpha=False)
    img.pixels = px.flatten().tolist()
    img.pack()
    return img


def face_uv(mesh, scale):
    """Front-facing polygons: planar projection of the face rectangle.
    Everything else samples a plain-skin pixel."""
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv = mesh.uv_layers.active.data
    z0, z1, half_w = 1.54 * scale, 1.83 * scale, 0.1 * scale
    for poly in mesh.polygons:
        front = poly.normal.y < -0.35
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            if front:
                uv[li].uv = (0.5 + co.x / (2 * half_w), (co.z - z0) / (z1 - z0))
            else:
                uv[li].uv = (0.04, 0.85)
