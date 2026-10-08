from pathlib import Path
from playwright.sync_api import sync_playwright
p=Path(__file__).resolve().parents[2]/'Demo/index.html'
with sync_playwright() as pw:
    b=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-dev-shm-usage','--allow-file-access-from-files'])
    page=b.new_page(viewport={'width':1600,'height':900})
    errs=[]; page.on('pageerror',lambda e:errs.append(str(e)))
    page.route('https://**/*',lambda route: route.abort())
    page.set_content(p.read_text(encoding='utf-8'),wait_until='load')
    page.wait_for_timeout(300)
    name=page.evaluate('window.__HEROPATH_DEBUG__.DATA.scenarios[0].name')
    dur=page.evaluate('window.__HEROPATH_DEBUG__.DATA.scenarios[0].duration')
    ev=page.evaluate('window.__HEROPATH_DEBUG__.DATA.scenarios[0].events')
    assert name=='Parcours d’exemple',name
    assert abs(dur-956.253)<1e-6,dur
    reloads=[e for e in ev if e.get('kind')=='reload']
    assert len(reloads)==4,len(reloads)
    page.evaluate('window.__HEROPATH_DEBUG__.setRevealAll(true)')
    page.wait_for_timeout(100)
    trails=page.evaluate('window.__HEROPATH_DEBUG__.visibleTrail()')
    assert len(trails)>=10,len(trails)
    assert page.locator('path.ghost').count()>=1
    assert page.locator('path.swim').count()>=1
    page.evaluate('window.__HEROPATH_DEBUG__.setZoom(1)')
    page.wait_for_timeout(60)
    low=page.evaluate('window.__HEROPATH_DEBUG__.nativeStats()')
    assert low['renderedTransport']==15,low
    assert low['visibleTransport']==15,low
    page.evaluate('window.__HEROPATH_DEBUG__.setZoom(9)')
    page.wait_for_timeout(60)
    high=page.evaluate('window.__HEROPATH_DEBUG__.nativeStats()')
    assert high['visibleTransport']==15,high
    assert not errs,errs
    page.screenshot(path='/mnt/data/HeroPath-1.0.0-demo.png',full_page=True)
    print('RELEASE_DEMO_BROWSER=PASS',name,'reloads',len(reloads),'trails',len(trails))
    b.close()
