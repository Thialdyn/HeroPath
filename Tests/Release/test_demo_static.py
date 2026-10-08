from pathlib import Path
import re, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]
html=(ROOT/'Demo/index.html').read_text(encoding='utf-8')
assert '../Maps/tiles/' in html
assert 'worldToMap' in html and 'mapToWorld' in html
assert 'Suivre' in html and 'Recentrer' in html
assert 'Tout afficher' in html and 'setRevealAll' in html
assert 'settingsToggle' in html and 'settingsPanel' in html and 'Calibration visuelle' in html and 'VISUAL_SETTINGS' in html
assert 'stableInterpolatingPath' in html and 'softenPoints' not in html and 'roundedPath' not in html
assert ('Frontière technique '+'réellement observée') not in html
assert 'z${zoom.toFixed(2)}' not in html
assert '<span class="map-source-note">' not in html
assert ('forever'+'changes.pro') not in html.lower()
assert 'visualLimit=revealAll?sc.duration:replayT' in html
assert '<option value="1" selected>1×</option>' in html
assert '<option value="satellite">Satellite</option>' in html
assert '<option value="worldmap">Carte du jeu</option>' in html
assert 'Terrain détaillé (local)' not in html
assert ('Forever'+'Changes - Carte M') not in html
assert "layerName='satellite'" in html
assert "ATLAS_WORLD.sea||'#122432'" in html
assert 'ATLAS_DATA' in html and 'ATLAS_WORLD' in html
assert html.count('worldTransportRoutes')<=2  # metadata/count only; route geometry stays in overlays.json
assert 'Maîtres de vol' in html and 'Cimetières' in html and 'Auberges' in html and 'Instances' in html and 'Ports / zeppelins' in html and 'Trajets en vol' in html and 'Trajets de mort' in html
assert '>Routes aériennes<' not in html and '>Bateaux / zeppelins<' not in html and '>Villes / POI<' not in html and '>Services<' not in html
assert "const nativeLayerState={flights:true,graveyard:true,inn:true,instance:true,transport:true}" in html
assert 'ly-transport' in html
assert "let showJourneyFlightTrail=true" in html
assert "if(sg.kind==='flight'&&!showJourneyFlightTrail)continue" in html
assert "if(sg.kind==='ghost'&&!showJourneyDeathTrail)continue" in html
assert "im.classList.add(`faction-${o.faction==='alliance'?'alliance':o.faction==='horde'?'horde':'neutral'}`)" in html
assert 'svc-graveyard-${f}.png' in html
for f in ('svc-graveyard-alliance.png','svc-graveyard-horde.png','svc-graveyard-neutral.png'):
    assert (ROOT/'Maps/WorldAtlas/icons'/f).exists()
assert 'border-radius:50%' not in html
assert '<div id="tileLayer"></div>' in html
assert "tileLayer.style.transform=`translate3d(" in html
assert "im.style.width=(TILE*f+overlap)+'px'" in html and "im.style.height=(TILE*f+overlap)+'px'" in html
assert 'requestAnimationFrame(()=>{frameRenderPending=false;render()})' in html
assert 'MAX_TILE_CACHE=128' in html
assert "nativeLines.innerHTML=''" in html
assert '../Maps/icons/classes-round/' in html and 'classicon_' in html
assert 'hero-icon-frame' not in html and 'hero-class-fallback' not in html
assert 'clip-path:circle(50% at 50% 50%)' in html
assert '../Maps/icons/death-location-user.png' in html and '../Maps/icons/ghost-user.png' in html
assert 'hero-death-marker' in html
assert 'Corpse_gravestone_20x20.png' not in html
assert 'corpse-gravestone-wow-fallback.svg' not in html
assert 'instance-anchor' in html
assert '.native-pin.instance{width:28px;height:28px}' in html
assert 'instanceActiveSpin' not in html and 'instance-anchor-ring' not in html and 'instance-elapsed-text' in html and 'instanceGlow' in html and 'instanceGlow' in html
assert 'im.draggable=false' in html and "map.addEventListener('dragstart',e=>e.preventDefault())" in html
assert not (ROOT/'demo-standalone.html').exists()
scripts=re.findall(r'<script>(.*?)</script>',html,re.S)
assert len(scripts)==1
with tempfile.NamedTemporaryFile('w',suffix='.js',delete=False,encoding='utf-8') as f:
    f.write(scripts[0]); name=f.name
p=subprocess.run(['node','--check',name],capture_output=True,text=True)
assert p.returncode==0,p.stderr
site=(ROOT/'Web/replay-renderer.js').read_text(encoding='utf-8')
assert 'e.insideInstance||e.positionKnown===false' in site
assert 'heroDeathMarker' in site
assert 'death-location-user.png' in site and 'ghost-user.png' in site
assert 'heroInstanceIsRemote' in site
assert 'hero-dead-state' in site
assert 'event-diamond' not in site
print('DEMO_JS_SYNTAX=PASS')
print('SITE_COHERENCE_STATIC=PASS')
print('DEMO_STATIC_CONTRACT=PASS')
