from pathlib import Path
import json, math
ROOT=Path(__file__).resolve().parents[2]
D=json.loads((ROOT/'Tests/Fixtures/scenarios.json').read_text(encoding='utf-8'))
assert len(D['scenarios'])>=19
master=D['scenarios'][0]
pex=D['scenarios'][1]
assert master['name']=='Tous les états' and master['duration']>=900
assert pex['name'].startswith('Progression 1 → 10') and pex['duration']>=1800
assert {'ground','ghost','flight'} <= {s['kind'] for s in master['segments']}
assert {0,1,2,3,4} <= {s.get('mode') for s in master['segments']}
master_kinds={e['kind'] for e in master['events']}
for k in ['death','respawn','resurrect','instance','hearth','portal','summon','boat','zeppelin','gap','reload','tram']:
    assert k in master_kinds,k
assert any(e.get('instanceType')=='pvp' for e in master['events'])
# Master outdoor death is exactly the last live aerial-route point and corpse run returns there.
fl=next(s for s in master['segments'] if s['kind']=='flight')
body=fl['points'][-1]
death=next(e for e in master['events'] if e['kind']=='death' and not e.get('insideInstance'))
ghost=next(s for s in master['segments'] if s['kind']=='ghost')['points'][-1]
resume=next(s for s in master['segments'] if s['name']=='vers instance')['points'][0]
for q in [death,ghost,resume]:
    assert (q['x'],q['y'])==(body['x'],body['y'])
# Leveling death continuity is exact too.
live=next(s for s in pex['segments'] if s['name']=='Niveau 7 - Eastvale')['points'][-1]
pdeath=next(e for e in pex['events'] if e['kind']=='death')
pghost=next(s for s in pex['segments'] if s['kind']=='ghost')['points'][-1]
presume=next(s for s in pex['segments'] if s['name']=='Niveau 8 - retour Goldshire')['points'][0]
for q in [pdeath,pghost,presume]: assert (q['x'],q['y'])==(live['x'],live['y'])
assert any('Niv. 10' in s['label'] for s in pex['segments'])
# Native/reference corpus is preserved.
over=json.loads((ROOT/'Maps/WorldAtlas/data/overlays.json').read_text(encoding='utf-8'))
assert len(over['worldTransportRoutes'])==9
assert sum(r['kind']=='boat' for r in over['worldTransportRoutes'])==6
assert sum(r['kind']=='zeppelin' for r in over['worldTransportRoutes'])==3
assert len(over['flightRoutes'])==288 and len(over['services'])==451 and len(over['pois'])==267
assert len([p for p in over['services'] if p['kind']=='graveyard'])==89
# Raw duplicate sources remain available for the developer, while public renderer canonicalizes them.
raw_inst_names={}
for p in over['entrances']+[x for x in over['services'] if x['kind']=='instance']:
    raw_inst_names.setdefault((p['mapID'],p['name'].lower()),0); raw_inst_names[(p['mapID'],p['name'].lower())]+=1
assert sum(v>1 for v in raw_inst_names.values())==5
assert any(p.get('name')=='TEST for GM Client Only - Do Not Bug' for p in over['services'])
# Exact specialized native flight route is still preserved point-for-point.
fr_native=next(r for r in over['flightRoutes'] if r['mapID']==0 and r['from']==2 and r['to']==4)
fr_sc=next(s for s in D['scenarios'] if s['name'].startswith('Trajet aérien'))
fr_seg=next(s for s in fr_sc['segments'] if s['kind']=='flight')
assert len(fr_seg['points'])==len(fr_native['points'])
for got,raw in zip(fr_seg['points'],fr_native['points']):
    assert abs(got['x']-raw[0])<1e-9 and abs(got['y']-raw[1])<1e-9
# Advanced scenario: chained native flights, spirit rez, instance reset, reconnect, AFK.
adv=next(s for s in D['scenarios'] if s['name'].startswith('Cas particuliers'))
assert adv['name'].startswith('Cas particuliers')
assert len([s for s in adv['segments'] if s['kind']=='flight'])==2
assert any('Spirit Healer' in e['label'] for e in adv['events'])
inst=[e for e in adv['events'] if e['kind']=='instance']; assert len(inst)==2 and inst[1]['t']>inst[0]['t']+inst[0]['duration']
assert any(e['kind']=='gap' for e in adv['events']) and any(e['kind']=='reload' for e in adv['events'])
assert any('AFK' in s['label'] for s in adv['segments'])
print('DEMO_SCENARIOS='+str(len(D['scenarios'])))
print('MASTER_ALL_STATES=PASS')
print('DEATH_CONTINUITY=PASS')
print('RAW_REFERENCE_CORPUS=PRESERVED')
print('ADVANCED_EDGE_CASES=PASS')
