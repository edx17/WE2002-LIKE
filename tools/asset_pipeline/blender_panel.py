"""WE2002 panel for Blender: one-click helpers for hand-made players.

How to use (once per session):
  1. In Blender, open the "Scripting" tab.
  2. Text -> Open -> tools/asset_pipeline/blender_panel.py
  3. Press "Run Script" (the ▶ button).
  4. In the 3D view press N: a "WE2002" tab appears in the side bar.

Buttons:
  * UV de camiseta      applies the kit UV contract to the selected mesh(es)
  * Crear animaciones   creates every missing action with the right length
  * Revisar             checks bones, materials and actions, reports in the bar
  * Exportar al juego   exports assets/players/custom/<name>.glb with the
                        right settings
"""

import json
import math
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath or __file__), "..", "..", ".."))
BONES = ["Hips", "Spine", "Chest", "Neck", "Head", "UpperArm.L", "LowerArm.L", "Hand.L", "UpperLeg.L",
         "LowerLeg.L", "Foot.L", "UpperArm.R", "LowerArm.R", "Hand.R", "UpperLeg.R", "LowerLeg.R", "Foot.R"]
MATERIALS = ["SKIN", "FACE", "KIT_SHIRT", "KIT_SHORTS", "KIT_SOCKS", "BOOTS", "HAIR", "EYES"]


def _project_root():
    """Finds the repo root walking up from the .blend (or this script)."""
    for start in (bpy.data.filepath, __file__):
        d = os.path.dirname(os.path.abspath(start)) if start else ""
        for _ in range(6):
            if os.path.exists(os.path.join(d, "project.godot")):
                return d
            d = os.path.dirname(d)
    return ROOT


def _clips():
    with open(os.path.join(_project_root(), "data", "animation", "clips.json"), encoding="utf-8") as f:
        return json.load(f)


def _armature():
    return next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)


class WE_OT_kit_uv(bpy.types.Operator):
    """Camiseta: proyección cilíndrica según la regla del juego (pecho al centro)"""
    bl_idname = "we2002.kit_uv"
    bl_label = "UV de camiseta"

    def execute(self, context):
        done = 0
        for obj in context.selected_objects:
            if obj.type != "MESH":
                continue
            me = obj.data
            if not me.uv_layers:
                me.uv_layers.new(name="UVMap")
            uv = me.uv_layers.active.data
            zs = [(obj.matrix_world @ v.co).z for v in me.vertices]
            z0, z1 = min(zs), max(zs)
            for poly in me.polygons:
                coords = []
                for li in poly.loop_indices:
                    co = obj.matrix_world @ me.vertices[me.loops[li].vertex_index].co
                    u = math.atan2(co.x, -co.y) / (2 * math.pi) + 0.5
                    coords.append([u, (co.z - z0) / max(z1 - z0, 1e-6) * 0.95])
                if max(c[0] for c in coords) - min(c[0] for c in coords) > 0.5:
                    for c in coords:
                        if c[0] < 0.5:
                            c[0] += 1.0
                for li, c in zip(poly.loop_indices, coords):
                    uv[li].uv = c
            done += 1
        self.report({"INFO"}, f"UV de camiseta aplicado a {done} objeto(s)")
        return {"FINISHED"}


class WE_OT_create_actions(bpy.types.Operator):
    """Crea las animaciones que faltan, con el nombre y la duración que espera el juego"""
    bl_idname = "we2002.create_actions"
    bl_label = "Crear animaciones"

    def execute(self, context):
        arm = _armature()
        if arm is None:
            self.report({"ERROR"}, "No hay esqueleto (Armature) en la escena")
            return {"CANCELLED"}
        clips = _clips()
        context.scene.render.fps = clips["fps"]
        arm.animation_data_create()
        created = []
        for name, spec in clips["clips"].items():
            if name in bpy.data.actions:
                continue
            act = bpy.data.actions.new(name)
            act.use_fake_user = True
            frames = round(spec["length"] * clips["fps"])
            arm.animation_data.action = act
            for pb in arm.pose.bones:
                pb.rotation_mode = "QUATERNION"
                pb.keyframe_insert("rotation_quaternion", frame=1)
                pb.keyframe_insert("rotation_quaternion", frame=frames + 1)
            created.append(f"{name} ({frames} cuadros)")
        self.report({"INFO"}, "Creadas: " + (", ".join(created) if created else "ninguna, ya estaban todas"))
        return {"FINISHED"}


class WE_OT_check(bpy.types.Operator):
    """Revisa huesos, materiales y animaciones contra lo que espera el juego"""
    bl_idname = "we2002.check"
    bl_label = "Revisar"

    def execute(self, context):
        problems = []
        arm = _armature()
        if arm is None:
            problems.append("no hay esqueleto")
        else:
            missing = [b for b in BONES if b not in arm.data.bones]
            if missing:
                problems.append("faltan huesos: " + ", ".join(missing))
        mats = {m.name for m in bpy.data.materials if m.users}
        for m in ("KIT_SHIRT", "KIT_SHORTS", "KIT_SOCKS"):
            if m not in mats:
                problems.append(f"falta el material {m}")
        for m in mats:
            if "." in m and m.split(".")[0] in MATERIALS:
                problems.append(f"el material '{m}' tiene un sufijo: renombralo a '{m.split('.')[0]}'")
        clips = _clips()
        for name, spec in clips["clips"].items():
            act = bpy.data.actions.get(name)
            if act is None:
                problems.append(f"falta la animación {name}")
                continue
            frames = act.frame_range[1] - act.frame_range[0]
            want = round(spec["length"] * clips["fps"])
            if abs(frames - want) > 2:
                problems.append(f"{name}: {int(frames)} cuadros, el juego espera {want}")
        if problems:
            self.report({"WARNING"}, " · ".join(problems[:6]) + (" …" if len(problems) > 6 else ""))
        else:
            self.report({"INFO"}, "Todo en orden ✓")
        return {"FINISHED"}


class WE_OT_export(bpy.types.Operator):
    """Exporta a assets/players/custom/<nombre del archivo>.glb con la configuración del juego"""
    bl_idname = "we2002.export"
    bl_label = "Exportar al juego"

    def execute(self, context):
        name = os.path.splitext(os.path.basename(bpy.data.filepath or "player_custom"))[0]
        name = name.split("_v")[0]  # jugador_v03.blend -> jugador
        out_dir = os.path.join(_project_root(), "assets", "players", "custom")
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                                  export_animations=True, export_animation_mode="ACTIONS",
                                  export_force_sampling=True)
        self.report({"INFO"}, f"Exportado: {path}. Ahora corré validate_glb.py o abrí ModelPreview en Godot.")
        return {"FINISHED"}


class WE_PT_panel(bpy.types.Panel):
    bl_label = "WE2002"
    bl_idname = "WE_PT_panel"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "WE2002"

    def draw(self, context):
        col = self.layout.column(align=True)
        col.label(text="Jugador para el juego")
        col.operator("we2002.kit_uv", icon="UV")
        col.operator("we2002.create_actions", icon="ACTION")
        col.operator("we2002.check", icon="CHECKMARK")
        col.separator()
        col.operator("we2002.export", icon="EXPORT")


CLASSES = (WE_OT_kit_uv, WE_OT_create_actions, WE_OT_check, WE_OT_export, WE_PT_panel)


def register():
    for c in CLASSES:
        try:
            bpy.utils.unregister_class(c)
        except RuntimeError:
            pass
        bpy.utils.register_class(c)


if __name__ == "__main__":
    register()
