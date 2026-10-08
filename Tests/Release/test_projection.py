from pathlib import Path
import json, math
ROOT=Path(__file__).resolve().parents[2]
route=json.loads((ROOT/'Tests/Fixtures/route-example.json').read_text(encoding='utf-8'))
H=1600/3
OFF={0:(26,-18),1:(-19,-9)}

def world_to_map(mid,x,y):
    ox,oy=OFF[mid]
    return (-(32-x/H+oy)*4, (32-y/H+ox)*4)
def map_to_world(mid,lat,lng):
    ox,oy=OFF[mid]
    return ((32-(-lat/4-oy))*H,(32-(lng/4-ox))*H)

def point_in_ring(x,y,ring):
    inside=False
    j=len(ring)-1
    for i in range(len(ring)):
        xi,yi=ring[i]; xj,yj=ring[j]
        if ((yi>y)!=(yj>y)) and (x < (xj-xi)*(y-yi)/(yj-yi if yj!=yi else 1e-12)+xi): inside=not inside
        j=i
    return inside

def subzone_at(x,y,name):
    subs=json.loads((ROOT/'Maps/data/subzones.json').read_text(encoding='utf-8'))
    for z in subs:
        if z.get('name')!=name or z.get('mapId')!=0: continue
        if any(point_in_ring(x,y,r) for r in z.get('rings',[])): return z
    return None

max_rt=0.0
for p in route['points']:
    lat,lng=world_to_map(p['mapID'],p['x'],p['y'])
    x,y=map_to_world(p['mapID'],lat,lng)
    max_rt=max(max_rt,math.hypot(x-p['x'],y-p['y']))
assert max_rt < 1e-8, max_rt

# Exact supplied POIs used by the realistic test.
data=json.loads((ROOT/'Maps/data/0.json').read_text(encoding='utf-8'))
by_name={row[1]:row for row in data['npc'] if len(row)>=6}
for name,xy in {
    'Innkeeper Farley':(-9463,16),
    'Gryan Stoutmantle':(-10509,1045),
    'Thor':(-10628,1037),
    'Innkeeper Heather':(-10653,1167),
}.items():
    row=by_name[name]
    assert (row[4],row[5])==xy,(name,row[4:6],xy)

assert subzone_at(-9463,16,'Goldshire')['zone']==1429
assert subzone_at(-10653,1167,'Sentinel Hill')['zone']==1436
assert subzone_at(-11017,1517,'Moonbrook')['zone']==1436

print(f'ROUNDTRIP_MAX_WORLD_ERROR={max_rt:.12g}')
print('REAL_POI_ANCHORS=4')
print('SUBZONE_CROSSING=Goldshire(1429)->Sentinel Hill(1436)->Moonbrook(1436)')
print('PROJECTION_TEST=PASS')
