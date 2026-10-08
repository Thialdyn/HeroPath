from pathlib import Path
import json,math
ROOT=Path(__file__).resolve().parents[2]
r=json.loads((ROOT/'Tests/Fixtures/route-example.json').read_text(encoding='utf-8'))
H=1600/3

def px(p):
    # mapID 0 exact formula from supplied world bundle
    lat=-(32-p['x']/H-18)*4
    lng=(32-p['y']/H+26)*4
    return lng*128,-lat*128

pts=r['points']
assert len(pts)>=40
assert all(p['mapID']==0 for p in pts)
assert all(not p.get('breakBefore',False) for p in pts)
assert pts[0]['zone']=='Forêt d’Elwynn' and pts[-1]['zone']=='Marche de l’Ouest'
assert any(p.get('kind')=='border' for p in pts)
# Monotonic timeline, including the protected wait at Heather.
assert all(pts[i]['t']<=pts[i+1]['t'] for i in range(len(pts)-1))
holds=[(a,b) for a,b in zip(pts,pts[1:]) if abs(a['x']-b['x'])<1e-6 and abs(a['y']-b['y'])<1e-6 and b['t']>a['t']]
assert holds and max(b['t']-a['t'] for a,b in holds)>=19.9

# No suspicious visual jump on the hand-traced road geometry.
max_seg=0
for a,b in zip(pts,pts[1:]):
    ax,ay=px(a); bx,by=px(b)
    max_seg=max(max_seg,math.hypot(bx-ax,by-ay))
assert max_seg < 125, max_seg

# Every z7 route tile and its immediate neighbours are present in the supplied local map.
missing=[]
for p in pts:
    x,y=px(p); tx,ty=int(x//512),int(y//512)
    for yy in range(ty-1,ty+2):
      for xx in range(tx-1,tx+2):
        f=ROOT/'Maps/tiles/world/7'/str(xx)/f'{yy}.webp'
        if not f.exists(): missing.append(str(f.relative_to(ROOT)))
assert not missing, missing[:10]

# Simulate initial demo viewport tile requests at common desktop sizes on both layers.
def requested(vieww,viewh,layer,native_max,minz):
    xy=[px(p) for p in pts]
    minx=min(x for x,y in xy); maxx=max(x for x,y in xy); miny=min(y for x,y in xy); maxy=max(y for x,y in xy)
    cx=(minx+maxx)/2; cy=(miny+maxy)/2
    sx=(vieww*.78)/max(1,maxx-minx); sy=(viewh*.72)/max(1,maxy-miny)
    zoom=max(6 if layer=='world' else minz,min(9,7+math.log2(min(sx,sy))))
    nz=min(math.floor(zoom),native_max); f=2**(7-nz); vs=2**(zoom-7)
    left=cx-vieww/(2*vs); right=cx+vieww/(2*vs); top=cy-viewh/(2*vs); bottom=cy+viewh/(2*vs)
    xmin=math.floor(left/(512*f))-1; xmax=math.floor(right/(512*f))+1; ymin=math.floor(top/(512*f))-1; ymax=math.floor(bottom/(512*f))+1
    return zoom,nz,[(x,y) for y in range(ymin,ymax+1) for x in range(xmin,xmax+1)]
for view in [(1366,768),(1440,900),(1920,1080)]:
  for layer,nmax,minz in [('world',7,3),('worldmap',5,2)]:
    zoom,nz,tiles=requested(*view,layer,nmax,minz)
    miss=[]
    for x,y in tiles:
      f=ROOT/'Maps/tiles'/layer/str(nz)/str(x)/f'{y}.webp'
      if not f.exists(): miss.append((x,y))
    assert not miss,(view,layer,zoom,nz,miss[:10])

print('ROUTE_POINTS',len(pts))
print('ROUTE_DURATION_SECONDS',r['duration'])
print('MAX_SEGMENT_Z7_PIXELS',round(max_seg,3))
print('ROUTE_Z7_NEIGHBOURHOOD_TILES=PASS')
print('DESKTOP_TILE_COVERAGE=PASS')
print('REALISTIC_ROUTE_TEST=PASS')
