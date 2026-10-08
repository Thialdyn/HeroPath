/* HeroPath web renderer - native map adapter. */
(function(g){
"use strict";
var TILE=512,H=1600/3;
var WORLD_OFFSETS={0:{x:26,y:-18},1:{x:-19,y:-9}};
var ATLAS_SHIFT={x:19*TILE,y:9*TILE};
var styles=[
 {id:"satellite",label:"Satellite",family:"native-satellite",nativeZoom:7,minZoom:1,shiftX:ATLAS_SHIFT.x,shiftY:ATLAS_SHIFT.y},
 {id:"worldmap",label:"Carte du jeu",family:"worldmap",nativeZoom:5,minZoom:2,shiftX:0,shiftY:0}
];
function basePixel(mapID,x,y){var o=WORLD_OFFSETS[mapID];if(!o||!Number.isFinite(x)||!Number.isFinite(y))return null;return{x:(32-y/H+o.x)*TILE,y:(32-x/H+o.y)*TILE};}
function pixelForStyle(styleID,mapID,x,y){var p=basePixel(mapID,x,y),s=styles.find(function(v){return v.id===styleID});if(!p||!s)return null;return{x:p.x+(s.shiftX||0),y:p.y+(s.shiftY||0)};}
function preserveCenter(oldStyle,newStyle,cx,cy){var a=styles.find(function(v){return v.id===oldStyle})||styles[0],b=styles.find(function(v){return v.id===newStyle})||styles[0];return{x:cx-(a.shiftX||0)+(b.shiftX||0),y:cy-(a.shiftY||0)+(b.shiftY||0)};}
function nativeTileSpec(world,z,x,y){if(!world)return{slug:"azeroth",z:z,x:x,y:y};var own=world.__ownSet||(world.__ownSet=new Set(world.own||[]));if(z===world.nativeZoom&&!own.has(x+"_"+y)){var px=(x+.5)*512,py=(y+.5)*512,p=(world.parts||[]).find(function(q){return px>=512*q.ox&&py>=512*q.oy&&px<(q.ox+q.cols)*512&&py<(q.oy+q.rows)*512});if(p)return{slug:p.slug,z:p.nativeZoom,x:x-p.ox,y:y-p.oy};}return{slug:"azeroth",z:z,x:x,y:y};}
function transportStyle(kind){if(kind==="boat")return{color:"#7fb5e6",dashArray:"6 6",weight:2,opacity:.75};if(kind==="zeppelin")return{color:"#e08a6a",dashArray:"2 7",weight:2,opacity:.75};if(kind==="skyship")return{color:"#c8aaff",dashArray:"6 6",weight:2,opacity:.75};return{color:"#fff",dashArray:"6 6",weight:2,opacity:.65};}
function worldRoutePixel(p){return p&&Number.isFinite(p[0])&&Number.isFinite(p[1])?{x:p[0]*TILE,y:p[1]*TILE}:null;}

function normalizeNativeName(v){return String(v||"").normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLowerCase().replace(/[^a-z0-9]+/g,"");}
function canonicalInstancePins(overlays){var m=new Map();(overlays&&overlays.services||[]).forEach(function(p){if(p.kind!=="instance")return;var k=Number(p.mapID)+":"+normalizeNativeName(p.name);if(k.endsWith(":"))return;if(!m.has(k))m.set(k,Object.assign({__source:"service"},p));});(overlays&&overlays.entrances||[]).forEach(function(p){var k=Number(p.mapID)+":"+normalizeNativeName(p.name);if(k.endsWith(":")||m.has(k))return;m.set(k,Object.assign({__source:"entrance"},p));});return Array.from(m.values());}
function publicTransportPins(overlays){return (overlays&&overlays.docks||[]).filter(function(p){return p.kind==="boat"||p.kind==="zeppelin";});}
async function loadNativeData(base){base=base||"Maps/WorldAtlas/data/";var r=await Promise.all([fetch(base+"world.json"),fetch(base+"overlays.json")]);if(!r[0].ok||!r[1].ok)throw new Error("Données cartographiques locales indisponibles");return{world:await r[0].json(),overlays:await r[1].json()};}
g.HeroPathNativeMap={styles:styles,basePixel:basePixel,pixelForStyle:pixelForStyle,preserveCenter:preserveCenter,nativeTileSpec:nativeTileSpec,transportStyle:transportStyle,worldRoutePixel:worldRoutePixel,loadNativeData:loadNativeData,canonicalInstancePins:canonicalInstancePins,publicTransportPins:publicTransportPins};
})(window);
