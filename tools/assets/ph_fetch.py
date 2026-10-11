"""Fetch a Poly Haven model (glTF + its textures) or texture set at a given resolution (CC0).

usage: python3 ph_fetch.py hdri <asset_id> <res> <out_root>
       python3 ph_fetch.py model <asset_id> <res> <out_root>     -> <out_root>/<asset_id>_<res>/<asset_id>_<res>.gltf
       python3 ph_fetch.py tex <asset_id> <res> <out_root> [maps]  -> <out_root>/<asset_id>_<res>/*.png
"""

import json
import sys
import urllib.request
from pathlib import Path

UA = {"User-Agent": "mwm-age-of-earth-asset-fetch"}


def get_json(url):
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60))


def dl(url, dst: Path):
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and dst.stat().st_size > 0:
        return
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r:
        dst.write_bytes(r.read())


def model(aid, res, root):
    files = get_json(f"https://api.polyhaven.com/files/{aid}")
    g = files["gltf"][res]["gltf"]
    out = Path(root) / f"{aid}_{res}"
    dl(g["url"], out / Path(g["url"]).name)
    for rel, inc in g.get("include", {}).items():
        dl(inc["url"], out / rel)
    print(out / Path(g["url"]).name)


def tex(aid, res, root, maps):
    files = get_json(f"https://api.polyhaven.com/files/{aid}")
    out = Path(root) / f"{aid}_{res}"
    for m in maps:
        if m not in files:
            print("missing", m)
            continue
        f = files[m][res]
        f = f.get("png") or f.get("exr") or f.get("jpg")
        dl(f["url"], out / Path(f["url"]).name)
        print(out / Path(f["url"]).name)


def hdri(aid, res, root):
    files = get_json(f"https://api.polyhaven.com/files/{aid}")
    f = files["hdri"][res]["hdr"]
    dst = Path(root) / Path(f["url"]).name
    dl(f["url"], dst)
    print(dst)


if __name__ == "__main__":
    kind, aid, res, root = sys.argv[1:5]
    if kind == "hdri":
        hdri(aid, res, root)
    elif kind == "model":
        model(aid, res, root)
    else:
        maps = (
            sys.argv[5].split(",")
            if len(sys.argv) > 5
            else ["Diffuse", "nor_gl", "arm", "Displacement", "AO", "Rough"]
        )
        tex(aid, res, root, maps)
