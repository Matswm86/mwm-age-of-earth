"""Headless Blender: source GLBs (assets/models) -> phone-ready GLBs for the game (assets/game_models).

blender -b --factory-startup -P tools/game/optimize_models.py -- [name ...]   (no names = all)

Per model: drop parts by material name, optionally cut the banyan aerial roots (not East African,
DESIGN 11.3), join into one object (one Godot mesh, one surface per material) unless keep_parts,
decimate to a triangle budget, apply transforms, export GLB with textures. Sizes stay as authored;
the game scales instances (DESIGN 7.5).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/models"
OUT = ROOT / "assets/game_models"

# name: (source, max_tris, options)
MODELS = {
    "home_fig": ("trees/home_fig.glb", 30000, {"cut_roots": True, "drop": r"Vines"}),
    "acacia": ("trees/acacia_tortilis.glb", 8200, {}),
    "doum_palm": (
        "trees/doum_palm.glb",
        9000,
        {"drop": r"fur|spines|cut stalk|stalk_0[236]|crownshaft"},
    ),
    "shrub_searsia": ("plants/shrub_searsia.glb", 3000, {}),
    "shrub_leafy": ("plants/shrub_leafy.glb", 2000, {}),
    "grass": ("plants/grass_tuft.glb", 0, {"keep_parts": True, "part_ratio": 0.35}),
    "cobbles": ("rocks/cobbles.glb", 700, {}),
    "stones": ("rocks/stones.glb", 500, {}),
    "boulder_a": ("rocks/boulder_a.glb", 2000, {}),
    "boulder_b": ("rocks/boulder_b.glb", 1600, {}),
    "boulder_c": ("rocks/boulder_c.glb", 1200, {}),
    "branch_heap": ("props/branch_heap.glb", 3000, {}),
    "dry_branches": ("props/dry_branches.glb", 1500, {}),
    "dead_branch": ("props/dead_branch.glb", 1500, {}),
    "hearth_stones": ("props/hearth_stones.glb", 2000, {}),
    "lithic_core": ("props/lithic_core.glb", 600, {}),
    "hand_axe": ("props/hand_axe.glb", 600, {}),
    "tuber": ("props/tuber.glb", 400, {}),
    "carcass_bones": ("props/carcass_bones.glb", 4000, {}),
    "crocodile": ("animals/crocodile.glb", 5000, {}),
    "hyena": ("animals/hyena.glb", 5000, {}),
}


def tris(o) -> int:
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def decimate(o, ratio: float) -> None:
    if ratio >= 0.999:
        return
    bpy.context.view_layer.objects.active = o
    m = o.modifiers.new("dec", "DECIMATE")
    m.ratio = ratio
    bpy.ops.object.modifier_apply(modifier="dec")


def cut_roots(o) -> None:
    """Banyan: delete bark islands that hang from the crown (aerial roots). An island is a root when
    it is much taller than wide, away from the trunk and below the top of the crown."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    zmin = min(v.co.z for v in bm.verts)
    zmax = max(v.co.z for v in bm.verts)
    h = zmax - zmin
    # trunk axis = centroid of the lowest 4 % of vertices weighted by density
    low = [v.co for v in bm.verts if v.co.z < zmin + 0.04 * h]
    c = sum(low, Vector()) / max(len(low), 1)
    seen = set()
    kill = []
    for f0 in bm.faces:
        if f0.index in seen:
            continue
        isl = []
        stack = [f0]
        seen.add(f0.index)
        while stack:
            f = stack.pop()
            isl.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        vs = {v for f in isl for v in f.verts}
        xs = [v.co.x for v in vs]
        ys = [v.co.y for v in vs]
        zs = [v.co.z for v in vs]
        horiz = max(max(xs) - min(xs), max(ys) - min(ys))
        tall = max(zs) - min(zs)
        foot = Vector((sum(xs) / len(xs), sum(ys) / len(ys), 0))
        r = (foot - Vector((c.x, c.y, 0))).length
        hanging = tall > 2.5 * horiz and tall > 0.05 * h
        if hanging and r > 0.07 * h and max(zs) < zmin + 0.8 * h:
            kill += isl
    print("cut_roots: removing", len(kill), "faces of", len(bm.faces))
    bmesh.ops.delete(bm, geom=list(set(kill)), context="FACES")
    bm.to_mesh(o.data)
    bm.free()


def run(name: str) -> None:
    src, max_tris, opt = MODELS[name]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SRC / src))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    # apply parent transforms, unparent
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.name != "Icosphere"]
    for o in list(bpy.data.objects):
        if o not in meshes:
            bpy.data.objects.remove(o, do_unlink=True)
    if "drop" in opt:
        rx = re.compile(opt["drop"])
        for o in list(meshes):
            if any(
                m and rx.search(m.name.replace(" ", "_")) for m in o.data.materials
            ) or rx.search(o.name):
                meshes.remove(o)
                bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if opt.get("cut_roots"):
        bark = next(o for o in meshes if any("Bark" in m.name for m in o.data.materials))
        cut_roots(bark)
    before = sum(tris(o) for o in meshes)
    if opt.get("keep_parts"):
        for o in meshes:
            decimate(o, opt["part_ratio"])
    else:
        if len(meshes) > 1:
            bpy.ops.object.join()
        o = bpy.context.view_layer.objects.active
        meshes = [o]
        if max_tris:
            decimate(o, max_tris / max(tris(o), 1))
    after = sum(tris(o) for o in meshes)
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / f"{name}.glb"),
        use_selection=True,
        export_format="GLB",
        export_animations=False,
    )
    mn = Vector(
        (
            min(min((o.matrix_world @ Vector(c)).x for c in o.bound_box) for o in meshes),
            min(min((o.matrix_world @ Vector(c)).y for c in o.bound_box) for o in meshes),
            min(min((o.matrix_world @ Vector(c)).z for c in o.bound_box) for o in meshes),
        )
    )
    mx = Vector(
        (
            max(max((o.matrix_world @ Vector(c)).x for c in o.bound_box) for o in meshes),
            max(max((o.matrix_world @ Vector(c)).y for c in o.bound_box) for o in meshes),
            max(max((o.matrix_world @ Vector(c)).z for c in o.bound_box) for o in meshes),
        )
    )
    print(
        f"MODEL {name}: tris {before} -> {after}, parts {len(meshes)}, size (x, y, z-up) "
        f"{[round(v, 2) for v in (mx - mn)]}, min {[round(v, 2) for v in mn]}"
    )


names = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
for n in names or list(MODELS):
    run(n)
