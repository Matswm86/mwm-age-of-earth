"""Pre-rendered planet stage of the Age of Earth opening (pale blue dot -> Earth -> dive onto the
Lake Turkana rift), Blender Cycles on the GPU. The camera path comes from the game itself
(tests/intro_export_camera.tscn writes camera.json), so the video ends exactly where the realtime
intro (scripts/Intro.gd) takes over behind the cloud veil.

Scene (units km, planet centre at the origin, Blender Z = north pole):
- Earth: NASA Blue Marble NG Dec 2004 (21600 x 10800) albedo, 500 m Blue Marble crop over East
  Africa, GEBCO elevation as bump, bathymetry-derived ocean mask for a glossy sea (sun glint).
- Rift patch: Copernicus GLO-30 heights (assets/intro/rift_height.png) as a displaced mesh with
  the Sentinel-2 cloudless 2016 mosaics (assets/intro/rift_s2_*.jpg) and a glossy lake.
- Clouds: Blue Marble cloud map on two drifting shells 6-7 km up (they cast real shadows),
  thinned round the dive target.
- Atmosphere: 16 nested homogeneous volume shells approximating exponential Rayleigh (H 8 km),
  Mie (H 1.2 km, g 0.76) and an ozone absorption band, sea-level coefficients per km. Path
  traced, so multiple scattering, the blue limb and red terminator come out of the physics.
- Sky: Yale Bright Star Catalogue baked to an equirect star map (camera rays only), sun disc,
  compositor fog glow for the sun glare.

Run (NVIDIA GPU, OptiX):
  BLENDER_USER_RESOURCES=~/MWM/data/tools/blender_user blender -b --factory-startup \\
    -P tools/intro/render_earth.py -- --camera <camera.json> --src <data dir> --out <frames dir> \\
    [--frames 0-1934] [--only 0,300,900] [--samples 48] [--scale 100] [--save scene.blend]
<data dir> holds bmng/ (Blue Marble, GEBCO) and stars/catalog.gz (see tools/intro/
bake_intro_assets.py); the rift textures are read from assets/intro/.
Encode: tools/intro/encode_video.sh <frames dir> assets/intro/intro_planet.ogv
"""

from __future__ import annotations

import argparse
import gzip
import json
import math
import sys
import time
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
R = 6371.0
CLOUD_ALT = (6.0, 7.0)
BMNG_REGION = (27.5, -4.7, 44.5, 12.3)
# sea-level scattering per km (Bruneton & Neyret 2008, Hillaire 2020)
BETA_R = (5.802e-3, 13.558e-3, 33.1e-3)
BETA_M = 3.996e-3
BETA_M_ABS = 0.444e-3
BETA_O = (0.650e-3, 1.881e-3, 0.085e-3)
SHELL_TOPS = [1, 2, 3.5, 5, 7, 9.5, 12.5, 16, 20, 25, 31, 38, 46, 56, 70, 100]
SUN_POWER = 4.0


def args() -> argparse.Namespace:
    a = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--camera", required=True)
    p.add_argument("--src", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--frames", default="")
    p.add_argument("--only", default="")
    p.add_argument("--samples", type=int, default=48)
    p.add_argument("--scale", type=int, default=100)
    p.add_argument("--save", default="")
    p.add_argument("--no-atmos", action="store_true")
    p.add_argument("--atmos-scale", type=float, default=1.0)
    return p.parse_args(a)


def g2b(v) -> Vector:
    """Godot planet frame (Y up) -> Blender (Z up): (x, y, z) -> (x, -z, y)."""
    return Vector((v[0], -v[2], v[1]))


def geo(lat: float, lon: float) -> Vector:
    la, lo = math.radians(lat), math.radians(lon)
    return Vector((math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la)))


# --- node helpers ---


class NB:
    def __init__(self, mat: bpy.types.Material) -> None:
        mat.use_nodes = True
        self.t = mat.node_tree
        self.t.nodes.clear()
        self.x = 0

    def n(self, kind: str, **kw):
        node = self.t.nodes.new(kind)
        node.location = (self.x, 0)
        self.x += 200
        for k, v in kw.items():
            if k.startswith("in_"):
                key = k[3:]
                node.inputs[int(key) if key.isdigit() else key].default_value = v
            else:
                setattr(node, k, v)
        return node

    def link(self, a, b) -> None:
        self.t.links.new(a, b)

    def math(self, op: str, a, b=None, clamp: bool = False):
        m = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                m.inputs[i].default_value = v
            else:
                self.link(v, m.inputs[i])
        return m.outputs[0]

    def vmath(self, op: str, a, b=None):
        m = self.n("ShaderNodeVectorMath", operation=op)
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (tuple, list, Vector)):
                m.inputs[i].default_value = v
            else:
                self.link(v, m.inputs[i])
        return m

    def smooth(self, x, lo: float, hi: float):
        m = self.n("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP", clamp=True)
        self.link(x, m.inputs["Value"])
        m.inputs["From Min"].default_value = lo
        m.inputs["From Max"].default_value = hi
        return m.outputs["Result"]

    def mix_rgb(self, fac, a, b):
        m = self.n("ShaderNodeMix", data_type="RGBA")
        self.link(fac, m.inputs["Factor"])
        self.link(a, m.inputs[6])
        self.link(b, m.inputs[7])
        return m.outputs[2]

    def image(
        self, path: Path, colour: bool, vec, extension: str = "REPEAT", interp: str = "Cubic"
    ):
        img = bpy.data.images.load(str(path), check_existing=True)
        img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
        node = self.n("ShaderNodeTexImage", image=img, extension=extension, interpolation=interp)
        self.link(vec, node.inputs["Vector"])
        return node

    def combine(self, x, y):
        c = self.n("ShaderNodeCombineXYZ")
        self.link(x, c.inputs[0])
        self.link(y, c.inputs[1])
        return c.outputs[0]


def latlon_nodes(nb: NB):
    """(lon, lat) radians from the object-space position."""
    tc = nb.n("ShaderNodeTexCoord")
    nrm = nb.vmath("NORMALIZE", tc.outputs["Object"])
    sep = nb.n("ShaderNodeSeparateXYZ")
    nb.link(nrm.outputs[0], sep.inputs[0])
    lon = nb.math("ARCTAN2", sep.outputs[1], sep.outputs[0])
    lat = nb.math("ARCSINE", sep.outputs[2])
    return lon, lat, nrm.outputs[0]


def box_uv_weight(nb: NB, lon, lat, box, feather: float):
    lon0, lat0, lon1, lat1 = (math.radians(v) for v in box)
    u = nb.math("DIVIDE", nb.math("SUBTRACT", lon, lon0), lon1 - lon0)
    v = nb.math("DIVIDE", nb.math("SUBTRACT", lat, lat0), lat1 - lat0)
    w = None
    for q in (u, nb.math("SUBTRACT", 1.0, u), v, nb.math("SUBTRACT", 1.0, v)):
        e = nb.smooth(q, 0.0, feather)
        w = e if w is None else nb.math("MULTIPLY", w, e)
    return nb.combine(u, v), w


def clear_hole(nb: NB, nrm, target: Vector, radius_deg: float):
    """1 far from the target, 0 at it (angular distance)."""
    d = nb.vmath("DOT_PRODUCT", nrm, tuple(target))
    ang = nb.math("ARCCOSINE", d.outputs["Value"])
    return nb.smooth(ang, math.radians(radius_deg * 0.2), math.radians(radius_deg * 2.0))


# --- scene ---


def earth_material(src: Path) -> bpy.types.Material:
    mat = bpy.data.materials.new("Earth")
    nb = NB(mat)
    lon, lat, _ = latlon_nodes(nb)
    gu = nb.math("ADD", nb.math("DIVIDE", lon, 2 * math.pi), 0.5)
    gv = nb.math("ADD", nb.math("DIVIDE", lat, math.pi), 0.5)
    guv = nb.combine(gu, gv)
    alb = nb.image(src / "bmng/world.topo.bathy.200412.3x21600x10800.jpg", True, guv).outputs[0]
    ruv, rw = box_uv_weight(nb, lon, lat, BMNG_REGION, 0.08)
    reg = nb.image(ROOT / "assets/intro/rift_bmng_4k.jpg", True, ruv, "EXTEND").outputs[0]
    alb = nb.mix_rgb(rw, alb, reg)
    puv, pw = box_uv_weight(nb, lon, lat, PATCH, 0.06)
    s2 = nb.image(ROOT / "assets/intro/rift_s2_coarse.jpg", True, puv, "EXTEND").outputs[0]
    alb = nb.mix_rgb(pw, alb, s2)
    ocean = nb.image(ROOT / "assets/intro/earth_ocean_8k.png", False, guv, interp="Linear").outputs[
        0
    ]
    elev = nb.image(src / "bmng/gebco_08_rev_elev_21600x10800.png", False, guv).outputs[0]
    bsdf = nb.n("ShaderNodeBsdfPrincipled")
    nb.link(alb, bsdf.inputs["Base Color"])
    rough = nb.n("ShaderNodeMapRange", clamp=True)
    nb.link(ocean, rough.inputs["Value"])
    rough.inputs["To Min"].default_value = 0.95
    rough.inputs["To Max"].default_value = 0.16
    nb.link(rough.outputs[0], bsdf.inputs["Roughness"])
    spec = nb.n("ShaderNodeMapRange", clamp=True)
    nb.link(ocean, spec.inputs["Value"])
    spec.inputs["To Min"].default_value = 0.2
    spec.inputs["To Max"].default_value = 0.5
    nb.link(spec.outputs[0], bsdf.inputs["Specular IOR Level"])
    bump = nb.n("ShaderNodeBump", in_Strength=0.6, in_Distance=6.4 * 4.0)
    nb.link(elev, bump.inputs["Height"])
    nb.link(bump.outputs[0], bsdf.inputs["Normal"])
    out = nb.n("ShaderNodeOutputMaterial")
    nb.link(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def cloud_material(name: str, shift_key: tuple, target: Vector, hole_deg: float, alpha: float):
    mat = bpy.data.materials.new(name)
    nb = NB(mat)
    lon, lat, nrm = latlon_nodes(nb)
    gu = nb.math("ADD", nb.math("DIVIDE", lon, 2 * math.pi), 0.5)
    shift = nb.n("ShaderNodeValue")
    shift.name = "shift"
    gu = nb.math("ADD", gu, shift.outputs[0])
    gv = nb.math("ADD", nb.math("DIVIDE", lat, math.pi), 0.5)
    tex = nb.image(ROOT / "assets/intro/earth_clouds_8k.jpg", False, nb.combine(gu, gv)).outputs[0]
    hole = clear_hole(nb, nrm, target, hole_deg)
    c = nb.math("SUBTRACT", tex, nb.math("MULTIPLY", nb.math("SUBTRACT", 1.0, hole), 0.8))
    c = nb.math("MULTIPLY", nb.smooth(c, 0.1, 0.85), alpha)
    diff = nb.n("ShaderNodeBsdfPrincipled", in_Roughness=1.0)
    diff.inputs["Base Color"].default_value = (0.92, 0.92, 0.92, 1.0)
    diff.inputs["Specular IOR Level"].default_value = 0.0
    tr = nb.n("ShaderNodeBsdfTransparent")
    mix = nb.n("ShaderNodeMixShader")
    nb.link(c, mix.inputs[0])
    nb.link(tr.outputs[0], mix.inputs[1])
    nb.link(diff.outputs[0], mix.inputs[2])
    out = nb.n("ShaderNodeOutputMaterial")
    nb.link(mix.outputs[0], out.inputs["Surface"])
    shift.outputs[0].default_value = 0.0
    return mat


def rift_material() -> bpy.types.Material:
    mat = bpy.data.materials.new("Rift")
    nb = NB(mat)
    uvn = nb.n("ShaderNodeUVMap")
    coarse = nb.image(
        ROOT / "assets/intro/rift_s2_coarse.jpg", True, uvn.outputs[0], "EXTEND"
    ).outputs[0]
    p, f = PATCH, FINE
    fu0, fu1 = (f[0] - p[0]) / (p[2] - p[0]), (f[2] - p[0]) / (p[2] - p[0])
    fv0, fv1 = (f[1] - p[1]) / (p[3] - p[1]), (f[3] - p[1]) / (p[3] - p[1])
    sep = nb.n("ShaderNodeSeparateXYZ")
    nb.link(uvn.outputs[0], sep.inputs[0])
    u = nb.math("DIVIDE", nb.math("SUBTRACT", sep.outputs[0], fu0), fu1 - fu0)
    v = nb.math("DIVIDE", nb.math("SUBTRACT", sep.outputs[1], fv0), fv1 - fv0)
    w = None
    for q in (u, nb.math("SUBTRACT", 1.0, u), v, nb.math("SUBTRACT", 1.0, v)):
        e = nb.smooth(q, 0.0, 0.06)
        w = e if w is None else nb.math("MULTIPLY", w, e)
    fine = nb.image(
        ROOT / "assets/intro/rift_s2_fine.jpg", True, nb.combine(u, v), "EXTEND"
    ).outputs[0]
    alb = nb.mix_rgb(w, coarse, fine)
    rel = nb.image(ROOT / "assets/intro/rift_normal.png", False, uvn.outputs[0], "EXTEND")
    sepc = nb.n("ShaderNodeSeparateColor")
    nb.link(rel.outputs[0], sepc.inputs[0])
    lake = sepc.outputs[2]
    bsdf = nb.n("ShaderNodeBsdfPrincipled")
    nb.link(alb, bsdf.inputs["Base Color"])
    rough = nb.n("ShaderNodeMapRange", clamp=True)
    nb.link(lake, rough.inputs["Value"])
    rough.inputs["To Min"].default_value = 0.95
    rough.inputs["To Max"].default_value = 0.07
    nb.link(rough.outputs[0], bsdf.inputs["Roughness"])
    out = nb.n("ShaderNodeOutputMaterial")
    nb.link(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def rift_mesh(exag: float, n: int = 513) -> bpy.types.Object:
    img = bpy.data.images.load(str(ROOT / "assets/intro/rift_height.png"))
    img.colorspace_settings.name = "Non-Color"
    w = img.size[0]
    px = np.empty(w * img.size[1] * 4, np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(img.size[1], w, 4)[::-1]  # Blender rows run bottom-up
    hm = (np.round(px[..., 0] * 255) * 256 + np.round(px[..., 1] * 255)) / 16.0
    lon0, lat0, lon1, lat1 = PATCH
    us = np.linspace(0.0, 1.0, n)
    verts, uvs = [], []
    for j, v in enumerate(us):  # v = 0 at the north edge
        lat = lat1 + (lat0 - lat1) * v
        py = min(int(round(v * (w - 1))), w - 1)
        for i, u in enumerate(us):
            lon = lon0 + (lon1 - lon0) * u
            pxi = min(int(round(u * (w - 1))), w - 1)
            edge = min(u, 1 - u, v, 1 - v)
            t = min(max(edge / 0.05, 0.0), 1.0)
            t = t * t * (3 - 2 * t)
            h = -0.3 + (hm[py, pxi] * 0.001 * exag + 0.3) * t
            verts.append(tuple(geo(lat, lon) * (R + h)))
            uvs.append((u, 1.0 - v))
    faces = []
    for j in range(n - 1):
        for i in range(n - 1):
            a = j * n + i
            faces.append((a, a + n, a + n + 1, a + 1))
    me = bpy.data.meshes.new("Rift")
    me.from_pydata(verts, [], faces)
    uvl = me.uv_layers.new(name="UVMap")
    vidx = np.empty(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", vidx)
    uv_arr = np.asarray(uvs, np.float32)[vidx]
    uvl.data.foreach_set("uv", uv_arr.ravel())
    me.shade_smooth()
    if me.polygons[0].normal.dot(Vector(verts[0]).normalized()) < 0:
        me.flip_normals()
    ob = bpy.data.objects.new("Rift", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def sphere(name: str, radius: float, segs: int, mat) -> bpy.types.Object:
    """UV sphere built with numpy + foreach_set (bpy.ops takes minutes at 1024 segments)."""
    rings = segs // 2
    th = np.linspace(0.0, math.pi, rings + 1)[1:-1]  # polar angle, poles separate
    ph = np.linspace(0.0, 2 * math.pi, segs, endpoint=False)
    st, ct = np.sin(th)[:, None], np.cos(th)[:, None]
    ring = np.stack(
        [
            st * np.cos(ph)[None, :],
            st * np.sin(ph)[None, :],
            np.broadcast_to(ct, (rings - 1, segs)),
        ],
        -1,
    ).reshape(-1, 3)
    verts = np.concatenate([[[0.0, 0.0, 1.0]], ring, [[0.0, 0.0, -1.0]]]) * radius
    nv = len(verts)
    c = np.arange(segs)

    def idx(r: int, cc: np.ndarray) -> np.ndarray:
        return 1 + r * segs + (cc % segs)

    polys = [np.stack([np.zeros(segs, int), idx(0, c + 1), idx(0, c)], -1).ravel()]
    sizes = [3] * segs
    for r in range(rings - 2):
        polys.append(
            np.stack([idx(r, c), idx(r, c + 1), idx(r + 1, c + 1), idx(r + 1, c)], -1).ravel()
        )
        sizes += [4] * segs
    polys.append(
        np.stack([idx(rings - 2, c), idx(rings - 2, c + 1), np.full(segs, nv - 1)], -1).ravel()
    )
    sizes += [3] * segs
    loops = np.concatenate(polys).astype(np.int32)
    sizes_a = np.asarray(sizes, np.int32)
    starts = np.concatenate([[0], np.cumsum(sizes_a)[:-1]]).astype(np.int32)
    me = bpy.data.meshes.new(name)
    me.vertices.add(nv)
    me.vertices.foreach_set("co", verts.astype(np.float32).ravel())
    me.loops.add(len(loops))
    me.loops.foreach_set("vertex_index", loops)
    me.polygons.add(len(sizes_a))
    me.polygons.foreach_set("loop_start", starts)
    me.polygons.foreach_set("loop_total", sizes_a)
    me.update(calc_edges=True)
    me.shade_smooth()
    mid = me.polygons[len(sizes_a) // 2]
    if mid.normal.dot(mid.center) < 0:
        me.flip_normals()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def atmosphere(scale: float = 1.0) -> None:
    def avg(h0: float, h1: float, H: float) -> float:
        return H * (math.exp(-h0 / H) - math.exp(-h1 / H)) / (h1 - h0)

    def ozone(h0: float, h1: float) -> float:
        hs = np.linspace(h0, h1, 50)
        return float(np.mean(np.maximum(0.0, 1.0 - np.abs(hs - 25.0) / 15.0)))

    bottoms = [0.0] + SHELL_TOPS[:-1]
    dens = [
        (avg(b, t, 8.0), avg(b, t, 1.2), ozone(b, t))
        for b, t in zip(bottoms, SHELL_TOPS, strict=True)
    ]
    for k, top in enumerate(SHELL_TOPS):
        nxt = dens[k + 1] if k + 1 < len(dens) else (0.0, 0.0, 0.0)
        inc = [dens[k][c] - nxt[c] for c in range(3)]
        mat = bpy.data.materials.new(f"Atmos{k}")
        nb = NB(mat)
        ray = nb.n("ShaderNodeVolumeScatter", in_Anisotropy=0.0)
        bmax = BETA_R[2]
        ray.inputs["Color"].default_value = (BETA_R[0] / bmax, BETA_R[1] / bmax, 1.0, 1.0)
        ray.inputs["Density"].default_value = bmax * inc[0] * scale
        mie = nb.n("ShaderNodeVolumeScatter", in_Anisotropy=0.76)
        mie.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
        mie.inputs["Density"].default_value = BETA_M * inc[1] * scale
        ab = nb.n("ShaderNodeVolumeAbsorption")
        omax = BETA_O[1]
        # absorption = density x (1 - colour)
        ab.inputs["Color"].default_value = (1 - BETA_O[0] / omax, 0.0, 1 - BETA_O[2] / omax, 1.0)
        ab.inputs["Density"].default_value = omax * inc[2] * scale
        ab2 = nb.n("ShaderNodeVolumeAbsorption")
        ab2.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
        ab2.inputs["Density"].default_value = BETA_M_ABS * inc[1] * scale
        add1 = nb.n("ShaderNodeAddShader")
        nb.link(ray.outputs[0], add1.inputs[0])
        nb.link(mie.outputs[0], add1.inputs[1])
        add2 = nb.n("ShaderNodeAddShader")
        nb.link(ab.outputs[0], add2.inputs[0])
        nb.link(ab2.outputs[0], add2.inputs[1])
        add3 = nb.n("ShaderNodeAddShader")
        nb.link(add1.outputs[0], add3.inputs[0])
        nb.link(add2.outputs[0], add3.inputs[1])
        out = nb.n("ShaderNodeOutputMaterial")
        nb.link(add3.outputs[0], out.inputs["Volume"])
        ob = sphere(f"Atmos{k}", R + top, 1024 if top <= 12.5 else 256, mat)
        ob.visible_shadow = True


def star_map(src: Path, ra_at_lon0: float, w: int = 8192) -> bpy.types.Image:
    """Equirect star map (Blender world direction: lon = atan2(y, x)) from Yale BSC5."""
    h = w // 2
    acc = np.zeros((h, w, 3), np.float32)
    with gzip.open(src / "stars/catalog.gz", "rt", encoding="latin-1") as f:
        for line in f:
            if len(line) < 114 or not line[75:77].strip() or not line[102:107].strip():
                continue
            ra = (int(line[75:77]) + int(line[77:79]) / 60 + float(line[79:83]) / 3600) * 15
            dec = int(line[84:86]) + int(line[86:88]) / 60 + int(line[88:90]) / 3600
            if line[83] == "-":
                dec = -dec
            vmag = float(line[102:107])
            bv = float(line[109:114]) if line[109:114].strip() else 0.6
            # Blender equirect: u = 0 at +X (lon 0), increasing towards +Y (east)
            x = ((ra - ra_at_lon0) % 360.0) / 360.0 * w
            y = (dec + 90.0) / 180.0 * h
            flux = 10 ** (-0.4 * (vmag - 1.0))
            col = np.array(bv_rgb(bv), np.float32) * flux
            # 3 x 3 Gaussian splat (sigma 0.6 px), wider in x towards the poles
            sx = 0.6 / max(math.cos(math.radians(dec)), 0.05)
            for dy in (-1, 0, 1):
                for dx in range(-int(math.ceil(2 * sx)), int(math.ceil(2 * sx)) + 1):
                    xi, yi = int(x) + dx, int(y) + dy
                    if 0 <= yi < h:
                        g = math.exp(
                            -((xi + 0.5 - x) ** 2) / (2 * sx * sx) - ((yi + 0.5 - y) ** 2) / 0.72
                        )
                        acc[yi, xi % w] += col * g
    img = bpy.data.images.new("Stars", w, h, alpha=False, float_buffer=True)
    rgba = np.ones((h, w, 4), np.float32)
    rgba[..., :3] = acc
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    return img


def bv_rgb(bv: float) -> tuple:
    b = min(max(bv, -0.4), 2.0)
    t = 4600.0 * (1.0 / (0.92 * b + 1.7) + 1.0 / (0.92 * b + 0.62)) / 100.0
    if t <= 66:
        r, g = 1.0, min(max((99.47 * math.log(t) - 161.12) / 255, 0), 1)
        bl = 0.0 if t <= 19 else min(max((138.52 * math.log(t - 10) - 305.04) / 255, 0), 1)
    else:
        r = min(max(329.7 * (t - 60) ** -0.1332 / 255, 0), 1)
        g = min(max(288.12 * (t - 60) ** -0.0755 / 255, 0), 1)
        bl = 1.0
    return tuple(c * 0.65 + 0.35 for c in (r, g, bl))


def world(stars: bpy.types.Image, sun: Vector) -> None:
    wo = bpy.data.worlds.new("Space")
    bpy.context.scene.world = wo
    wo.use_nodes = True
    t = wo.node_tree
    t.nodes.clear()
    tc = t.nodes.new("ShaderNodeTexCoord")
    env = t.nodes.new("ShaderNodeTexEnvironment")
    env.image = stars
    env.interpolation = "Linear"
    t.links.new(tc.outputs["Generated"], env.inputs["Vector"])
    gain = t.nodes.new("ShaderNodeValue")
    gain.name = "star_gain"
    mul = t.nodes.new("ShaderNodeMixRGB")
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    t.links.new(env.outputs[0], mul.inputs[1])
    t.links.new(gain.outputs[0], mul.inputs[2])
    dot = t.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    t.links.new(tc.outputs["Generated"], dot.inputs[0])
    dot.inputs[1].default_value = tuple(sun)
    disc = t.nodes.new("ShaderNodeMapRange")
    disc.interpolation_type = "SMOOTHSTEP"
    disc.inputs["From Min"].default_value = math.cos(math.radians(0.29))
    disc.inputs["From Max"].default_value = math.cos(math.radians(0.24))
    disc.inputs["To Max"].default_value = 3000.0
    t.links.new(dot.outputs["Value"], disc.inputs["Value"])
    bg = t.nodes.new("ShaderNodeBackground")
    t.links.new(mul.outputs[0], bg.inputs["Color"])
    bg_sun = t.nodes.new("ShaderNodeEmission")
    bg_sun.inputs["Color"].default_value = (1.0, 0.97, 0.92, 1.0)
    t.links.new(disc.outputs[0], bg_sun.inputs["Strength"])
    add_s = t.nodes.new("ShaderNodeAddShader")
    t.links.new(bg.outputs[0], add_s.inputs[0])
    t.links.new(bg_sun.outputs[0], add_s.inputs[1])
    # only camera rays see stars and the disc; the sun lamp lights the scene
    lp = t.nodes.new("ShaderNodeLightPath")
    black = t.nodes.new("ShaderNodeBackground")
    black.inputs["Strength"].default_value = 0.0
    mix = t.nodes.new("ShaderNodeMixShader")
    t.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    t.links.new(black.outputs[0], mix.inputs[1])
    t.links.new(add_s.outputs[0], mix.inputs[2])
    out = t.nodes.new("ShaderNodeOutputWorld")
    t.links.new(mix.outputs[0], out.inputs["Surface"])


def compositor() -> None:
    sc = bpy.context.scene
    sc.use_nodes = True
    t = sc.node_tree
    t.nodes.clear()
    rl = t.nodes.new("CompositorNodeRLayers")
    glow = t.nodes.new("CompositorNodeGlare")
    glow.glare_type = "FOG_GLOW"
    glow.quality = "HIGH"
    # Blender 4.4+ moved the settings to input sockets; older builds keep them as properties
    for prop, sock, val in (
        ("threshold", "Threshold", 1.5),
        ("size", "Size", 9),
        ("mix", None, -0.6),
    ):
        if sock and sock in glow.inputs:
            glow.inputs[sock].default_value = val if sock != "Size" else 0.6
        elif hasattr(glow, prop):
            setattr(glow, prop, val)
    if "Strength" in glow.inputs:
        glow.inputs["Strength"].default_value = 0.35
    comp = t.nodes.new("CompositorNodeComposite")
    t.links.new(rl.outputs["Image"], glow.inputs["Image"])
    t.links.new(glow.outputs["Image"], comp.inputs["Image"])


def gpu() -> None:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = kind
            prefs.get_devices()
            devs = [d for d in prefs.devices if d.type == kind]
            if devs:
                for d in prefs.devices:
                    d.use = d.type == kind
                print("GPU", kind, [d.name for d in devs])
                return kind
        except TypeError:
            continue
    raise SystemExit("no NVIDIA GPU device for Cycles")


PATCH: tuple = ()
FINE: tuple = ()


def main() -> None:
    global PATCH, FINE
    a = args()
    cam_data = json.loads(Path(a.camera).read_text())
    PATCH = tuple(cam_data["patch"])
    FINE = tuple(cam_data["fine"])
    src = Path(a.src).expanduser()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    kind = gpu()
    sc.cycles.device = "GPU"
    sc.cycles.samples = a.samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPTIX" if kind == "OPTIX" else "OPENIMAGEDENOISE"
    sc.cycles.max_bounces = 64
    sc.cycles.diffuse_bounces = 1
    sc.cycles.glossy_bounces = 1
    # every atmosphere shell and cloud layer boundary costs one transparent bounce (16 + 2, twice)
    sc.cycles.transparent_max_bounces = 64
    sc.cycles.volume_bounces = 2
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.render.resolution_x = 1920
    sc.render.resolution_y = 1080
    sc.render.resolution_percentage = a.scale
    sc.render.fps = int(cam_data["fps"])
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Base Contrast"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_depth = "8"

    t_setup = time.time()

    def stage(name: str) -> None:
        print(f"setup {name}: {time.time() - t_setup:.1f} s", flush=True)

    sun = g2b(cam_data["sun_dir"]).normalized()
    target = geo(*cam_data["target"])
    sphere("Earth", R, 1024, earth_material(src))
    stage("earth")
    rift_mesh(cam_data["relief_exag"]).data.materials.append(rift_material())
    clouds = []
    for k, (alt, alpha) in enumerate(zip(CLOUD_ALT, (1.0, 0.45), strict=True)):
        m = cloud_material(f"Clouds{k}", (), target, cam_data["clear_hole_deg"], alpha)
        sphere(f"Clouds{k}", R + alt, 512, m)
        clouds.append(m)
    stage("rift + clouds")
    if not a.no_atmos:
        atmosphere(a.atmos_scale)
    stage("atmosphere")
    lamp = bpy.data.lights.new("Sun", "SUN")
    lamp.energy = SUN_POWER
    lamp.angle = math.radians(0.53)
    lamp.color = (1.0, 0.98, 0.95)
    lo = bpy.data.objects.new("Sun", lamp)
    sc.collection.objects.link(lo)
    lo.rotation_euler = sun.to_track_quat("Z", "Y").to_euler()
    world(star_map(src, cam_data["sky_ra_at_lon0"]), sun)
    stage("stars")
    compositor()

    cam = bpy.data.cameras.new("Cam")
    cam.sensor_fit = "VERTICAL"
    co = bpy.data.objects.new("Cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    frames = cam_data["frames"]
    star_gain = sc.world.node_tree.nodes["star_gain"].outputs[0]
    fps = cam_data["fps"]
    drift = cam_data["cloud_drift"]

    def pose(i: int) -> None:
        f = frames[i]
        m = Matrix.Identity(4)
        for col, key in enumerate(("x", "y", "z")):
            v = g2b(f[key])
            for r in range(3):
                m[r][col] = v[r]
        p = g2b(f["pos"])
        m[0][3], m[1][3], m[2][3] = p
        co.matrix_world = m
        cam.angle = math.radians(f["fov"])
        cam.clip_start = max(f["near"] * 0.3, 0.001)
        cam.clip_end = f["far"] * 1.2
        d = p.length
        px_ang = 2.0 * math.tan(math.radians(f["fov"]) * 0.5) / 1080.0
        planet_px = math.asin(min(R / d, 1.0)) / px_ang
        x = min(max((planet_px - 60.0) / 200.0, 0.0), 1.0)
        star_gain.default_value = 1.6 * (1.0 - x * x * (3 - 2 * x))
        for k, m2 in enumerate(clouds):
            m2.node_tree.nodes["shift"].outputs[0].default_value = -drift[k] * f["t"]

    out_dir = Path(a.out).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    if a.save:
        pose(0)
        bpy.ops.wm.save_as_mainfile(filepath=a.save)
    todo: list[int]
    if a.only:
        todo = [int(v) for v in a.only.split(",")]
    elif a.frames:
        lo_f, hi_f = (int(v) for v in a.frames.split("-"))
        todo = list(range(lo_f, min(hi_f, len(frames) - 1) + 1))
    else:
        todo = list(range(len(frames)))
    t_all = time.time()
    for i in todo:
        target_png = out_dir / f"{i:04d}.png"
        if target_png.exists() and not a.only:
            continue
        pose(i)
        sc.frame_current = i
        sc.render.filepath = str(target_png)
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        print(f"frame {i} t={frames[i]['t']:.2f}s rendered in {time.time() - t0:.1f} s", flush=True)
    print(f"done {len(todo)} frames in {time.time() - t_all:.0f} s", flush=True)
    _ = fps


if __name__ == "__main__":
    main()
