const fs=require('fs'),vm=require('vm'),path=require('path');
const ROOT=path.resolve(__dirname,'../..');
const src=fs.readFileSync(path.join(ROOT,'Web/map-native-adapter.js'),'utf8');
const overlays=JSON.parse(fs.readFileSync(path.join(ROOT,'Maps/WorldAtlas/data/overlays.json'),'utf8'));
function assert(c,m){if(!c)throw new Error(m)}
const ctx={window:{},Set,Map,Math,Number,String,Array,Object,Promise,fetch:()=>{throw new Error('fetch not used')}};
vm.createContext(ctx);vm.runInContext(src,ctx);
const A=ctx.window.HeroPathNativeMap;assert(A,'adapter missing');
assert(A.styles.length===2,'style count');
const pins=A.canonicalInstancePins(overlays);assert(pins.length===29,'canonical instance count '+pins.length);
for(const name of ['Scholomance','Uldaman','Wailing Caverns',"Onyxia's Lair",'Maraudon']){
 const p=pins.find(x=>x.name===name);assert(p,'missing '+name);assert(p.__source==='service','native Dungeon/Raid entrance service not preferred '+name);
}
const t=A.publicTransportPins(overlays);assert(t.length===15,'transport pins '+t.length);assert(t.filter(x=>x.kind==='boat').length===12,'boat count');assert(t.filter(x=>x.kind==='zeppelin').length===3,'zeppelin count');
console.log('NATIVE_INSTANCE_SERVICE=PASS');
console.log('NATIVE_TRANSPORT_TERMINALS_15=PASS');
console.log('NATIVE_MAP_ADAPTER=PASS');
