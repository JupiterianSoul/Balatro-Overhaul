local Nav = {}
Nav.__index = Nav

Nav.MAX = 16

function Nav.new(same)
    return setmetatable({stack = {}, cur = nil, same = same or function() return false end}, Nav)
end

function Nav:reset()
    self.stack = {}
    self.cur = nil
end

function Nav:depth()
    return #self.stack
end

function Nav:matches(entry, name, fp, safe)
    if not entry then return false end
    if name and entry.name == name then return true end
    if safe and name and entry.name then return false end
    if fp == nil or entry.fp == nil then return false end
    local ok, same = pcall(self.same, entry.fp, fp)
    return ok and same and true or false
end

function Nav:opened(o)
    local entry = {name = o.name, arg = o.arg, fp = o.fp, safe = o.safe and true or false}
    if o.reopening then
        self.cur = o.reopening
        if o.fp ~= nil then self.cur.fp = o.fp end
        return "reopen", self.cur
    end
    if not o.was_open then
        self.stack = {}
        self.cur = entry
        return "fresh", entry
    end
    if self:matches(self.cur, o.name, o.fp, o.safe) then
        if o.fp ~= nil then self.cur.fp = o.fp end
        return "refresh", self.cur
    end
    for i = #self.stack, 1, -1 do
        local e = self.stack[i]
        if self:matches(e, o.name, o.fp, o.safe) then
            for j = #self.stack, i, -1 do self.stack[j] = nil end
            if o.fp ~= nil then e.fp = o.fp end
            self.cur = e
            return "return", e
        end
    end
    if o.backing then
        self.stack = {}
        self.cur = entry
        return "jump", entry
    end
    if self.cur and self.cur.safe then
        self.cur.tabs = o.tabs
        self.stack[#self.stack + 1] = self.cur
        while #self.stack > Nav.MAX do table.remove(self.stack, 1) end
    else
        self.stack = {}
    end
    self.cur = entry
    return "forward", entry
end

function Nav:back()
    return table.remove(self.stack)
end

return Nav
