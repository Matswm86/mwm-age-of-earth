"""Headless Blender: list meshes, triangles, materials + texture maps, armature bones and actions of GLBs.
blender -b --factory-startup -P tools/assets/inspect_glb.py -- a.glb [b.glb ...]"""

import sys

import bpy

for path in sys.argv[sys.argv.index("--") + 1 :]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    tris = 0
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    maps = set()
    for m in bpy.data.materials:
        if m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image:
                    for lk in n.outputs[0].links:
                        maps.add(
                            lk.to_socket.name
                            if lk.to_node.type == "BSDF_PRINCIPLED"
                            else lk.to_node.type
                        )
                    maps.add(f"{n.image.size[0]}px")
    import mathutils

    mn = mathutils.Vector((1e9,) * 3)
    mx = -mn
    for o in bpy.data.objects:
        if o.type == "MESH":
            for c in o.bound_box:
                w = o.matrix_world @ mathutils.Vector(c)
                mn = mathutils.Vector(map(min, mn, w))
                mx = mathutils.Vector(map(max, mx, w))
    print(
        f"GLB {path.split('/')[-1]} tris={tris} mats={len(bpy.data.materials)} maps={sorted(maps)} "
        f"bones={sum(len(a.data.bones) for a in arms)} actions={[a.name for a in bpy.data.actions][:8]} "
        f"size={[round(v, 2) for v in (mx - mn)]}"
    )
