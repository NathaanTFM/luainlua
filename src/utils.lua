-- custom contains function is useful
local function contains(haystack, needle)
    for k,v in pairs(haystack) do
        if v == needle then
            return true 
        end
    end
    return false
end

-- get identifier function
local function get_identifier(elt)
    local mt = getmetatable(elt)
    setmetatable(elt, nil)
    local typename, address = string.match(tostring(elt), "^([a-z]+): ([a-fA-F0-9]+)$")
    setmetatable(elt, mt)
    if typename == type(elt) then
        return address
    end
    return "(lost)"
end

-- dump_value is defined later
local dump_value

-- dumps a string with quotes
local function dump_string(str)
    str = string.gsub(str, "\\", "\\\\")
    str = string.gsub(str, "'", "\\'")
    str = string.gsub(str, "\n", "\\n")
    str = string.gsub(str, "\r", "\\r")
    str = string.gsub(str, "\t", "\\t")
    
    local ret = "'"
    ret = ret .. str
    ret = ret .. "'"
    return ret
end

-- dumps a table, checks for recursion
local function dump_table(tbl, recursion)
    if recursion == nil then
        recursion = {}
    end
    
    if contains(recursion, tbl) then
        return "(" .. tostring(tbl) .. ")"
    end
    
    table.insert(recursion, tbl)
    
    local ret = "{"
    local flag = false
    
    for k,v in pairs(tbl) do
        if flag then
            ret = ret .. ", "
        else
            flag = true
        end
        
        -- special check for key
        local car = string.sub(k, 1, 1)
        if string.match(car, "^[a-zA-Z_][a-zA-Z0-9_]*$") then
            ret = ret .. k
        else
            ret = ret .. "[" .. dump_value(k, recursion) .. "]"
        end
        
        ret = ret .. " = "
        ret = ret .. dump_value(v, recursion)
    end
    
    ret = ret .. "}"
    return ret
end

dump_value = function(elt, recursion)
    local typeof = type(elt)
    
    if typeof == "string" then
        -- check if it starts with a letter or underscore
        return dump_string(elt, recursion)
        
    elseif typeof == "table" then
        return dump_table(elt, recursion)
        
    elseif typeof == "function" or typeof == "thread" then
        -- we cannt read functions or threads
        return "(" .. tostring(elt) .. ")"
        
    else
        -- nil, boolean, number
        return tostring(elt)
    end
end

-- custom dump function, dumps tables without recursive values
--[[local function dump(...)
    local args = table.pack(...)
    local message = ""
    for i = 1, args.n do
        if i ~= 1 then
            message = message .. "  "
        end
        message = message .. dump_value(args[i])
    end
    _G.print(message)
end]]--

-- custom print function that tostrings everything
local function print(...)
    local args = pack(...)
    local message = ""
    for i = 1, args.n do
        if i ~= 1 then
            message = message .. "  "
        end
        message = message .. tostring(args[i])
    end
    _G.print(message)
end

return {
    dump = dump_value,
    print = print,
    contains = contains,
    get_identifier = get_identifier
}