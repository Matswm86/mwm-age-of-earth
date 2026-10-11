"""Download Commons files by title into dl/commons, saving licence metadata JSON next to each."""

import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
import commons

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
titles = sys.argv[2:]
if len(titles) == 1 and titles[0].endswith(".txt"):
    titles = [
        ln.strip()
        for ln in Path(titles[0]).read_text().splitlines()
        if ln.strip() and not ln.startswith("#")
    ]
for title in titles:
    fn0 = re.sub(r"[^A-Za-z0-9._-]+", "_", title[5:])
    if os.path.exists(os.path.join(out, fn0)) and os.path.exists(os.path.join(out, fn0) + ".json"):
        print("have", fn0, flush=True)
        continue
    d = commons.get(
        {
            "action": "query",
            "format": "json",
            "titles": title,
            "prop": "imageinfo",
            "iiprop": "url|size|mime|extmetadata",
        }
    )
    p = list(d["query"]["pages"].values())[0]
    if "imageinfo" not in p:
        print("MISSING", title)
        continue
    ii = p["imageinfo"][0]
    em = ii.get("extmetadata", {})
    meta = {
        "title": title,
        "url": ii["url"],
        "page": ii["descriptionurl"],
        "license": em.get("LicenseShortName", {}).get("value"),
        "license_url": em.get("LicenseUrl", {}).get("value"),
        "artist": re.sub("<[^>]+>", "", em.get("Artist", {}).get("value", "")).strip(),
        "credit": re.sub("<[^>]+>", "", em.get("Credit", {}).get("value", "")).strip(),
        "attribution": re.sub("<[^>]+>", "", em.get("Attribution", {}).get("value", "")).strip(),
        "description": re.sub(
            "<[^>]+>", "", em.get("ImageDescription", {}).get("value", "")
        ).strip()[:600],
        "fetched": time.strftime("%Y-%m-%d"),
    }
    fn = re.sub(r"[^A-Za-z0-9._-]+", "_", title[5:])
    dest = os.path.join(out, fn)
    if not os.path.exists(dest):
        req = urllib.request.Request(ii["url"], headers={"User-Agent": commons.UA})
        ok = False
        for k in range(10):
            try:
                time.sleep(3)
                with urllib.request.urlopen(req, timeout=120) as r:
                    data = r.read()
                Path(dest).write_bytes(data)
                ok = True
                break
            except Exception as e:
                print("retry", k, e, flush=True)
                time.sleep(60 * (k + 1))
        if not ok:
            print("FAILED", fn, flush=True)
            continue
    Path(dest + ".json").write_text(json.dumps(meta, indent=1, ensure_ascii=False))
    print(meta["license"], "|", meta["artist"][:50], "|", fn, flush=True)
