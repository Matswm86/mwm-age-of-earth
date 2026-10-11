"""Search Wikimedia Commons audio files and print licence metadata. Usage: commons.py <query> [limit]"""

import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "AgeOfEarthAudioFetch/1.0 (https://github.com/Matswm86/mwm-age-of-earth; game asset download)"
API = "https://commons.wikimedia.org/w/api.php"


def get(params):
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for k in range(6):
        try:
            time.sleep(1.5)
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code != 429:
                raise
            time.sleep(15 * (k + 1))
    raise RuntimeError("rate limited")


def search(q, limit=40):
    d = get(
        {
            "action": "query",
            "format": "json",
            "generator": "search",
            "gsrsearch": f"{q} filetype:audio",
            "gsrnamespace": 6,
            "gsrlimit": limit,
            "prop": "imageinfo",
            "iiprop": "url|size|mime|extmetadata",
            "iiextmetadatafilter": "LicenseShortName|Artist|UsageTerms|ImageDescription",
        }
    )
    out = []
    for p in (d.get("query", {}).get("pages", {}) or {}).values():
        ii = p["imageinfo"][0]
        em = ii.get("extmetadata", {})
        lic = em.get("LicenseShortName", {}).get("value", "?")
        art = re.sub("<[^>]+>", "", em.get("Artist", {}).get("value", "?")).strip()
        desc = re.sub("<[^>]+>", "", em.get("ImageDescription", {}).get("value", ""))[:110].replace(
            "\n", " "
        )
        out.append(
            {
                "title": p["title"],
                "lic": lic,
                "artist": art,
                "url": ii["url"],
                "page": ii.get("descriptionurl"),
                "size": ii.get("size"),
                "dur": ii.get("duration"),
                "desc": desc,
            }
        )
    return out


if __name__ == "__main__":
    for r in search(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 40):
        ok = (
            "OK "
            if re.match(
                r"^(CC0|Public domain|PD|CC BY \d|CC-BY-\d|CC BY 4|CC BY 3|CC BY 2)", r["lic"]
            )
            and "SA" not in r["lic"]
            and "NC" not in r["lic"]
            else "-- "
        )
        print(
            ok,
            r["lic"][:22].ljust(22),
            str(r["dur"])[:6].ljust(6),
            r["title"][5:80],
            "|",
            r["artist"][:30],
            "|",
            r["desc"][:70],
        )


def wikitext(title):
    d = get(
        {
            "action": "query",
            "format": "json",
            "titles": title,
            "prop": "revisions",
            "rvprop": "content",
            "rvslots": "main",
        }
    )
    p = list(d["query"]["pages"].values())[0]
    return p["revisions"][0]["slots"]["main"]["*"]
