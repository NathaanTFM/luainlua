local loadstring = require("loadstring")

local og_eventChatCommand = eventChatCommand

function eventChatCommand(name, command)
    if command:sub(1, 5) == "eval " then
        local script = command:sub(6)
        local status, func = pcall(loadstring, script)
        if status then
            pcall(func)
        end
        
    elseif og_eventChatCommand ~= nil then
        return og_eventChatCommand(name, command)
    end
end