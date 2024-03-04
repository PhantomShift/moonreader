--- Lazy truncated version of a maid service
local Garbage = {}

function Garbage:__index(key) : RBXScriptConnection
    if Garbage[key] then
        return Garbage[key]
    end
    return self.Connections[key]
end

function Garbage:__newindex(key: any, value: RBXScriptConnection?)
    local old = self.Connections[key]
    if old ~= nil then
        if typeof(old) == "Instance" then
            old:Destroy()
        else
            old:Disconnect()
        end
        self.Connections[key] = nil
    end
    self.Connections[key] = value
end

function Garbage:__iter()
    return next, self.Connections
end

function Garbage:Sweep()
    for k in self do
        self[k] = nil
    end
end

---@return Garbage
function Garbage.new()
    local inner = {Connections = {}}

    return setmetatable(inner, Garbage)
end

return Garbage