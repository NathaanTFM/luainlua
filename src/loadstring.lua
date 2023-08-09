local LuaParser = require("parser")
local create_function = require("compiler")

return function(script)
    local parser = LuaParser(script)
    local func = create_function(parser.body)
    return func
end