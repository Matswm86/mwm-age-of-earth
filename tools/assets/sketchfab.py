"""Sketchfab search + licence check + download (token read from ~/.config/sketchfab/token, never printed).

Adapted from mwm-wayfarer tools/assets/sketchfab.py. Search is restricted to CC BY and CC0 (no NC, ND, SA,
Standard or Editorial). `info` re-reads the licence from the model API, which is the licence of record.

usage:
  python3 sketchfab.py search "acacia tree" [--max-faces 60000] [--count 24] [--anim]
  python3 sketchfab.py info <uid>
  python3 sketchfab.py get <uid> <out_dir>     # glb, plus <uid>.json with the API licence and author
"""

import json
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

API = "https://api.sketchfab.com/v3"
TOKEN = (Path.home() / ".config/sketchfab/token").read_text().strip()
OK_LICENCES = {"CC Attribution", "CC0 Public Domain", "Public Domain"}


def _get(url: str, auth: bool = False) -> dict:
    req = urllib.request.Request(url)
    if auth:
        req.add_header("Authorization", f"Token {TOKEN}")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def search(q: str, max_faces: int = 0, count: int = 24, anim: bool = False) -> None:
    results = []
    for lic_slug in ("by", "cc0"):  # one licence per call: repeated params are AND-ed by the API
        params = [
            ("type", "models"),
            ("q", q),
            ("downloadable", "true"),
            ("count", count),
            ("sort_by", "-likeCount"),
            ("license", lic_slug),
        ]
        if max_faces:
            params.append(("max_face_count", max_faces))
        if anim:
            params.append(("animated", "true"))
        results += _get(f"{API}/search?{urllib.parse.urlencode(params)}").get("results", [])
    for m in results:
        lic = (m.get("license") or {}).get("label", "?")
        print(
            f"{m['uid']}  f={m.get('faceCount')}  likes={m.get('likeCount')}  anim={m.get('animationCount')}  "
            f"lic={lic}  by={m['user']['username']}  | {m['name']}"
        )


def info(uid: str) -> dict:
    m = _get(f"{API}/models/{uid}")
    keep = {
        k: m.get(k)
        for k in (
            "name",
            "faceCount",
            "vertexCount",
            "animationCount",
            "isDownloadable",
            "viewerUrl",
        )
    }
    keep["license"] = (m.get("license") or {}).get("label")
    keep["author"] = m["user"]["username"]
    keep["author_name"] = m["user"].get("displayName")
    keep["ok"] = keep["license"] in OK_LICENCES
    print(json.dumps(keep, indent=1))
    print((m.get("description") or "")[:400])
    return keep


def get(uid: str, out: str) -> None:
    m = _get(f"{API}/models/{uid}")
    lic = (m.get("license") or {}).get("label")
    if lic not in OK_LICENCES:
        sys.exit(f"REFUSED {uid}: licence {lic!r} is not CC BY / CC0")
    out_dir = Path(out)
    out_dir.mkdir(parents=True, exist_ok=True)
    d = _get(f"{API}/models/{uid}/download", auth=True)
    if "glb" in d:
        url, name = d["glb"]["url"], f"{uid}.glb"
    else:
        url, name = d["gltf"]["url"], f"{uid}_gltf.zip"
    dst = out_dir / name
    urllib.request.urlretrieve(url, dst)
    if name.endswith(".zip"):
        with zipfile.ZipFile(dst) as z:
            z.extractall(out_dir / uid)
    (out_dir / f"{uid}.json").write_text(
        json.dumps(
            {
                "uid": uid,
                "name": m["name"],
                "author": m["user"]["username"],
                "author_name": m["user"].get("displayName"),
                "author_url": m["user"]["profileUrl"],
                "url": m["viewerUrl"],
                "license": lic,
                "faces": m.get("faceCount"),
                "animations": m.get("animationCount"),
            },
            indent=1,
        )
    )
    print(dst, dst.stat().st_size // 1024, "KB", lic)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "search":
        mf = int(sys.argv[sys.argv.index("--max-faces") + 1]) if "--max-faces" in sys.argv else 0
        n = int(sys.argv[sys.argv.index("--count") + 1]) if "--count" in sys.argv else 24
        search(sys.argv[2], mf, n, "--anim" in sys.argv)
    elif cmd == "info":
        info(sys.argv[2])
    elif cmd == "get":
        get(sys.argv[2], sys.argv[3])
