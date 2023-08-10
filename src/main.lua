local loadstring = require("loadstring")
local env = _G or _ENV

env.loadstring = loadstring

local og_eventChatCommand = eventChatCommand

local function sanitize(str)
    return str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end
    
function eventChatCommand(name, command)
    if command:sub(1, 5) == "eval " then
        local script = command:sub(6)
        local status, func = pcall(loadstring, script)
        if status then
            local status, ret = pcall(func)
            if status then
                --ui.addPopup(0x4e415421, 0, "<text align='center'>Eval OK", name, (800 - 300) / 2, 100, 300, true)
            else
                ui.addPopup(0x4e415421, 0, "<text align='center'>Eval error: " .. sanitize(tostring(ret)), name, 50, 50, nil, true)
                print(tostring(ret))
            end
        else
            ui.addPopup(0x4e415421, 0, "<text align='center'>Parse error: " .. sanitize(tostring(func)), name, 50, 50, nil, true)
            print(tostring(func))
        end
        
    elseif og_eventChatCommand ~= nil then
        return og_eventChatCommand(name, command)
    end
end