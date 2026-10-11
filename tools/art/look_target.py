"""Look-target render of the RTS camera view (Blender 4.5, headless EEVEE).

blender -b --factory-startup -P tools/art/look_target.py -- [out.jpg] [samples] [scale]

Reads the real terrain (assets/terrain/rift_lake), Poly Haven CC0 textures/HDRI/models and the CC BY Sketchfab
models in assets/_raw/sketchfab + assets/models/hominins. Only things the Godot Mobile renderer can also do are
used: one sun with soft shadows, HDRI sky light, AgX, no screen-space reflections or ray tracing.
Frame: Blender metres, Z up, +X east, +Y north; map pixel (col, row) -> x = col*0.5 - 256, y = 256 - row*0.5.
"""

from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
TER = ROOT / "assets/terrain/rift_lake"
PH = ROOT / "assets/_raw/polyhaven"
SF = ROOT / "assets/_raw/sketchfab"
HOM = ROOT / "assets/models/hominins"
args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
OUT = Path(args[0]) if args else ROOT / "docs/mockups/look_target.jpg"
SAMPLES = int(args[1]) if len(args) > 1 else 48
SCALE = float(args[2]) if len(args) > 2 else 1.0
rng = random.Random(11)
nrng = np.random.default_rng(11)

meta = json.loads((TER / "meta.json").read_text())


def load_png16(path):
    im = bpy.data.images.load(str(path))
    im.colorspace_settings.name = "Non-Color"
    w, h = im.size
    px = np.empty(w * h * 4, np.float32)
    im.pixels.foreach_get(px)
    a = px.reshape(h, w, 4)[::-1, :, 0]  # Blender rows bottom-up -> row 0 = north
    return a


H01 = load_png16(TER / "height.png")
HGT = meta["h_min"] + H01 * (meta["h_max"] - meta["h_min"])
SHORE = load_png16(TER / "shore.png") * 40.0
WATER = load_png16(TER / "water.png")
WL = meta["water_level"]


def _veg_channel(c):
    im = bpy.data.images.load(str(TER / "veg.png"), check_existing=True)
    w, h = im.size
    px = np.empty(w * h * 4, np.float32)
    im.pixels.foreach_get(px)
    return px.reshape(h, w, 4)[::-1, :, c]


VEGC = [_veg_channel(c) for c in range(4)]


def sample(grid, x, y):
    c = (x + 256.0) / 0.5
    r = (256.0 - y) / 0.5
    c0 = int(np.clip(np.floor(c), 0, 1023))
    r0 = int(np.clip(np.floor(r), 0, 1023))
    fc, fr = c - c0, r - r0
    g = grid
    return (
        g[r0, c0] * (1 - fc) * (1 - fr)
        + g[r0, c0 + 1] * fc * (1 - fr)
        + g[r0 + 1, c0] * (1 - fc) * fr
        + g[r0 + 1, c0 + 1] * fc * fr
    )


def ground(x, y):
    return float(sample(HGT, x, y))


# ------------------------------------------------------------------ scene
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
sc.render.resolution_percentage = int(SCALE * 100)
sc.eevee.taa_render_samples = SAMPLES
if hasattr(sc.eevee, "use_raytracing"):
    sc.eevee.use_raytracing = False  # Godot Mobile has no SSR/SSGI
if hasattr(sc.eevee, "use_shadows"):
    sc.eevee.use_shadows = True
if hasattr(sc.eevee, "shadow_resolution_scale"):
    sc.eevee.shadow_resolution_scale = 1.0
sc.view_settings.view_transform = "AgX"
for look in ("AgX - Medium High Contrast", "Medium High Contrast"):
    try:
        sc.view_settings.look = look
        break
    except TypeError:
        pass
sc.view_settings.exposure = -0.35

# Camp centre: land 30 m from the waterline on map row 520 (the shore bulge)
row = 520
cols = np.where((WATER[row] == 0) & (np.abs(SHORE[row] - 30) < 1.2))[0]
CAMP = Vector((cols[-1] * 0.5 - 256.0 - 6.0, 256.0 - row * 0.5))
print("CAMP", CAMP, "ground", ground(*CAMP))

# ------------------------------------------------------------------ world + sun
SUN_ELEV, SUN_AZ = 20.0, 258.0  # degrees; azimuth from north clockwise: WSW, late afternoon
world = bpy.data.worlds.new("sky")
sc.world = world
world.use_nodes = True
wn = world.node_tree.nodes
wl = world.node_tree.links
env = wn.new("ShaderNodeTexEnvironment")
env.image = bpy.data.images.load(str(PH / "hdri/qwantani_late_afternoon_4k.hdr"))
# rotate the HDRI so its sun sits at SUN_AZ: find the brightest texel
w_, h_ = env.image.size
px = np.empty(w_ * h_ * 4, np.float32)
env.image.pixels.foreach_get(px)
lum = px.reshape(h_, w_, 4)[..., :3].sum(-1)
ry, rx = np.unravel_index(np.argmax(lum), lum.shape)
hdri_az = (
    rx / w_
) * 360.0  # equirect u -> azimuth (Blender: u=0.5 faces -Y... handled by offset below)
hdri_el = (ry / h_) * 180.0 - 90.0
print("HDRI sun texel", rx, ry, "el", round(hdri_el, 1))
mapn = wn.new("ShaderNodeMapping")
tc = wn.new("ShaderNodeTexCoord")
wl.new(tc.outputs["Generated"], mapn.inputs[0])
wl.new(mapn.outputs[0], env.inputs[0])
# Blender equirect: u = atan2(dir.y, -dir.x)/(2pi) + 0.5. Solve rotation so the HDRI sun lands at SUN_AZ.
sun_dir = Vector((math.sin(math.radians(SUN_AZ)), math.cos(math.radians(SUN_AZ)), 0))
u_target = math.atan2(sun_dir.y, -sun_dir.x) / (2 * math.pi) + 0.5
mapn.inputs["Rotation"].default_value[2] = (rx / w_ - u_target) * 2 * math.pi
bg = wn["Background"]
bg.inputs["Strength"].default_value = 0.45
wl.new(env.outputs[0], bg.inputs[0])

sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sc.collection.objects.link(sun)
sun.data.energy = 6.0
sun.data.color = (1.0, 0.86, 0.70)
sun.data.angle = math.radians(1.2)
sun.rotation_euler = (
    (Vector((0, 0, 0)) - sun_dir.normalized() * 0).to_track_quat("Z", "Y").to_euler()
)
d = Vector(
    (
        sun_dir.x * math.cos(math.radians(SUN_ELEV)),
        sun_dir.y * math.cos(math.radians(SUN_ELEV)),
        math.sin(math.radians(SUN_ELEV)),
    )
)
sun.rotation_euler = d.to_track_quat("Z", "Y").to_euler()


# ------------------------------------------------------------------ materials helpers
def tex_node(nt, path, non_color=False, proj=None):
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(str(path), check_existing=True)
    if non_color:
        n.image.colorspace_settings.name = "Non-Color"
    return n


def ph_set(name):
    d = PH / "textures" / f"{name}_2k"
    f = {p.name.split(f"{name}_")[1].rsplit("_2k", 1)[0]: p for p in d.iterdir()}
    return f["diff"], f["nor_gl"], f["arm"], f.get("disp")


def bsdf(m):
    return next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


# ------------------------------------------------------------------ terrain
HALF = 125.0
STEP = 0.3
cx, cy = round(CAMP.x / STEP) * STEP, round(CAMP.y / STEP) * STEP
xs = np.arange(cx - HALF, cx + HALF + 1e-6, STEP)
ys = np.arange(cy - HALF, cy + HALF + 1e-6, STEP)
GX, GY = np.meshgrid(xs, ys)
cc = (GX + 256.0) / 0.5
rr = (256.0 - GY) / 0.5
c0 = np.clip(np.floor(cc).astype(int), 0, 1023)
r0 = np.clip(np.floor(rr).astype(int), 0, 1023)
fc, fr = cc - c0, rr - r0
Z = (
    HGT[r0, c0] * (1 - fc) * (1 - fr)
    + HGT[r0, c0 + 1] * fc * (1 - fr)
    + HGT[r0 + 1, c0] * (1 - fc) * fr
    + HGT[r0 + 1, c0 + 1] * fc * fr
)
# camp floor: trampled, slightly levelled
dc = np.hypot(GX - CAMP.x, GY - CAMP.y)
ny, nx = GX.shape
verts = np.stack([GX, GY, Z], -1).reshape(-1, 3)
ii = np.arange(ny * nx).reshape(ny, nx)
quads = np.stack([ii[:-1, :-1], ii[:-1, 1:], ii[1:, 1:], ii[1:, :-1]], -1).reshape(-1, 4)
me = bpy.data.meshes.new("terrain")
me.vertices.add(len(verts))
me.vertices.foreach_set("co", verts.astype(np.float32).ravel())
me.loops.add(quads.size)
me.loops.foreach_set("vertex_index", quads.astype(np.int32).ravel())
me.polygons.add(len(quads))
me.polygons.foreach_set("loop_start", np.arange(0, quads.size, 4, dtype=np.int32))
me.polygons.foreach_set("loop_total", np.full(len(quads), 4, np.int32))
me.update()
me.validate()
me.polygons.foreach_set("use_smooth", np.ones(len(quads), bool))
uv = me.uv_layers.new(name="map")  # map-space UV: (x+256)/512, (y+256)/512
luv = np.stack([(GX.ravel() + 256) / 512, (GY.ravel() + 256) / 512], -1)[quads.ravel()]
uv.data.foreach_set("uv", luv.astype(np.float32).ravel())
terrain = bpy.data.objects.new("terrain", me)
sc.collection.objects.link(terrain)

LAYERS = [  # (splat image, channel, poly haven set, tint multiplier, tile metres)
    ("splat_a", 0, "withered_grass", (0.78, 0.70, 0.56), 3.0),
    ("splat_a", 1, "red_mud_stones", (0.80, 0.70, 0.62), 2.5),
    ("splat_a", 2, "dark_rock", (0.85, 0.82, 0.80), 3.5),
    ("splat_a", 3, "coast_sand_01", (0.92, 0.88, 0.82), 3.0),
    ("splat_b", 0, "brown_mud_02", (0.8, 0.78, 0.74), 2.5),
    ("splat_b", 1, "dry_river_pebbles", (0.95, 0.92, 0.88), 1.8),
    ("splat_b", 2, "mud_cracked_dry_riverbed_002", (1.0, 0.95, 0.9), 3.0),
]
mat = bpy.data.materials.new("terrain")
mat.use_nodes = True
nt = mat.node_tree
N, L = nt.nodes, nt.links
b = bsdf(mat)
b.inputs["Specular IOR Level"].default_value = 0.35
uvn = N.new("ShaderNodeUVMap")
uvn.uv_map = "map"
geo = N.new("ShaderNodeNewGeometry")
pos = N.new("ShaderNodeSeparateXYZ")
L.new(geo.outputs["Position"], pos.inputs[0])
wpos = N.new("ShaderNodeCombineXYZ")
L.new(pos.outputs[0], wpos.inputs[0])
L.new(pos.outputs[1], wpos.inputs[1])
splats = {}
for s in ("splat_a", "splat_b"):
    t = tex_node(nt, TER / f"{s}.png", non_color=True)
    t.interpolation = "Cubic"
    L.new(uvn.outputs[0], t.inputs[0])
    sep = N.new("ShaderNodeSeparateColor")
    L.new(t.outputs["Color"], sep.inputs[0])
    splats[s] = (sep, t)
# camp mask: trampled red earth around the Home Tree
campd = N.new("ShaderNodeVectorMath")
campd.operation = "DISTANCE"
L.new(wpos.outputs[0], campd.inputs[0])
campd.inputs[1].default_value = (CAMP.x, CAMP.y, 0)
campn = N.new("ShaderNodeTexNoise")
campn.inputs["Scale"].default_value = 0.6
campn.inputs["Detail"].default_value = 6
L.new(wpos.outputs[0], campn.inputs["Vector"])
campm = N.new("ShaderNodeMath")
campm.operation = "MULTIPLY_ADD"
L.new(campn.outputs["Fac"], campm.inputs[0])
campm.inputs[1].default_value = 8.0
L.new(campd.outputs["Value"], campm.inputs[2])
camp_r = N.new("ShaderNodeMapRange")
camp_r.inputs["From Min"].default_value = 8.0
camp_r.inputs["From Max"].default_value = 16.0
camp_r.inputs["To Min"].default_value = 0.75
camp_r.inputs["To Max"].default_value = 0.0
L.new(campm.outputs[0], camp_r.inputs["Value"])

macro = N.new("ShaderNodeTexNoise")
macro.inputs["Scale"].default_value = 0.03
macro.inputs["Detail"].default_value = 4
L.new(wpos.outputs[0], macro.inputs["Vector"])

acc_col = acc_nrm = acc_rgh = acc_w = None
for i, (s, ch, setname, tint, tile) in enumerate(LAYERS):
    diff, nor, arm, disp = ph_set(setname)
    sc_m = N.new("ShaderNodeVectorMath")
    sc_m.operation = "SCALE"
    rot = N.new("ShaderNodeVectorRotate")
    rot.rotation_type = "Z_AXIS"
    rot.inputs["Angle"].default_value = 0.6 * i
    L.new(wpos.outputs[0], rot.inputs[0])
    L.new(rot.outputs[0], sc_m.inputs[0])
    sc_m.inputs["Scale"].default_value = 1.0 / tile
    tc_ = tex_node(nt, diff)
    L.new(sc_m.outputs[0], tc_.inputs[0])
    tn_ = tex_node(nt, nor, True)
    L.new(sc_m.outputs[0], tn_.inputs[0])
    ta_ = tex_node(nt, arm, True)
    L.new(sc_m.outputs[0], ta_.inputs[0])
    td_ = tex_node(nt, disp, True) if disp else None
    if td_:
        L.new(sc_m.outputs[0], td_.inputs[0])
    tintn = N.new("ShaderNodeMix")
    tintn.data_type = "RGBA"
    tintn.blend_type = "MULTIPLY"
    tintn.inputs["Factor"].default_value = 1.0
    L.new(tc_.outputs["Color"], tintn.inputs[6])
    tintn.inputs[7].default_value = (*tint, 1)
    # weight = splat * (0.35 + height)^4 : height-blended transitions
    wsrc = splats[s][0].outputs[ch] if ch < 3 else splats[s][1].outputs["Alpha"]
    if setname == "red_mud_stones":  # camp floor uses the red earth layer
        mx = N.new("ShaderNodeMath")
        mx.operation = "MAXIMUM"
        L.new(wsrc, mx.inputs[0])
        L.new(camp_r.outputs[0], mx.inputs[1])
        wsrc = mx.outputs[0]
    elif True:
        inv = N.new("ShaderNodeMath")
        inv.operation = "MULTIPLY"
        one = N.new("ShaderNodeMath")
        one.operation = "SUBTRACT"
        one.inputs[0].default_value = 1.0
        L.new(camp_r.outputs[0], one.inputs[1])
        L.new(wsrc, inv.inputs[0])
        L.new(one.outputs[0], inv.inputs[1])
        wsrc = inv.outputs[0]
    hadd = N.new("ShaderNodeMath")
    hadd.operation = "ADD"
    hadd.inputs[1].default_value = 0.35
    if td_:
        L.new(td_.outputs["Color"], hadd.inputs[0])
    else:
        hadd.inputs[0].default_value = 0.5
    hp = N.new("ShaderNodeMath")
    hp.operation = "POWER"
    hp.inputs[1].default_value = 4.0
    L.new(hadd.outputs[0], hp.inputs[0])
    wv = N.new("ShaderNodeMath")
    wv.operation = "MULTIPLY"
    L.new(wsrc, wv.inputs[0])
    L.new(hp.outputs[0], wv.inputs[1])
    wp = N.new("ShaderNodeMath")
    wp.operation = "POWER"
    wp.inputs[1].default_value = 2.0
    L.new(wv.outputs[0], wp.inputs[0])
    w = wp.outputs[0]

    def wmul(sock, is_color=True):
        m_ = N.new("ShaderNodeVectorMath")
        m_.operation = "SCALE"
        L.new(sock, m_.inputs[0])
        L.new(w, m_.inputs["Scale"])  # noqa: B023 (called inside the same loop iteration)
        return m_.outputs[0]

    rough = N.new("ShaderNodeSeparateColor")
    L.new(ta_.outputs["Color"], rough.inputs[0])
    c_ = wmul(tintn.outputs[2])
    n_ = wmul(tn_.outputs["Color"])
    r_ = wmul(rough.outputs[1])
    if acc_col is None:
        acc_col, acc_nrm, acc_rgh, acc_w = c_, n_, r_, w
    else:
        for name in ("col", "nrm", "rgh"):
            a_ = N.new("ShaderNodeVectorMath")
            a_.operation = "ADD"
            src = {"col": acc_col, "nrm": acc_nrm, "rgh": acc_rgh}[name]
            new = {"col": c_, "nrm": n_, "rgh": r_}[name]
            L.new(src, a_.inputs[0])
            L.new(new, a_.inputs[1])
            if name == "col":
                acc_col = a_.outputs[0]
            elif name == "nrm":
                acc_nrm = a_.outputs[0]
            else:
                acc_rgh = a_.outputs[0]
        aw = N.new("ShaderNodeMath")
        aw.operation = "ADD"
        L.new(acc_w, aw.inputs[0])
        L.new(w, aw.inputs[1])
        acc_w = aw.outputs[0]

eps = N.new("ShaderNodeMath")
eps.operation = "MAXIMUM"
eps.inputs[1].default_value = 1e-5
L.new(acc_w, eps.inputs[0])
rcp = N.new("ShaderNodeMath")
rcp.operation = "DIVIDE"
rcp.inputs[0].default_value = 1.0
L.new(eps.outputs[0], rcp.inputs[1])


def norm(sock):
    m_ = N.new("ShaderNodeVectorMath")
    m_.operation = "SCALE"
    L.new(sock, m_.inputs[0])
    L.new(rcp.outputs[0], m_.inputs["Scale"])
    return m_.outputs[0]


col = norm(acc_col)
# macro variation: +-12 % brightness over 25 m to kill tiling
mv = N.new("ShaderNodeMapRange")
mv.inputs["To Min"].default_value = 0.72
mv.inputs["To Max"].default_value = 1.12
L.new(macro.outputs["Fac"], mv.inputs["Value"])
mv.inputs["From Min"].default_value = 0.3
mv.inputs["From Max"].default_value = 0.7
colm = N.new("ShaderNodeVectorMath")
colm.operation = "SCALE"
L.new(col, colm.inputs[0])
L.new(mv.outputs[0], colm.inputs["Scale"])
L.new(colm.outputs[0], b.inputs["Base Color"])
nm = N.new("ShaderNodeNormalMap")
nm.inputs["Strength"].default_value = 1.0
L.new(norm(acc_nrm), nm.inputs["Color"])
L.new(nm.outputs[0], b.inputs["Normal"])
rs = N.new("ShaderNodeSeparateXYZ")
L.new(norm(acc_rgh), rs.inputs[0])
L.new(rs.outputs[0], b.inputs["Roughness"])
terrain.data.materials.append(mat)

# ------------------------------------------------------------------ water (Lake Turkana, the "Jade Sea")
wme = bpy.data.meshes.new("water")
bpy_verts = [
    (cx - 400, cy - 400, WL),
    (cx + 400, cy - 400, WL),
    (cx + 400, cy + 400, WL),
    (cx - 400, cy + 400, WL),
]
wme.from_pydata(bpy_verts, [], [(0, 1, 2, 3)])
wuv = wme.uv_layers.new(name="map")
for li, (x, y, _) in enumerate(bpy_verts):
    wuv.data[li].uv = ((x + 256) / 512, (y + 256) / 512)
water = bpy.data.objects.new("water", wme)
sc.collection.objects.link(water)
wm = bpy.data.materials.new("water")
wm.use_nodes = True
nt = wm.node_tree
N, L = nt.nodes, nt.links
b = bsdf(wm)
uvn = N.new("ShaderNodeUVMap")
uvn.uv_map = "map"
dep = tex_node(nt, TER / "water.png", True)
L.new(uvn.outputs[0], dep.inputs[0])
dep.interpolation = "Cubic"
dep.extension = "EXTEND"
sho = tex_node(nt, TER / "shore.png", True)
L.new(uvn.outputs[0], sho.inputs[0])
sho.interpolation = "Cubic"
sho.extension = "EXTEND"
ramp = N.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.0
ramp.color_ramp.elements[0].color = (0.16, 0.17, 0.11, 1)  # silty shallows over the mud shelf
ramp.color_ramp.elements[1].position = 0.55
ramp.color_ramp.elements[1].color = (0.035, 0.105, 0.085, 1)  # jade
e = ramp.color_ramp.elements.new(0.18)
e.color = (0.07, 0.13, 0.085, 1)
L.new(dep.outputs["Color"], ramp.inputs[0])
# foam: thin broken band at the waterline
fn = N.new("ShaderNodeTexNoise")
fn.inputs["Scale"].default_value = 1.6
fn.inputs["Detail"].default_value = 6
geo = N.new("ShaderNodeNewGeometry")
L.new(geo.outputs["Position"], fn.inputs["Vector"])
fm = N.new("ShaderNodeMapRange")
fm.inputs["From Min"].default_value = 0.0
fm.inputs["From Max"].default_value = 0.022
fm.inputs["To Min"].default_value = 1.0
fm.inputs["To Max"].default_value = 0.0
L.new(sho.outputs["Color"], fm.inputs["Value"])
fk = N.new("ShaderNodeMath")
fk.operation = "MULTIPLY"
L.new(fm.outputs[0], fk.inputs[0])
fth = N.new("ShaderNodeMapRange")
fth.inputs["From Min"].default_value = 0.5
fth.inputs["From Max"].default_value = 0.66
L.new(fn.outputs["Fac"], fth.inputs["Value"])
L.new(fth.outputs[0], fk.inputs[1])
mixc = N.new("ShaderNodeMix")
mixc.data_type = "RGBA"
L.new(fk.outputs[0], mixc.inputs["Factor"])
L.new(ramp.outputs[0], mixc.inputs[6])
mixc.inputs[7].default_value = (0.75, 0.73, 0.66, 1)
L.new(mixc.outputs[2], b.inputs["Base Color"])
rmix = N.new("ShaderNodeMapRange")
rmix.inputs["To Min"].default_value = 0.035
rmix.inputs["To Max"].default_value = 0.7
L.new(fk.outputs[0], rmix.inputs["Value"])
L.new(rmix.outputs[0], b.inputs["Roughness"])
b.inputs["Specular IOR Level"].default_value = 0.5
wv = N.new("ShaderNodeTexWave")
wv.wave_type = "BANDS"
wv.inputs["Scale"].default_value = 0.35
wv.inputs["Distortion"].default_value = 6
wv.inputs["Detail"].default_value = 4
wn2 = N.new("ShaderNodeTexNoise")
wn2.inputs["Scale"].default_value = 1.2
wn2.inputs["Detail"].default_value = 8
L.new(geo.outputs["Position"], wv.inputs["Vector"])
L.new(geo.outputs["Position"], wn2.inputs["Vector"])
add = N.new("ShaderNodeMath")
add.operation = "ADD"
L.new(wv.outputs["Fac"], add.inputs[0])
L.new(wn2.outputs["Fac"], add.inputs[1])
bump = N.new("ShaderNodeBump")
bump.inputs["Strength"].default_value = 0.18
bump.inputs["Distance"].default_value = 0.05
L.new(add.outputs[0], bump.inputs["Height"])
L.new(bump.outputs[0], b.inputs["Normal"])
water.data.materials.append(wm)


# ------------------------------------------------------------------ asset import helpers
def import_asset(path, name):
    before = set(bpy.data.objects)
    if str(path).endswith((".glb", ".gltf")):
        bpy.ops.import_scene.gltf(filepath=str(path))
    new = [o for o in bpy.data.objects if o not in before]
    coll = bpy.data.collections.new(name)
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
    return coll, new


def bounds(objs):
    """World bounds from vertex data (bound_box is stale right after mesh edits)."""
    mn = np.full(3, 1e9)
    mx = -mn
    for o in objs:
        if o.type != "MESH" or not len(o.data.vertices):
            continue
        co = np.empty(len(o.data.vertices) * 3, np.float32)
        o.data.vertices.foreach_get("co", co)
        co = (
            co.reshape(-1, 3) @ np.array(o.matrix_world)[:3, :3].T + np.array(o.matrix_world)[:3, 3]
        )
        mn = np.minimum(mn, co.min(0))
        mx = np.maximum(mx, co.max(0))
    return Vector(mn), Vector(mx)


def proto(path, name, height=None, length=None, split=False):
    """Import once into a hidden collection, normalised so origin = bottom centre, Z up; returns list of
    collections (one per mesh variant if split)."""
    coll, objs = import_asset(path, name)
    meshes = [o for o in objs if o.type == "MESH"]
    bpy.context.view_layer.update()
    # bake world transforms into mesh data, drop parents/empties
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data = o.data.copy()
        o.data.transform(mw)
        o.matrix_world = Matrix()
    for o in objs:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    groups = [[o] for o in meshes] if split else [meshes]
    out = []
    for gi, g in enumerate(groups):
        mn, mx = bounds(g)
        s = 1.0
        if height:
            s = height / max(mx.z - mn.z, 1e-6)
        if length:
            s = length / max(mx.x - mn.x, mx.y - mn.y, 1e-6)
        c = coll if not split else bpy.data.collections.new(f"{name}_{gi}")
        for o in g:
            o.data.transform(
                Matrix.Scale(s, 4)
                @ Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
            )
            if split:
                coll.objects.unlink(o)
                c.objects.link(o)
        out.append(c)
    return out


HIDDEN = bpy.data.collections.new("_protos")
sc.collection.children.link(HIDDEN)
bpy.context.view_layer.layer_collection.children["_protos"].exclude = True


def stash(colls):
    for c in colls:
        HIDDEN.children.link(c)
    return colls


def place(coll, x, y, rotz=None, scale=1.0, z_off=0.0, tilt=0.0):
    e = bpy.data.objects.new(coll.name + "_i", None)
    e.instance_type = "COLLECTION"
    e.instance_collection = coll
    e.location = (x, y, ground(x, y) + z_off)
    e.rotation_euler = (
        rng.uniform(-tilt, tilt),
        rng.uniform(-tilt, tilt),
        rng.uniform(0, 6.283) if rotz is None else rotz,
    )
    e.scale = (scale,) * 3
    sc.collection.objects.link(e)
    return e


def tint_materials(colls, mul, sat=None):
    seen = set()
    for c in colls:
        for o in c.all_objects:
            for m in o.data.materials:
                if not m or m.name in seen or not m.use_nodes:
                    continue
                seen.add(m.name)
                bb = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                if not bb or not bb.inputs["Base Color"].is_linked:
                    continue
                src = bb.inputs["Base Color"].links[0].from_socket
                hsv = m.node_tree.nodes.new("ShaderNodeHueSaturation")
                hsv.inputs["Saturation"].default_value = sat if sat is not None else 1.0
                hsv.inputs["Value"].default_value = 1.0
                m.node_tree.links.new(src, hsv.inputs["Color"])
                mm = m.node_tree.nodes.new("ShaderNodeMix")
                mm.data_type = "RGBA"
                mm.blend_type = "MULTIPLY"
                mm.inputs["Factor"].default_value = 1.0
                m.node_tree.links.new(hsv.outputs[0], mm.inputs[6])
                mm.inputs[7].default_value = (*mul, 1)
                m.node_tree.links.new(mm.outputs[2], bb.inputs["Base Color"])


def points_instancer(name, colls, pts, rots, scales, idx):
    """Geometry-nodes instancer: one mesh of points, attributes rot/scl/idx, picks a child of a collection."""
    holder = bpy.data.collections.new(name + "_set")
    for c in colls:
        holder.children.link(c)
    HIDDEN.children.link(holder)
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(pts))
    me.vertices.foreach_set("co", np.asarray(pts, np.float32).ravel())
    a = me.attributes.new("rot", "FLOAT_VECTOR", "POINT")
    a.data.foreach_set("vector", np.asarray(rots, np.float32).ravel())
    a = me.attributes.new("scl", "FLOAT", "POINT")
    a.data.foreach_set("value", np.asarray(scales, np.float32))
    a = me.attributes.new("idx", "INT", "POINT")
    a.data.foreach_set("value", np.asarray(idx, np.int32))
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    ng = bpy.data.node_groups.new(name + "_gn", "GeometryNodeTree")
    ng.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    n_in = ng.nodes.new("NodeGroupInput")
    n_out = ng.nodes.new("NodeGroupOutput")
    ci = ng.nodes.new("GeometryNodeCollectionInfo")
    ci.inputs["Collection"].default_value = holder
    ci.inputs["Separate Children"].default_value = True
    ci.inputs["Reset Children"].default_value = True
    iop = ng.nodes.new("GeometryNodeInstanceOnPoints")
    iop.inputs["Pick Instance"].default_value = True
    ar = ng.nodes.new("GeometryNodeInputNamedAttribute")
    ar.data_type = "FLOAT_VECTOR"
    ar.inputs["Name"].default_value = "rot"
    as_ = ng.nodes.new("GeometryNodeInputNamedAttribute")
    as_.data_type = "FLOAT"
    as_.inputs["Name"].default_value = "scl"
    ai = ng.nodes.new("GeometryNodeInputNamedAttribute")
    ai.data_type = "INT"
    ai.inputs["Name"].default_value = "idx"
    lk = ng.links.new
    lk(n_in.outputs[0], iop.inputs["Points"])
    lk(ci.outputs[0], iop.inputs["Instance"])
    lk(ai.outputs["Attribute"], iop.inputs["Instance Index"])
    lk(ar.outputs["Attribute"], iop.inputs["Rotation"])
    lk(as_.outputs["Attribute"], iop.inputs["Scale"])
    lk(iop.outputs[0], n_out.inputs[0])
    mod = ob.modifiers.new("inst", "NODES")
    mod.node_group = ng
    ob.visible_shadow = False  # ground cover casts no sun shadow (also the phone setting)
    for c in colls:
        for o in c.all_objects:
            o.visible_shadow = False
    return ob


# ------------------------------------------------------------------ vegetation + rocks
acacia = stash(proto(SF / "trees/bb14c2bb679b4d0bb1c578a27e2ddabf.glb", "acacia", height=7.5))[0]
palm = stash(proto(SF / "trees/00bd2ea54eb1405bb056eac3f1e14673.glb", "doum_palm", height=11.0))[0]
fig = stash(proto(SF / "trees/2a0dbcdf8f5d48f5ad79987c7a8170ce.glb", "home_fig", height=17.0))[0]
grass = stash(proto(PH / "models/grass_medium_02_2k/grass_medium_02_2k.gltf", "grass", split=True))
bermuda = stash(
    proto(PH / "models/grass_bermuda_01_2k/grass_bermuda_01_2k.gltf", "bermuda", split=True)
)
shrub4 = stash(proto(PH / "models/shrub_04_2k/shrub_04_2k.gltf", "shrub4", height=1.6))
shrub2 = stash(proto(PH / "models/shrub_02_2k/shrub_02_2k.gltf", "shrub2", split=True))
searsia = stash(
    proto(PH / "models/searsia_lucida_2k/searsia_lucida_2k.gltf", "searsia", split=True)
)
boulders = stash(
    proto(PH / "models/namaqualand_boulder_04_2k/namaqualand_boulder_04_2k.gltf", "b4", split=True)
    + proto(
        PH / "models/namaqualand_boulder_02_2k/namaqualand_boulder_02_2k.gltf", "b2", split=True
    )
    + proto(
        PH / "models/namaqualand_boulder_05_2k/namaqualand_boulder_05_2k.gltf", "b5", split=True
    )
)
stones = stash(
    proto(
        PH / "models/namaqualand_stones_01_2k/namaqualand_stones_01_2k.gltf", "stones", split=True
    )
)
rocks_s = stash(
    proto(PH / "models/namaqualand_rocks_01_2k/namaqualand_rocks_01_2k.gltf", "rocks", split=True)
)
branches = stash(
    proto(
        PH / "models/dry_branches_medium_01_2k/dry_branches_medium_01_2k.gltf",
        "branches",
        split=True,
    )
)
deadb = stash(
    proto(PH / "models/dead_quiver_branch_01_2k/dead_quiver_branch_01_2k.gltf", "deadb", split=True)
)
deadtrunk = stash(proto(PH / "models/dead_tree_trunk_2k/dead_tree_trunk_2k.gltf", "deadtrunk"))[0]
heap = stash(proto(SF / "props/31a023461b2f4b1fb912b25e86acb586.glb", "branch_heap", length=2.6))[0]
tubers = stash(proto(PH / "models/sweet_potato_2k/sweet_potato_2k.gltf", "tuber", split=True))
tint_materials(grass, (1.55, 1.22, 0.70), sat=0.30)  # sun-cured straw
tint_materials(bermuda, (0.95, 0.85, 0.6), sat=0.45)
tint_materials(
    boulders + rocks_s, (0.42, 0.38, 0.35), sat=0.5
)  # granite scans -> dark vesicular basalt
tint_materials(stones, (0.45, 0.41, 0.37), sat=0.6)
tint_materials(shrub4 + searsia, (0.85, 0.85, 0.72), sat=0.75)
tint_materials([acacia], (0.95, 0.95, 0.85), sat=0.85)

for (
    m_
) in bpy.data.materials:  # alpha-tested foliage: dithered (= Godot alpha scissor), never blended
    if m_.use_nodes:
        bb_ = next((n for n in m_.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if (
            bb_
            and not bb_.inputs["Alpha"].is_linked
            and ("grass" in m_.name or "bermuda" in m_.name)
        ):
            tex_ = next(
                (
                    n
                    for n in m_.node_tree.nodes
                    if n.type == "TEX_IMAGE" and n.image and "diff" in n.image.name
                ),
                None,
            )
            if tex_:
                m_.node_tree.links.new(tex_.outputs["Alpha"], bb_.inputs["Alpha"])
        if bb_ and bb_.inputs["Alpha"].is_linked:
            m_.surface_render_method = "DITHERED"
        if (
            bb_ and bb_.inputs["Metallic"].is_linked
        ):  # Poly Haven ARM blue is ~0; keep foliage dielectric
            m_.node_tree.links.remove(bb_.inputs["Metallic"].links[0])
            bb_.inputs["Metallic"].default_value = 0.0

VIEW_R = 95.0
gpts, grot, gscl, gidx = [], [], [], []
for _ in range(90000):
    x = CAMP.x + nrng.uniform(-VIEW_R, VIEW_R)
    y = CAMP.y + nrng.uniform(-VIEW_R, VIEW_R)
    if sample(WATER, x, y) > 0:
        continue
    sh_ = sample(SHORE, x, y)
    dens = sample(VEGC[2], x, y)
    dcamp = math.hypot(x - CAMP.x, y - CAMP.y)
    if dcamp < 15 + 3 * nrng.random():
        dens *= 0.12
    if sh_ < 5 or nrng.random() > dens * 0.75:
        continue
    gpts.append((x, y, ground(x, y) - 0.02))
    grot.append((0, 0, nrng.uniform(0, 6.283)))
    gscl.append(nrng.uniform(2.6, 4.6))
    gidx.append(int(nrng.integers(0, 1 << 30)))
print("grass tufts", len(gpts))
# tussocks: 3 clumps of 18 blades-sets each (one PH tuft is too thin to read at 50 m)
tus = []
for k in range(3):
    c = bpy.data.collections.new(f"tussock_{k}")
    for j in range(18):
        src = rng.choice(grass).objects[0]
        o = bpy.data.objects.new(f"tus{k}_{j}", src.data)
        a = rng.uniform(0, 6.283)
        r = 0.22 * math.sqrt(rng.random())
        o.location = (r * math.cos(a), r * math.sin(a), 0)
        o.rotation_euler = (
            rng.uniform(-0.25, 0.25),
            rng.uniform(-0.25, 0.25),
            rng.uniform(0, 6.283),
        )
        o.scale = (rng.uniform(1.6, 2.6),) * 3
        c.objects.link(o)
    tus.append(c)
stash(tus)
points_instancer("grass_tufts", tus, gpts, grot, [g_ * 0.26 for g_ in gscl], gidx)

# reeds/green sedge band at the waterline (bermuda grass, greener)
reeds = stash(
    proto(PH / "models/grass_bermuda_01_2k/grass_bermuda_01_2k.gltf", "reedgrass", split=True)
)
tint_materials(reeds, (0.8, 0.95, 0.65), sat=1.0)
rp, rr_, rs_, ri = [], [], [], []
for _ in range(9000):
    x = CAMP.x + nrng.uniform(-VIEW_R, VIEW_R)
    y = CAMP.y + nrng.uniform(-VIEW_R, VIEW_R)
    sh_ = sample(SHORE, x, y)
    wet = sample(WATER, x, y)
    if not (wet == 0 and 1.0 < sh_ < 6.0) or nrng.random() > sample(VEGC[3], x, y):
        continue
    rp.append((x, y, ground(x, y)))
    rr_.append((0, 0, nrng.uniform(0, 6.283)))
    rs_.append(nrng.uniform(1.4, 2.4))
    ri.append(int(nrng.integers(0, 1 << 30)))
points_instancer("shore_sedge", reeds, rp, rr_, rs_, ri)

# trees: acacias in the dry channels, doum palms along the shore, the Home Tree at camp
placed = []


def free(x, y, r):
    return all(math.hypot(x - a, y - b_) > r for a, b_ in placed)


for _ in range(4000):
    x = CAMP.x + nrng.uniform(-VIEW_R, VIEW_R)
    y = CAMP.y + nrng.uniform(-VIEW_R, VIEW_R)
    if (
        sample(WATER, x, y) > 0
        or sample(SHORE, x, y) < 10
        or math.hypot(x - CAMP.x, y - CAMP.y) < 20
        or math.hypot(x - CAMP.x - 4, y - CAMP.y + 24) < 20
    ):
        continue
    if nrng.random() < 0.05 + sample(VEGC[0], x, y) * 0.6 and free(x, y, 7):
        place(acacia, x, y, scale=nrng.uniform(0.75, 1.25))
        placed.append((x, y))
for _ in range(3000):
    x = CAMP.x + nrng.uniform(-VIEW_R, VIEW_R)
    y = CAMP.y + nrng.uniform(-VIEW_R, VIEW_R)
    if (
        sample(WATER, x, y) > 0
        or sample(SHORE, x, y) < 7
        or math.hypot(x - CAMP.x, y - CAMP.y) < 18
        or math.hypot(x - CAMP.x - 4, y - CAMP.y + 24) < 18
    ):
        continue
    if nrng.random() < sample(VEGC[1], x, y) * 0.05 and free(x, y, 5):
        place(palm, x, y, scale=nrng.uniform(0.7, 1.15), tilt=0.06)
        placed.append((x, y))
for _ in range(5000):
    x = CAMP.x + nrng.uniform(-VIEW_R, VIEW_R)
    y = CAMP.y + nrng.uniform(-VIEW_R, VIEW_R)
    if (
        sample(WATER, x, y) > 0
        or sample(SHORE, x, y) < 9
        or math.hypot(x - CAMP.x, y - CAMP.y) < 14
    ):
        continue
    if nrng.random() < 0.10 + sample(VEGC[0], x, y) * 0.4 and free(x, y, 2.2):
        place(rng.choice(searsia + searsia + shrub4), x, y, scale=nrng.uniform(0.6, 1.3))
        placed.append((x, y))
print("trees+shrubs", len(placed))

# basalt boulders and cobbles where the rock layer shows, more on the low ridge
for _ in range(220):
    x = CAMP.x + nrng.uniform(-VIEW_R, VIEW_R)
    y = CAMP.y + nrng.uniform(-VIEW_R, VIEW_R)
    if sample(WATER, x, y) > 0 or math.hypot(x - CAMP.x, y - CAMP.y) < 16:
        continue
    place(rng.choice(boulders), x, y, scale=nrng.uniform(0.25, 0.8), z_off=-0.15, tilt=0.3)
for _ in range(500):
    x = CAMP.x + nrng.uniform(-VIEW_R, VIEW_R)
    y = CAMP.y + nrng.uniform(-VIEW_R, VIEW_R)
    if sample(WATER, x, y) > 0:
        continue
    place(rng.choice(rocks_s + stones), x, y, scale=nrng.uniform(0.8, 1.6), z_off=-0.03)

cp, cr, cs, ci = [], [], [], []
for _ in range(40000):  # desert pavement: dark lava cobbles everywhere on the dry plain
    x = CAMP.x + nrng.uniform(-VIEW_R, VIEW_R)
    y = CAMP.y + nrng.uniform(-VIEW_R, VIEW_R)
    if sample(WATER, x, y) > 0 or sample(SHORE, x, y) < 3:
        continue
    cp.append((x, y, ground(x, y) - 0.02))
    cr.append((nrng.uniform(-0.4, 0.4), nrng.uniform(-0.4, 0.4), nrng.uniform(0, 6.3)))
    cs.append(nrng.uniform(0.6, 1.6))
    ci.append(int(nrng.integers(0, 1 << 30)))
cob = stash(
    proto(PH / "models/namaqualand_rocks_01_2k/namaqualand_rocks_01_2k.gltf", "cobble", split=True)
)
tint_materials(cob, (0.38, 0.34, 0.31), sat=0.4)
points_instancer("lava_cobbles", cob, cp, cr, cs, ci)

# ------------------------------------------------------------------ the camp (Age 1)
home = place(fig, CAMP.x, CAMP.y, rotz=0.4)
for dx, dy, k in [
    (31, 14, "a"),
    (42, -1, "p"),
    (37, 19, "p"),
    (45, 9, "p"),
    (-2, -38, "a"),
    (34, -30, "a"),
]:
    place(
        acacia if k == "a" else palm,
        CAMP.x + dx,
        CAMP.y + dy,
        scale=rng.uniform(0.85, 1.1),
        tilt=0.04 if k == "p" else 0,
    )
placed.append(tuple(CAMP))
# nest grove: a cluster of acacias with branch nests, NW of the Home Tree
for k, (dx, dy) in enumerate([(-16, 9), (-21, 3), (-12, 15)]):
    t = place(acacia, CAMP.x + dx, CAMP.y + dy, scale=0.95 + 0.1 * k)
    for j in range(3):
        nb = place(
            rng.choice(branches),
            CAMP.x + dx + rng.uniform(-1.5, 1.5),
            CAMP.y + dy + rng.uniform(-1.5, 1.5),
            scale=0.9,
        )
        nb.location.z += 4.6 + rng.uniform(-0.4, 0.4)
# cache: food and stone piled by the tree (tubers, cobbles, a branch heap)
CACHE = Vector((CAMP.x + 8.5, CAMP.y - 6.0))
place(heap, CACHE.x, CACHE.y, rotz=0.3, z_off=-0.25)
for j in range(4):  # windbreak-style sleeping nests on the ground at the nest grove
    place(heap, CAMP.x - 17 + 3.5 * j, CAMP.y + 6 + rng.uniform(-2, 2), scale=0.8, z_off=-0.25)
for j in range(40):
    place(
        rng.choice(tubers),
        CACHE.x + 2.2 + rng.uniform(-0.6, 0.6),
        CACHE.y + rng.uniform(-0.6, 0.6),
        scale=2.2,
        z_off=0.02,
        tilt=1.2,
    )
for j in range(10):
    place(
        rng.choice(stones + rocks_s),
        CACHE.x - 2.2 + rng.uniform(-0.8, 0.8),
        CACHE.y + rng.uniform(-0.8, 0.8),
        scale=1.4,
    )
# knapping floor: cobbles and flakes on a cleared patch SW of the tree
KNAP = Vector((CAMP.x - 9.0, CAMP.y - 11.0))
for j in range(70):
    a = rng.uniform(0, 6.283)
    r = 3.2 * math.sqrt(rng.random())
    place(
        rng.choice(stones + rocks_s),
        KNAP.x + r * math.cos(a),
        KNAP.y + r * math.sin(a),
        scale=rng.uniform(0.6, 1.3),
    )
for j in range(5):
    place(
        rng.choice(boulders),
        KNAP.x + rng.uniform(-2.5, 2.5),
        KNAP.y + rng.uniform(-2.5, 2.5),
        scale=0.18,
        z_off=-0.05,
    )
# carcass in the open to the south: a skeleton scan lying on its side, bone + dried hide material
CARC = Vector((CAMP.x + 13.0, CAMP.y - 19.0))
skel = stash(proto(SF / "props/eaca504567604e879b8ab2cf2763025e.glb", "carcass", length=2.4))[0]
bone = bpy.data.materials.new("bone")
bone.use_nodes = True
bb_ = bsdf(bone)
bn_ = bone.node_tree.nodes.new("ShaderNodeTexNoise")
bn_.inputs["Scale"].default_value = 9
br_ = bone.node_tree.nodes.new("ShaderNodeValToRGB")
br_.color_ramp.elements[0].color = (0.16, 0.05, 0.03, 1)
br_.color_ramp.elements[1].color = (0.62, 0.55, 0.44, 1)
br_.color_ramp.elements[0].position = 0.42
br_.color_ramp.elements[1].position = 0.6
bone.node_tree.links.new(bn_.outputs["Fac"], br_.inputs[0])
bone.node_tree.links.new(br_.outputs[0], bb_.inputs["Base Color"])
bb_.inputs["Roughness"].default_value = 0.6
for o in skel.objects:
    o.data.materials.clear()
    o.data.materials.append(bone)
    o.data.transform(Matrix.Rotation(math.radians(90), 4, "Y"))  # on its side
mn_, mx_ = bounds(list(skel.objects))
for o in skel.objects:
    o.data.transform(Matrix.Translation((0, 0, -mn_.z - 0.25)))
place(skel, CARC.x, CARC.y, rotz=1.1)

# ------------------------------------------------------------------ hominins (Age 1, retargeted rig)
TEAM = {"ochre": (0.22, 0.035, 0.018), "clay": (0.58, 0.56, 0.51)}


def posed_copy(glb, clip, frame, name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(glb))
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    meshes = [o for o in new if o.type == "MESH" and not o.name.lower().startswith("icosphere")]
    for o in meshes:  # rest height for the body paint band
        z = np.empty(len(o.data.vertices) * 3, np.float32)
        o.data.vertices.foreach_get("co", z)
        zw = (np.array(o.matrix_world) @ np.c_[z.reshape(-1, 3), np.ones(len(o.data.vertices))].T)[
            2
        ]
        at = o.data.attributes.new("restz", "FLOAT", "POINT")
        at.data.foreach_set("value", zw.astype(np.float32))
    act = bpy.data.actions.get(clip) or next(a for a in bpy.data.actions if a.name.startswith(clip))
    arm.animation_data_create()
    for tr in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(tr)
    arm.animation_data.action = act
    if (
        hasattr(arm.animation_data, "action_suitable_slots")
        and arm.animation_data.action_suitable_slots
    ):
        arm.animation_data.action_slot = arm.animation_data.action_suitable_slots[0]
    sc.frame_set(int(frame))
    dg = bpy.context.evaluated_depsgraph_get()
    outs = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        m = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
        m.transform(o.matrix_world)
        ob = bpy.data.objects.new(name, m)
        outs.append(ob)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    coll = bpy.data.collections.new(name)
    for ob in outs:
        coll.objects.link(ob)
    HIDDEN.children.link(coll)
    return coll


def team_paint(coll, colour, lo=0.70, hi=0.79, lo2=0.47, hi2=0.53):
    """Ochre / white clay body paint: a chest-shoulder band and a hip band, by rest-pose height (fraction of
    a 1.3 m body). Reads at 40 px from the RTS camera; the Godot shader does the same with a UV2/vertex mask."""
    for o in coll.objects:
        for slot in o.material_slots:
            m = slot.material.copy()
            slot.material = m
            nt = m.node_tree
            bb = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            src = (
                bb.inputs["Base Color"].links[0].from_socket
                if bb.inputs["Base Color"].is_linked
                else None
            )
            at = nt.nodes.new("ShaderNodeAttribute")
            at.attribute_name = "restz"
            nz = nt.nodes.new("ShaderNodeTexNoise")
            nz.inputs["Scale"].default_value = 30.0
            band = nt.nodes.new("ShaderNodeMath")
            band.operation = "MAXIMUM"
            parts = []
            for a_, b_ in ((lo, hi), (lo2, hi2)):
                r1 = nt.nodes.new("ShaderNodeMapRange")
                r1.interpolation_type = "SMOOTHSTEP"
                r1.inputs["From Min"].default_value = a_ * 1.3
                r1.inputs["From Max"].default_value = a_ * 1.3 + 0.03
                r2 = nt.nodes.new("ShaderNodeMapRange")
                r2.interpolation_type = "SMOOTHSTEP"
                r2.inputs["From Min"].default_value = b_ * 1.3
                r2.inputs["From Max"].default_value = b_ * 1.3 + 0.03
                r2.inputs["To Min"].default_value = 1.0
                r2.inputs["To Max"].default_value = 0.0
                nt.links.new(at.outputs["Fac"], r1.inputs["Value"])
                nt.links.new(at.outputs["Fac"], r2.inputs["Value"])
                mu = nt.nodes.new("ShaderNodeMath")
                mu.operation = "MULTIPLY"
                nt.links.new(r1.outputs[0], mu.inputs[0])
                nt.links.new(r2.outputs[0], mu.inputs[1])
                parts.append(mu.outputs[0])
            nt.links.new(parts[0], band.inputs[0])
            nt.links.new(parts[1], band.inputs[1])
            rough = nt.nodes.new("ShaderNodeMapRange")
            rough.inputs["From Min"].default_value = 0.3
            rough.inputs["From Max"].default_value = 0.6
            rough.inputs["To Min"].default_value = 0.35
            rough.inputs["To Max"].default_value = 0.85
            nt.links.new(nz.outputs["Fac"], rough.inputs["Value"])
            f = nt.nodes.new("ShaderNodeMath")
            f.operation = "MULTIPLY"
            nt.links.new(band.outputs[0], f.inputs[0])
            nt.links.new(rough.outputs[0], f.inputs[1])
            mx = nt.nodes.new("ShaderNodeMix")
            mx.data_type = "RGBA"
            nt.links.new(f.outputs[0], mx.inputs["Factor"])
            if src:
                nt.links.new(src, mx.inputs[6])
            mx.inputs[7].default_value = (*colour, 1)
            nt.links.new(mx.outputs[2], bb.inputs["Base Color"])


AUS = HOM / "australopith/australopith.glb"
poses = {}
for clip, frames in {
    "walk": [3, 11, 19, 27],
    "idle": [10, 40],
    "gather": [30, 80],
    "crouch": [20],
    "pickup": [10],
    "attack": [12],
    "throw": [6],
    "run": [5, 15],
}.items():
    for f in frames:
        c = posed_copy(AUS, clip, f, f"aus_{clip}_{f}")
        team_paint(c, TEAM["ochre"])
        poses[(clip, f)] = c
rival = posed_copy(AUS, "walk", 7, "aus_rival")
team_paint(rival, TEAM["clay"])
rival_run = posed_copy(AUS, "run", 9, "aus_rival_run")
team_paint(rival_run, TEAM["clay"])

units = []


def unit(clip, f, x, y, face, scale=1.0, coll=None):
    c = coll or poses[(clip, f)]
    e = place(c, x, y, rotz=face, scale=scale * rng.uniform(0.92, 1.06))
    units.append(e)
    return e


# Foragers at the knapping floor and the cache, a gathering line to the tubers, a few resting under the fig
for k in range(4):
    a = k * 1.57 + 0.3
    unit(
        "gather",
        rng.choice([30, 80]),
        KNAP.x + 1.6 * math.cos(a),
        KNAP.y + 1.6 * math.sin(a),
        a + math.pi,
    )
unit("crouch", 20, CACHE.x + 1.0, CACHE.y + 1.6, 3.6)
unit("pickup", 10, CACHE.x - 1.6, CACHE.y - 1.4, 0.8)
for k in range(3):
    unit(
        "idle",
        rng.choice([10, 40]),
        CAMP.x + rng.uniform(-5, 5),
        CAMP.y + rng.uniform(-5, 5),
        rng.uniform(0, 6.28),
    )
unit("crouch", 20, CAMP.x + 3, CAMP.y - 3.5, 2.0)
# a file of foragers walking back from the carcass with the RTS move order
for k in range(5):
    t = k / 4
    x = CARC.x + (CACHE.x - CARC.x) * (0.25 + 0.6 * t) + rng.uniform(-1.2, 1.2)
    y = CARC.y + (CACHE.y - CARC.y) * (0.25 + 0.6 * t)
    unit(
        "walk",
        [3, 11, 19, 27][k % 4],
        x,
        y,
        math.atan2(CACHE.y - CARC.y, CACHE.x - CARC.x) - math.pi / 2,
    )
for k in range(3):  # butchering at the carcass
    unit(
        "gather",
        30 if k % 2 else 80,
        CARC.x + rng.uniform(-1.8, 1.8),
        CARC.y + rng.uniform(-1.2, 1.2),
        rng.uniform(0, 6.28),
    )
# Bruisers + a thrower facing two hyenas that came for the carcass
unit("attack", 12, CARC.x + 5.5, CARC.y - 2.0, -0.6)
unit("throw", 6, CARC.x + 3.5, CARC.y - 4.0, -0.9)
unit("run", 5, CARC.x + 1.5, CARC.y - 4.5, -0.4)
# rival scouts (white clay) at the edge of the camp, north
for k in range(2):
    unit(
        None,
        None,
        CAMP.x - 26 + 2.2 * k,
        CAMP.y + 30 + 1.4 * k,
        math.pi + 0.3,
        coll=rival if k else rival_run,
    )
print("hominins", len(units))

# ------------------------------------------------------------------ animals
gaz = posed_copy(SF / "animals/b2c70a0821ef4c6ca0c096e33bc97593.glb", "Animation", 5, "gazelle")
for o in gaz.objects:
    mn, mx = bounds([o])
hy = stash(proto(SF / "animals/f74b47c36a10443388905407958db591.glb", "hyena", length=1.45))[0]
croc = stash(proto(SF / "animals/52aefd22731d41829423a184c10244f2.glb", "croc", length=4.2))[0]
tint_materials(
    [croc], (0.36, 0.36, 0.28), sat=0.6
)  # sun-dried Nile croc, not the scan's pale yellow


def norm_coll(c, length):
    mn, mx = bounds(list(c.objects))
    s = length / max(mx.x - mn.x, mx.y - mn.y)
    for o in c.objects:
        o.data.transform(
            Matrix.Scale(s, 4) @ Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
        )


norm_coll(gaz, 1.25)
for k in range(7):  # gazelle herd grazing between camp and shore, north-east
    place(
        gaz,
        CAMP.x + 25 + rng.uniform(-5, 5),
        CAMP.y - 3 + rng.uniform(-4, 4),
        scale=rng.uniform(0.9, 1.05),
    )
place(hy, CARC.x + 9.0, CARC.y - 3.5, rotz=2.3)
place(hy, CARC.x + 10.5, CARC.y - 1.0, rotz=2.8)
# crocodile basking on the mud at the waterline east of camp
for x_ in np.arange(CAMP.x, CAMP.x + 60, 0.5):
    if sample(SHORE, x_, CAMP.y - 12) < 1.2 and sample(WATER, x_, CAMP.y - 12) == 0:
        place(croc, x_, CAMP.y - 12, rotz=1.9, z_off=-0.05)
        break

# ------------------------------------------------------------------ selection FX + move marker
sel = bpy.data.materials.new("sel")
sel.use_nodes = True
sb = bsdf(sel)
sb.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1)
sb.inputs["Emission Color"].default_value = (0.55, 1.0, 0.45, 1)
sb.inputs["Emission Strength"].default_value = 1.6
sel.surface_render_method = "BLENDED" if hasattr(sel, "surface_render_method") else None
for e in units[9:14]:  # the selected walking file
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.62,
        minor_radius=0.035,
        location=(e.location.x, e.location.y, e.location.z + 0.04),
    )
    t = bpy.context.active_object
    t.scale.z = 0.3
    t.data.materials.append(sel)

# ------------------------------------------------------------------ camera: default RTS view
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.lens = 35.0
cam.data.clip_start = 1.0
cam.data.clip_end = 1500
PITCH, DIST = 50.0, 43.0
focus = Vector((CAMP.x + 10.0, CAMP.y - 9.0, ground(CAMP.x, CAMP.y)))
yaw = math.radians(-28)  # looking a little east of north: lake on the right third
back = Vector((math.sin(yaw), -math.cos(yaw), 0)) * DIST * math.cos(math.radians(PITCH))
cam.location = focus + back + Vector((0, 0, DIST * math.sin(math.radians(PITCH))))
cam.rotation_euler = (focus - cam.location).to_track_quat("-Z", "Y").to_euler()

# ------------------------------------------------------------------ haze (depth fog, like Godot's fog)
vl = sc.view_layers[0]
vl.use_pass_mist = True
world.mist_settings.start = 60.0
world.mist_settings.depth = 260.0
world.mist_settings.falloff = "LINEAR"
sc.use_nodes = True
ct = sc.node_tree
for n in list(ct.nodes):
    ct.nodes.remove(n)
rl = ct.nodes.new("CompositorNodeRLayers")
mix = ct.nodes.new("CompositorNodeMixRGB")
mix.blend_type = "MIX"
mixf = ct.nodes.new("CompositorNodeMath")
mixf.operation = "MULTIPLY"
mixf.inputs[1].default_value = 0.35
ct.links.new(rl.outputs["Mist"], mixf.inputs[0])
ct.links.new(mixf.outputs[0], mix.inputs[0])
ct.links.new(rl.outputs["Image"], mix.inputs[1])
mix.inputs[2].default_value = (0.78, 0.70, 0.58, 1)
glare = ct.nodes.new("CompositorNodeGlare")
try:
    glare.glare_type = "BLOOM"
except TypeError:
    glare.glare_type = "FOG_GLOW"
glare.threshold = 1.2
ct.links.new(mix.outputs[0], glare.inputs[0])
comp = ct.nodes.new("CompositorNodeComposite")
ct.links.new(glare.outputs[0], comp.inputs[0])

sc.render.image_settings.file_format = "JPEG"
sc.render.image_settings.quality = 92
OUT.parent.mkdir(parents=True, exist_ok=True)
sc.render.filepath = str(OUT)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "assets/_raw/build/look_target.blend"))
import time  # noqa: E402

t0 = time.time()
bpy.ops.render.render(write_still=True)
print("RENDER", OUT, round(time.time() - t0, 1), "s")
