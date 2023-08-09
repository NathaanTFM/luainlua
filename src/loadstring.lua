local LuaParser = require("parser")
local create_function = require("interpreter")

return function(script)
    local parser = LuaParser(script)
    local func = create_function(parser.body)
    return func
end