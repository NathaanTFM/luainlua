local loadstring = require("loadstring")
local env = _G or _ENV

env.loadstring = loadstring

local og_eventChatCommand = eventChatCommand

local function sanitize(str)
    return tostring(str):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end
    
function eventChatCommand(name, command)
    if command:sub(1, 5) == "eval " then
        local script = command:sub(6)
        
        local status, err = pcall(function()
            local func, err = loadstring(script)
            if not func then
                error(err, 0)
            end
            
            local ret = func()
        end)
        
        if not status then
            ui.addPopup(0x4e415421, 0, "<text align='center'>Lua error: " .. sanitize(err), name, 50, 50, nil, true)
        end
        
    elseif og_eventChatCommand ~= nil then
        return og_eventChatCommand(name, command)
    end
end