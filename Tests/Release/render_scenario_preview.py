from pathlib import Path
import sys
from PIL import Image,ImageDraw,ImageFont
import json, math
ROOT=Path(__file__).resolve().parents[2]
D=json.loads((ROOT/'Tests/Fixtures/scenarios.json').read_text(encoding='utf-8'))
sc=D['scenarios'][0]
T=512; z=5; factor=2**(7-z)  # z7 pixel -> z5 pixel
xs=range(0,21); ys=range(0,12)
canvas=Image.new('RGB',(21*T,12*T),(7,9,11))
missing=0
for x in xs:
  for y in ys:
    p=ROOT/'Maps/tiles/worldmap'/str(z)/str(x)/f'{y}.webp'
    if p.exists():
      im=Image.open(p).convert('RGB')
      canvas.paste(im,(x*T,y*T))
    else: missing+=1
H=1600/3;OFF={0:(26,-18),1:(-19,-9)}
def pxy(p):
  ox,oy=OFF[p['mapID']]
  lat=-(32-p['x']/H+oy)*4;lng=(32-p['y']/H+ox)*4
  return (lng*128/factor,-lat*128/factor)

draw=ImageDraw.Draw(canvas)
# strong dark halo then route. Use no event connector lines.
for sg in sc['segments']:
  pts=[pxy(p) for p in sg['points']]
  if len(pts)<2: continue
  draw.line(pts,fill=(7,12,7),width=16,joint='curve')
  col=(120,230,92) if sg['kind']!='ghost' else (185,190,198)
  if sg['kind']=='flight':
    # Draw dotted/dashed path manually.
    for a,b in zip(pts,pts[1:]):
      ax,ay=a;bx,by=b;L=math.hypot(bx-ax,by-ay); n=max(1,int(L/18))
      for i in range(n):
        if i%2==0:
          t0=i/n;t1=min(1,(i+0.65)/n)
          draw.line([(ax+(bx-ax)*t0,ay+(by-ay)*t0),(ax+(bx-ax)*t1,ay+(by-ay)*t1)],fill=col,width=8)
  else: draw.line(pts,fill=col,width=8,joint='curve')

# Mark transitions independently at source/destination to demonstrate intentional discontinuity.
def diamond(x,y,r=14,fill=(244,202,115)):
  draw.polygon([(x,y-r),(x+r,y),(x,y+r),(x-r,y)],fill=fill,outline=(30,24,12))
def cross(x,y,r=17):
  draw.line((x-r,y-r,x+r,y+r),fill=(255,88,88),width=9)
  draw.line((x-r,y+r,x+r,y-r),fill=(255,88,88),width=9)
labels=[]
for e in sc['events']:
  if e['kind']=='death':
    x,y=pxy(e);cross(x,y);labels.append((x+20,y-20,'Mort'))
  elif e['kind'] in {'hearth','tram','boat','gap','reload'}:
    if 'from' in e:
      x,y=pxy(e['from']);diamond(x,y);labels.append((x+18,y-18,e['kind']))
    elif 'mapID' in e:
      x,y=pxy(e);diamond(x,y)
    if 'to' in e:
      x,y=pxy(e['to']);diamond(x,y)

# Crop to union of scenario positions with padding.
allp=[]
for sg in sc['segments']: allp += [pxy(p) for p in sg['points']]
for e in sc['events']:
  if 'from' in e: allp.append(pxy(e['from']))
  if 'to' in e: allp.append(pxy(e['to']))
  if 'mapID' in e and 'x' in e: allp.append(pxy(e))
minx=min(x for x,y in allp);maxx=max(x for x,y in allp);miny=min(y for x,y in allp);maxy=max(y for x,y in allp)
pad=260
box=(max(0,int(minx-pad)),max(0,int(miny-pad)),min(canvas.width,int(maxx+pad)),min(canvas.height,int(maxy+pad)))
crop=canvas.crop(box)
# resize into a manageable preview while preserving detail
maxw,maxh=2200,1500
scale=min(maxw/crop.width,maxh/crop.height,1)
if scale<1: crop=crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.LANCZOS)
# top banner legend after resize
W,Hh=crop.size
banner=110
out=Image.new('RGB',(W,Hh+banner),(14,16,18));out.paste(crop,(0,banner))
d=ImageDraw.Draw(out)
try:
 font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',22)
 bold=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',28)
 small=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',18)
except: font=bold=small=None
d.text((20,12),'Hero’s Path - test extérieur complet sur les vraies tuiles WoWForeverMap',font=bold,fill=(244,236,210))
d.line((22,65,95,65),fill=(120,230,92),width=6);d.text((108,51),'Sol',font=font,fill=(230,230,220))
# dashed legend
for x in range(220,300,18): d.line((x,65,x+10,65),fill=(120,230,92),width=6)
d.text((312,51),'Flight Path',font=font,fill=(230,230,220))
d.line((500,65,575,65),fill=(185,190,198),width=6);d.text((587,51),'Fantôme',font=font,fill=(230,230,220))
d.polygon([(800,52),(813,65),(800,78),(787,65)],fill=(244,202,115));d.text((825,51),'Transition sans connecteur',font=font,fill=(230,230,220))
d.text((20,86),'Hearth / Tram / Navire / changement de continent : aucun trait artificiel entre départ et arrivée.',font=small,fill=(205,195,175))
out_path=Path(sys.argv[1]) if len(sys.argv)>1 else Path.cwd()/'HeroPath-scenario-preview.png'
out.save(out_path,optimize=True)
print('WORLD_MAP_MISSING_TILES',missing)
print('TRANSPORT_SCENARIO_PREVIEW=PASS')
