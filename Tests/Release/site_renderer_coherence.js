const fs=require('fs'),vm=require('vm'),path=require('path');
const ROOT=path.resolve(__dirname,'../..');
const src=fs.readFileSync(path.join(ROOT,'Web/replay-renderer.js'),'utf8');
function assert(c,m){if(!c)throw new Error(m)}
const ctx={
  console,WeakMap,Math,Number,String,Array,Object,Infinity,isFinite,
  window:{HeroPathAssetBase:'Maps/icons/'},
  S:{heroPathPlayerClass:'warrior',heroPathPlayerFaction:'alliance'},AW:1000,AH:800,
  heroReplayPlayed:10,heroPathFilter:'all',heroRouteVisible:true,heroReplayPlaying:false,heroReplaySpeed:1,heroFollowPlayer:true,heroLastReplayMarker:null,
  onView:(view,p)=>[p.X/100,p.Y/100],heroPointAt:()=>null,heroPointDistance:()=>0,heroFocusReplayPoint:()=>{},heroModeAllowed:()=>true,
  heroModeGroup:(m)=>m===3?'flight':m===4?'ghost':'alive',heroModeLabel:(m)=>m===3?'Flight Path':m===4?'Fantôme':'Déplacement',heroRoutePathMarkup:()=>'',fallbackRouteFor:()=>'',registerHeroView:()=>'',refreshHeroRouteLayers:()=>{},heroSyncCameraControlAvailability:()=>{},installHeroCameraInteraction:()=>{},heroRestoreFollowAfterInteraction:()=>{},pauseHeroReplay:()=>{},playHeroReplay:()=>{},exitHeroReplay:()=>{},dur:(x)=>String(x),$:()=>null,performance:{now:()=>0}
};
vm.createContext(ctx);vm.runInContext(src,ctx);
ctx.S.heroPathEventIndex={deaths:[{played:5,mapID:0,X:20,Y:30,insideInstance:false,positionAccuracy:1},{played:6,mapID:0,X:25,Y:35,insideInstance:true,positionAccuracy:3}],instances:[],states:[],gaps:[]};ctx.S.heroPathEvents=[];
let out=ctx.heroDeathMarkup({kind:'zone'},10);
assert((out.match(/hero-death-marker/g)||[]).length===1,'inside death leaked or outside death missing');
assert(out.includes('death-location-user.png'),'user death asset absent');
assert(!out.includes('Corpse_gravestone')&&!out.includes('corpse-gravestone'),'graveyard-like corpse marker leaked');
ctx.heroPointAt=()=>({played:10,mapID:0,X:20,Y:30,mode:0,dead:true,deadGap:{}});out=ctx.heroOverlayMarkup({kind:'zone'});assert(out.includes('hero-dead-state')&&out.includes('death-location-user.png')&&!out.includes('classicon_warrior.jpg'),'dedicated death marker missing');
ctx.heroPointAt=()=>({played:10,mapID:0,X:20,Y:30,mode:0,inInstance:true,instance:{name:'Deadmines',instanceType:'party'}});out=ctx.heroOverlayMarkup({kind:'zone'});assert(out.includes('hero-instance-anchor'),'physical instance anchor missing');assert(!out.includes('classicon_'),'physical instance pretends player is outdoors');
for(const t of ['pvp','arena','transport']){ctx.heroPointAt=()=>({played:10,mapID:0,X:20,Y:30,mode:0,inInstance:true,instance:{name:'Remote',instanceType:t,startPlayed:1}});out=ctx.heroOverlayMarkup({kind:'zone'});assert(out.includes('hero-instance-anchor remote')&&!out.includes('classicon_'),'remote instance absence indicator incorrect: '+t);}
ctx.heroPointAt=()=>({played:10,mapID:0,X:20,Y:30,mode:0});out=ctx.heroOverlayMarkup({kind:'zone'});assert(out.includes('classicon_warrior.jpg'),'class icon missing');
ctx.heroPointAt=()=>({played:10,mapID:0,X:20,Y:30,mode:3});out=ctx.heroOverlayMarkup({kind:'zone'});assert(out.includes('hero-flight-badge')&&out.includes('Maps/WorldAtlas/icons/flight.png'),'flight badge missing');
ctx.heroPointAt=()=>({played:10,mapID:0,X:20,Y:30,mode:4});out=ctx.heroOverlayMarkup({kind:'zone'});assert(out.includes('hero-ghost-icon')&&out.includes('ghost-user.png'),'supplied ghost state icon missing');
const curveA=ctx.heroStableSubpath([{x:0,y:0},{x:50,y:0},{x:0,y:0}]);const curveB=ctx.heroStableSubpath([{x:0,y:0},{x:50,y:0},{x:0,y:0},{x:-30,y:10}]);assert(curveB.startsWith(curveA),'existing path geometry moved after appending a future point');
console.log('SITE_OUTSIDE_DEATH_GAME_ASSET=PASS');
console.log('SITE_INSIDE_DEATH_HIDDEN=PASS');
console.log('SITE_INSTANCE_SEMANTICS=PASS');
console.log('SITE_PLAYER_STATE_ICONS=PASS');
console.log('SITE_COHERENCE=PASS');
