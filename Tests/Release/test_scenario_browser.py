from __future__ import annotations
from pathlib import Path
import json
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[2]
DEMO=ROOT/'Demo'/'index.html'
DATA=json.loads((ROOT/'Tests'/'Fixtures'/'scenarios.json').read_text(encoding='utf-8'))

def expect(c,m):
    if not c: raise AssertionError(m)
def set_time(page,t):
    page.eval_on_selector('#timeline',"(el,t)=>{el.value=String(t);el.dispatchEvent(new Event('input',{bubbles:true}))}",float(t))
    page.wait_for_timeout(20)
def state(page): return page.evaluate('window.__HEROPATH_DEBUG__.getState()')
def txt(page,s): return page.locator(s).inner_text().strip()
def trail(page): return page.evaluate('window.__HEROPATH_DEBUG__.visibleTrail()')
def events(page): return page.evaluate('window.__HEROPATH_DEBUG__.visibleEvents()')
def scenario(prefix): return next(s for s in DATA['scenarios'] if s['name'].startswith(prefix))
def event(sc,kind,contains=''):
    return next(e for e in sc['events'] if e['kind']==kind and contains in e.get('label',''))
def seg(sc,contains='',kind=None,mode=None):
    return next(s for s in sc['segments'] if contains in (s.get('label','')+' '+s.get('name','')) and (kind is None or s.get('kind')==kind) and (mode is None or s.get('mode')==mode))
def mid_event(e): return e['t'] + max(0.5,float(e.get('duration') or 2))/2
def mid_seg(s): return (s['points'][0]['t']+s['points'][-1]['t'])/2
def select_prefix(page,prefix):
    idx=page.evaluate("p=>window.__HEROPATH_DEBUG__.DATA.scenarios.findIndex(s=>s.name.startsWith(p))",prefix)
    expect(idx>=0,'missing scenario '+prefix)
    page.select_option('#scenario',str(idx)); page.wait_for_timeout(20)
    return idx

with sync_playwright() as pw:
    browser=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-dev-shm-usage','--allow-file-access-from-files'])
    page=browser.new_page(viewport={'width':1600,'height':900})
    page.route("https://**/*",lambda route: route.abort())
    errs=[]; page.on('pageerror',lambda e: errs.append(str(e)))
    page.set_content(DEMO.read_text(encoding='utf-8'),wait_until='load')
    expect(page.evaluate('window.__HEROPATH_DEBUG__.DATA.scenarios.length')>=19,'scenario count')

    opts=page.locator('#mapStyle option').all_text_contents()
    expect(opts==['Satellite','Carte du jeu'],f'map options {opts}')
    expect(state(page)['layerName']=='satellite','Satellite must be default')
    tc=page.evaluate('window.__HEROPATH_DEBUG__.tileCandidates(7,27,13)')
    expect(any('/Maps/tiles/world/7/8/4.webp' in x for x in tc),f'satellite z7 local fallback mapping {tc}')

    for mid,x,y in [(0,-9465.6,16.8),(0,-8832.8,478.6),(1,6341.4,557.7),(1,-1005.6,-3841.6)]:
        e=page.evaluate('''([m,x,y])=>{const A=window.__HEROPATH_DEBUG__,q=A.worldToMap(m,x,y),w=A.mapToWorld(m,q.lat,q.lng);return Math.hypot(w.x-x,w.y-y)}''',[mid,x,y])
        expect(e<1e-8,'projection')

    master=scenario('Tous les états')
    select_prefix(page,'Tous les états')
    set_time(page,0); expect(len(trail(page))==0,'future path visible at start')
    first_mount=seg(master,'Monture · Elwynn')
    set_time(page,mid_seg(first_mount)); tm=trail(page)
    expect(any(x['cls']=='ground' for x in tm),'walk trail missing')
    expect(any(x['cls']=='mounted' for x in tm),'mounted trail missing')
    expect(page.locator('path.mounted-underlay').count()>=1,'mounted leather underlay missing')
    expect(any('C' in x['d'] for x in tm),'smoothed cubic curves missing')

    # Death: active death uses the dedicated, readable death icon.
    de=event(master,'death','Mort extérieure')
    set_time(page,mid_event(de))
    expect(txt(page,'#kind')=='Mort','death state')
    dead=page.locator('.hero-marker.hero-dead-state .hero-current-death')
    expect(dead.count()==1,'active death marker invisible')
    expect('death-location-user.png' in (dead.get_attribute('href') or ''),'wrong active death icon')
    expect(float(dead.get_attribute('width'))>40,'active death marker too small')
    expect(events(page)['deathMarkers']==0,'corpse icon should not cover active death icon')

    ghost_seg=next(s for s in master['segments'] if s['kind']=='ghost')
    set_time(page,mid_seg(ghost_seg))
    g=page.locator('.hero-ghost-state .hero-ghost-icon')
    expect(g.count()==1 and float(g.get_attribute('width'))>=40,'ghost marker size/visibility')
    expect(events(page)['deathMarkers']==1,'historical corpse marker missing')
    expect(page.locator('path.ghost').count()>=1,'ghost trail missing')
    page.locator('#journey-death-trail').uncheck(); page.wait_for_timeout(5)
    expect(page.locator('path.ghost').count()==0,'death trail toggle')
    expect(page.locator('.hero-ghost-state').count()==1,'death trail toggle hid ghost player')
    page.locator('#journey-death-trail').check(); page.wait_for_timeout(5)

    # Flight badge stays visible if trail hidden.
    fseg=next(s for s in master['segments'] if s['kind']=='flight')
    set_time(page,mid_seg(fseg)); expect(txt(page,'#kind')=='Trajet aérien','flight state')
    badge=page.locator('.hero-flight-badge'); expect(badge.count()==1 and float(badge.get_attribute('width'))>=24,'flight badge size')
    page.locator('#journey-flight-trail').uncheck(); page.wait_for_timeout(5)
    expect(page.locator('path.flight').count()==0 and badge.count()==1,'flight trail toggle semantics')
    page.locator('#journey-flight-trail').check(); page.wait_for_timeout(5)

    # Instance and BG states.
    inst=event(master,'instance','Deadmines · instance physique')
    set_time(page,mid_event(inst)); expect(txt(page,'#kind')=='Instance','instance state')
    ii=page.locator('.instance-anchor-icon'); expect(ii.count()==1 and float(ii.get_attribute('width'))>=44,'instance icon')
    expect((page.locator('.instance-elapsed-text').text_content() or '').strip()!='','instance timer')
    bg=event(master,'instance','Goulet')
    set_time(page,mid_event(bg)); expect(txt(page,'#kind')=='Champ de bataille','BG state')
    expect(page.locator('.instance-anchor.remote').count()==1,'BG indicator missing')
    expect(page.locator('.hero-class-icon').count()==0,'BG exterior player leaked')

    # Transport transitions stay semantic only; terminal pins exist but no route paths.
    boat=event(master,'boat'); set_time(page,mid_event(boat)); expect(txt(page,'#kind')=='Navire','boat transition')
    zepp=event(master,'zeppelin'); set_time(page,mid_event(zepp)); expect(txt(page,'#kind')=='Zeppelin','zeppelin transition')
    expect(page.locator('#nativeLines path').count()==0,'transport line geometry rendered')

    # Focused demos exist for every major visual/transition category.
    for prefix in ['Marche','Monture','Nage','Hearthstone','Portail / invocation','Tram des profondeurs','Reconnexion et interruption','Spirit Healer']:
        select_prefix(page,prefix)

    # Dedicated outdoor death.
    ds=scenario('Mort extérieure')
    select_prefix(page,'Mort extérieure')
    dde=event(ds,'death'); set_time(page,mid_event(dde))
    expect(page.locator('.hero-dead-state').count()==1 and events(page)['deathMarkers']==0,'direct death active state')
    after=max(e['t']+float(e.get('duration') or 0) for e in ds['events'])+1
    set_time(page,min(after,ds['duration']-.1)); expect(events(page)['deathMarkers']>=1,'corpse marker after death')

    # Swim + portal remains broken geographically at transition.
    ps=scenario('Menethil → Goldshire')
    select_prefix(page,'Menethil → Goldshire')
    sw=next(s for s in ps['segments'] if s['mode']==2); set_time(page,mid_seg(sw)); expect(txt(page,'#kind')=='Nage','swim status')
    pe=event(ps,'portal'); set_time(page,mid_event(pe)); expect('Portail' in txt(page,'#kind'),'portal status'); expect(page.locator('.hero-marker').count()==0,'portal marker visible')

    # Map switch, native layers, canonical instance positions.
    page.locator('#follow').uncheck(); rt=state(page)['replayT']
    for style in ['worldmap','satellite']:
        page.select_option('#mapStyle',style); page.wait_for_timeout(10)
        expect(state(page)['layerName']==style,'map style '+style); expect(abs(state(page)['replayT']-rt)<1e-6,'map switch changed time')
    labels=page.locator('#layersPanel .layer-toggle').all_text_contents()
    expect(labels==['Maîtres de vol','Cimetières','Auberges','Instances','Ports / zeppelins','Trajets en vol','Trajets de mort'],f'public layers {labels}')
    ns=page.evaluate('window.__HEROPATH_DEBUG__.nativeStats()')
    expect(ns['rawFlightRoutes']==288 and ns['rawTransportSegments']==22 and ns['rawWorldTransportRoutes']==9,'raw route corpus')
    expect(ns['renderedInstances']==29 and ns['renderedTransport']==15,'native pin counts')
    expect(page.locator('#nativeLines path').count()==0,'route lines must be archive-only')
    for name in ['Scholomance','Uldaman','Wailing Caverns',"Onyxia's Lair",'Maraudon']:
        pin=page.locator(f'.native-pin.instance[data-name="{name}"]')
        expect(pin.count()==1,'duplicate '+name); expect(pin.get_attribute('data-source')=='service','wrong canonical source '+name)
    expect(page.locator('.native-pin[data-name*="TEST for GM Client Only"]').count()==0,'developer graveyard leaked')

    # Map POIs stay available even at full zoom-out when their layers are enabled.
    page.evaluate('window.__HEROPATH_DEBUG__.setZoom(1)')
    page.wait_for_timeout(10)
    ns2=page.evaluate('window.__HEROPATH_DEBUG__.nativeStats()')
    expect(ns2['visibleGraveyards']==ns2['renderedGraveyards'],'graveyards hidden at zoom-out')
    expect(ns2['visibleInns']==ns2['renderedInns'],'inns hidden at zoom-out')

    # Display settings are exposed through the gear menu and affect rendering.
    page.locator('#settingsToggle').click(); expect(not page.locator('#settingsPanel').evaluate('(e)=>e.classList.contains("hidden")'),'settings panel did not open')
    page.eval_on_selector('[data-setting="groundWidth"]',"el=>{el.value='145';el.dispatchEvent(new Event('input',{bubbles:true}))}")
    page.wait_for_timeout(5)
    expect(abs(state(page)['displayPrefs']['groundWidth']-1.45)<1e-9,'ground trail scale setting')
    expect(len(page.evaluate('window.__HEROPATH_DEBUG__.visualSettings()'))>=35,'atomic visual settings registry incomplete')
    page.locator('#settingsReset').click(); page.wait_for_timeout(5)
    expect(abs(state(page)['displayPrefs']['groundWidth']-1.0)<1e-9,'settings reset')

    # Point-preserving smoothing: adding a future point must not move existing geometry.
    stable=page.evaluate('''()=>{const A=window.__HEROPATH_DEBUG__;const a=[{x:0,y:0},{x:100,y:0},{x:0,y:0}],b=[...a,{x:0,y:100}];return [A.stablePath(a),A.stablePath(b)]}''')
    expect(stable[1].startswith(stable[0]),'future point changed already-drawn path')

    ps=page.evaluate('window.__HEROPATH_DEBUG__.performanceStats()')
    expect(ps['maxTileCache']==128 and ps['tileCache']<=128,'tile cache ceiling')
    expect(ps['tileLayerChildren']==ps['tileCache'],'tile layer/cache mismatch')
    expect(not errs,'page errors '+repr(errs))
    browser.close()
print('BROWSER_SCENARIOS_ALL=PASS')
