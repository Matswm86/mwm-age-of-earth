"""Raw downloads -> game GLBs in assets/models/<kind>/ (Blender 4.5 headless).

blender -b --factory-startup -P tools/assets/process_assets.py -- [name ...]

Per asset: import, bake transforms, put the origin at the bottom centre, scale to a real size, decimate to a phone
budget (LOD0) and write <name>.glb (Godot makes the LODs on import; lod1 = the count to expect). Textures keep their source size
(all <= 2048 px). Animated models keep their armature and actions (no decimation on skinned meshes beyond the
target). Licences: see CREDITS.md; only CC BY / CC0 sources are listed here.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[2]
SF = ROOT / "assets/_raw/sketchfab"
PH = ROOT / "assets/_raw/polyhaven/models"
OUT = ROOT / "assets/models"

# name: (source, kind, size_axis, size_m, lod0_tris, lod1_tris, extra)
ASSETS = {
    # trees
    "acacia_tortilis": (
        SF / "trees/bb14c2bb679b4d0bb1c578a27e2ddabf.glb",
        "trees",
        "z",
        7.5,
        8200,
        2500,
        {},
    ),
    "home_fig": (
        SF / "trees/2a0dbcdf8f5d48f5ad79987c7a8170ce.glb",
        "trees",
        "z",
        17.0,
        60000,
        15000,
        {},
    ),
    "doum_palm": (
        SF / "trees/00bd2ea54eb1405bb056eac3f1e14673.glb",
        "trees",
        "z",
        11.0,
        24000,
        6000,
        {},
    ),
    "shrub_searsia": (
        PH / "searsia_lucida_2k/searsia_lucida_2k.gltf",
        "plants",
        "z",
        2.4,
        20000,
        5000,
        {"first": True},
    ),
    "shrub_leafy": (PH / "shrub_04_2k/shrub_04_2k.gltf", "plants", "z", 1.6, 8000, 2500, {}),
    "grass_tuft": (
        PH / "grass_medium_02_2k/grass_medium_02_2k.gltf",
        "plants",
        "z",
        0.45,
        8000,
        0,
        {},
    ),
    # rocks (Namaqualand granite scans; the game tints them to basalt, see DESIGN.md 7.3)
    "boulder_a": (
        PH / "namaqualand_boulder_04_2k/namaqualand_boulder_04_2k.gltf",
        "rocks",
        "z",
        1.9,
        4000,
        800,
        {},
    ),
    "boulder_b": (
        PH / "namaqualand_boulder_02_2k/namaqualand_boulder_02_2k.gltf",
        "rocks",
        "z",
        0.9,
        3000,
        600,
        {},
    ),
    "boulder_c": (
        PH / "namaqualand_boulder_05_2k/namaqualand_boulder_05_2k.gltf",
        "rocks",
        "z",
        0.55,
        2500,
        500,
        {},
    ),
    "cobbles": (
        PH / "namaqualand_rocks_01_2k/namaqualand_rocks_01_2k.gltf",
        "rocks",
        "x",
        1.45,
        6000,
        0,
        {},
    ),
    "stones": (
        PH / "namaqualand_stones_01_2k/namaqualand_stones_01_2k.gltf",
        "rocks",
        "x",
        1.0,
        6000,
        0,
        {},
    ),
    # animals
    "gazelle": (
        SF / "animals/b2c70a0821ef4c6ca0c096e33bc97593.glb",
        "animals",
        "len",
        1.25,
        0,
        0,
        {"anim": True},
    ),
    "hyena": (
        SF / "animals/f74b47c36a10443388905407958db591.glb",
        "animals",
        "len",
        1.45,
        9100,
        3000,
        {},
    ),
    "hyena_animated": (
        SF / "animals/4559fe724ecb47c1af735fe464044af7.glb",
        "animals",
        "len",
        1.45,
        0,
        0,
        {"anim": True},
    ),
    "leopard": (
        SF / "animals/5a36868106f843d4a24d87334f1550fe.glb",
        "animals",
        "len",
        2.0,
        0,
        0,
        {"anim": True},
    ),
    "crocodile": (
        SF / "animals/52aefd22731d41829423a184c10244f2.glb",
        "animals",
        "len",
        4.2,
        9000,
        2500,
        {},
    ),
    "crocodile_b": (
        SF / "animals/a242e4634a234d3fb909c54b2c39d7b8.glb",
        "animals",
        "len",
        4.2,
        9000,
        2500,
        {},
    ),
    "buffalo": (
        SF / "animals/c4d6b985fdc840aea430b6f540b6dff2.glb",
        "animals",
        "len",
        3.0,
        0,
        0,
        {"anim": True, "clips": ["Idle", "Walk", "Run", "Graze", "Eat", "Death", "Die"]},
    ),
    # props
    "carcass_bones": (
        SF / "props/eaca504567604e879b8ab2cf2763025e.glb",
        "props",
        "len",
        2.4,
        6000,
        1500,
        {},
    ),
    "branch_heap": (
        SF / "props/31a023461b2f4b1fb912b25e86acb586.glb",
        "props",
        "len",
        2.6,
        12000,
        3000,
        {},
    ),
    "hand_axe": (
        SF / "props/06309df47b73468a8cd2500b236e80ee.glb",
        "props",
        "len",
        0.16,
        2000,
        0,
        {},
    ),
    "lithic_core": (
        SF / "props/4fa02d3df2044b7ca4a3ac9ae3354bee.glb",
        "props",
        "len",
        0.12,
        2000,
        0,
        {},
    ),
    "digging_stick": (
        SF / "props/f85c07a9d6414ff09e46a5d2ad87c7d6.glb",
        "props",
        "len",
        1.3,
        1500,
        0,
        {},
    ),
    "hearth_stones": (
        PH / "stone_fire_pit_2k/stone_fire_pit_2k.gltf",
        "props",
        "len",
        1.3,
        3900,
        0,
        {},
    ),
    "tuber": (PH / "sweet_potato_2k/sweet_potato_2k.gltf", "props", "len", 0.18, 600, 0, {}),
    "dry_branches": (
        PH / "dry_branches_medium_01_2k/dry_branches_medium_01_2k.gltf",
        "props",
        "len",
        1.3,
        6000,
        0,
        {},
    ),
    "dead_branch": (
        PH / "dead_quiver_branch_01_2k/dead_quiver_branch_01_2k.gltf",
        "props",
        "len",
        0.9,
        5000,
        0,
        {},
    ),
}


def mesh_bounds(objs):
    mn = np.full(3, 1e9)
    mx = -mn
    for o in objs:
        co = np.empty(len(o.data.vertices) * 3, np.float32)
        o.data.vertices.foreach_get("co", co)
        co = (
            co.reshape(-1, 3) @ np.array(o.matrix_world)[:3, :3].T + np.array(o.matrix_world)[:3, 3]
        )
        mn = np.minimum(mn, co.min(0))
        mx = np.maximum(mx, co.max(0))
    return mn, mx


def tris(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)


def decimate(objs, target):
    tot = tris(objs)
    if not target or tot <= target:
        return
    r = target / tot
    for o in objs:
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = r
        m.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.ops.object.modifier_apply(modifier="dec")


def export(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        use_selection=True,
        export_format="GLB",
        export_animations=True,
        export_apply=False,
    )


def run(name):
    src, kind, axis, size, lod0, lod1, extra = ASSETS[name]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(src))
    objs = list(bpy.data.objects)
    meshes = [o for o in objs if o.type == "MESH" and not o.name.lower().startswith("icosphere")]
    if extra.get("first"):  # Poly Haven sets with several variants in a row: keep the largest
        big = max(meshes, key=lambda o: tris([o]))
        meshes = [big]
    anim = extra.get("anim")
    bpy.context.view_layer.update()
    if not anim:
        for o in list(bpy.data.objects):
            if o not in meshes:
                bpy.data.objects.remove(o, do_unlink=True)
        for o in meshes:
            mw = o.matrix_world.copy()
            o.parent = None
            o.data = o.data.copy()
            o.data.transform(mw)
            o.matrix_world = Matrix()
            o.data.shape_keys and o.shape_key_clear()
        mn, mx = mesh_bounds(meshes)
        ext = mx - mn
        s = size / (ext[2] if axis == "z" else ext[0] if axis == "x" else max(ext[0], ext[1]))
        for o in meshes:
            o.data.transform(
                Matrix.Scale(s, 4)
                @ Matrix.Translation((-(mn[0] + mx[0]) / 2, -(mn[1] + mx[1]) / 2, -mn[2]))
            )
        decimate(meshes, lod0)
        export(OUT / kind / f"{name}.glb", meshes)
        print("ASSET", name, "lod0 tris", tris(meshes))
        # LOD1: Godot generates mesh LODs on import (Mesh > Generate LODs, on by default), so no second GLB with a
        # second copy of the textures; lod1 in the table is the triangle count to check in the import dock.
    else:  # skinned: scale the root, keep rig + clips
        keep = extra.get("clips")
        if keep:  # files with 100+ clips: keep the ones the game uses (export time and size)
            for a in list(bpy.data.actions):
                if not any(k.lower() in a.name.lower() for k in keep):
                    bpy.data.actions.remove(a)
        roots = [o for o in objs if o.parent is None]
        mn, mx = mesh_bounds(meshes)
        ext = mx - mn
        s = size / (ext[2] if axis == "z" else max(ext[0], ext[1]))
        for r in roots:
            r.matrix_world = Matrix.Scale(s, 4) @ r.matrix_world
        bpy.context.view_layer.update()
        mn, mx = mesh_bounds(meshes)
        for r in roots:
            r.matrix_world = (
                Matrix.Translation((-(mn[0] + mx[0]) / 2, -(mn[1] + mx[1]) / 2, -mn[2]))
                @ r.matrix_world
            )
        bpy.context.view_layer.update()
        export(OUT / kind / f"{name}.glb", objs)
        print(
            "ASSET", name, "skinned tris", tris(meshes), "clips", [a.name for a in bpy.data.actions]
        )


names = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
for n in names or ASSETS:
    try:
        run(n)
    except Exception as e:  # noqa: BLE001 (report and continue with the next asset)
        print("ASSET_FAIL", n, type(e).__name__, e)
