from pathlib import Path
import re,json
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
for f in ['zeppelin-user.png','ghost-user.png','death-location-user.png']:
    p=ROOT/'Maps/icons'/f
    assert p.exists(),f
    im=Image.open(p); assert im.mode=='RGBA' and im.size==(192,192)
    assert im.getchannel('A').getextrema()[0]==0
html=(ROOT/'Demo/index.html').read_text(encoding='utf-8')
assert "GHOST_ICON='../Maps/icons/ghost-user.png'" in html
assert "ZEPPELIN_ICON='../Maps/icons/zeppelin-user.png'" in html
assert "DEATH_ICON='../Maps/icons/death-location-user.png'" in html
assert "key=flight?'heroFlightScale':st.mode===2?'heroSwimScale':st.mode===1?'heroMountedScale':'heroGroundScale'" in html
assert 'heroGhostScale' in html and 'heroDeadScale' in html and 'heroFlightBadgeScale' in html
assert '16.5*ts' in html
assert 'stableInterpolatingPath' in html and 'C ${f(c1x)}' in html
assert "if(!instances.has(key))instances.set(key" in html
assert "o.kind==='zeppelin'?ZEPPELIN_ICON" in html

# Approved current visual defaults.
expected_defaults={
    'heroGroundScale':1.3,'heroMountedScale':1.3,'heroSwimScale':1.3,'heroFlightScale':1.3,'heroFlightBadgeScale':1.15,
    'heroGhostScale':1.3,'heroDeadScale':1.3,'deathHistoryScale':1.3,
    'dungeonIconScale':1.0,'dungeonTimerScale':1.0,'raidIconScale':1.0,'raidTimerScale':1.0,
    'bgIconScale':1.0,'bgTimerScale':1.0,'arenaIconScale':1.0,'arenaTimerScale':1.0,
    'transportIconScale':1.0,'transportTimerScale':1.0,'poiFlightScale':1.15,'poiGraveyardScale':1.0,
    'poiInnScale':1.15,'poiInstanceScale':1.2,'poiBoatScale':1.2,'poiZeppelinScale':1.2,
    'groundWidth':1.0,'mountedWidth':1.0,'mountedUnderlayWidth':1.0,'swimWidth':1.0,'flightWidth':1.0,'ghostWidth':1.0,
    'groundHaloWidth':1.0,'mountedHaloWidth':1.0,'swimHaloWidth':1.0,'flightHaloWidth':1.0,'ghostHaloWidth':1.0,
    'trackPointScale':2.0,'legendTextScale':1.3,'legendIconScale':1.75,
}
for key,val in expected_defaults.items():
    mdef=re.search(rf"key:'{re.escape(key)}'.*?def:([0-9.]+)",html)
    assert mdef and abs(float(mdef.group(1))-val)<1e-9,(key,mdef.group(1) if mdef else None,val)
assert '{showTrackPoints:false,showCoordinates:true}' in html
assert "el.dataset.layer==='transport'&&z<" not in html
import hashlib
assert hashlib.sha256((ROOT/'Maps/icons/death-location-user.png').read_bytes()).hexdigest()=='a29224dfcd02edaf016adc4df2f34c09aa1f81731121834bcbdf67db7ac29caa'

m=re.search(r'const ATLAS_DATA=(.*?);\n\(\(\)=>',html,re.S); assert m
fc=json.loads(m.group(1)); assert len(fc.get('docks',[]))==15
assert sum(1 for x in fc['docks'] if x.get('kind')=='zeppelin')==3
print('VISUAL_STATIC=PASS')
