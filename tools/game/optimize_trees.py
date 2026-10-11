"""Headless Blender: PlantCatalog trees (Sketchfab, CC BY) -> phone-ready tree GLBs for the game.

blender -b --factory-startup -P tools/game/optimize_trees.py -- [name ...]   (no names = all)

Leaf cards cannot go through a Decimate modifier (it collapses the cards into slivers), so per tree:
drop fruit / flower / stalk parts, thin the leaf cards by deleting whole random card islands and
growing the kept cards so the crown keeps its cover, decimate only the bark and branches, shrink
textures (leaves 1024 px, bark 1024 px), and export one GLB (one surface per material, Y-up in
Godot) to assets/game_models/<name>.glb. Sizes stay as authored; the game scales instances.
Sources: assets/_raw/sketchfab/trees2/<uid>.glb with the API licence record next to each (CREDITS.md).
"""

from __future__ import annotations

import random
import re
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets/_raw/sketchfab/trees2"
OUT = ROOT / "assets/game_models"

# name: (uid, leaf islands kept, max bark/branch tris, drop regex[, max card growth[, browse
# line m: leaf cards whose centre is lower are removed, so the trunk shows and units stay visible]])
# Delonix (poinciana) cards are whole leaf sprays: grown much they read as cartoon blobs.
TREES = {
    "chinaberry_a": (
        "6e9ad5fa65784b189d9aaf0d2fb77e40",
        0.22,
        22000,
        r"fruit|flower|stalk",
        1.6,
        1.4,
    ),
    "chinaberry_b": (
        "24dc62d8e4d04297987b9c19784458f0",
        0.24,
        20000,
        r"fruit|flower|stalk",
        1.6,
        1.4,
    ),
    # the Home Tree: the same Melia, crown kept dense (focal object, one per home)
    "home_tree": ("6e9ad5fa65784b189d9aaf0d2fb77e40", 0.55, 40000, r"fruit|flower|stalk", 1.2, 2.2),
    # far LODs (beyond ~45 m, and the shadow caster at every range): few, large leaf cards
    "chinaberry_a_far": (
        "6e9ad5fa65784b189d9aaf0d2fb77e40",
        0.05,
        9000,
        r"fruit|flower|stalk",
        3.2,
        1.4,
    ),
    "chinaberry_b_far": (
        "24dc62d8e4d04297987b9c19784458f0",
        0.05,
        8000,
        r"fruit|flower|stalk",
        3.2,
        1.4,
    ),
    "chinaberry_young_far": (
        "243119a8928f42ceb37951559a7461f1",
        0.12,
        2500,
        r"fruit|flower|stalk",
        2.4,
    ),
    "poinciana_b_far": ("b6fe3f23c7964e9f94703bf5c1b3099c", 0.07, 12000, r"^$", 2.2),
    "chinaberry_young": ("243119a8928f42ceb37951559a7461f1", 0.6, 9000, r"fruit|flower|stalk"),
    "poinciana_b": ("b6fe3f23c7964e9f94703bf5c1b3099c", 0.38, 36000, r"^$", 1.15),
    "fig_bush": ("3a0e18aff86f4b0daf02ff75745a0ae0", 0.3, 3000, r"y2a|_y1", 1.35),
}
LEAF_RX = re.compile(r"leaf|lf_|twig|needle", re.I)
MAX_TEX = 1024


def tris(o) -> int:
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def thin_leaves(o, keep: float, rng: random.Random, max_grow: float = 1.6) -> None:
    """Deletes whole leaf-card islands (faces of leaf materials), keeping `keep` of them, and scales
    the kept cards about their centre by 1/sqrt(keep) (capped) so the crown cover holds."""
    leaf_idx = {i for i, m in enumerate(o.data.materials) if m and LEAF_RX.search(m.name)}
    if not leaf_idx or keep >= 0.999:
        return
    grow = min(1.0 / keep**0.5, max_grow)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    seen: set[int] = set()
    kill = []
    for f0 in bm.faces:
        if f0.index in seen or f0.material_index not in leaf_idx:
            continue
        isl = []
        stack = [f0]
        seen.add(f0.index)
        while stack:
            f = stack.pop()
            isl.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen and g.material_index in leaf_idx:
                        seen.add(g.index)
                        stack.append(g)
        if rng.random() > keep:
            kill += isl
        else:
            vs = {v for f in isl for v in f.verts}
            c = sum((v.co for v in vs), Vector()) / len(vs)
            for v in vs:
                v.co = c + (v.co - c) * grow
    print(f"thin_leaves: {len(kill)} of {len(bm.faces)} faces removed, cards x{grow:.2f}")
    bmesh.ops.delete(bm, geom=list(set(kill)), context="FACES")
    bm.to_mesh(o.data)
    bm.free()


def drop_faces(o, rx: re.Pattern) -> None:
    idx = {i for i, m in enumerate(o.data.materials) if m and rx.search(m.name)}
    if not idx:
        return
    bm = bmesh.new()
    bm.from_mesh(o.data)
    kill = [f for f in bm.faces if f.material_index in idx]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(o.data)
    bm.free()
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.material_slot_remove_unused()
    print(f"drop_faces: {len(kill)} faces")


def bark_verts(o) -> list:
    """World positions of the vertices on non-leaf faces (bark, trunk, branches)."""
    leaf_idx = {i for i, m in enumerate(o.data.materials) if m and LEAF_RX.search(m.name)}
    ids = {v for p in o.data.polygons if p.material_index not in leaf_idx for v in p.vertices}
    return [o.matrix_world @ o.data.vertices[i].co for i in ids]


def browse_line(o, z: float) -> None:
    """Removes leaf-card islands whose centre is below world height z."""
    leaf_idx = {i for i, m in enumerate(o.data.materials) if m and LEAF_RX.search(m.name)}
    bm = bmesh.new()
    bm.from_mesh(o.data)
    seen: set[int] = set()
    kill = []
    for f0 in bm.faces:
        if f0.index in seen or f0.material_index not in leaf_idx:
            continue
        isl = []
        stack = [f0]
        seen.add(f0.index)
        while stack:
            f = stack.pop()
            isl.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen and g.material_index in leaf_idx:
                        seen.add(g.index)
                        stack.append(g)
        vs = {v for f in isl for v in f.verts}
        cz = sum((o.matrix_world @ v.co).z for v in vs) / len(vs)
        if cz < z:
            kill += isl
    bmesh.ops.delete(bm, geom=list(set(kill)), context="FACES")
    bm.to_mesh(o.data)
    bm.free()
    print(f"browse_line: {len(kill)} leaf faces below {z:.2f} m removed")


def merge_materials(o) -> None:
    """One bark and one leaf surface per tree where the source splits them (Melia bark_01..05,
    twig cards into the leaf material): each surface is a draw call per chunk and shadow split."""
    mats = [m.name if m else "" for m in o.data.materials]

    def canon(n: str) -> str:
        low = n.lower()
        if "bark" in low or "trunk" in low or "branch" in low:
            return next(m for m in mats if any(k in m.lower() for k in ("bark", "trunk", "branch")))
        if LEAF_RX.search(n) and "twig" not in low:
            return n
        if "twig" in low:
            leaves = [m for m in mats if "leaf" in m.lower()]
            return leaves[0] if leaves else n
        return n

    target = {i: mats.index(canon(n)) for i, n in enumerate(mats)}
    for p in o.data.polygons:
        p.material_index = target[p.material_index]
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.material_slot_remove_unused()
    print(
        "merge_materials:",
        len(mats),
        "->",
        len(o.data.materials),
        [m.name for m in o.data.materials],
    )


def keep_low_bark(o, frac: float) -> None:
    """Far LODs: deletes bark faces above `frac` of the bark height. From 48 m and beyond the
    large leaf cards hide the upper branch work; trunk and main limbs stay."""
    leaf_idx = {i for i, m in enumerate(o.data.materials) if m and LEAF_RX.search(m.name)}
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bark = [f for f in bm.faces if f.material_index not in leaf_idx]
    z0 = min(v.co.z for f in bark for v in f.verts)
    z1 = max(v.co.z for f in bark for v in f.verts)
    cut = z0 + (z1 - z0) * frac
    kill = [f for f in bark if f.calc_center_median().z > cut]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(o.data)
    bm.free()
    print(f"keep_low_bark: {len(kill)} bark faces above {cut:.2f} removed")


def decimate_wood(o, max_tris: int) -> None:
    """Decimates only the non-leaf faces (vertex group + modifier restricted to it). Keep the
    budget generous: at ~15 % of the source the collapse ate the long trunk cylinders and the
    trees had no trunk at all (2026-10-11)."""
    leaf_idx = {i for i, m in enumerate(o.data.materials) if m and LEAF_RX.search(m.name)}
    wood = [p for p in o.data.polygons if p.material_index not in leaf_idx]
    n_wood = sum(len(p.vertices) - 2 for p in wood)
    if n_wood <= max_tris:
        return
    vg = o.vertex_groups.new(name="wood")
    leaf_verts = {v for p in o.data.polygons if p.material_index in leaf_idx for v in p.vertices}
    ids = [v for p in wood for v in p.vertices if v not in leaf_verts]
    vg.add(list(set(ids)), 1.0, "REPLACE")
    bpy.context.view_layer.objects.active = o
    m = o.modifiers.new("dec", "DECIMATE")
    m.ratio = max_tris / n_wood
    m.vertex_group = "wood"
    bpy.ops.object.modifier_apply(modifier="dec")
    print(f"decimate_wood: {n_wood} -> ~{max_tris}")


def shrink_images() -> None:
    for img in bpy.data.images:
        if img.size[0] > MAX_TEX or img.size[1] > MAX_TEX:
            s = MAX_TEX / max(img.size[0], img.size[1])
            img.scale(max(int(img.size[0] * s), 1), max(int(img.size[1] * s), 1))
            img.pack()


def run(name: str) -> None:
    uid, keep, max_wood, drop = TREES[name][:4]
    max_grow = TREES[name][4] if len(TREES[name]) > 4 else 1.6
    lift = TREES[name][5] if len(TREES[name]) > 5 else 0.0
    rng = random.Random(7)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(RAW / f"{uid}.glb"))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    # drop fruit / flower / stalk faces only (an object can mix them with bark)
    drop_faces(o, re.compile(drop, re.I))
    before = tris(o)
    thin_leaves(o, keep, rng, max_grow)
    merge_materials(o)
    if name.endswith("_far"):
        keep_low_bark(o, 0.55)
    decimate_wood(o, max_wood)
    after = tris(o)
    # base: the lowest BARK vertex sits 5 cm below z = 0 (root flare into the ground), trunk foot
    # at the origin. Measured on the vertices, not o.bound_box: the bounding box was stale after
    # the joins and every tree floated 1.6 m above the ground (2026-10-11).
    bark = bark_verts(o)
    zmin = min(v.z for v in bark) + 0.05
    if lift > 0.0:
        browse_line(o, zmin + lift)
        after = tris(o)
    low = [v for v in bark if v.z < zmin + 0.4]
    foot = sum(low, Vector()) / max(len(low), 1)
    o.location -= Vector((foot.x, foot.y, zmin))
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    shrink_images()
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / f"{name}.glb"),
        use_selection=False,
        export_format="GLB",
        export_animations=False,
        export_image_format="AUTO",
    )
    dims = [round(v, 2) for v in o.dimensions]
    print(f"TREE {name}: tris {before} -> {after}, size (x, y, z-up) {dims}")


names = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
for n in names or list(TREES):
    run(n)
