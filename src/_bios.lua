do
    -- modules are in this environment
    local require -- defined later
    
    -- better minification output?
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

    -- custom pack and unpack functions
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
    
    -- define require, pass modules as a parameter
    require = (function(modules)
        local loaded = {}
        
        return function(name, ...)
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
    end)(--[[ XXX modules here ]]--)

    require("main")
end