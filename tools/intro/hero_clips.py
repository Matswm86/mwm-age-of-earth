"""Hero hominin for the opening intro: the Age 1 australopith body with two extra clips.

  wake        Quaternius Universal Animation Library 2 "LayToIdle" (CC0), retargeted onto the rig
              with the same method as tools/assets/retarget_char.py.
  climb_down  authored here: one in-place cycle of climbing down a vertical trunk (radius
              TRUNK_R, axis TRUNK_Y ahead of the body). IK targets for hands and feet hold on the
              bark while the body sinks, then reach down for the next grip (diagonal pairs).
              The intro moves the whole body down DESCENT_M per cycle, so grips stay put.

blender -b --factory-startup -P tools/intro/hero_clips.py
Writes assets/intro/hero/australopith_hero.glb (clips idle, walk, crouch, gather, wake,
climb_down) and check renders to ~/MWM/scratch/aoe-intro/hero_*.png.
"""

from __future__ import annotations

import math
import re
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "assets/models/hominins/australopith/australopith.glb"
UAL2 = (
    Path.home()
    / "MWM/scratch/wayfarer/anim/ual2/Universal Animation Library 2 [Standard]/Unreal-Godot/UAL2_Standard.glb"
)
OUT = REPO / "assets/intro/hero/australopith_hero.glb"
CHECK = Path.home() / "MWM/scratch/aoe-intro"
KEEP = ("idle", "walk", "crouch", "gather")
# climb cycle (Blender units: metres, character faces -Y, Z up, feet at z 0 in rest)
CYCLE_F = 24
DESCENT_M = 0.6
TRUNK_R = 0.45
TRUNK_Y = -0.5
HAND_Z = 1.36
FOOT_Z = 0.40
HAND_ANG = 60.0
FOOT_ANG = 48.0
LEAN_DEG = 20.0


def log(*a) -> None:
    print("HERO", *a, flush=True)


def canon(n: str) -> str | None:
    """Canonical bone key (subset of retarget_char.canon)."""
    n = re.sub(r"^.*mixamorig[:_]?", "", n)
    n = re.sub(r"_\d+$", "", n)
    side = ""
    m = re.search(r"(\.L|\.R|_l|_r)$", n)
    if m:
        side = ".L" if m.group(1) in (".L", "_l") else ".R"
        n = n[: m.start()]
    if n.startswith("Left"):
        side, n = ".L", n[4:]
    elif n.startswith("Right"):
        side, n = ".R", n[5:]
    table = {
        "hips": "hips",
        "Hips": "hips",
        "pelvis": "hips",
        "Spine": "spine1",
        "spine_01": "spine1",
        "Spine1": "spine2",
        "spine_02": "spine2",
        "Spine2": "spine3",
        "spine_03": "spine3",
        "neck": "neck",
        "Neck": "neck",
        "neck_01": "neck",
        "head": "head",
        "Head": "head",
        "Shoulder": "shoulder",
        "clavicle": "shoulder",
        "Arm": "upperarm",
        "upperarm": "upperarm",
        "ForeArm": "forearm",
        "lowerarm": "forearm",
        "Hand": "hand",
        "hand": "hand",
        "UpLeg": "thigh",
        "thigh": "thigh",
        "Leg": "shin",
        "calf": "shin",
        "Foot": "foot",
        "foot": "foot",
        "ToeBase": "toe",
        "ball": "toe",
    }
    if n in table:
        k = table[n]
        limb = ("shoulder", "upperarm", "forearm", "hand", "thigh", "shin", "foot", "toe")
        return k + side if k in limb else k
    return None


def setup() -> tuple:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 24
    bpy.ops.import_scene.gltf(filepath=str(SRC))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm]
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o not in meshes:
            bpy.data.objects.remove(o, do_unlink=True)
    keep = {}
    for a in list(bpy.data.actions):
        if a.name in KEEP:
            keep[a.name] = a
            a.use_fake_user = True
        else:
            bpy.data.actions.remove(a)
    ad = arm.animation_data
    ad.action = None
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix()
        pb.rotation_mode = "QUATERNION"
    bpy.context.view_layer.update()
    return arm, meshes, keep


def bones_by_key(arm) -> dict:
    out = {}
    for b in arm.data.bones:
        k = canon(b.name)
        if k and k not in out:
            out[k] = b.name
    return out


def assign(arm, act) -> None:
    arm.animation_data.action = act
    ad = arm.animation_data
    if hasattr(ad, "action_suitable_slots") and ad.action_suitable_slots:
        ad.action_slot = ad.action_suitable_slots[0]


# ------------------------------------------------------------------ wake (retarget LayToIdle)
def retarget_wake(tarm) -> None:
    sc = bpy.context.scene
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(UAL2))
    new = [o for o in bpy.data.objects if o not in before]
    sarm = next(o for o in new if o.type == "ARMATURE")
    for o in new:
        if o.type == "MESH":
            o.hide_render = True
    sact = next(a for a in bpy.data.actions if a.name.startswith("LayToIdle"))
    if sarm.animation_data is None:
        sarm.animation_data_create()
    tmap, smap = bones_by_key(tarm), bones_by_key(sarm)
    pairs = [(k, smap[k], tmap[k]) for k in tmap if k in smap]
    order = [b.name for b in tarm.data.bones]
    pairs.sort(key=lambda p: order.index(p[2]))
    log("wake mapped", len(pairs))

    def head_w(a, bn):
        return a.matrix_world @ a.data.bones[bn].head_local

    leg_ratio = head_w(tarm, tmap["hips"]).z / head_w(sarm, smap["hips"]).z
    fs = (head_w(sarm, smap["toe.L"]) - head_w(sarm, smap["foot.L"])).y
    ft = (head_w(tarm, tmap["toe.L"]) - head_w(tarm, tmap["foot.L"])).y
    if fs * ft < 0:
        sarm.rotation_euler.z += math.pi
        bpy.context.view_layer.update()
    sarm.animation_data.action = None
    for pb in sarm.pose.bones:
        pb.matrix_basis = Matrix()
    bpy.context.view_layer.update()
    child = {
        "hips": "spine1",
        "spine1": "spine2",
        "spine2": "spine3",
        "spine3": "neck",
        "neck": "head",
    }
    for sd in (".L", ".R"):
        child.update(
            {
                f"shoulder{sd}": f"upperarm{sd}",
                f"upperarm{sd}": f"forearm{sd}",
                f"forearm{sd}": f"hand{sd}",
                f"thigh{sd}": f"shin{sd}",
                f"shin{sd}": f"foot{sd}",
                f"foot{sd}": f"toe{sd}",
            }
        )
    common = {k for k, _, _ in pairs}

    def cdir(a, mp, key, posed):
        def hp(k):
            if posed:
                return a.matrix_world @ a.pose.bones[mp[k]].head
            return a.matrix_world @ a.data.bones[mp[k]].head_local

        ch = child.get(key)
        if ch in common:
            return (hp(ch) - hp(key)).normalized()
        return None

    for k, sb, _tb in pairs:
        if k == "hips" or child.get(k) not in common:
            continue
        have, want = cdir(sarm, smap, k, True), cdir(tarm, tmap, k, False)
        pb = sarm.pose.bones[sb]
        cur = sarm.matrix_world @ pb.matrix
        rot = have.rotation_difference(want).to_matrix()
        pb.matrix = sarm.matrix_world.inverted() @ (
            Matrix.Translation(cur.translation) @ (rot @ cur.to_3x3()).to_4x4()
        )
        bpy.context.view_layer.update()

    def wrot(a, bn):
        return (a.matrix_world @ a.pose.bones[bn].matrix).to_3x3().normalized()

    ref = {sb: wrot(sarm, sb) for _, sb, _ in pairs}
    ref_hip = (sarm.matrix_world @ sarm.pose.bones[smap["hips"]].matrix).translation.copy()
    trest = {
        tb: (tarm.matrix_world @ tarm.data.bones[tb].matrix_local).to_3x3().normalized()
        for _, _, tb in pairs
    }
    corr = {sb: ref[sb].inverted() @ trest[tb] for _, sb, tb in pairs}
    t_hip = (tarm.matrix_world @ tarm.data.bones[tmap["hips"]].matrix_local).translation.copy()
    assign(sarm, sact)
    f0, f1 = (int(round(v)) for v in sact.frame_range)
    tact = bpy.data.actions.new("wake")
    tact.use_fake_user = True
    assign(tarm, tact)
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        for pb in tarm.pose.bones:
            pb.matrix_basis = Matrix()
        bpy.context.view_layer.update()
        for k, sb, tb in pairs:
            w = wrot(sarm, sb) @ corr[sb]
            tpb = tarm.pose.bones[tb]
            loc = (tarm.matrix_world @ tpb.matrix).translation
            if k == "hips":
                s_now = (sarm.matrix_world @ sarm.pose.bones[sb].matrix).translation
                loc = t_hip + (s_now - ref_hip) * leg_ratio
            tpb.matrix = tarm.matrix_world.inverted() @ (Matrix.Translation(loc) @ w.to_4x4())
            bpy.context.view_layer.update()
        for k, _sb, tb in pairs:
            tpb = tarm.pose.bones[tb]
            tpb.keyframe_insert("rotation_quaternion", frame=f - f0)
            if k == "hips":
                tpb.keyframe_insert("location", frame=f - f0)
    log("wake frames", f1 - f0 + 1)
    tarm.animation_data.action = None
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a not in acts_before and a.name != "wake":
            bpy.data.actions.remove(a)


# ------------------------------------------------------------------ climb_down (IK authored)
def climb(arm) -> None:
    sc = bpy.context.scene
    km = bones_by_key(arm)
    mw = arm.matrix_world
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix()
    bpy.context.view_layer.update()
    rest_hip = (mw @ arm.data.bones[km["hips"]].matrix_local).copy()
    axis_y = TRUNK_Y
    empties = {}

    def empty(name):
        e = bpy.data.objects.new(name, None)
        sc.collection.objects.link(e)
        empties[name] = e
        return e

    for sd, sx in ((".L", 1.0), (".R", -1.0)):
        for limb, bone, chain in (("hand", "forearm", 2), ("foot", "shin", 2)):
            tgt = empty(f"t_{limb}{sd}")
            pole = empty(f"p_{limb}{sd}")
            if limb == "hand":
                pole.location = (0.7 * sx, 0.35, 0.75)
            else:
                pole.location = (0.75 * sx, -0.5, 0.75)
            c = arm.pose.bones[km[bone + sd]].constraints.new("IK")
            c.target = tgt
            c.pole_target = pole
            c.chain_count = chain
            c.pole_angle = 0.0
            c.use_stretch = False
    act = bpy.data.actions.new("climb_src")
    assign(arm, act)

    def grip(limb: str, sd: str, phase: float) -> Vector:
        """Body-space target. phase 0..1 over the cycle; this limb swings in the first half."""
        sx = 1.0 if sd == ".L" else -1.0
        ang = math.radians(HAND_ANG if limb == "hand" else FOOT_ANG)
        base_z = HAND_Z if limb == "hand" else FOOT_Z
        x = sx * TRUNK_R * math.sin(ang)
        y = axis_y + TRUNK_R * math.cos(ang)
        q = DESCENT_M * 0.25
        if phase < 0.5:  # swing: from +q to -q, lifted off the bark
            u = phase / 0.5
            s = u * u * (3 - 2 * u)
            z = base_z + q - 2 * q * s
            off = math.sin(math.pi * u) * 0.09
            return Vector((x * (1 + off), y + off, z))
        u = (phase - 0.5) / 0.5  # grip: rises in body space as the body sinks
        return Vector((x, y, base_z - q + 2 * q * u))

    for f in range(CYCLE_F + 1):
        sc.frame_set(f)
        ph = f / CYCLE_F
        # left hand + right foot swing in the first half, the other pair in the second
        for limb, sd, off in (
            ("hand", ".L", 0.0),
            ("foot", ".R", 0.0),
            ("hand", ".R", 0.5),
            ("foot", ".L", 0.5),
        ):
            e = empties[f"t_{limb}{sd}"]
            e.location = grip(limb, sd, (ph + off) % 1.0)
            e.keyframe_insert("location", frame=f)
        # hips: lean in, sway toward the gripping hand, small bob
        sway = math.sin(2 * math.pi * ph) * 0.035
        bob = math.cos(4 * math.pi * ph) * 0.015
        hb = arm.pose.bones[km["hips"]]
        rot = (
            Matrix.Rotation(math.radians(-LEAN_DEG), 4, "X")
            @ Matrix.Rotation(sway * 4.0, 4, "Y")
            @ Matrix.Rotation(sway * 2.5, 4, "Z")
        )
        m = rest_hip.copy()
        loc = m.translation + Vector((sway, 0.04, -0.02 + bob))
        m = Matrix.Translation(loc) @ rot @ m.to_3x3().to_4x4()
        hb.matrix = mw.inverted() @ m
        hb.keyframe_insert("location", frame=f)
        hb.keyframe_insert("rotation_quaternion", frame=f)
        bpy.context.view_layer.update()
        # spine curls in toward the trunk, head turns down and over the shoulder
        for key, deg in (("spine1", 6.0), ("spine2", 6.0), ("spine3", 4.0)):
            pb = arm.pose.bones[km[key]]
            pb.rotation_quaternion = (Matrix.Rotation(math.radians(deg), 4, "X")).to_quaternion()
            pb.keyframe_insert("rotation_quaternion", frame=f)
        hd = arm.pose.bones[km["head"]]
        look = math.sin(2 * math.pi * ph * 0.5) * 0.25
        hd.rotation_quaternion = (
            Matrix.Rotation(math.radians(22.0), 4, "X") @ Matrix.Rotation(look, 4, "Y")
        ).to_quaternion()
        hd.keyframe_insert("rotation_quaternion", frame=f)
    # bake visual pose into a clean action, drop IK
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.nla.bake(
        frame_start=0,
        frame_end=CYCLE_F,
        only_selected=True,
        visual_keying=True,
        clear_constraints=True,
        use_current_action=False,
        bake_types={"POSE"},
    )
    bpy.ops.object.mode_set(mode="OBJECT")
    baked = arm.animation_data.action
    baked.name = "climb_down"
    baked.use_fake_user = True
    arm.animation_data.action = None
    bpy.data.actions.remove(act)
    for e in empties.values():
        bpy.data.objects.remove(e, do_unlink=True)
    log("climb_down frames", CYCLE_F + 1, "descent m", DESCENT_M)


# ------------------------------------------------------------------ check renders + export
def render_checks(arm) -> None:
    sc = bpy.context.scene
    try:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 640, 800
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.6, 0.65, 1)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sc.collection.objects.link(sun)
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    bpy.ops.mesh.primitive_cylinder_add(radius=TRUNK_R, depth=4.0, location=(0, TRUNK_Y, 0.8))
    trunk = bpy.context.active_object
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    for clip, frames, show_trunk in (
        ("climb_down", (0, 6, 12, 18), True),
        ("wake", (0, 40, 80, 120), False),
    ):
        trunk.hide_render = not show_trunk
        assign(arm, bpy.data.actions[clip])
        for f in frames:
            sc.frame_set(f)
            cam.location = Vector((2.4, 1.6, 1.2))
            cam.rotation_euler = (
                (Vector((0, -0.2, 0.75)) - cam.location).to_track_quat("-Z", "Y").to_euler()
            )
            sc.render.filepath = str(CHECK / f"hero_{clip}_{f:03d}.png")
            bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(trunk, do_unlink=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.data.objects.remove(sun, do_unlink=True)
    arm.animation_data.action = None


def export(arm, meshes) -> None:
    ad = arm.animation_data
    for name in list(KEEP) + ["wake", "climb_down"]:
        tr = ad.nla_tracks.new()
        tr.name = name
        tr.strips.new(name, 0, bpy.data.actions[name])
        tr.mute = True
    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for o in meshes:
        o.select_set(True)
    arm.name = "australopith_hero_rig"
    bpy.ops.export_scene.gltf(
        filepath=str(OUT),
        use_selection=True,
        export_format="GLB",
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_skins=True,
    )
    log("exported", OUT)


def main() -> None:
    arm, meshes, _keep = setup()
    retarget_wake(arm)
    climb(arm)
    render_checks(arm)
    export(arm, meshes)


main()
