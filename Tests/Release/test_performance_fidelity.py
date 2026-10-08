from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[2]
html=(ROOT/'Demo/index.html').read_text(encoding='utf-8')
data=json.loads((ROOT/'Maps/WorldAtlas/data/overlays.json').read_text(encoding='utf-8'))

# Preserve developer corpus while keeping the public surface narrow.
assert len(data.get('transportLines',[]))==22
assert len(data.get('worldTransportRoutes',[]))==9
assert len(data.get('pois',[]))==267
assert len(data.get('services',[]))==451
for label in ('Maîtres de vol','Cimetières','Auberges','Instances','Ports / zeppelins','Trajets en vol','Trajets de mort'):
    assert f'>{label}<' in html
for label in ('Routes aériennes','Bateaux / zeppelins','Villes / POI','Services'):
    assert f'>{label}<' not in html

# Fidelity: native assets are not wrapped in invented decoration.
assert 'hero-icon-frame' not in html
assert 'hero-class-fallback' not in html
assert 'clip-path:circle(50% at 50% 50%)' in html
assert 'instance-anchor-ring' not in html
assert 'instance-anchor-pulse' not in html
assert 'instanceActiveSpin' not in html
assert 'instanceActivePulse' not in html
assert html.count('filter:drop-shadow')>=4
assert '.instance-anchor-icon{image-rendering:auto;filter:drop-shadow' in html
assert '.native-pin.instance{width:28px;height:28px}' in html
for f in ('svc-graveyard-alliance.png','svc-graveyard-horde.png','svc-graveyard-neutral.png'):
    assert (ROOT/'Maps/WorldAtlas/icons'/f).exists()
assert "svc-graveyard-${f}.png" in html

# Loading / rendering architecture.
assert '<div id="tileLayer"></div>' in html
assert 'MAX_TILE_CACHE=128' in html
assert "tileWindowSignature=''" in html
assert 'translate3d(${r.width/2-cx*sc}px,${r.height/2-cy*sc}px,0) scale(${sc})' in html
assert 'contain:layout paint' not in html
assert 'will-change:transform,width,height' not in html
assert 'transform:translateZ(0)' not in html
assert 'backdrop-filter:blur' not in html
assert "im.decoding='async'" in html
assert "im.loading='eager'" in html


# Runtime payload is intentionally slim; full hidden data stays in overlays.json.
assert len(html.encode('utf-8')) < 190000
assert 'archiveCounts' in html
assert html.count('flightRoutes') < 10  # counts/metadata, not the full 288-route geometry corpus

# Local Satellite z6 fallback coverage: lower-resolution derivatives only, never invented geography.
fallback=list((ROOT/'Maps/WorldAtlas/fallback/azeroth/6').glob('*/*.webp'))
assert len(fallback)==330
assert sum(x.stat().st_size for x in fallback)==6274706
assert 'atlasFallbackTile(spec)' in html
assert "spec.slug==='azeroth'&&spec.z===6" in html

# Native layer visibility is not walked on every camera frame anymore.
native_transform=html.split('function updateNativeTransform(){',1)[1].split('}',1)[0]
assert 'updateNativeVisibility()' not in native_transform

print('PERFORMANCE_CORPUS_PRESERVED=PASS')
print('PERFORMANCE_WOW_ASSET_FIDELITY=PASS')
print('PERFORMANCE_ROUND_CLASS_ICON=PASS')
print('PERFORMANCE_INSTANCE_GLOW_ONLY=PASS')
print('PERFORMANCE_SINGLE_TILE_COMPOSITE_LAYER=PASS')
print('PERFORMANCE_TILE_CACHE_128=PASS')
print('PERFORMANCE_TILE_WINDOW_DEDUP=PASS')
print('PERFORMANCE_NO_BACKDROP_BLUR=PASS')
print('PERFORMANCE_RUNTIME_PAYLOAD_SLIM=PASS')
print('PERFORMANCE_LOCAL_FALLBACK_ZOOM6=PASS')
