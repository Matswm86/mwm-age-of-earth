"""Realistic character -> game GLB with RTS clips baked from Quaternius UAL (CC0). Copied from mwm-wayfarer.

Run: blender -b --factory-startup -P tools/assets/retarget_char.py -- <char.glb> <name> <height_m> <albedo_hi_png|-> [max_tris]
Writes assets/models/hominins/<name>/<name>.glb (+ _albedo/_normal/_orm.png, check renders <name>_face.png,
<name>_poses.png).

Retarget: bones are matched by canonical name (Rigify DEF-*, Mixamo, Unreal-style). The source is first
posed so every mapped bone points along the target's rest direction (handles T-pose vs A-pose), that
pose is the reference; per frame each target bone gets
    world_rot_target = world_rot_source(frame) @ inverse(world_rot_source(reference)) @ world_rot_target(rest)
Hips translation is scaled by the leg-length ratio. Loops come in place (UAL loops have no root motion).
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

REPO = Path(__file__).resolve().parents[2]
UAL = (
    Path.home()
    / "MWM/scratch/wayfarer/anim/ual1/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb"
)
args = sys.argv[sys.argv.index("--") + 1 :]
src_glb, name, height = args[0], args[1], float(args[2])
albedo_hi = args[3] if len(args) > 3 and args[3] != "-" else None
max_tris = int(args[4]) if len(args) > 4 else 0
OUT = REPO / "assets/models/hominins" / name
OUT.mkdir(parents=True, exist_ok=True)
CLIPS = {
    "idle": "Idle_Loop",
    "walk": "Walk_Loop",
    "run": "Jog_Fwd_Loop",
    "gather": "Fixing_Kneeling",  # knapping, digging tubers, butchering
    "pickup": "PickUp_Table",
    "attack": "Punch_Cross",  # Bruiser, unarmed
    "swing": "Sword_Attack",  # club / spear thrust stand-in
    "throw": "Spell_Simple_Shoot",  # Stone Thrower release
    "hit": "Hit_Chest",
    "death": "Death01",
    "crouch": "Crouch_Idle_Loop",
    "torch": "Idle_Torch_Loop",
    "sit": "Sitting_Idle_Loop",
}


def log(*a):
    print("RT", *a, flush=True)


def canon(n: str) -> str | None:
    n = re.sub(r"^.*mixamorig[:_]?", "", n)
    n = re.sub(r"^rp_.*_(walking|rigged|posed|animated)_", "", n)
    if not n.startswith("DEF-"):
        n = re.sub(r"_\d+$", "", n)  # glTF importer's numeric suffix
    side = ""
    m = re.search(r"(\.L|\.R|_l|_r)$", n)
    if m:
        side = ".L" if m.group(1) in (".L", "_l") else ".R"
        n = n[: m.start()]
    if n.startswith("Left"):
        side, n = ".L", n[4:]
    elif n.startswith("Right"):
        side, n = ".R", n[5:]
    n = n.replace("DEF-", "")
    table = {
        "hips": "hips",
        "Hips": "hips",
        "hip": "hips",
        "pelvis": "hips",
        "spine.001": "spine1",
        "Spine": "spine1",
        "spine_01": "spine1",
        "spine.002": "spine2",
        "Spine1": "spine2",
        "spine_02": "spine2",
        "spine.003": "spine3",
        "Spine2": "spine3",
        "spine_03": "spine3",
        "neck": "neck",
        "Neck": "neck",
        "head": "head",
        "Head": "head",
        "shoulder": "shoulder",
        "Shoulder": "shoulder",
        "upper_arm": "upperarm",
        "Arm": "upperarm",
        "upperarm": "upperarm",
        "forearm": "forearm",
        "ForeArm": "forearm",
        "lowerarm": "forearm",
        "hand": "hand",
        "Hand": "hand",
        "thigh": "thigh",
        "UpLeg": "thigh",
        "upperleg": "thigh",
        "shin": "shin",
        "Leg": "shin",
        "calf": "shin",
        "lowerleg": "shin",
        "foot": "foot",
        "Foot": "foot",
        "toe": "toe",
        "ToeBase": "toe",
        "ball": "toe",
    }
    if n in table:
        k = table[n]
        return (
            k + side
            if k in ("shoulder", "upperarm", "forearm", "hand", "thigh", "shin", "foot", "toe")
            else k
        )
    fm = re.match(r"^(?:f_)?(index|middle|ring|pinky|thumb)[._]?0?(\d)$", n) or re.match(
        r"^Hand(Index|Middle|Ring|Pinky|Thumb)(\d)$", n
    )
    if fm:
        f, i = fm.group(1).lower(), int(fm.group(2))
        if i <= 3:
            return f"{f}{i}{side}"
    return None


# ---------------------------------------------------------------- target
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=src_glb)
tarm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
tmeshes = [
    o
    for o in bpy.data.objects
    if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)
]
junk = [o for o in bpy.data.objects if o.type == "MESH" and o not in tmeshes]
for o in junk:
    log("drop unskinned mesh", o.name, tuple(round(v, 2) for v in o.dimensions))
    bpy.data.objects.remove(o, do_unlink=True)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
if tarm.animation_data:
    tarm.animation_data.action = None
    for tr in list(tarm.animation_data.nla_tracks):
        tarm.animation_data.nla_tracks.remove(tr)
for o in [tarm] + tmeshes:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in list(bpy.data.objects):
    if o.type == "EMPTY":
        bpy.data.objects.remove(o, do_unlink=True)
for pb in tarm.pose.bones:
    pb.matrix_basis = Matrix()
bpy.context.view_layer.update()


def eval_height():
    dg = bpy.context.evaluated_depsgraph_get()
    zs = []
    for o in tmeshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        co = np.empty(len(me.vertices) * 3, np.float32)
        me.vertices.foreach_get("co", co)
        co = (
            co.reshape(-1, 3) @ np.array(ev.matrix_world)[:3, :3].T
            + np.array(ev.matrix_world)[:3, 3]
        )
        zs.append(co)
        ev.to_mesh_clear()
    allc = np.concatenate(zs)
    return allc.min(0), allc.max(0)


mn, mx = eval_height()
s = height / (mx[2] - mn[2])
log("raw height", round(float(mx[2] - mn[2]), 3), "scale", round(s, 4))
for o in [tarm] + tmeshes:
    o.matrix_world = (
        Matrix.Translation((-(mn[0] + mx[0]) / 2 * s, -(mn[1] + mx[1]) / 2 * s, -mn[2] * s))
        @ Matrix.Scale(s, 4)
        @ o.matrix_world
    )
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
for o in [tarm] + tmeshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = tarm
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mn, mx = eval_height()
log("height now", round(float(mx[2] - mn[2]), 3))

# fragmented-UV meshes (RT_REBAKE=1): join, decimate, re-unwrap, bake albedo from the full mesh at 4K
import os  # noqa: E402

if max_tris and os.environ.get("RT_REBAKE") == "1":
    if albedo_hi:
        hi_img = bpy.data.images.load(albedo_hi)
        for o in tmeshes:
            for m in o.data.materials:
                b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                if (
                    b
                    and b.inputs["Base Color"].is_linked
                    and b.inputs["Base Color"].links[0].from_node.type == "TEX_IMAGE"
                ):
                    b.inputs["Base Color"].links[0].from_node.image = hi_img
        albedo_hi = None
    bpy.ops.object.select_all(action="DESELECT")
    for o in tmeshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = tmeshes[0]
    if len(tmeshes) > 1:
        bpy.ops.object.join()
    full = tmeshes[0]
    lo = full.copy()
    lo.data = full.data.copy()
    sc.collection.objects.link(lo)
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(lo.data)
    nv = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)  # glTF split every UV seam
    log("welded", nv, "->", len(bm.verts), "verts")
    bm.to_mesh(lo.data)
    bm.free()
    m_ = lo.modifiers.new("dec", "DECIMATE")
    m_.ratio = max_tris / sum(len(p.vertices) - 2 for p in lo.data.polygons)
    bpy.ops.object.select_all(action="DESELECT")
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
    bpy.ops.object.modifier_apply(modifier="dec")
    while lo.data.uv_layers:
        lo.data.uv_layers.remove(lo.data.uv_layers[0])
    lo.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.002)
    bpy.ops.object.mode_set(mode="OBJECT")
    newmat = bpy.data.materials.new(f"{name}_body")
    newmat.use_nodes = True
    lo.data.materials.clear()
    lo.data.materials.append(newmat)
    img = bpy.data.images.new(f"{name}_albedo", 4096, 4096, alpha=False)
    tn = newmat.node_tree.nodes.new("ShaderNodeTexImage")
    tn.image = img
    newmat.node_tree.nodes.active = tn
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 8
    bk = sc.render.bake
    bk.use_selected_to_active = True
    bk.cage_extrusion = 0.01
    bk.max_ray_distance = 0.04
    bk.margin = 8
    bk.use_pass_direct = bk.use_pass_indirect = False
    bk.use_pass_color = True
    bpy.ops.object.select_all(action="DESELECT")
    full.select_set(True)
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.bake(type="DIFFUSE")
    img.filepath_raw = str(OUT / f"{name}_albedo.png")
    img.file_format = "PNG"
    img.save()
    b = next(n for n in newmat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    newmat.node_tree.links.new(tn.outputs[0], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.8
    bpy.data.objects.remove(full, do_unlink=True)
    tmeshes = [lo]
    max_tris = 0
    log("rebaked albedo 4K on", len(lo.data.polygons), "tris")

# optional decimation (keeps vertex groups). RTS bodies need no facial morphs: drop shape keys so CC3-style
# bodies decimate too (Age of Earth change).
if max_tris:
    for o in tmeshes:
        if o.data.shape_keys:
            o.shape_key_clear()
    tot = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in tmeshes)
    if tot > max_tris:
        r = max_tris / tot
        for o in tmeshes:
            if o.data.shape_keys:
                continue
            m = o.modifiers.new("dec", "DECIMATE")
            m.ratio = r
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
            bpy.ops.object.modifier_apply(modifier="dec")
tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in tmeshes)
log("TRIS", tris)

# hi-res albedo: replace the base-colour image of every material
if albedo_hi:
    hi = bpy.data.images.load(albedo_hi)
    for o in tmeshes:
        for m in o.data.materials:
            b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if b and b.inputs["Base Color"].is_linked:
                n = b.inputs["Base Color"].links[0].from_node
                if n.type == "TEX_IMAGE":
                    n.image = hi
    log("albedo", albedo_hi, tuple(hi.size))

# ---------------------------------------------------------------- source
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(UAL))
new = [o for o in bpy.data.objects if o not in before]
sarm = next(o for o in new if o.type == "ARMATURE")
for o in new:
    if o.type == "MESH":
        o.hide_render = True
        o.hide_viewport = True
src_actions = {a.name: a for a in bpy.data.actions}
if sarm.animation_data is None:
    sarm.animation_data_create()

tmap = {}
for b in tarm.data.bones:
    k = canon(b.name)
    if k and k not in tmap:
        tmap[k] = b.name
smap = {}
for b in sarm.data.bones:
    k = canon(b.name)
    if k and k not in smap:
        smap[k] = b.name
pairs = [(k, smap[k], tmap[k]) for k in tmap if k in smap]
log("mapped", len(pairs), "missing in target", sorted(set(smap) - set(tmap)))
order = [b.name for b in tarm.data.bones]  # bones are listed parents-first
pairs.sort(key=lambda p: order.index(p[2]))


# scale source to the target's size (hip height)
def bone_head_w(arm, bn):
    return arm.matrix_world @ arm.data.bones[bn].head_local


s_hip = bone_head_w(sarm, smap["hips"]).z
t_hip = bone_head_w(tarm, tmap["hips"]).z
leg_ratio = t_hip / s_hip
log("hip heights", round(s_hip, 3), round(t_hip, 3))


# facing check: toe ahead of foot along -Y in both?
def facing(arm, mp):
    return (bone_head_w(arm, mp["toe.L"]) - bone_head_w(arm, mp["foot.L"])).y


if facing(sarm, smap) * facing(tarm, tmap) < 0:
    sarm.rotation_euler.z += math.pi
    bpy.context.view_layer.update()
    log("source turned 180 deg to face like the target")


def world_rot(arm, bn):
    return (arm.matrix_world @ arm.pose.bones[bn].matrix).to_3x3().normalized()


# reference pose: source bones pointed along the target's rest directions
sarm.animation_data.action = None
for pb in sarm.pose.bones:
    pb.matrix_basis = Matrix()
bpy.context.view_layer.update()
CHILD = {"hips": "spine1", "spine1": "spine2", "spine2": "spine3", "spine3": "neck", "neck": "head"}
for sd in (".L", ".R"):
    CHILD.update(
        {
            f"shoulder{sd}": f"upperarm{sd}",
            f"upperarm{sd}": f"forearm{sd}",
            f"forearm{sd}": f"hand{sd}",
            f"hand{sd}": f"middle1{sd}",
            f"thigh{sd}": f"shin{sd}",
            f"shin{sd}": f"foot{sd}",
            f"foot{sd}": f"toe{sd}",
        }
    )
    for fg in ("thumb", "index", "middle", "ring", "pinky"):
        CHILD.update({f"{fg}1{sd}": f"{fg}2{sd}", f"{fg}2{sd}": f"{fg}3{sd}"})
PARENT = {v: k for k, v in CHILD.items()}
common = {k for k, _, _ in pairs}


def chain_dir(arm, mp, key, posed):
    """Direction along the limb: this bone's head -> its mapped child's head (bone axes from glTF are arbitrary)."""

    def hp(k):
        if posed:
            return arm.matrix_world @ arm.pose.bones[mp[k]].head
        return arm.matrix_world @ arm.data.bones[mp[k]].head_local

    ch = CHILD.get(key)
    if ch in common:
        return (hp(ch) - hp(key)).normalized()
    par = PARENT.get(key)
    if par in common:
        return (hp(key) - hp(par)).normalized()
    return None


for k, sb, tb in pairs:
    if k == "hips":
        continue
    pb = sarm.pose.bones[sb]
    have = chain_dir(sarm, smap, k, True)
    want = chain_dir(tarm, tmap, k, False)
    if have is None or want is None:
        continue
    ch = CHILD.get(k)
    if ch not in common:
        continue  # leaves follow their parent; aligning them again would double-rotate
    cur = sarm.matrix_world @ pb.matrix
    rot = have.rotation_difference(want).to_matrix()
    new_w = Matrix.Translation(cur.translation) @ (rot @ cur.to_3x3()).to_4x4()
    pb.matrix = sarm.matrix_world.inverted() @ new_w
    bpy.context.view_layer.update()
ref = {sb: world_rot(sarm, sb) for _, sb, _ in pairs}
ref_hip = (sarm.matrix_world @ sarm.pose.bones[smap["hips"]].matrix).translation.copy()
trest = {
    tb: (tarm.matrix_world @ tarm.data.bones[tb].matrix_local).to_3x3().normalized()
    for _, _, tb in pairs
}
corr = {sb: ref[sb].inverted() @ trest[tb] for _, sb, tb in pairs}
t_hip_rest = (tarm.matrix_world @ tarm.data.bones[tmap["hips"]].matrix_local).translation.copy()


def solve_frame():
    for pb in tarm.pose.bones:
        pb.matrix_basis = Matrix()
    bpy.context.view_layer.update()
    for k, sb, tb in pairs:
        w = world_rot(sarm, sb) @ corr[sb]
        tpb = tarm.pose.bones[tb]
        cur = tarm.matrix_world @ tpb.matrix
        loc = cur.translation
        if k == "hips":
            s_now = (sarm.matrix_world @ sarm.pose.bones[sb].matrix).translation
            loc = t_hip_rest + (s_now - ref_hip) * leg_ratio
        tpb.matrix = tarm.matrix_world.inverted() @ (Matrix.Translation(loc) @ w.to_4x4())
        bpy.context.view_layer.update()


# self-test: the source held in its reference pose must give the target's rest pose
solve_frame()
err = max(
    math.degrees(
        (tarm.matrix_world @ tarm.pose.bones[tb].matrix)
        .to_quaternion()
        .rotation_difference((tarm.matrix_world @ tarm.data.bones[tb].matrix_local).to_quaternion())
        .angle
    )
    for _, _, tb in pairs
)
log("self-test max bone error deg", round(err, 3))

if tarm.animation_data is None:
    tarm.animation_data_create()
baked = {}
for clip, sname in CLIPS.items():
    if sname not in src_actions:
        log("missing clip", sname)
        continue
    sact = src_actions[sname]
    sarm.animation_data.action = sact
    if (
        hasattr(sarm.animation_data, "action_suitable_slots")
        and sarm.animation_data.action_suitable_slots
    ):
        sarm.animation_data.action_slot = sarm.animation_data.action_suitable_slots[0]
    f0, f1 = (int(round(v)) for v in sact.frame_range)
    tact = bpy.data.actions.new(clip)
    tarm.animation_data.action = tact
    sc.frame_set(f0 + (f1 - f0) // 2)
    hp = (sarm.matrix_world @ sarm.pose.bones[smap["hips"]].matrix).translation
    lf = (sarm.matrix_world @ sarm.pose.bones[smap["foot.L"]].matrix).translation
    log(
        clip,
        "src mid-frame hips",
        tuple(round(v, 2) for v in hp),
        "footL",
        tuple(round(v, 2) for v in lf),
    )
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        solve_frame()
        if f == f0 and clip == "idle":
            for k, sb, tb in pairs:
                if k in (
                    "hips",
                    "spine1",
                    "spine2",
                    "spine3",
                    "neck",
                    "head",
                    "thigh.L",
                    "shin.L",
                    "upperarm.L",
                ):
                    sy = (
                        sarm.matrix_world @ sarm.pose.bones[sb].matrix
                    ).to_3x3().normalized() @ Vector((0, 1, 0))
                    ty = (
                        tarm.matrix_world @ tarm.pose.bones[tb].matrix
                    ).to_3x3().normalized() @ Vector((0, 1, 0))
                    log(
                        "dir",
                        k,
                        "src",
                        tuple(round(v, 2) for v in sy),
                        "tgt",
                        tuple(round(v, 2) for v in ty),
                    )
        for k, sb, tb in pairs:
            tpb = tarm.pose.bones[tb]
            tpb.keyframe_insert("rotation_quaternion", frame=f - f0)
            if k == "hips":
                tpb.keyframe_insert("location", frame=f - f0)
    tact.use_fake_user = True
    baked[clip] = f1 - f0 + 1
    log("baked", clip, f1 - f0 + 1, "frames")

# stash each action on its own NLA track so the exporter writes them all
tarm.animation_data.action = None
for clip in baked:
    tr = tarm.animation_data.nla_tracks.new()
    tr.name = clip
    tr.strips.new(clip, 0, bpy.data.actions[clip])
    tr.mute = True

# ---------------------------------------------------------------- texture set (albedo, normal, orm)
from_img = None
for o in tmeshes:
    for m in o.data.materials:
        b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if (
            b
            and b.inputs["Base Color"].is_linked
            and b.inputs["Base Color"].links[0].from_node.type == "TEX_IMAGE"
        ):
            from_img = from_img or b.inputs["Base Color"].links[0].from_node.image
log("main albedo image", from_img.name if from_img else None)

# ---------------------------------------------------------------- export
for o in list(bpy.data.objects):
    if o in new:
        bpy.data.objects.remove(o, do_unlink=True)
for a in list(bpy.data.actions):
    if a.name not in baked:
        bpy.data.actions.remove(a)
for o in list(
    bpy.data.objects
):  # stray helpers (e.g. an Icosphere from the source file) must not export
    if o is not tarm and o not in tmeshes:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
tarm.select_set(True)
for o in tmeshes:
    o.select_set(True)
tarm.name = f"{name}_rig"
bpy.ops.export_scene.gltf(
    filepath=str(OUT / f"{name}.glb"),
    use_selection=True,
    export_format="GLB",
    export_image_format="AUTO",
    export_animations=True,
    export_animation_mode="NLA_TRACKS",
    export_force_sampling=True,
    export_morph=True,
    export_skins=True,
)
log("exported", OUT / f"{name}.glb", "clips", baked)
bpy.ops.wm.save_as_mainfile(filepath=str(REPO / "assets/_raw/build" / f"{name}_rt.blend"))
