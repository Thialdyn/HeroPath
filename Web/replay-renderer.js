// HeroPath web renderer - replay integration.
// Recorded data stays authoritative; LOD and smoothing are display-only.
// Unknown/special movement is rendered separately instead of being mislabeled as walking.
var HPF = 9;
var heroPathRenderCache = (typeof WeakMap !== "undefined") ? new WeakMap() : null;
var heroRevealAll=false, heroRevealReturnPlayed=null;

function heroPathPointCount() { return Number(S.heroPathCount) || 0; }
function hpv(i,k) { return S.heroPathPacked[i*HPF+k]; }
function hpPlayed(i){return hpv(i,0);} function hpMap(i){return hpv(i,1);}
function hpX(i){return hpv(i,2);} function hpY(i){return hpv(i,3);}
function hpMode(i){return hpv(i,4);} function hpBreak(i){return hpv(i,5)===1;} function hpProtected(i){return hpv(i,6)===1;}
function hpOrder(i){return Number(hpv(i,7))||0;} function hpReason(i){return Number(hpv(i,8))||0;}
function heroPointObjectAt(i){return {played:hpPlayed(i),mapID:hpMap(i),X:hpX(i),Y:hpY(i),mode:hpMode(i),breakBefore:hpBreak(i),order:hpOrder(i),breakReason:hpReason(i)};}
function heroEvents(){return S.heroPathEvents||[];}
function heroEventIndex(){return S.heroPathEventIndex||{deaths:[],instances:[],states:[],gaps:[]};}

function heroPathBounds(){
  var n=heroPathPointCount();if(!n)return null;
  var first=hpPlayed(0),last=hpPlayed(n-1);
  var ev=heroEvents();for(var i=0;i<ev.length;i++){var e=ev[i],a=e.kind==="instance"?e.startPlayed:e.played,b=e.kind==="instance"&&e.endPlayed>0?e.endPlayed:a;if(isFinite(a))first=Math.min(first,a);if(isFinite(b))last=Math.max(last,b);}
  if(isFinite(S.heroPathLastPlayed)&&S.heroPathLastPlayed>0)last=Math.max(last,S.heroPathLastPlayed);
  return {first:first,last:last};
}

function heroFindIntervalByStart(arr,played,startKey,endKey){
  var lo=0,hi=arr.length;while(lo<hi){var mid=(lo+hi)>>1;if(Number(arr[mid][startKey])<=played)lo=mid+1;else hi=mid;}
  var i=lo-1;if(i<0)return null;var e=arr[i],end=Number(e[endKey]);if(!isFinite(end)||end<=0)end=Infinity;return played>=Number(e[startKey])&&played<end?e:null;
}
function heroInstanceAt(played){return heroFindIntervalByStart(heroEventIndex().instances,played,"startPlayed","endPlayed");}
function heroInstanceBetween(a,b){var arr=heroEventIndex().instances;for(var i=0;i<arr.length;i++){var e=arr[i],end=e.endPlayed>0?e.endPlayed:Infinity;if(e.startPlayed<=b&&end>=a)return e;if(e.startPlayed>b)break;}return null;}
function heroGapAt(played){var gaps=heroEventIndex().gaps,lo=0,hi=gaps.length;while(lo<hi){var m=(lo+hi)>>1;if(gaps[m].start.played<=played)lo=m+1;else hi=m;}var i=lo-1;if(i<0)return null;var g=gaps[i];return played>=g.start.played&&played<g.end?g:null;}
function heroTransportStateAt(played){
  var a=heroEventIndex().states||[],lo=0,hi=a.length;while(lo<hi){var m=(lo+hi)>>1;if(Number(a[m].played)<=played)lo=m+1;else hi=m;}var i=lo-1;if(i<0)return null;var e=a[i],code=Number(e.stateCode)||0;if(code<8||code>14||played-Number(e.played)>5)return null;return e;
}
function heroTransportLabel(code){return ({8:"Téléportation / transition",9:"Hearthstone",10:"Tram - entrée",11:"Tram - sortie",12:"Navire",13:"Zeppelin",14:"Transport non identifié"})[Number(code)]||"";}

function heroPointLowerBound(played){var n=heroPathPointCount(),lo=0,hi=n;while(lo<hi){var m=(lo+hi)>>1;if(hpPlayed(m)<played)lo=m+1;else hi=m;}return lo;}
function heroPointUpperBound(played){var n=heroPathPointCount(),lo=0,hi=n;while(lo<hi){var m=(lo+hi)>>1;if(hpPlayed(m)<=played)lo=m+1;else hi=m;}return lo;}
function heroNextPointAfterEvent(event){
  var n=heroPathPointCount();if(!event||!n)return null;var t=Number(event.played),ord=Number(event.order)||0,i=heroPointLowerBound(t);
  for(;i<n;i++){var pt=hpPlayed(i),po=hpOrder(i);if(pt>t)return heroPointObjectAt(i);if(pt===t){if(ord>0&&po>ord)return heroPointObjectAt(i);if(ord===0&&po===0&&(hpBreak(i)||hpMode(i)===4))return heroPointObjectAt(i);}if(pt>t)break;}return null;
}
function heroDeathGapAt(played){
  if(heroInstanceAt(played))return null;var ds=heroEventIndex().deaths,lo=0,hi=ds.length;while(lo<hi){var m=(lo+hi)>>1;if(ds[m].played<=played)lo=m+1;else hi=m;}var d=lo?ds[lo-1]:null;if(!d||d.insideInstance)return null;
  var next=heroNextPointAfterEvent(d);if(!next||played<next.played)return {death:d,next:next,positionUnknown:d.positionKnown===false||Number(d.positionAccuracy)===4};return null;
}

function heroBreakBetween(aPlayed,bPlayed){
  if(!isFinite(aPlayed)||!isFinite(bPlayed)||aPlayed===bPlayed)return false;var low=Math.min(aPlayed,bPlayed),high=Math.max(aPlayed,bPlayed),i=heroPointUpperBound(low),n=heroPathPointCount();
  for(;i<n&&hpPlayed(i)<=high;i++)if(hpBreak(i))return true;return false;
}
function heroTimelineBoundaries(){return S.heroPathBoundaryTimes||[];}

function heroPointAt(played){
  var inst=heroInstanceAt(played);if(inst){if(inst.anchorKnown===false)return {played:played,mode:5,inInstance:true,instance:inst,hidden:true,anchorUnknown:true,breakBefore:false};return {played:played,mapID:inst.mapID,X:inst.X,Y:inst.Y,mode:0,inInstance:true,instance:inst,breakBefore:false};}
  var dg=heroDeathGapAt(played);if(dg){if(dg.positionUnknown)return {played:played,mode:5,hidden:true,dead:true,deadGap:dg,deathPositionUnknown:true,breakBefore:false};return {played:played,mapID:dg.death.mapID,X:dg.death.X,Y:dg.death.Y,mode:0,hidden:false,dead:true,deadGap:dg,breakBefore:false};}
  var gap=heroGapAt(played);if(gap){var s=gap.start;return {played:played,mapID:s.mapID,X:s.X,Y:s.Y,mode:0,hidden:true,positionGap:gap,breakBefore:false};}
  var n=heroPathPointCount();if(!n)return null;
  if(played<=hpPlayed(0)){var f=heroPointObjectAt(0);f.played=played;f.breakBefore=true;return f;}
  if(played>=hpPlayed(n-1)){var l=heroPointObjectAt(n-1);l.played=played;return l;}
  var hi=heroPointUpperBound(played),lo=hi-1,a=heroPointObjectAt(lo),b=heroPointObjectAt(hi);
  if(b.breakBefore||b.mapID!==a.mapID||b.played<=a.played){if(played>=b.played){b.played=played;return b;}a.played=played;a.holdingForJump=true;a.breakBefore=false;return a;}
  var r=Math.max(0,Math.min(1,(played-a.played)/(b.played-a.played)));
  return {played:played,mapID:a.mapID,X:a.X+(b.X-a.X)*r,Y:a.Y+(b.Y-a.Y)*r,mode:b.mode,breakBefore:false};
}

function heroRenderCacheFor(view){
  if(!heroPathRenderCache)return null;var c=heroPathRenderCache.get(view);if(!c){c={filter:null,stride:1,endIndex:0,foot:"",mounted:"",swim:"",flight:"",ghost:"",special:"",tails:{foot:null,mounted:null,swim:null,flight:null,ghost:null,special:null}};heroPathRenderCache.set(view,c);}return c;
}
function heroResetRenderCache(c){c.endIndex=0;c.foot=c.mounted=c.swim=c.flight=c.ghost=c.special="";c.tails={foot:null,mounted:null,swim:null,flight:null,ghost:null,special:null};}
function heroModeGroup(m){m=Number(m);return m===1?"mounted":m===2?"swim":m===3?"flight":m===4?"ghost":m===5?"special":"foot";}
function heroModeAllowed(m){if(heroPathFilter==="ghost")return Number(m)===4;if(heroPathFilter==="alive")return Number(m)!==4;return true;}
function heroModeLabel(m){return ({0:"Marche",1:"Monture",2:"Nage",3:"Trajet aérien",4:"Fantôme",5:"Déplacement spécial / transport non identifié"})[Number(m)]||"Déplacement";}
function heroResetTails(c){Object.keys(c.tails||{}).forEach(function(k){c.tails[k]=null;});}
function heroRenderStride(view){return 1;}
function heroStableSubpath(pts){
  if(!pts||pts.length<2)return "";var f=function(n){return Number(n).toFixed(1);};if(pts.length===2)return "M"+f(pts[0].x)+" "+f(pts[0].y)+"L"+f(pts[1].x)+" "+f(pts[1].y);
  var d="M"+f(pts[0].x)+" "+f(pts[0].y);
  for(var i=0;i<pts.length-1;i++){
    var a=pts[i],b=pts[i+1],vx=b.x-a.x,vy=b.y-a.y,len=Math.hypot(vx,vy);if(len<.001)continue;
    var ux=vx/len,uy=vy/len,sx=ux,sy=uy,startHandle=len*.18;
    if(i>0){var prev=pts[i-1],pvx=a.x-prev.x,pvy=a.y-prev.y,plen=Math.hypot(pvx,pvy);if(plen>.001){var pux=pvx/plen,puy=pvy/plen,dot=pux*ux+puy*uy;if(dot<.2)startHandle=0;else{sx=pux;sy=puy;startHandle=Math.min(plen,len)*.18*Math.min(1,Math.max(.25,(dot+.2)/1.2));}}}
    var endHandle=len*.18,c1x=a.x+sx*startHandle,c1y=a.y+sy*startHandle,c2x=b.x-ux*endHandle,c2y=b.y-uy*endHandle;
    d+="C"+f(c1x)+" "+f(c1y)+","+f(c2x)+" "+f(c2y)+","+f(b.x)+" "+f(b.y);
  }
  return d;
}
function heroSmoothSvgPath(raw){
  if(!raw||raw.indexOf("L")<0)return raw||"";var re=/([ML])(-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?)/g,m,runs=[],run=[];
  while((m=re.exec(raw))){var p={x:Number(m[2]),y:Number(m[3])};if(m[1]==="M"){if(run.length>1)runs.push(run);run=[p];}else run.push(p);}if(run.length>1)runs.push(run);var out="";for(var i=0;i<runs.length;i++)out+=heroStableSubpath(runs[i]);return out;
}
function heroRoutePathMarkup(paths){
  function one(cls,d,style){d=heroSmoothSvgPath(d);return d?'<path class="hero-route '+cls+'" d="'+d+'" style="fill:none;'+style+';stroke-linecap:round;stroke-linejoin:round;vector-effect:non-scaling-stroke"></path>':'';}
  var keys=['foot','mounted','swim','flight','ghost','special'],out='';
  keys.forEach(function(k){if(paths[k])out+=one('halo',paths[k],'stroke:rgba(4,7,4,.88);stroke-width:6px');});
  out+=one('foot',paths.foot,'stroke:#78e65c;stroke-width:3.2px');
  if(paths.mounted){out+=one('mounted-underlay',paths.mounted,'stroke:#6f4822;stroke-width:5.2px');out+=one('mounted',paths.mounted,'stroke:#ddb45d;stroke-width:2.8px');}
  out+=one('swim',paths.swim,'stroke:#73cfe4;stroke-width:3.2px;stroke-dasharray:2.5 5');
  out+=one('flight',paths.flight,'stroke:rgba(255,209,0,.78);stroke-width:3.2px;stroke-dasharray:9 7');
  out+=one('ghost',paths.ghost,'stroke:#b6bcc4;stroke-width:3.1px');
  out+=one('special',paths.special,'stroke:#9bb7c9;stroke-width:3px;stroke-dasharray:5 5');
  return out;
}
function heroAppendEdgeToCache(c,view,i,stride,forceFinal){
  var prev=i-1;if(i<=0||hpBreak(i)||hpMap(i)!==hpMap(prev)){heroResetTails(c);return;}
  var mode=hpMode(i),prevMode=hpMode(prev);if(!heroModeAllowed(mode)){heroResetTails(c);return;}
  var style=heroModeGroup(mode),boundary=mode!==prevMode||hpProtected(i)||hpProtected(prev),take=boundary||i===1||forceFinal||(i%stride===0);
  if(!take)return;
  var bo=heroPointObjectAt(i),b=onView(view,bo);if(!b){heroResetTails(c);return;}var bx=b[0]*AW,by=b[1]*AH,tail=c.tails[style],cmd;
  if(tail){cmd="L"+bx.toFixed(1)+" "+by.toFixed(1);}else{var ao=heroPointObjectAt(prev),a=onView(view,ao);if(!a){heroResetTails(c);return;}cmd="M"+(a[0]*AW).toFixed(1)+" "+(a[1]*AH).toFixed(1)+"L"+bx.toFixed(1)+" "+by.toFixed(1);}
  c[style]+=cmd;c.tails[style]={index:i,x:bx,y:by};Object.keys(c.tails).forEach(function(k){if(k!==style)c.tails[k]=null;});
}
function heroPathsFor(view,maxPlayed){
  var empty={foot:"",mounted:"",swim:"",flight:"",ghost:"",special:""},n=heroPathPointCount();if(n<2)return empty;
  var complete=maxPlayed===null?n-1:Math.max(0,heroPointUpperBound(maxPlayed)-1),stride=heroRenderStride(view),c=heroRenderCacheFor(view);
  if(!c)c={filter:heroPathFilter,stride:stride,endIndex:0,foot:"",mounted:"",swim:"",flight:"",ghost:"",special:"",tails:{foot:null,mounted:null,swim:null,flight:null,ghost:null,special:null}};
  if(c.filter!==heroPathFilter||c.stride!==stride||complete<c.endIndex){heroResetRenderCache(c);c.filter=heroPathFilter;c.stride=stride;}
  for(var i=Math.max(1,c.endIndex+1);i<=complete;i++)heroAppendEdgeToCache(c,view,i,stride,maxPlayed===null&&i===complete);c.endIndex=Math.max(c.endIndex,complete);
  var out={foot:c.foot,mounted:c.mounted,swim:c.swim,flight:c.flight,ghost:c.ghost,special:c.special};
  if(maxPlayed!==null&&!heroInstanceAt(maxPlayed)&&!heroGapAt(maxPlayed)&&!heroDeathGapAt(maxPlayed)){
    var i2=Math.min(n-1,complete+1),style=heroModeGroup(hpMode(i2)),valid=i2>0&&!hpBreak(i2)&&hpMap(i2)===hpMap(complete)&&heroModeAllowed(hpMode(i2)),bx,by,ax0,ay0;
    if(valid){var ao=heroPointObjectAt(complete),bo=heroPointObjectAt(i2),a=onView(view,ao),b=onView(view,bo);if(a&&b){var r=bo.played>ao.played?(maxPlayed-ao.played)/(bo.played-ao.played):0;r=Math.max(0,Math.min(1,r));ax0=a[0]*AW;ay0=a[1]*AH;bx=ax0+(b[0]*AW-ax0)*r;by=ay0+(b[1]*AH-ay0)*r;}}
    if(isFinite(bx)&&isFinite(by)){var tail=c.tails[style];if(tail&&(Math.abs(tail.x-bx)>.05||Math.abs(tail.y-by)>.05))out[style]+="M"+tail.x.toFixed(1)+" "+tail.y.toFixed(1)+"L"+bx.toFixed(1)+" "+by.toFixed(1);else if(!tail&&isFinite(ax0)&&isFinite(ay0)&&(Math.abs(ax0-bx)>.05||Math.abs(ay0-by)>.05))out[style]+="M"+ax0.toFixed(1)+" "+ay0.toFixed(1)+"L"+bx.toFixed(1)+" "+by.toFixed(1);}
  }
  return out;
}

function routeLayer(view){
  var hasHeroPath=heroPathPointCount()>0,key=hasHeroPath?registerHeroView(view):"";
  var renderLimit=heroReplayPlayed===null?null:(heroRevealAll?null:heroReplayPlayed);
  var paths=(hasHeroPath&&heroRouteVisible)?heroPathsFor(view,renderLimit):null,fallback=hasHeroPath?"":fallbackRouteFor(view),path=(hasHeroPath&&heroRouteVisible)?heroRoutePathMarkup(paths):(fallback&&heroRouteVisible?'<path class="halo" d="'+fallback+'"></path><path class="line" d="'+fallback+'"></path>':"");
  return '<svg class="atlas-route"'+(key?' data-hero-view="'+key+'"':'')+' viewBox="0 0 '+AW+' '+AH+'" preserveAspectRatio="none" aria-hidden="true"><g class="hero-route-layer">'+path+'</g><g class="hero-death-layer">'+heroDeathMarkup(view,renderLimit)+'</g><g class="hero-replay-overlay">'+heroOverlayMarkup(view)+'</g></svg>';
}

function heroDeathAssetBase(){return window.HeroPathAssetBase||"Maps/icons/";}
function heroDeathIcon(){return window.HeroPathDeathIcon||heroDeathAssetBase()+"death-location-user.png";}
function heroGhostIcon(){return window.HeroPathGhostIcon||heroDeathAssetBase()+"ghost-user.png";}
function heroDeathMarker(at,view,approx){
  var x=at[0]*AW,y=at[1]*AH,sz=view.kind==="zone"?26:18,h=sz/2,title=approx?"Position de décès approximative":"Décès du joueur";
  return '<g class="hero-death-marker'+(approx?' hero-death-approx':'')+'" transform="translate('+x.toFixed(1)+' '+y.toFixed(1)+')"><title>'+title+'</title><image href="'+heroDeathIcon()+'" x="'+(-h)+'" y="'+(-h)+'" width="'+sz+'" height="'+sz+'"/></g>';
}
function heroDeathMarkup(view,maxPlayed){
  var ds=heroEventIndex().deaths,out="";for(var i=0;i<ds.length;i++){var e=ds[i];if(maxPlayed!==null&&e.played>maxPlayed)break;if(e.insideInstance||e.positionKnown===false||Number(e.positionAccuracy)===4)continue;var at=onView(view,e);if(!at||at[0]<0||at[0]>1||at[1]<0||at[1]>1)continue;out+=heroDeathMarker(at,view,!!(e.positionAccuracy&&e.positionAccuracy!==1));}return out;
}

function heroUpdateCamera(force){
  if(heroReplayPlayed===null)return;var p=heroPointAt(heroReplayPlayed);if(!p)return;
  if(p.hidden){
    if(p.deadGap){var same=heroLastReplayMarker&&heroLastReplayMarker.hidden&&heroLastReplayMarker.deadGap&&heroLastReplayMarker.deadGap.death.played===p.deadGap.death.played;if(force||!same)heroFocusReplayPoint(p,"death",true,false);}
    else if(p.positionGap){var sameGap=heroLastReplayMarker&&heroLastReplayMarker.hidden&&heroLastReplayMarker.positionGap&&heroLastReplayMarker.positionGap.start.played===p.positionGap.start.played;if(force||!sameGap)heroFocusReplayPoint(p,"transition",true,false);}
    else if(p.transitionGap){var sameT=heroLastReplayMarker&&heroLastReplayMarker.hidden&&heroLastReplayMarker.transitionGap&&heroLastReplayMarker.transitionGap.to.played===p.transitionGap.to.played;if(force||!sameT)heroFocusReplayPoint(p,"transition",true,false);}
    heroLastReplayMarker=p;return;
  }
  var reason="follow",crossed=heroLastReplayMarker&&heroBreakBetween(heroLastReplayMarker.played,p.played);if(!heroLastReplayMarker||crossed||p.inInstance!==heroLastReplayMarker.inInstance||p.mapID!==heroLastReplayMarker.mapID||heroPointDistance(p,heroLastReplayMarker)>200)reason=p.inInstance?"instance":"jump";heroFocusReplayPoint(p,reason,!!force,false);heroLastReplayMarker=p;
}

function setHeroReplayPlayed(value,camera,forceCamera,updateRoute){var b=heroPathBounds();if(!b)return;heroReplayPlayed=Math.max(b.first,Math.min(b.last,value));var s=$("hero-replay-slider");if(s)s.value=heroReplayPlayed.toFixed(3);refreshHeroRouteLayers(updateRoute);if(camera!==false)heroUpdateCamera(!!forceCamera);}

function updateHeroReplayStatus(){
  var status=$("hero-replay-status"),label=$("hero-replay-time");if(heroReplayPlayed===null){if(status)status.textContent="Voyage complet";return;}var b=heroPathBounds(),p=heroPointAt(heroReplayPlayed);if(label&&b)label.textContent=dur(Math.max(0,heroReplayPlayed-b.first))+" / "+dur(Math.max(0,b.last-b.first));if(!status||!p)return;
  if(p.inInstance){var end=p.instance.endPlayed>0?p.instance.endPlayed:heroReplayPlayed,insideFor=Math.max(0,Math.min(heroReplayPlayed,end)-p.instance.startPlayed),it=String(p.instance.instanceType||"").toLowerCase(),prefix=it==="pvp"?"Champ de bataille":it==="arena"?"Arène":it==="transport"?"Transport instancié":"Instance";status.textContent=prefix+" - "+p.instance.name+" · "+dur(insideFor)+(p.instance.anchorKnown===false?" · position extérieure inconnue, aucune position inventée":heroInstanceIsRemote(p.instance)?" · aucune fausse entrée extérieure":" · ancre extérieure temporaire");return;}
  if(p.hidden){status.textContent=p.deathPositionUnknown?"Mort - position extérieure inconnue":p.positionGap?"Position indisponible":"Transition de déplacement";return;}
  if(p.deadGap){status.textContent="Mort - décès indiqué par le marqueur WoW"+(heroRevealAll?" · Tout afficher":" ");return;}
  else{var te=heroTransportStateAt(heroReplayPlayed),tl=te?heroTransportLabel(te.stateCode):"";status.textContent=(tl||heroModeLabel(p.mode))+(heroRevealAll?" · Tout afficher":"");}
}

function heroClassIconUrl(){var c=(S.heroPathPlayerClass||"warrior").toLowerCase(),b=window.HeroPathClassIconBase||"Maps/WorldAtlas/class-icons/";return b+"classicon_"+c+".jpg";}
function heroFlightBadgeUrl(){return (window.HeroPathNativeIconBase||"Maps/WorldAtlas/icons/")+"flight.png";}
function heroInstanceIsRemote(inst){var t=String(inst&&inst.instanceType||"").toLowerCase();return t==="pvp"||t==="arena"||t==="transport";}
function heroInstanceAnchorMarkup(view,p,at){
  var inst=p.instance;if(!inst)return "";var remote=heroInstanceIsRemote(inst),x=at[0]*AW,y=at[1]*AH,sz=view.kind==="zone"?28:22,h=sz/2,raid=String(inst.instanceType||"").toLowerCase()==="raid",icon=(window.HeroPathInstanceIconBase||"Maps/WorldAtlas/icons/")+(raid?"svc-raid.png":"svc-dungeon.png"),elapsed=Math.max(0,heroReplayPlayed-Number(inst.startPlayed||heroReplayPlayed)),title=remote?'Zone instanciée':String(inst.name||"Instance");
  return '<g class="hero-instance-anchor'+(remote?' remote':'')+'" transform="translate('+x.toFixed(1)+' '+y.toFixed(1)+')"><title>'+title+'</title><image class="hero-instance-active-icon" style="filter:drop-shadow(0 0 3px rgba(255,210,105,.95)) drop-shadow(0 0 7px rgba(255,150,25,.65))" href="'+icon+'" x="'+(-h)+'" y="'+(-h)+'" width="'+sz+'" height="'+sz+'"/><text class="hero-instance-elapsed" style="font-size:14px;font-weight:900;fill:#ffe2a0;paint-order:stroke;stroke:#080808;stroke-width:2.2px" x="0" y="'+(h+12)+'" text-anchor="middle">'+dur(elapsed)+'</text></g>';
}
function heroOverlayMarkup(view){
  if(heroReplayPlayed===null)return "";var p=heroPointAt(heroReplayPlayed);if(!p||p.hidden)return "";var at=onView(view,p);if(!at||at[0]<0||at[0]>1||at[1]<0||at[1]>1)return "";
  if(p.deadGap&&p.hidden)return "";
  if(p.inInstance)return heroInstanceAnchorMarkup(view,p,at);
  var x=at[0]*AW,y=at[1]*AH,dead=!!p.dead,ghost=!dead&&p.mode===4;
  if(dead){var ds=view.kind==="zone"?30:24,dh=ds/2;return '<g class="hero-player-marker hero-dead-state" transform="translate('+x.toFixed(1)+' '+y.toFixed(1)+')"><image class="hero-death-icon" href="Maps/icons/death-location-user.png" x="'+(-dh)+'" y="'+(-dh)+'" width="'+ds+'" height="'+ds+'" preserveAspectRatio="xMidYMid meet"/></g>';}
  if(ghost){var gs=view.kind==="zone"?24:18,gh=gs/2;return '<g class="hero-player-marker hero-ghost-state" transform="translate('+x.toFixed(1)+' '+y.toFixed(1)+')"><image class="hero-ghost-icon" href="'+heroGhostIcon()+'" x="'+(-gh)+'" y="'+(-gh)+'" width="'+gs+'" height="'+gs+'" preserveAspectRatio="xMidYMid meet"/></g>';}
  var sz=view.kind==="zone"?16:12,h=sz/2,clip=' style="clip-path:circle(50% at 50% 50%);"';var out='<g class="hero-player-marker" transform="translate('+x.toFixed(1)+' '+y.toFixed(1)+')"><image href="'+heroClassIconUrl()+'" x="'+(-h)+'" y="'+(-h)+'" width="'+sz+'" height="'+sz+'"'+clip+'/>';
  if(p.mode===3){var bs=view.kind==="zone"?18:14;out+='<image class="hero-flight-badge" href="'+heroFlightBadgeUrl()+'" x="'+(h-1)+'" y="'+(-h-9)+'" width="'+bs+'" height="'+bs+'"/>';}return out+'</g>';
}

function installHeroPathControls(){
  if(heroPathPointCount()<1||$("hero-path-controls"))return;var caption=$("map-caption");if(!caption||!caption.parentNode)return;var bounds=heroPathBounds(),controls=document.createElement("div");controls.id="hero-path-controls";controls.className="hero-path-controls";
  controls.innerHTML='<label class="hero-path-toggle"><input id="hero-path-visible" type="checkbox" checked> <span>Afficher le trajet</span></label><label class="hero-path-select">Trajet <select id="hero-path-filter"><option value="all">Tout</option><option value="alive">Vivant</option><option value="ghost">Fantôme</option></select></label><button id="hero-replay-start" type="button">Rejouer le voyage</button><div id="hero-replay-panel" class="hero-replay-panel" hidden><button id="hero-replay-play" type="button">Pause</button><label class="hero-path-select">Vitesse <select id="hero-replay-speed"><option value="0.5">0.5×</option><option value="1" selected>1×</option><option value="2">2×</option><option value="4">4×</option><option value="8">8×</option></select></label><label class="hero-path-toggle"><input id="hero-reveal-all" type="checkbox"> <span>Tout afficher</span></label><input id="hero-replay-slider" type="range" min="'+bounds.first.toFixed(3)+'" max="'+bounds.last.toFixed(3)+'" step="0.001" value="'+bounds.first.toFixed(3)+'" aria-label="Journey replay position"><span id="hero-replay-time" class="hero-replay-time"></span><label class="hero-path-toggle hero-follow-toggle"><input id="hero-follow-player" type="checkbox" checked> <span>Suivre</span></label><button id="hero-recenter" type="button" hidden>Recentrer</button><button id="hero-replay-full" type="button">Quitter le replay</button></div><div id="hero-replay-status" class="hero-replay-status">Voyage complet</div>';
  caption.parentNode.insertBefore(controls,caption);heroSyncCameraControlAvailability();
  $("hero-path-visible").addEventListener("change",function(){heroRouteVisible=this.checked;refreshHeroRouteLayers();});
  $("hero-path-filter").addEventListener("change",function(){heroPathFilter=this.value;if(heroPathRenderCache)heroPathRenderCache=new WeakMap();refreshHeroRouteLayers();});
  $("hero-replay-start").addEventListener("click",function(){heroSyncCameraControlAvailability();installHeroCameraInteraction();$("hero-replay-panel").hidden=false;this.textContent="Recommencer le replay";playHeroReplay(true);});
  $("hero-replay-play").addEventListener("click",function(){if(heroRevealAll){$("hero-reveal-all").checked=false;heroRevealAll=false;refreshHeroRouteLayers();}if(heroReplayPlaying)pauseHeroReplay();else playHeroReplay(false);});
  $("hero-replay-speed").addEventListener("change",function(){heroReplaySpeed=Number(this.value)||1;if(heroReplayPlaying){heroReplayStartPlayed=heroReplayPlayed;heroReplayStartReal=performance.now();}});
  $("hero-reveal-all").addEventListener("change",function(){
    var slider=$("hero-replay-slider"),play=$("hero-replay-play"),speed=$("hero-replay-speed");
    if(this.checked){pauseHeroReplay();heroRevealReturnPlayed=heroReplayPlayed;heroRevealAll=true;if(slider)slider.disabled=true;if(play)play.disabled=true;if(speed)speed.disabled=true;}
    else{heroRevealAll=false;if(heroRevealReturnPlayed!==null)setHeroReplayPlayed(heroRevealReturnPlayed,false,false);heroRevealReturnPlayed=null;if(slider)slider.disabled=false;if(play)play.disabled=false;if(speed)speed.disabled=false;heroUpdateCamera(true);}
    refreshHeroRouteLayers();updateHeroReplayStatus();
  });
  $("hero-replay-slider").addEventListener("input",function(){pauseHeroReplay();setHeroReplayPlayed(Number(this.value),true,true);});
  $("hero-follow-player").addEventListener("change",function(){heroFollowPlayer=this.checked;$("hero-recenter").hidden=heroFollowPlayer;if(heroFollowPlayer)heroRestoreFollowAfterInteraction();});
  $("hero-recenter").addEventListener("click",function(){heroFocusReplayPoint(heroPointAt(heroReplayPlayed),"jump",true,true);});
  $("hero-replay-full").addEventListener("click",exitHeroReplay);
  setHeroReplayPlayed(bounds.first,false);heroReplayPlayed=null;installHeroCameraInteraction();refreshHeroRouteLayers();
}
