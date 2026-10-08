from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import urllib.request, urllib.error, time, os, sys

BASE = "https://assets.wowforevermap.com/20261005"
ROOT = Path(__file__).resolve().parent
TILE = 512
LOGICAL_MAX = 7
CELLS = (0, 0, 72, 47)  # left, top, right, bottom

LAYERS = {
    "world":    (3, 7),  # min zoom, max native zoom
    "worldmap": (2, 5),
}

ICONS = [
    "poi-majorcity.png","poi-town.png","dungeon.png","raid.png",
    "taxinode_alliance.png","taxinode_horde.png","taxinode_neutral.png",
    "questnormal.png","vignettekill.png","vignettekillelite.png",
    "Mobile-Herbalism.png","Mobile-Mining.png","Mobile-Fishing.png",
    "Mobile-TreasureIcon.png","mailbox.png",
    "skyborne-high-order-c60.png","skyborne-windshapers-c60.png"
]

def tile_range(z):
    left, top, right, bottom = CELLS
    f = 2 ** (LOGICAL_MAX - z)
    import math
    return (math.floor(left/f), math.ceil(right/f)-1,
            math.floor(top/f), math.ceil(bottom/f)-1)

jobs = []
for layer, (minz, maxz) in LAYERS.items():
    for z in range(minz, maxz + 1):
        xmin,xmax,ymin,ymax = tile_range(z)
        for x in range(xmin, xmax+1):
            for y in range(ymin, ymax+1):
                rel = f"tiles/{layer}/{z}/{x}/{y}.webp"
                jobs.append((f"{BASE}/{rel}", ROOT / rel))

for name in ICONS:
    jobs.append((f"{BASE}/icons/{name}", ROOT / "icons" / name))

# Useful POI datasets for the two outdoor continents. Missing files are harmless.
for map_id in (0,1):
    for suffix in (".json",".nodes.json",".mailboxes.json"):
        rel=f"pois/{map_id}{suffix}"
        jobs.append((f"{BASE}/{rel}", ROOT / "data" / Path(rel).name))
jobs.append((f"{BASE}/pois/counts.json", ROOT / "data" / "counts.json"))

total=len(jobs)
done=0
downloaded=0
skipped=0
missing=0
failed=0

def fetch(job):
    url,dest=job
    if dest.exists() and dest.stat().st_size > 0:
        return "skip", url, dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    req=urllib.request.Request(url, headers={"User-Agent":"Mozilla/5.0 WoWForeverMap-LocalMirror/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            data=r.read()
        dest.write_bytes(data)
        return "ok", url, dest
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return "404", url, dest
        return f"http{e.code}", url, dest
    except Exception as e:
        return "err", url, str(e)

print(f"{total} fichiers à vérifier/télécharger.")
print("Les fichiers déjà extraits du HAR sont conservés et ignorés.")

with ThreadPoolExecutor(max_workers=12) as ex:
    futures=[ex.submit(fetch,j) for j in jobs]
    for f in as_completed(futures):
        state,url,info=f.result()
        done+=1
        if state=="ok": downloaded+=1
        elif state=="skip": skipped+=1
        elif state=="404": missing+=1
        else:
            failed+=1
            print("ERREUR:", state, url, info)
        if done % 100 == 0 or done == total:
            print(f"{done}/{total} | téléchargés {downloaded} | déjà présents {skipped} | 404 {missing} | erreurs {failed}")

print("\nTerminé.")
print(f"Téléchargés : {downloaded}")
print(f"Déjà présents : {skipped}")
print(f"404 attendus/absents : {missing}")
print(f"Erreurs réseau : {failed}")
input("Entrée pour fermer...")
