local utils = require("utils")
local contains = utils.contains
local get_identifier = utils.get_identifier
local dump = utils.dump
local print = utils.print

-- table of lua keywords
local keywords = {
    'function',
    'elseif', 'repeat', 'return',
    'break', 'false', 'local', 'until', 'while',
    'else', 'then', 'true',
    'and', 'end', 'for', 'nil', 'not',
    'do', 'if', 'in', 'or'
}

-- table of lua tokens sorted by reversed length
local tokens = {
    '...',
    '..', '~=', '==', '<=', '>=',
    '+', '-', '*', '/', '%', '^', '<', '>', '#', '=', '.',
    '(', ')', '[', ']', '{', '}', ',', ';', ':'
}

-- our beautiful lexer
local LuaLexer = {}

-- metatable for instances
local metatable = {}

metatable.__tostring = function()
    return "LuaLexer: " .. get_identifier(elt)
end

-- instance creator
local function new(cls, script)
    local self = {}
    setmetatable(self, metatable)
    
    -- current position (READ-ONLY, use setpos)
    local position = 1
    
    -- current character
    local current = string.sub(script, 1, 1)
    
    -- history
    local history = {}
    
    local function lex_error(str)
        local row, col = self.get_row_col()
        print("\nCurrent: " .. self.dump())
        error("lex error at line " .. row ..": " .. str, 0)
    end
    
    -- skips to the next character
    local function skip(count)
        if count == nil then
            count = 1
        end
        position = position + count
        current = string.sub(script, position, position)
    end
    
    -- read the n next characters
    local function peek(length)
        return string.sub(script, position, position+length-1)
    end
    
    local function setpos(pos)
        position = pos
        current = string.sub(script, position, position)
    end
    
    local function strip()
        while true do
            -- skip to next non empty character
            local target = string.find(script, "[^\n\r\t ]", position)
            if target == nil then target = #script+1 end -- eof
            
            if target ~= position then
                -- new position
                setpos(target)
                
            else
                -- we're already at a non empty character. check for comments
                if peek(2) ~= "--" then
                    break
                    
                else
                    -- check if it's a long comment
                    local equals = string.match(script, "^--%[(=*)%[", position)
                    if equals ~= nil then
                        -- definitely a long comment
                        target = string.find(script, "%]" .. equals .. "%]", position)
                        if target == nil then
                            lex_error("long comment not closed")
                        end
                        setpos(target+#equals+2)
                        
                    else
                        -- otherwise, it's a single-line comment, just read until next \n
                        target = string.find(script, "\n", position, true)
                        if target == nil then target = #script end -- eof
                        
                        setpos(target+1)
                    end
               end
            end
        end
    end
    
    local function read_token()
        local cached = ""
        for _, token in pairs(tokens) do
            if #cached ~= #token then cached = peek(#token) end
            if cached == token then
                skip(#token)
                return token
            end
        end
        return nil
    end
    
    local function read_name()
        local name = string.match(script, "^[a-zA-Z_][a-zA-Z0-9_]*", position)
        if name ~= nil then
            skip(#name)
            return name
        end
        return nil
    end
    
    local function read_string_escape()
        -- error if invalid
        if current ~= "\\" then
            lex_error("invalid string escape")
        end
        skip(1)
        
        -- check for \xxx
        local integer = string.match(script, "^([0-9]+)", position) 
        if integer ~= nil then
            local value = tonumber(integer)
            if value > 255 then
                lex_error("escape sequence too large")
            end
            skip(#integer)
            return string.char(value)
        end
        
        local c = current
        if c == "" then
            lex_error("eof while parsing string escape")
        end
        skip(1)
        
        if c == "a" then
            return "\a"
        elseif c == "b" then
            return "\b"
        elseif c == "f" then
            return "\f"
        elseif c == "n" then
            return "\n"
        elseif c == "r" then
            return "\r"
        elseif c == "t" then
            return "\t"
        elseif c == "v" then    
            return "\v"
        else
            return c
        end
    end
    
    local function read_long_string()
        local equals = string.match(script, "^%[(=+)%[", position)
        if equals == nil then
            return nil
        end
        
        skip(2+#equals)
        
        -- special case: if the first character is a newline, skip it
        if current == "\n" then skip(1) end
        
        local closing = "]" .. equals .. "]"
        local str = ""
        
        while true do
            if current == "" then
                lex_error("eof while reading string")
                
            elseif current == "]" then
                if peek(#closing) == closing then
                    skip(#closing)
                    break
                else
                    str = str .. current
                    skip(1)
                end
                
            else
                str = str .. current
                skip(1)
            end
        end
        
        return str
    end
    
    local function read_quote_string()
        if current ~= '"' and current ~= "'" then
            return nil
        end
        
        local quote = current
        skip(1)
        
        local str = ""
        
        while true do
            if current == "\\" then
                -- read escape
                str = str .. read_string_escape()
                
            elseif current == quote then
                -- skip closing quote
                skip(1)
                break
                
            elseif current == "" then
                lex_error("eof while reading string")
                
            elseif current == "\n" then
                lex_error("unexpected newline in string")
                
            else
                -- any character
                str = str .. current
                skip(1)
            end
        end
        
        return str
    end
    
    local function read_string()
        local str = read_quote_string()
        if str == nil then
            str = read_long_string()
        end
        return str
    end
    
    local function read_number()
        local value = string.match(script, "^0[xX][0-9a-fA-F]+", position)
        if value ~= nil then
            -- just hexadecimal, lua 5.1 doesnt have decimal or power,
            -- so we can just return it
            assert(tonumber(value) ~= nil, "failed to read number")
            skip(#value)
            return tonumber(value)
        end
        
        -- then it's not hexadecimal
        
        -- optional integer, mandatory decimal
        value = string.match(script, "^([0-9]*%.[0-9]+)", position)
        
        if value == nil then
            -- integer only?
            value = string.match(script, "^([0-9]+)", position)
        end
        
        if value == nil then
            -- not a number (i mean, literally)
            return nil
        end
        
        -- okay, now we figured that it's such number. let's read it
        skip(#value)
        
        -- is there any exponential part?
        local exponential = string.match(script, "^([eE]%-?[0-9]+)", position)
        if exponential ~= nil then
            skip(#exponential)
            value = value .. exponential
        end
        
        -- try to read any exponential part that the number might have
        assert(tonumber(value) ~= nil, "failed to read number")
        return tonumber(value)
    end
    
    local function reset_value()
        self.eof = false
        self.keyword = nil
        self.name = nil
        self.number = nil
        self.string = nil
        self.token = nil
    end
    
    self.next = function()
        strip()
        
        history[1] = history[2]
        history[2] = position
        
        reset_value()
        
        if current == "" then
            -- reached EOF
            self.eof = true
            return
        end
        
        local name = read_name()
        if name ~= nil then
            if contains(keywords, name) then
                self.keyword = name
            else
                self.name = name
            end
            return
        end
        
        local number = read_number()
        if number ~= nil then
            self.number = number
            return
        end
        
        local str = read_string()
        if str ~= nil then
            self.string = str
            return
        end 
        
        local token = read_token()
        if token ~= nil then
            self.token = token
            return
        end
        
        lex_error("unexpected \"" .. peek(1) .. "\"")
    end
    
    self.dump = function()
        if self.eof == true then
            return "end-of-file"
        elseif self.keyword ~= nil then
            return "keyword " .. dump(self.keyword) .. ""
        elseif self.name ~= nil then
            return "name " .. dump(self.name) .. ""
        elseif self.string ~= nil then
            return "string " .. dump(self.string) .. ""
        elseif self.number ~= nil then
            return "number " .. dump(self.number) .. ""
        elseif self.token ~= nil then
            return "token " .. dump(self.token) .. ""
        else
            return "unknown"
        end
    end
    
    local cached_row = 1
    local cached_col = 1
    local cached_pos = 1
    
    -- XXX very slow
    self.get_row_col = function()
        while cached_pos < position do
            local target = string.find(script, "\n", cached_pos, true)
            if target == nil or target > position then
                break
            else
                cached_row = cached_row + 1
                cached_pos = target + 1
            end 
        end
        return cached_row, cached_col
    end
    
    self.restore = function()
        if history[1] == nil then
            lex_error("cannot restore")
        end
        setpos(history[1])
        history = {}
        self.next()
    end
    
    -- read first one
    self.next()
    return self
end

-- metatable for class
setmetatable(LuaLexer, {
    __call = new,
    
    __tostring = (function(elt)
        return "LuaLexer"
    end)
})

return LuaLexer