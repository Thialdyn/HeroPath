from pathlib import Path
from urllib.parse import urlparse, unquote
from io import BytesIO
from PIL import Image
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[2]
DEMO=ROOT/'Demo'/'index.html'
html=DEMO.read_text(encoding='utf-8').replace('<head>','<head><base href="http://app.local/demo/">',1)
MIME={'.webp':'image/webp','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.json':'application/json','.js':'text/javascript','.css':'text/css','.html':'text/html'}

with sync_playwright() as pw:
    browser=pw.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-dev-shm-usage'])
    page=browser.new_page(viewport={'width':1440,'height':900})
    misses=[]
    def serve(route):
        u=urlparse(route.request.url)
        if u.hostname=='app.local':
            f=ROOT/unquote(u.path.lstrip('/'))
            if f.is_file():
                route.fulfill(status=200,body=f.read_bytes(),content_type=MIME.get(f.suffix.lower(),'application/octet-stream'))
            else:
                misses.append(str(f.relative_to(ROOT)))
                route.fulfill(status=404,body=b'')
        else:
            route.abort()
    page.route('**/*',serve)
    page.set_content(html,wait_until='load')
    page.wait_for_timeout(500)
    tile_info=page.locator('#tileLayer img').evaluate_all('''els=>els.map(e=>({nw:e.naturalWidth,nh:e.naturalHeight,vis:getComputedStyle(e).visibility,rect:e.getBoundingClientRect().toJSON(),src:e.src}))''')
    loaded=[t for t in tile_info if t['nw']>0 and t['nh']>0 and t['vis']=='visible']
    assert loaded, 'no actual local map tile decoded'
    intersect=[t for t in loaded if t['rect']['right']>0 and t['rect']['bottom']>200 and t['rect']['left']<1440 and t['rect']['top']<900]
    assert intersect, 'decoded tiles do not intersect the map viewport'
    assert 'paint' not in page.locator('#tileLayer').evaluate("e=>getComputedStyle(e).contain"), 'paint containment clips world-positioned tiles'
    png=page.screenshot()
    browser.close()

img=Image.open(BytesIO(png)).convert('RGB')
crop=img.crop((100,220,1340,760))
sea=(18,36,50)
pixels=list(crop.get_flattened_data() if hasattr(crop, "get_flattened_data") else crop.getdata())
sea_like=sum(1 for r,g,b in pixels if abs(r-sea[0])<=2 and abs(g-sea[1])<=2 and abs(b-sea[2])<=2)
ratio=sea_like/len(pixels)
assert ratio < 0.75, f'map pixels are still clipped/blank: sea-background ratio={ratio:.3f}'
print('MAP_ACTUAL_TILE_DECODE=PASS')
print('MAP_TILE_VIEWPORT_INTERSECTION=PASS')
print(f'MAP_MAP_PIXEL_PAINT=PASS sea_ratio={ratio:.3f}')
