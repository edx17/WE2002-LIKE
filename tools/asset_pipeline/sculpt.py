"""Procedural sculpting for the PLAYER_MASTER.

Anatomy is described as a list of primitives (tapered capsules and rotated
ellipsoids), each tagged with the bone it belongs to. They are fused into a
single watertight, organic surface with a voxel remesh (no seams at the
joints), lightly smoothed and decimated to a triangle budget.

Clothes are separate shells built the same way from inflated copies of the
anatomy and then CUT open (hem, sleeves, collar, leg openings), so a shirt
has real volume and real edges instead of being painted on the skin.

Skinning: the body gets smooth weights from its primitives (soft-min of
distances); clothes copy the weights of the nearest body vertex.
"""

import math

import bpy  # noqa: F401 - provides bmesh/mathutils when running as a module
import bmesh
from mathutils import Euler, Matrix, Vector


# --- primitives ------------------------------------------------------------------

class Capsule:
    def __init__(self, a, b, r1, r2, bone, region=""):
        self.a, self.b = Vector(a), Vector(b)
        self.r1, self.r2 = r1, r2
        self.bone, self.region = bone, region

    def inflated(self, d1, d2=None):
        return Capsule(self.a, self.b, self.r1 + d1, self.r2 + (d1 if d2 is None else d2), self.bone, self.region)

    def scaled(self, s):
        return Capsule(self.a * s, self.b * s, self.r1 * s, self.r2 * s, self.bone, self.region)

    def param(self, p):
        ab = self.b - self.a
        return max(0.0, min(1.0, (p - self.a).dot(ab) / max(ab.length_squared, 1e-9)))

    def distance(self, p):
        t = self.param(p)
        return (p - self.a.lerp(self.b, t)).length - (self.r1 + (self.r2 - self.r1) * t)

    def add_to(self, bm):
        axis = self.b - self.a
        res = bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=self.r1, radius2=self.r2,
                                    depth=axis.length)
        rot = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=Matrix.Translation((self.a + self.b) * 0.5) @ rot, verts=res["verts"])
        for c, r in ((self.a, self.r1), (self.b, self.r2)):
            sph = bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=r)
            bmesh.ops.translate(bm, vec=c, verts=sph["verts"])


class Ellipsoid:
    def __init__(self, c, r, bone, region="", rot=(0, 0, 0)):
        self.c, self.r = Vector(c), Vector(r)
        self.rot = Euler([math.radians(a) for a in rot]).to_matrix()
        self.rot_deg = rot
        self.bone, self.region = bone, region

    def inflated(self, d):
        return Ellipsoid(self.c, self.r + Vector((d, d, d)), self.bone, self.region, self.rot_deg)

    def scaled(self, s):
        return Ellipsoid(self.c * s, self.r * s, self.bone, self.region, self.rot_deg)

    def distance(self, p):
        q = self.rot.transposed() @ (p - self.c)
        k = Vector((q.x / self.r.x, q.y / self.r.y, q.z / self.r.z)).length
        return (k - 1.0) * min(self.r)

    def add_to(self, bm):
        res = bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=1.0)
        m = Matrix.Translation(self.c) @ self.rot.to_4x4() @ Matrix.Diagonal((*self.r, 1.0))
        bmesh.ops.transform(bm, matrix=m, verts=res["verts"])


def nearest(prims, p):
    best, best_d = None, 1e9
    for prim in prims:
        d = prim.distance(p)
        if d < best_d:
            best, best_d = prim, d
    return best


# --- fused surfaces --------------------------------------------------------------------

def fuse(name, prims, voxel, smooth=(0.5, 4), max_tris=None):
    """Union of primitives -> one remeshed, smoothed mesh (uniform quads).

    The triangle budget is met by choosing the voxel size up front (never by
    decimating: collapse decimation leaves long slivers that tear when cut
    and animated)."""
    if max_tris:
        area = _surface_area(_remesh(name, prims, max(voxel * 2.0, 0.02), None))
        # Voxel remesh yields ~3 tris per voxel² of surface.
        voxel = max(voxel, math.sqrt(3.0 * area / max_tris))
    mesh = _remesh(name, prims, voxel, smooth)
    mesh.name = name
    return mesh


def _remesh(name, prims, voxel, smooth):
    bm = bmesh.new()
    for prim in prims:
        prim.add_to(bm)
    raw = bpy.data.meshes.new(name + "_raw")
    bm.to_mesh(raw)
    bm.free()
    obj = bpy.data.objects.new(name + "_raw", raw)
    bpy.context.scene.collection.objects.link(obj)
    rem = obj.modifiers.new("Remesh", "REMESH")
    rem.mode = "VOXEL"
    rem.voxel_size = voxel
    rem.adaptivity = 0.0
    if smooth:
        sm = obj.modifiers.new("Smooth", "SMOOTH")
        sm.factor, sm.iterations = smooth
    bpy.context.view_layer.update()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(raw)
    return mesh


def _surface_area(mesh):
    area = sum(p.area for p in mesh.polygons)
    bpy.data.meshes.remove(mesh)
    return area


def join(name, meshes):
    """Concatenates meshes (no boolean): overlapping shells stay separate."""
    bm = bmesh.new()
    for m in meshes:
        bm.from_mesh(m)
        bpy.data.meshes.remove(m)
    out = bpy.data.meshes.new(name)
    bm.to_mesh(out)
    bm.free()
    return out


def cut(mesh, sdf):
    """Opens the shell where sdf(co) > 0 (hem, sleeves, collar, legs).

    Deleting voxel faces leaves a saw-tooth edge, so every vertex on the new
    border is then projected onto the cut surface (sdf = 0) with a couple of
    Newton steps: hems come out as clean lines, like sewn fabric."""
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if sdf(v.co) > 0.0], context="VERTS")
    _drop_islands(bm)
    eps = 0.002
    border = [v for v in bm.verts if v.is_boundary]
    for v in border:
        for _ in range(3):
            f = sdf(v.co)
            g = Vector(((sdf(v.co + Vector((eps, 0, 0))) - sdf(v.co - Vector((eps, 0, 0)))) / (2 * eps),
                        (sdf(v.co + Vector((0, eps, 0))) - sdf(v.co - Vector((0, eps, 0)))) / (2 * eps),
                        (sdf(v.co + Vector((0, 0, eps))) - sdf(v.co - Vector((0, 0, eps)))) / (2 * eps)))
            if g.length_squared < 1e-6 or abs(f) > 0.05:
                break
            v.co -= g * (f / g.length_squared)
    # Relax the ring next to the border so the projection doesn't leave a crease.
    ring = {e.other_vert(v) for v in border for e in v.link_edges} - set(border)
    for v in ring:
        nbrs = [e.other_vert(v).co for e in v.link_edges]
        avg = sum(nbrs, Vector()) / len(nbrs)
        v.co = v.co.lerp(avg, 0.5)
    bm.to_mesh(mesh)
    bm.free()


def _drop_islands(bm):
    """Removes tiny islands left behind by a cut."""
    bm.verts.ensure_lookup_table()
    islands, seen = [], set()
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, island = [v], []
        seen.add(v.index)
        while stack:
            cur = stack.pop()
            island.append(cur)
            for e in cur.link_edges:
                o = e.other_vert(cur)
                if o.index not in seen:
                    seen.add(o.index)
                    stack.append(o)
        islands.append(island)
    if islands:
        biggest = max(len(i) for i in islands)
        loose = [v for i in islands if len(i) < biggest * 0.02 for v in i]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")


def tris(mesh):
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


# --- skinning ----------------------------------------------------------------------------

def skin(obj, prims, skeleton, tau=0.012, rigid=None):
    """Smooth skinning: each primitive pulls its bone with exp(-d/tau), relative
    to the closest one. Neighbouring vertices therefore never jump between
    bones (no tearing), and joints blend where the anatomy overlaps."""
    groups = _groups(obj, skeleton)
    for v in obj.data.vertices:
        if rigid:
            groups[rigid].add([v.index], 1.0, "REPLACE")
            continue
        for bone, w in bone_weights(prims, v.co, tau).items():
            groups[bone].add([v.index], w, "REPLACE")


def bone_weights(prims, co, tau):
    ds = [(p.distance(co), p.bone) for p in prims]
    d_min = min(d for d, _ in ds)
    acc = {}
    for d, bone in ds:
        x = (d - d_min) / tau
        if x < 6.0:
            acc[bone] = acc.get(bone, 0.0) + math.exp(-x)
    top = sorted(acc.items(), key=lambda kv: kv[1], reverse=True)[:3]
    total = sum(w for _, w in top)
    return {b: w / total for b, w in top if w / total > 0.02}


def transfer_weights(obj, source, skeleton):
    """Clothes copy the weights of the nearest skin vertex: fabric follows the
    body underneath exactly, so hems never tear."""
    from mathutils.kdtree import KDTree
    groups = _groups(obj, skeleton)
    tree = KDTree(len(source.data.vertices))
    for v in source.data.vertices:
        tree.insert(v.co, v.index)
    tree.balance()
    names = {g.index: g.name for g in source.vertex_groups}
    for v in obj.data.vertices:
        _, idx, _ = tree.find(v.co)
        for g in source.data.vertices[idx].groups:
            groups[names[g.group]].add([v.index], g.weight, "REPLACE")


def _groups(obj, skeleton):
    for name in skeleton:
        if name not in obj.vertex_groups:
            obj.vertex_groups.new(name=name)
    return {g.name: g for g in obj.vertex_groups}


# --- UVs ---------------------------------------------------------------------------------

def cylindrical_uv(mesh, z0, z1, collar=None):
    """Kit UV contract: u = angle around the torso (0.5 chest, 0/1 back),
    v = height from hem (0) to the shoulders (0.95). The strip v > 0.955 is
    reserved for the collar: only vertices where collar(co) is true map there,
    so the collar colour never bleeds over the shoulders."""
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv = mesh.uv_layers.active.data
    for poly in mesh.polygons:
        coords = []
        for li in poly.loop_indices:
            co = mesh.vertices[mesh.loops[li].vertex_index].co
            v = min(max((co.z - z0) / (z1 - z0), 0.0), 0.95)
            if collar is not None and collar(co):
                v = 0.98
            coords.append([math.atan2(co.x, -co.y) / (2 * math.pi) + 0.5, v])
        if max(c[0] for c in coords) - min(c[0] for c in coords) > 0.5:
            for c in coords:
                if c[0] < 0.5:
                    c[0] += 1.0
        for li, c in zip(poly.loop_indices, coords):
            uv[li].uv = c


def planar_uv(mesh):
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv = mesh.uv_layers.active.data
    for loop in mesh.loops:
        co = mesh.vertices[loop.vertex_index].co
        uv[loop.index].uv = (co.x + 0.5, co.z / 2.0)
