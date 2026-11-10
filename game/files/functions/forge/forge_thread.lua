local inbox, outbox = ...
while true do
  local req = inbox:demand()
  if type(req) == "table" and req.quit then return end
  if type(req) == "table" and req.cmd then
    local raw, code = "", nil
    local ok, err = pcall(function()
      local f = io.popen(req.cmd .. " 2>/dev/null; echo \"__FORGE_EXIT__$?\"", "r")
      if not f then return end
      raw = f:read("*a") or ""
      f:close()
    end)
    local body = raw
    local at = raw:find("__FORGE_EXIT__", 1, true)
    if at then
      code = tonumber(raw:sub(at + 14):match("%d+"))
      body = raw:sub(1, at - 1)
    end
    outbox:push({id = req.id, out = body, code = code or -1, err = not ok and tostring(err) or nil})
  end
end
