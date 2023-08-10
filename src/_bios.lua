do
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
    
    -- we don't want to interfere with global, so let's call those pack and unpack
    local function pack(...)
        return {n = select('#', ...); ...}
    end

    local _unpack = unpack or table.unpack    
    local function unpack(tbl, i, j)
        if i == nil then i = 1 end
        if j == nil then j = tbl.n end
        if j == nil then j = #tbl end -- if tbl.n is nil
        return _unpack(tbl, i, j)
    end

    local require
    local modules = {}
    local loaded = {}
    
    -- XXX INSERT MODULES HERE
    
    require = function(name, ...)
        if loaded[name] ~= nil then
            return unpack(loaded[name])
            
        elseif modules[name] ~= nil then
            loaded[name] = pack(modules[name](...))
            modules[name] = nil
            return unpack(loaded[name])
            
        else
            error("module '" .. name .. "' not found")
        end
    end

    require("main")
end