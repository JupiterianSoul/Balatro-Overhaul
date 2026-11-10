mp_log={info=function()end,warn=function(_,f,...)print("WARN",f,...)end,error=function(_,f,...)print("ERR",f,...)end,debug=function()end}
local function rd(p) local f=assert(io.open(p)); local s=f:read("*a"); f:close(); return s end
mp_config={}
AndroidWS=nil
local A=assert(loadstring(rd("/home/jupiteriansoul/BalatroV2-wt/mp-round/assets/multiplayer/android_ws.lua")))()
AndroidWS=AndroidWS or A
local core=rd("/home/jupiteriansoul/BalatroV2-wt/mp-round/assets/multiplayer/bom_core.lua")
local a=core:find("bom_core.json = {}",1,true); local b=core:find("-- WEBSOCKET CLIENT",1,true)
local json=assert(loadstring("local bom_core={} "..core:sub(a,b-50).." return bom_core.json"))()
local url=arg and arg[2] or "ws://127.0.0.1:18321/ws"
local size=tonumber(arg and arg[3]) or 20000
AndroidWS.init(); AndroidWS.connect(url)
NAME="Zork"..string.char(97+os.time()%26)..string.char(97+size%26)..tostring(os.time()%9973)
local stage,t,code,token=0,0
local function send(m) local e=json.encode(m); print(string.format("%.1f",love.timer.getTime()),"->",m.type,#e); AndroidWS.send(e) end
local function wants(m)
  print(string.format("%.1f",love.timer.getTime()),"<-",m.type,m.reason or "",m.snapshot and m.snapshot.data and #m.snapshot.data or "")
  if m.type=="room_created" then send({type="add_bot",level="easy"}) end
  if m.type=="room_ready" then send({type="match_start",seed="ABCD",settings={mode="faceoff",starting_lives=1},player_name=NAME}) end
  if m.type=="match_session" then code,token=m.code,m.token
    send({type="ready_blind"}) end
  if m.type=="start_blind" then send({type="blind_entered",ante=1,blind="S"}); send({type="play_hand",score="100",hands_left=3})
    local cs="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"; local t={}; for i=1,math.floor(size/4)*4 do local k=love.math.random(1,64); t[i]=cs:sub(k,k) end
    send({type="save_snapshot",data=table.concat(t),seq=1,ante=1,blind="S"}) end
  if m.type=="snapshot_ack" then send({type="return_to_menu"}); stage=1;t=love.timer.getTime() end
  if m.type=="rejoin_status" then print("status rejoinable",m.rejoinable); send({type="rejoin_match",code=code,token=token}) end
  if m.type=="rejoin_ok" then print("GOT rejoin_ok"); love.event.quit() end
end
function love.update(dt)
  AndroidWS.poll()
  if stage==0 and AndroidWS.isConnected() and not code and not sent then sent=true; send({type="create_room",name=NAME,version="x",mp_version=0}) end
  if stage==1 and love.timer.getTime()-t>0.5 then stage=2; AndroidWS.close(); t=love.timer.getTime() end
  if stage==2 and love.timer.getTime()-t>0.5 then stage=3; AndroidWS.connect(url) end
  if stage==3 and AndroidWS.isConnected() then stage=4; send({type="check_rejoin",code=code,token=token}) end
  if love.timer.getTime()>27 then print("TIMEOUT",AndroidWS.isConnected(),AndroidWS.lastError()); love.event.quit() end
  while true do local msg=AndroidWS.receive(); if not msg then break end
    local rawlen=#msg
    if msg:sub(1,6)=='{"z":1' then local e=json.decode(msg); local d=love.data.decode("string","base64",e.d); local ok,u=pcall(love.data.decompress,"string","deflate",d); if ok then msg=u else print("DECOMP FAIL",u) end end
    local m=json.decode(msg)
    if m and m.type then wants(m) else print("UNDECODED",rawlen,msg:sub(1,60)) end
  end
end
