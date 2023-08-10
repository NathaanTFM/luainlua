local utils = require("utils")
local contains = utils.contains
local get_identifier = utils.get_identifier
local dump = utils.dump
local print = utils.print

local LuaLexer = require("lexer")

-- parser class
local LuaParser = {}

-- metatable for instances
local metatable = {}

metatable.__tostring = function()
    return "LuaParser: " .. get_identifier(elt)
end

local function new(cls, script, chunkname)
    if type(chunkname) ~= "string" then
        chunkname = "[string]"
    end
    
    local self = {}
    setmetatable(self, metatable)
    
    local lexer = LuaLexer(script, chunkname)
    
    local function parse_error(str)
        local row, col = lexer.get_row_col()
        print("Current: " .. lexer.dump())
        error(chunkname .. ":" .. row ..": " .. str, 0)
    end
    
    -- binary operators and their [left, right] priority
    local binary_ops = {
        ["+"] = {10, 10}, ["-"] = {10, 10},
        ["*"] = {11, 11}, ["%"] = {11, 11},
        ["^"] = {14, 13},
        ["/"] = {11, 11},
        [".."] = {9, 8},
        ["=="] = {3, 3}, ["<"] = {3, 3}, ["<="] = {3, 3},
        ["~="] = {3, 3}, [">"] = {3, 3}, [">="] = {3, 3},
        ["and"] = {2, 2}, ["or"] = {1, 1}
    }
    
    local unary_ops = {["not"] = 12, ["-"] = 12, ["#"] = 12} -- they must all have the same priority
    
    -- read_xx: raises error if it doesn't match
    -- parse_xx: returns nil if it doesn't match
    
    local read_expr, parse_stmt
    
    local function expect_token(token)
        if lexer.token ~= token then
            parse_error("expected '" .. token .. "', got " .. lexer.dump())
        end
        lexer.next()
    end
    
    local function expect_keyword(keyword)
        if lexer.keyword ~= keyword then
            parse_error("expected '" .. keyword .. "', got " .. lexer.dump())
        end
        lexer.next()
    end
    
    local function expect_name()
        local name = lexer.name
        if name == nil then
            parse_error("expected name, got " .. lexer.dump())
        end
        lexer.next()
        return name
    end
    
    local function read_table_field()
        if lexer.token == '[' then
            lexer.next()
            
            local expr = read_expr()
            expect_token(']')
            expect_token('=')
            
            local value = read_expr()
            return {type = "expr", expr = expr, value = value}
            
        elseif lexer.name ~= nil then
            local name = lexer.name
            lexer.next()
            
            if lexer.token == '=' then
                lexer.next()
                
                local value = read_expr()
                return {type = "name", name = name, value = value}
                
            else
                -- was an expression. restore
                lexer.restore()
            end
        end
        
        local value = read_expr()
        return {type = "value", value = value}
    end
    
    local function read_table_expr()
        -- lua tables accept both "," and ";" as separators
        expect_token('{')
        
        local fields = {}
        
        if lexer.token ~= '}' then
            while true do
                local field = read_table_field()
                table.insert(fields, field)
                
                if lexer.token ~= ',' and lexer.token ~= ';' then
                    break
                else 
                    lexer.next()
                    
                    -- there was an extra comma
                    if lexer.token == '}' then
                        break
                    end
                end
            end
        end
        
        expect_token('}')
        return {type = "table", fields = fields}
    end
    
    local function read_params()
        expect_token('(')
        
        local params = {positional = {}, vararg = false}
        
        if lexer.token ~= ')' then
            while true do
                if lexer.name ~= nil then
                    table.insert(params.positional, lexer.name)
                    lexer.next()
                    
                elseif lexer.token == "..." then
                    params.vararg = true
                    lexer.next()
                    
                else
                    parse_error("cannot read param")
                end
                
                if lexer.token == "," then
                    lexer.next()
                else
                    break
                end
            end
        end
        
        expect_token(')')
        
        return params
    end
    
    local function is_block_end()
        return (lexer.keyword == "end" or lexer.keyword == "else" or lexer.keyword == "elseif" or lexer.keyword == "until")
    end
        
    local function read_body()
        local body = {}
        
        while not is_block_end() do
            local stmt = parse_stmt()
            if stmt == nil then
                parse_error("cannot read stmt")
            end
            table.insert(body, stmt)
        end
        
        return body
    end
    
    local function read_body_end()
        local body = read_body()
        expect_keyword("end")
        return body
    end
    
    local function read_function_expr()
        expect_keyword("function")
        local params = read_params()
        local body = read_body_end()
        
        return {type = "function", params = params, body = body}
    end
    
    local function read_values()
        local values = {}
        
        while true do
            local expr = read_expr()
            table.insert(values, expr)
            
            if lexer.token == "," then
                lexer.next()
            else
                break
            end
        end
        
        return values
    end
    
    local function parse_args()
        if lexer.token == '(' then
            local args = {}
            lexer.next()
            
            if lexer.token ~= ')' then
                args = read_values()
            end
            
            expect_token(')')
            return args
            
        elseif lexer.token == '{' then
            local args = {}
            table.insert(args, read_table_expr())
            return args
        
        elseif lexer.string ~= nil then
            local args = {}
            table.insert(args, {type = "constant", value = lexer.string})
            lexer.next()
            return args
            
        else
            return nil
        end
    end
    
    local function read_suffixed_expr()
        -- read primary expr
        local ret
        if lexer.token == "(" then
            lexer.next()
            ret = read_expr()
            expect_token(')')
            
        elseif lexer.name ~= nil then
            ret = {type = "name", name = lexer.name}
            lexer.next()
            
        else
            parse_error("expected '(' or name")
        end
        
        while true do
            if lexer.token == "." then
                lexer.next()
                
                local name = expect_name()
                ret = {type = "index", value = ret, name = name}
                
            elseif lexer.token == "[" then
                lexer.next()
                
                local expr = read_expr()
                ret = {type = "index", value = ret, expr = expr}
                
                expect_token(']')
                
            elseif lexer.token == ":" then
                lexer.next()
                
                local name = expect_name()
                local args = parse_args()
                if args == nil then
                    parse_error("expected call args")
                end
                
                ret = {type = "invoke", value = ret, name = name, args = args}
                
            else
                -- attempt at call args
                local args = parse_args()
                if args ~= nil then
                    ret = {type = "call", value = ret, args = args}
                else
                    break
                end
            end
        end
        
        return ret
        -- .name, [exp], :name funcargs, funcargs
    end
    
    local function read_simple_expr()
        local ret = nil
        
        -- constants
        if lexer.number ~= nil then
            ret = {type = "constant", value = tonumber(lexer.number)}
            lexer.next()
            
        elseif lexer.string ~= nil then
            ret = {type = "constant", value = lexer.string}
            lexer.next()
            
        elseif lexer.keyword == "nil" then
            ret = {type = "constant", value = nil}
            lexer.next()
            
        elseif lexer.keyword == "true" then
            ret = {type = "constant", value = true}
            lexer.next()
            
        elseif lexer.keyword == "false" then
            ret = {type = "constant", value = false}
            lexer.next()
            
        elseif lexer.token == "..." then
            ret = {type = "vararg"}
            lexer.next()
            
        -- special
        elseif lexer.token == "{" then
            ret = read_table_expr()
            
        elseif lexer.keyword == "function" then
            ret = read_function_expr()
            
        elseif lexer.name ~= nil or lexer.token == '(' then
            ret = read_suffixed_expr()
        end
        
        if ret == nil then
            parse_error("expected expression, got " .. lexer.dump())
        end
        
        return ret
    end
    
    read_expr = function(limit)
        if limit == nil then limit = 0 end
        
        -- read an expression
        local left
        local uop = lexer.keyword or lexer.token
        if unary_ops[uop] ~= nil then
            lexer.next()
            left = {type = "unary", uop = uop, value = read_expr(unary_ops[uop])}
        else
            left = read_simple_expr()
        end
        
        local op = lexer.keyword or lexer.token
        while binary_ops[op] ~= nil and binary_ops[op][1] > limit do
            lexer.next()
            local right = read_expr(binary_ops[op][2])
            left = {type = "binary", left = left, op = op, right = right}
            op = lexer.keyword or lexer.token
        end
        
        return left
    end
    
    local function read_local_function()
        assert(lexer.keyword == "function")
        lexer.next()
        
        local name = expect_name()
        local params = read_params()
        local body = read_body_end()
        
        return {type = "local_function", name = name, params = params, body = body}
    end
    
    local function read_local_variable()
        local targets = {}
        
        while true do
            table.insert(targets, expect_name())
            
            if lexer.token == "," then
                lexer.next()
            else
                break
            end
        end
        
        local values = nil
        
        if lexer.token == "=" then
            lexer.next()
            values = read_values()
        end
        
        return {type = "local_assign", targets = targets, values = values}
    end
    
    local function parse_function()
        if lexer.keyword ~= "function" then
            return nil
        end
        lexer.next()
        
        -- name of the function
        local name = {}
        table.insert(name, expect_name())
        
        while lexer.token == "." do
            lexer.next()
            table.insert(name, expect_name())
        end
        
        local method = (lexer.token == ':')
        if method then
            lexer.next()
            table.insert(name, expect_name())
        end
        
        local params = read_params()
        local body = read_body_end()        
        return {type = "function", name = name, method = method, params = params, body = body}
    end
    
    local function parse_local()
        if lexer.keyword ~= "local" then
            return nil
        end
        
        lexer.next()
        
        if lexer.keyword == "function" then
            return read_local_function()
            
        elseif lexer.name ~= nil then
            return read_local_variable()
            
        else
            parse_error("exported 'function' or name")
        end
    end
    
    local function parse_if()
        if lexer.keyword ~= "if" then
            return nil
        end
        
        lexer.next()
        
        local cond = read_expr()
        expect_keyword("then")
        
        local body = read_body()
        local elseifs = {}
        local elsebody = nil
        
        while lexer.keyword == "elseif" do
            lexer.next()
            
            local cond = read_expr()
            expect_keyword("then")
            
            local elseifbody = read_body()
            
            table.insert(elseifs, {cond = cond, body = elseifbody})
        end
        
        if lexer.keyword == "else" then
            lexer.next()
            elsebody = read_body()
        end
        
        expect_keyword("end")
        
        return {type = "if", cond = cond, body = body, elseifs = elseifs, elsebody = elsebody}
    end
    
    local function parse_while()
        if lexer.keyword ~= "while" then
            return nil
        end
        
        lexer.next()
        
        local cond = read_expr()
        expect_keyword("do")
        
        local body = read_body_end()
        return {type = "while", cond = cond, body = body}
    end
    
    local function parse_repeat()
        if lexer.keyword ~= "repeat" then
            return nil
        end
        
        lexer.next()
        
        local body = read_body()
        expect_keyword("until")
        local cond = read_expr()
        
        return {type = "repeat", cond = cond, body = body}
    end
    
    local function parse_break()
        if lexer.keyword ~= "break" then
            return nil
        end
        
        lexer.next()
        
        return {type = "break"}
    end
    
    local function is_assignable(expr)
        return expr.type == "index" or expr.type == "name"
    end
    
    local function parse_assign_or_call()
        if lexer.name == nil and lexer.token ~= '(' then
            return nil
        end
        
        local expr = read_suffixed_expr()
        
        if lexer.token == "," or lexer.token == "=" then
            -- it's an assign
            local targets = {}
            
            if not is_assignable(expr) then
                parse_error("cannot assign to expr")
            end
            
            table.insert(targets, expr)
            
            while lexer.token == "," do
                lexer.next()
                
                expr = read_suffixed_expr()
                if not is_assignable(expr) then
                    parse_error("cannot assign to expr")
                end
                table.insert(targets, expr)
            end
                
            expect_token("=")
            
            -- read values
            local values = read_values()
            return {type = "assign", targets = targets, values = values}
            
        else
            -- should we check if it's a call?
            -- lua does this check, but it might be useless
            return {type = "expr", expr = expr}
        end
        
    end
    
    local function parse_return()
        if lexer.keyword ~= "return" then
            return nil
        end
        
        lexer.next()
        
        local values = {}
        if not is_block_end() and lexer.token ~= ";" then
            values = read_values()
        end
        
        return {type = "return", values = values}
    end
    
    local function parse_do()
        if lexer.keyword ~= "do" then
            return nil
        end
        
        lexer.next()
        local body = read_body_end()
        
        return {type = "do", body = body}
    end
    
    local function parse_for()
        if lexer.keyword ~= "for" then
            return nil
        end
        
        lexer.next()
        
        -- two for loops:
        -- for targets in expressions do
        -- for target = start, stop, step do
        local target = expect_name()
        
        if lexer.token == "=" then
            -- start, stop(, step)
            lexer.next()
            
            local start = read_expr()
            expect_token(",")
            local stop = read_expr()
            local step = nil
            if lexer.token == "," then
                lexer.next()
                step = read_expr()
            end
            
            expect_keyword("do")
            local body = read_body_end()
            
            return {type = "fornum", target = target, start = start, stop = stop, step = step, body = body}
            
        elseif lexer.keyword == "in" or lexer.token == "," then
            local targets = {target}
            
            while lexer.token == "," do
                lexer.next()
                table.insert(targets, expect_name())
            end
            
            expect_keyword("in")
            
            local values = read_values()
            expect_keyword("do")
            
            local body = read_body_end()
            
            return {type = "forin", targets = targets, values = values, body = body}
        end     
    end
        
    parse_stmt = function()
        while lexer.token == ";" do lexer.next() end
        
        -- XXX VERY SLOW
        local row, col = lexer.get_row_col()
        
        local ret = (parse_function()
            or parse_local()
            or parse_if()
            or parse_while()
            or parse_return()
            or parse_do()
            or parse_break()
            or parse_for()
            or parse_repeat()
            or parse_assign_or_call()
        )
        if not ret then
            error("** parse_stmt failed: " .. lexer.dump())
        end
        
        ret._chunk = chunkname
        ret._row = row
        ret._col = col
        
        return ret
    end
    
    self.body = {}
    
    while not lexer.eof do
        local stmt = parse_stmt()
        if not stmt then
            parse_error("unexpected " .. lexer.dump())
        end
        
        table.insert(self.body, stmt)
    end

    return self
end

-- metatable for class
setmetatable(LuaParser, {
    __call = new,
    
    __tostring = (function(elt)
        return "LuaParser"
    end)
})

return LuaParser