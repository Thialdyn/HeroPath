from pathlib import Path
from playwright.sync_api import sync_playwright
import random
ROOT=Path(__file__).resolve().parents[2]
HTML=(ROOT/'Demo/index.html').read_text(encoding='utf-8')

def expect(c,m):
    if not c: raise AssertionError(m)
with sync_playwright() as pw:
    browser=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-dev-shm-usage'])
    page=browser.new_page(viewport={'width':1440,'height':900})
    page.route("https://**/*",lambda route: route.abort())
    errs=[]; page.on('pageerror',lambda e:errs.append(str(e)))
    page.set_content(HTML,wait_until='load')
    data=page.evaluate('window.__HEROPATH_DEBUG__.DATA'); checks=0
    for si,sc in enumerate(data['scenarios']):
        page.evaluate('(i)=>window.__HEROPATH_DEBUG__.selectScenario(i)',si)
        times={0.0,sc['duration']}
        for sg in sc['segments']:
            a,b=sg['points'][0]['t'],sg['points'][-1]['t'];times.update([a,min(b,a+.001),(a+b)/2,b])
        for e in sc['events']:
            a=e['t'];b=a+e.get('duration',0);times.update([max(0,a-.001),a])
            if b>a: times.update([(a+b)/2,max(a,b-.001),b])
        for t in sorted(times):
            page.evaluate('(t)=>window.__HEROPATH_DEBUG__.scrubTo(t)',t)
            st=page.evaluate('window.__HEROPATH_DEBUG__.getState()');expect(not st['playing'],f'scrub playing s{si} t{t}')
            vis=page.evaluate('window.__HEROPATH_DEBUG__.visibleTrail()')
            started=sum(1 for sg in sc['segments'] if t>sg['points'][0]['t'])
            expect(len(vis)<=started,f'future segment s{si} t{t}: {len(vis)} > {started}')
            ev=page.evaluate('window.__HEROPATH_DEBUG__.visibleEvents()')
            exp_deaths=sum(1 for e in sc['events'] if e['kind']=='death' and not e.get('insideInstance') and e['t']+e.get('duration',0)<=t)
            expect(ev['deathMarkers']==exp_deaths,f'death temporal leak s{si} t{t}: {ev} expected {exp_deaths}')
            expect(ev['technicalGlyphs']==0,f'technical glyph clutter s{si} t{t}')
            active_anchor=0
            for e in sc['events']:
                if e['kind']=='instance' and e['t']<=t<e['t']+e.get('duration',0): active_anchor=1
            expect(ev['instanceAnchors']==active_anchor,f'instance anchor s{si} t{t}: {ev}')
            checks+=1
    rng=random.Random(6000)
    for i in range(60):
        si=rng.randrange(len(data['scenarios'])); page.evaluate('(i)=>window.__HEROPATH_DEBUG__.selectScenario(i)',si)
        dur=data['scenarios'][si]['duration']; t=rng.random()*dur; page.evaluate('(t)=>window.__HEROPATH_DEBUG__.scrubTo(t)',t)
        if t<dur-.01:
            page.evaluate('window.__HEROPATH_DEBUG__.play()'); expect(page.evaluate('window.__HEROPATH_DEBUG__.getState().playing'),'play failed')
            t2=rng.random()*dur; page.evaluate('(t)=>window.__HEROPATH_DEBUG__.scrubTo(t)',t2); expect(not page.evaluate('window.__HEROPATH_DEBUG__.getState().playing'),'scrub did not stop')
        if i%3==0: page.locator('#follow').click()
        if i%5==0:
            before=page.evaluate('window.__HEROPATH_DEBUG__.getState()'); page.locator('#reveal').click(); page.wait_for_timeout(3); during=page.evaluate('window.__HEROPATH_DEBUG__.getState()')
            expect(during['revealAll'] and abs(during['replayT']-before['replayT'])<1e-6,'reveal changed timeline')
            expect(page.evaluate('window.__HEROPATH_DEBUG__.visibleEvents().technicalGlyphs')==0,'reveal introduced technical clutter')
            page.locator('#reveal').click(); page.wait_for_timeout(3); after=page.evaluate('window.__HEROPATH_DEBUG__.getState()'); expect(not after['revealAll'] and abs(after['replayT']-before['replayT'])<1e-6,'reveal restore')
        page.select_option('#mapStyle','worldmap' if i%2 else 'satellite')
    expect(not errs,'page errors '+repr(errs)); browser.close()
print('REPLAY_MATRIX_CHECKS='+str(checks))
print('REPLAY_INTERACTION_CYCLES=60')
print('REPLAY_COHERENCE_MATRIX=PASS')
