import {inflateRawSync} from 'node:zlib';
const url = process.argv[2] ?? 'wss://balatro-overhaul-muliplayer.onrender.com/ws';
const size = Number(process.argv[3] ?? 300000);
function conn(tag:string){ return new Promise<any>((res)=>{ const ws=new WebSocket(url); const q:any[]=[]; const wait:any[]=[];
 ws.onmessage=(e)=>{ let s=String(e.data); let raw=s.length; if(s.startsWith('{"z":1')){ const p=JSON.parse(s); s=inflateRawSync(Buffer.from(p.d,'base64')).toString()} const m=JSON.parse(s); m._raw=raw; console.log(tag,'<-',m.type,raw, m.reason??''); q.push(m); for(const w of [...wait]) if(w.f(m)){wait.splice(wait.indexOf(w),1);w.r(m)} };
 ws.onopen=()=>res({ws,send:(o:any)=>ws.send(JSON.stringify(o)),waitFor:(f:any,ms=25000)=>new Promise((r,j)=>{const hit=q.find(f); if(hit) return r(hit); wait.push({f,r}); setTimeout(()=>j(new Error('timeout')),ms)})}); ws.onclose=()=>console.log(tag,'closed'); })}
const a=await conn('A');
a.send({type:'create_room',name:'Zork'+Math.floor(Math.random()*1e6).toString(36),version:'x',mp_version:0});
const rc:any=await a.waitFor((m:any)=>m.type==='room_created');
a.send({type:'add_bot',level:'easy'});
await a.waitFor((m:any)=>m.type==='room_ready');
a.send({type:'room_joined',player:{name:'Zork'+Math.floor(Math.random()*1e6).toString(36),rank:1},mp_version:0,version:'x'});
a.send({type:'match_start',seed:'ABCD',settings:{mode:'faceoff',starting_lives:1}});
const ms:any=await a.waitFor((m:any)=>m.type==='match_session');
a.send({type:'ready_blind'});await a.waitFor((m:any)=>m.type==='start_blind',30000);a.send({type:'blind_entered',ante:1,blind:'S'});a.send({type:'play_hand',score:'100',hands_left:3});
const chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';let d='';for(let i=0;i<size;i++)d+=chars[(Math.random()*62)|0]; d=d.slice(0,size-size%4);
a.send({type:'save_snapshot',data:d,seq:1,ante:1,blind:'S'});
await a.waitFor((m:any)=>m.type==='snapshot_ack');
a.send({type:'return_to_menu'});
await new Promise(r=>setTimeout(r,500));a.ws.close();await new Promise(r=>setTimeout(r,500));
const b=await conn('B');b.send({type:'check_rejoin',code:ms.code,token:ms.token});await b.waitFor((m:any)=>m.type==='rejoin_status');b.send({type:'rejoin_match',code:ms.code,token:ms.token});
try{const ok:any=await b.waitFor((m:any)=>m.type==='rejoin_ok',20000);console.log('REJOIN_OK frame',ok._raw,'snap',ok.snapshot?.data?.length)}catch(e){console.log('NO rejoin_ok')}
b.send({type:'leave_match'});
await new Promise(r=>setTimeout(r,800));process.exit(0)
