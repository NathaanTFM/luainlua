-- util for minifiers
local getmetatable = _G.getmetatable
local table = _G.table
local pairs = _G.pairs
local ipairs = _G.ipairs
local type = _G.type
local string = _G.string
local setmetatable = _G.setmetatable
local select = _G.select
local tostring = _G.tostring
local next = _G.next

-- add table.pack if missing
if table.pack == nil then
    -- https://github.com/lunarmodules/Penlight/blob/master/lua/pl/compat.lua
    function table.pack(...)
        return {n = select('#', ...); ...}
    end
end

-- add table.unpack if missing
if table.unpack == nil then
    function table.unpack(...)
        local args = table.pack(...)
        if args.n ~= 1 then
            print("args.n", args.n)
            error("extra args on table.unpack")
        end
        return unpack(args[1], 1, args[1].n)
    end
end

local argv = table.pack(...)

local require
do
    local modules = {}
    local loaded = {}
    
    -- XXX INSERT MODULES HERE
    
    require = function(name, ...)
        if loaded[name] ~= nil then
            return table.unpack(loaded[name])
            
        elseif modules[name] ~= nil then
            loaded[name] = table.pack(modules[name](...))
            modules[name] = nil
            return table.unpack(loaded[name])
            
        else
            error("module '" .. name .. "' not found")
        end
    end
end

require("main")
