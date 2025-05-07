type GarbageImpl = {
    __index: (self: Garbage, key: any) -> RBXScriptConnection | Instance?,
    __newindex: (self: Garbage, key: any, value: RBXScriptConnection | Instance?) -> (),
    __iter: (self: Garbage) -> (typeof(next), { [any]: RBXScriptConnection | Instance }),

    Sweep: (self: Garbage) -> (),
    
    new: () -> Garbage
}

export type Garbage = typeof(setmetatable(
    {} :: { Connections: { [any]: RBXScriptConnection | Instance } },
    {} :: GarbageImpl
))

--- Lazy truncated version of a maid service
local Garbage: GarbageImpl = {} :: GarbageImpl
function Garbage:__index(key) : RBXScriptConnection | Instance?
    if Garbage[key] then
        return Garbage[key]
    end
    return self.Connections[key]
end

function Garbage:__newindex(key: any, value: RBXScriptConnection | Instance?)
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