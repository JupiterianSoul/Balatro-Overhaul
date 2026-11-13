require("love.filesystem")
local list_text, out, chan_name = ...
local chan = love.thread.getChannel(chan_name)
local ok, SIO = pcall(require, "functions/save_io")
if not ok then
  chan:push("err " .. tostring(SIO))
  return
end
local list = {}
for line in list_text:gmatch("[^\n]+") do
  local name, path = line:match("^(.-)\t(.*)$")
  if name then list[#list + 1] = {name = name, path = path} end
end
local done, err = SIO.zip_stream(love.filesystem, list, out, function(i, n)
  if i % 10 == 0 or i == n then
    chan:clear()
    chan:push("p " .. i .. " " .. n)
  end
end)
chan:clear()
chan:push(done and ("ok " .. out) or ("err " .. tostring(err)))
