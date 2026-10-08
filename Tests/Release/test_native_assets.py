from pathlib import Path
import json
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
ATLAS=ROOT/'Maps'/'WorldAtlas'
d=json.loads((ATLAS/'data'/'overlays.json').read_text(encoding='utf-8'))
assert len(d['flights'])==67
assert len(d['flightRoutes'])==288
assert len(d['docks'])==17
assert len(d['transportLines'])==22
assert len(d['worldTransportRoutes'])==9
assert len(d['entrances'])==6
assert len(d['services'])==451
assert len(d['pois'])==267
assert (ATLAS/'data'/'transport-routes-world.json').exists()
assert d['style']['boat']=='#7fb5e6' and d['style']['boatDash']=='6 6'
assert d['style']['zeppelin']=='#e08a6a' and d['style']['zeppelinDash']=='2 7'
for n in ['flight.png','svc-graveyard.png','svc-inn.png','svc-dungeon.png','svc-raid.png','svc-repair.png','svc-stable.png','svc-bank.png','svc-auction.png','svc-mailbox.png','poi-145.png']:
    assert (ATLAS/'icons'/n).exists(),n
assert (ROOT/'Maps/icons/vignettekill.png').exists(), 'death game asset missing'
classes=sorted((ATLAS/'class-icons').glob('classicon_*.jpg')); assert len(classes)==9,len(classes)
tiles=list((ATLAS/'tiles').rglob('*.webp')); assert len(tiles)==205,len(tiles)
print('ATLAS_FLIGHTS=67')
print('ATLAS_FLIGHT_ROUTES=288')
print('ATLAS_TRANSPORT_SEGMENTS_RAW=22')
print('ATLAS_WORLD_TRANSPORT_ROUTES=9')
print('ATLAS_SERVICES=451')
print('ATLAS_CLASS_ICONS=9')
print('ATLAS_REFERENCE_TILES=205')
print('ATLAS_NATIVE_ASSETS=PASS')
