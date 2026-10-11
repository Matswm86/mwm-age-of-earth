"""Headless Blender: one 3/4 view per GLB under the look HDRI, for quality review.
blender -b --factory-startup -P tools/assets/preview_glb.py -- <out_dir> a.glb [b.glb ...]"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
HDRI = ROOT / "assets/_raw/polyhaven/hdri/qwantani_late_afternoon_4k.hdr"
args = sys.argv[sys.argv.index("--") + 1 :]
out = Path(args[0])
out.mkdir(parents=True, exist_ok=True)
for path in args[1:]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    try:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 512
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    env = w.node_tree.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(str(HDRI))
    w.node_tree.links.new(env.outputs[0], w.node_tree.nodes["Background"].inputs[0])
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in sc.objects if o.type == "MESH"]
    mn = Vector((1e9,) * 3)
    mx = -mn
    for o in meshes:
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, p))
            mx = Vector(map(max, mx, p))
    ctr = (mn + mx) / 2
    r = (mx - mn).length / 2
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 50
    d = r / math.tan(cam.data.angle / 2) * 1.05
    cam.location = ctr + Vector((0.75, -0.9, 0.45)).normalized() * d
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.clip_end = d * 10
    cam.data.clip_start = d / 1000
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sc.collection.objects.link(sun)
    sun.data.energy = 3
    sun.rotation_euler = (math.radians(55), 0, math.radians(40))
    sc.render.filepath = str(out / (Path(path).stem + ".png"))
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", sc.render.filepath)
