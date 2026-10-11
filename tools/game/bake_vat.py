"""Headless Blender: skinned GLB -> vertex animation texture (VAT) + static mesh for the game.

blender -b --factory-startup -P tools/game/bake_vat.py -- <in.glb> <name> <height_m> <yaw_deg> <max_tris> <clip> [<clip> ...]
  clip = out_name:action[:first:last[:loop]]   (frames in the action's own numbering; loop 1/0, default 1)
  height_m  = height of the first clip's first frame after scaling (feet at y = 0)
  yaw_deg   = turn about the vertical axis so the body faces Godot +Z (the game's unit forward)
blender ... -- --sheet <in.glb> <out.png> <action> <first> <last> <step>   (contact sheet to find clip ranges)

Writes assets/vat/<name>.glb      static mesh at the first clip's first frame, materials kept,
                                  UV2.x = (vertex id + 0.5) / vertex count, UV2.y = rest height / body height
       assets/vat/<name>.vat      raw little-endian float16 RGBA, width 2048 (1024 vertices x [position, normal]),
                                  rows_per_frame = ceil(vertices / 1024) rows per sampled frame, frames stacked
       assets/vat/<name>.json     vertex count, rows per frame, fps, clips {name: [first_row_frame, frames, loop]}
Positions and normals are in Godot space (x, y up, z), metres. Samples at FPS frames per second of action time.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/vat"
FPS = 15.0
COLS = 1024

args = sys.argv[sys.argv.index("--") + 1 :]


def import_glb(path: str):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    skinned = [
        o
        for o in bpy.data.objects
        if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)
    ]
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o not in skinned:
            bpy.data.objects.remove(o, do_unlink=True)
    return arm, skinned


def set_action(arm, name: str):
    act = next(a for a in bpy.data.actions if a.name == name or name in a.name)
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    if (
        hasattr(arm.animation_data, "action_suitable_slots")
        and arm.animation_data.action_suitable_slots
    ):
        arm.animation_data.action_slot = arm.animation_data.action_suitable_slots[0]
    return act


def set_time(frame: float):
    sc = bpy.context.scene
    f = int(math.floor(frame))
    sc.frame_set(f, subframe=frame - f)


def sheet():
    _, path, out, action, first, last, step = args
    arm, meshes = import_glb(path)
    set_action(arm, action)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = 256, 256
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    tiles = []
    frames = list(range(int(first), int(last) + 1, int(step)))
    import tempfile

    tmp = Path(tempfile.mkdtemp())
    for f in frames:
        set_time(f)
        dg = bpy.context.evaluated_depsgraph_get()
        pts = []
        for o in meshes:
            ev = o.evaluated_get(dg)
            m = ev.to_mesh()
            pts += [o.matrix_world @ v.co for v in m.vertices]
            ev.to_mesh_clear()
        mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        c = (mn + mx) / 2
        r = (mx - mn).length
        cam.data.ortho_scale = r * 1.1
        cam.location = c + Vector((r * 2, 0, 0))
        cam.rotation_euler = (math.radians(90), 0, math.radians(90))
        sc.render.filepath = str(tmp / f"{f:04d}.png")
        bpy.ops.render.render(write_still=True)
        tiles.append(sc.render.filepath)
    n = len(tiles)
    cols = 8
    rows = (n + cols - 1) // cols
    big = bpy.data.images.new("sheet", 256 * cols, 256 * rows)
    px = np.zeros((256 * rows, 256 * cols, 4), np.float32)
    for i, t in enumerate(tiles):
        im = bpy.data.images.load(t)
        a = np.array(im.pixels[:], np.float32).reshape(256, 256, 4)
        r_, c_ = divmod(i, cols)
        px[(rows - 1 - r_) * 256 : (rows - r_) * 256, c_ * 256 : (c_ + 1) * 256] = a
    big.pixels[:] = px.ravel()
    big.filepath_raw = out
    big.file_format = "PNG"
    big.save()
    print("SHEET", out, "frames", frames)


def bake():
    path, name, height, yaw_deg, max_tris = (
        args[0],
        args[1],
        float(args[2]),
        float(args[3]),
        int(args[4]),
    )
    clips = []
    for spec in args[5:]:
        p = spec.split(":")
        clips.append(
            {
                "name": p[0],
                "action": p[1],
                "first": float(p[2]) if len(p) > 2 else None,
                "last": float(p[3]) if len(p) > 3 else None,
                "loop": (p[4] != "0") if len(p) > 4 else True,
            }
        )
    arm, meshes = import_glb(path)
    # one mesh: join the skinned meshes (same armature)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    me = obj.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    if max_tris and tris > max_tris:
        dec = obj.modifiers.new("dec", "DECIMATE")
        dec.ratio = max_tris / tris
        bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
        bpy.ops.object.modifier_apply(modifier="dec")
        me.calc_loop_triangles()
        print("decimated", tris, "->", len(me.loop_triangles))
    nv = len(me.vertices)
    sc = bpy.context.scene
    scene_fps = sc.render.fps / sc.render.fps_base

    def sample() -> tuple[np.ndarray, np.ndarray]:
        dg = bpy.context.evaluated_depsgraph_get()
        ev = obj.evaluated_get(dg)
        m = ev.to_mesh()
        assert len(m.vertices) == nv, "topology changed during evaluation"
        co = np.empty(nv * 3, np.float32)
        m.vertices.foreach_get("co", co)
        nr = np.empty(nv * 3, np.float32)
        m.vertices.foreach_get("normal", nr)
        ev.to_mesh_clear()
        mw = np.array(obj.matrix_world, np.float32)
        co = co.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
        nr = nr.reshape(-1, 3) @ np.linalg.inv(mw[:3, :3])
        nr /= np.maximum(np.linalg.norm(nr, axis=1, keepdims=True), 1e-8)
        # Blender (x, y, z up) -> Godot (x, y up, z) = (x, z, -y)
        return co[:, [0, 2, 1]] * [1, 1, -1], nr[:, [0, 2, 1]] * [1, 1, -1]

    frames_pos = []
    frames_nrm = []
    meta_clips = {}
    rest = None
    for c in clips:
        act = set_action(arm, c["action"])
        f0 = c["first"] if c["first"] is not None else act.frame_range[0]
        f1 = c["last"] if c["last"] is not None else act.frame_range[1]
        dur = (f1 - f0) / scene_fps
        n = max(1, int(round(dur * FPS)))
        if not c["loop"]:
            n += 1
        start = len(frames_pos)
        for k in range(n):
            set_time(f0 + k / FPS * scene_fps)
            p, q = sample()
            frames_pos.append(p)
            frames_nrm.append(q)
            if rest is None:
                set_time(f0)
                rest = sample()[0]
        meta_clips[c["name"]] = [start, n, 1 if c["loop"] else 0]
        print("clip", c["name"], c["action"], f0, f1, "frames", n)
    pos = np.stack(frames_pos)  # F, V, 3
    nrm = np.stack(frames_nrm)
    # normalise: turn to face +Z, feet at 0, centred on x/z, scaled to height
    a = math.radians(yaw_deg)
    rot = np.array(
        [[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]], np.float32
    )
    pos = pos @ rot.T
    nrm = nrm @ rot.T
    rest = rest @ rot.T
    s = height / (rest[:, 1].max() - rest[:, 1].min())
    off = np.array(
        [
            (rest[:, 0].max() + rest[:, 0].min()) / 2,
            rest[:, 1].min(),
            (rest[:, 2].max() + rest[:, 2].min()) / 2,
        ]
    )
    pos = (pos - off) * s
    rest = (rest - off) * s
    print("rest size", np.round(rest.max(0) - rest.min(0), 3))
    top = rest[:, 1] > np.percentile(rest[:, 1], 92)
    print(
        "head offset x/z (body faces the larger |z| sign if >0)",
        np.round(rest[top].mean(0) - rest.mean(0), 3),
    )
    # texture: rows_per_frame x 2048 texels per frame, [pos, normal] per vertex
    rpf = (nv + COLS - 1) // COLS
    nf = pos.shape[0]
    tex = np.zeros((nf * rpf, COLS * 2, 4), np.float16)
    pad = rpf * COLS
    for f in range(nf):
        pp = np.zeros((pad, 4), np.float32)
        pp[:nv, :3] = pos[f]
        pp[:nv, 3] = 1.0
        qq = np.zeros((pad, 4), np.float32)
        qq[:nv, :3] = nrm[f]
        blk = np.stack([pp, qq], 1).reshape(rpf, COLS * 2, 4)
        tex[f * rpf : (f + 1) * rpf] = blk.astype(np.float16)
    OUT.mkdir(parents=True, exist_ok=True)
    tex.astype("<f2").tofile(OUT / f"{name}.vat")
    meta = {
        "vertices": nv,
        "rows_per_frame": rpf,
        "width": COLS * 2,
        "height": nf * rpf,
        "fps": FPS,
        "body_height": height,
        "clips": meta_clips,
    }
    (OUT / f"{name}.json").write_text(json.dumps(meta, indent=1))
    # static mesh: the first frame, with UV2 = (vertex id, rest height)
    # write the rest frame back in Blender space (Godot -> Blender = (x, -z, y)), unparented
    for mod in list(obj.modifiers):
        obj.modifiers.remove(mod)
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
    rb = rest
    me.vertices.foreach_set(
        "co", np.stack([rb[:, 0], -rb[:, 2], rb[:, 1]], 1).astype(np.float32).ravel()
    )
    obj.vertex_groups.clear()
    # keep only the texture UV map so the id layer exports as TEXCOORD_1 (= Godot UV2); the
    # australopith source carries a second UV map and the id layer silently became TEXCOORD_2
    while len(me.uv_layers) > 1:
        me.uv_layers.remove(me.uv_layers[-1])
    uv = me.uv_layers.new(name="vat")
    loops_v = np.empty(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", loops_v)
    hn = (rest[:, 1] - rest[:, 1].min()) / max(rest[:, 1].max() - rest[:, 1].min(), 1e-6)
    uvs = np.stack([(loops_v + 0.5) / nv, hn[loops_v]], 1).astype(np.float32)
    uv.data.foreach_set("uv", uvs.ravel())
    me.update()
    for o in list(bpy.data.objects):
        if o is not obj:
            bpy.data.objects.remove(o, do_unlink=True)
    for a_ in list(bpy.data.actions):
        bpy.data.actions.remove(a_)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    obj.name = name
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / f"{name}.glb"),
        use_selection=True,
        export_format="GLB",
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_attributes=False,
    )
    print(
        "VAT", name, "verts", nv, "frames", nf, "tex", COLS * 2, "x", nf * rpf, "clips", meta_clips
    )


if args[0] == "--sheet":
    sheet()
else:
    bake()
