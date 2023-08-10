local LuaParser = require("parser")
local create_function = require("interpreter")

local loadstring = function(script, chunkname, globals)
    local status, parser = pcall(function()
        return LuaParser(script, chunkname)
    end)
    if not status then
        -- parser is error message
        return nil, parser
    end
    local func = create_function(parser.body, globals)
    return func
end

return loadstring