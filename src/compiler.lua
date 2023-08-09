local utils = require("utils")
local contains = utils.contains
local get_identifier = utils.get_identifier
local dump = utils.dump
local print = utils.print

local gen = require("generator")()

local function dump_expr(expr)
    gen.buffer = ""
    gen.add_expression(expr)
    return gen.buffer
end

local create_function_internal

local function create_instance(body, params, initblocks)
    -- blocks
    local blocks = {table.unpack(initblocks)}
    
    local varargs = {value = nil}
    
    local evaluate_expr, evaluate_stmt
    local debug_cur_stmt
    
    local function on_error(message)
        error("error on line " .. debug_cur_stmt._row .. ": " .. message)
    end
     
    local function debug_locals()
        print()
        print("-- debug_locals --")
        
        for k,v in ipairs(blocks) do
            print("-> block " .. k)
            for k2, v2 in pairs(v.locals) do
                print("    ", k2, dump(v2.value):sub(1, 40))
            end
            print()
        end
        print()
        
    end
    
    local function push_block()
        local prev = blocks[#blocks]
        
        local block = {
            locals = {},
        }
        table.insert(blocks, block)
    end
    
    local function pop_block()
        table.remove(blocks)
    end
    
    local function search_local(name)
        for i = #blocks, 1, -1 do
            local block = blocks[i]
            if block.locals[name] ~= nil then
                return block.locals[name]
            end 
        end
        return nil
    end
    
    local function add_local(name, value)
        local block = blocks[#blocks]
        block.locals[name] = {value = value}
    end
    
    local function pack_values(values)
        local tbl = {}
        tbl.n = 0 -- in case its empty
        
        if values ~= nil then
            for i, value in ipairs(values) do
                if i == #values then
                    -- multiple elements
                    local packed = table.pack(evaluate_expr(value))
                    for j = 1, packed.n do
                        tbl[i+j-1] = packed[j]
                    end
                    tbl.n = i+packed.n-1
                    
                else
                    -- single element
                    local res = evaluate_expr(value)
                    tbl[i] = res
                end
            end
        end
        
        return tbl
    end
    
    evaluate_expr = function(expr)
        if expr.type == "index" then
            local value = evaluate_expr(expr.value)
            if value == nil then
                on_error("attempt to index a nil value (" .. dump_expr(expr.value) .. ")")
            end
            
            if expr.name ~= nil then
                return value[expr.name]
            else
                local expr = evaluate_expr(expr.expr)
                return value[expr]
            end
            
        elseif expr.type == "name" then            
            local loc = search_local(expr.name)
            if loc ~= nil then
                return loc.value
            else
                --print("using global for " .. expr.name)
                return _G[expr.name]
            end
            
        elseif expr.type == "unary" then
            local value = evaluate_expr(expr.value)
            if expr.uop == "-" then return -value end
            if expr.uop == "#" then return #value end
            if expr.uop == "not" then return not value end
            error("uop: " .. expr.uop)
            
        elseif expr.type == "binary" then
            -- special case for "and" and "or": lazy
            local left = evaluate_expr(expr.left)
            if expr.op == "and" then
                if left then
                    return evaluate_expr(expr.right)
                else
                    return left
                end 
                
            elseif expr.op == "or" then
                if not left then
                    return evaluate_expr(expr.right)
                else
                    return left
                end
            end
            
            local right = evaluate_expr(expr.right)
            
            if expr.op == "+" then return left + right end
            if expr.op == "-" then return left - right end
            if expr.op == "*" then return left * right end
            if expr.op == "%" then return left % right end
            if expr.op == "^" then return left ^ right end
            if expr.op == "/" then return left / right end
            if expr.op == ".." then return left .. right end
            if expr.op == "==" then return left == right end
            if expr.op == "<" then return left < right end
            if expr.op == "<=" then return left <= right end
            if expr.op == "~=" then return left ~= right end
            if expr.op == ">" then return left > right end
            if expr.op == ">=" then return left >= right end
            
            error("op: " .. expr.op)
            
        elseif expr.type == "constant" then
            return expr.value
            
        elseif expr.type == "table" then
            local ret = {}
            local k = 1
            for i, field in ipairs(expr.fields) do
                -- special case if it's the last one
                if i == #expr.fields and field.type == "value" then
                    local values = table.pack(evaluate_expr(field.value))
                    for j = 1, values.n do
                        ret[k+j-1] = values[j]
                    end
                else
                    local value = evaluate_expr(field.value)
                    
                    if field.type == "name" then
                        ret[field.name] = value
                    elseif field.type == "expr" then
                        local expr = evaluate_expr(field.expr)
                        ret[expr] = value
                    else
                        ret[k] = value
                        k = k + 1
                    end
                end
            end 
            return ret
            
        elseif expr.type == "function" then
            return create_function_internal(expr.body, expr.params, blocks)
            
        elseif expr.type == "call" then
            local value = evaluate_expr(expr.value)
            local args = pack_values(expr.args)
            
            --[[if _G.debugIndent == nil then
                _G.debugIndent = 0
            end
            local indent = string.rep(" ", _G.debugIndent)
            _G.debugIndent = _G.debugIndent + 2
            
            print(indent)
            print(indent, "| -- call --")
            print(indent, "| value:", value)
            print(indent, "| expr.value:", dump_expr(expr.value))
            print(indent, "| args:", dump(args))
            
            if value == nil then
                _G.debugIndent = _G.debugIndent - 2
                error("attempt to call a nil value (" .. dump_expr(expr.value) .. ")")
            end]]--
            
            -- XX local res = table.pack(value(table.unpack(args)))
            
            --_G.debugIndent = _G.debugIndent - 2
            --print(indent, "| res:", dump(res))
            --print(indent)
            
            -- XX return table.unpack(res)
            
            if value == nil then
                -- debug locals
                debug_locals()
                on_error("attempt to call a nil value (" .. dump_expr(expr.value) .. ")")
            end
            return value(table.unpack(args))
            
        elseif expr.type == "invoke" then
            local value = evaluate_expr(expr.value)
            if value == nil then
                on_error("attempt to index a nil value (" .. dump_expr(expr.value) .. ")")
            end
            
            local func = value[expr.name]
            if func == nil then
                on_error("attempt to call a nil value (" .. dump_expr(expr.value) .. ":" .. expr.name .. ")")
            end
            
            local args = pack_values(expr.args)
            
            return func(value, table.unpack(args))
            
            
        elseif expr.type == "vararg" then
            if varargs.value ~= nil then
                return table.unpack(varargs.value)
            else
                on_error("attempt to use varargs in func without varargs")
            end
            
        else
            error("cannot evaluate " .. expr.type)
        end
    end
    
    evaluate_stmt = function(stmt)
        debug_cur_stmt = stmt
        
        local status = 0
        local results = nil
        
        if stmt.type == "local_assign" then
            local tbl = pack_values(stmt.values)
            
            for i, target in ipairs(stmt.targets) do
                add_local(stmt.targets[i], tbl[i])
            end
        
        elseif stmt.type == "assign" then
            local tbl = pack_values(stmt.values)
            
            for i, target in ipairs(stmt.targets) do
                if target.type == "name" then
                    local loc = search_local(target.name)
                    if loc then
                        loc.value = tbl[i]
                    else
                        _G[target.name] = tbl[i]
                    end
                    
                elseif target.type == "index" then
                    local value = evaluate_expr(target.value)
                    if value == nil then
                        debug_locals()
                        on_error("attempt to index a nil value (" .. dump_expr(target.value) .. ")")
                    end
                    
                    if target.name ~= nil then
                        value[target.name] = tbl[i]
                    else
                        local expr = evaluate_expr(target.expr)
                        value[expr] = tbl[i]
                    end
                    
                else
                    error("cannot assign to " .. target.type)
                end
            end
            
        elseif stmt.type == "if" then
            local cond = evaluate_expr(stmt.cond)
            local body = stmt.elsebody
            
            if cond then
                body = stmt.body
            else
                for i, elt in ipairs(stmt.elseifs) do
                    cond = evaluate_expr(elt.cond)
                    if cond then
                        body = elt.body
                        break
                    end
                end
            end
            
            if body ~= nil then
                push_block()
                for _, stmt2 in ipairs(body) do
                    status, results = evaluate_stmt(stmt2)
                    if status > 0 then
                        break
                    end
                end
                pop_block()
            end
            
        elseif stmt.type == "while" then
            local cond = evaluate_expr(stmt.cond)
            local body = stmt.body
            
            while cond do
                push_block()
                for _, stmt2 in ipairs(stmt.body) do
                    status, results = evaluate_stmt(stmt2)
                    if status > 0 then
                        break
                    end
                end
                pop_block()
                
                if status == 1 then
                    break
                elseif status == 2 then
                    status = 0
                    break
                end
                
                cond = evaluate_expr(stmt.cond)
            end
            
        elseif stmt.type == "do" then
            push_block()
            for _, stmt2 in ipairs(stmt.body) do
                status, results = evaluate_stmt(stmt2)
                if status > 0 then
                    break
                end
            end
            pop_block()
            
        elseif stmt.type == "expr" then
            evaluate_expr(stmt.expr)
            
        elseif stmt.type == "local_function" then
            add_local(stmt.name, create_function_internal(stmt.body, stmt.params, blocks))
            
        elseif stmt.type == "function" then
            local params = {positional = {}, vararg = stmt.params.vararg}
            
            if stmt.method then
                table.insert(params.positional, "self")
            end
                
            for k,v in pairs(stmt.params.positional) do
                table.insert(params.positional, v)
            end
            
            local func = create_function_internal(stmt.body, params, blocks)
            local tbl = _G
            for k,v in pairs(stmt.name) do
                if k == #stmt.name then
                    tbl[v] = func
                else
                    tbl = tbl[v]
                end
            end
            
        elseif stmt.type == "return" then
            status = 1
            results = pack_values(stmt.values)
            
            --print("returning results: ", dump(results))
            
        elseif stmt.type == "fornum" then
            local start = evaluate_expr(stmt.start)
            local stop = evaluate_expr(stmt.stop)
            local step = 1
            if stmt.step ~= nil then
                step = evaluate_expr(stmt.step)
            end
            
            for i = start, stop, step do
                push_block()
                add_local(stmt.target, i)
                
                for _, stmt2 in ipairs(stmt.body) do
                    status, results = evaluate_stmt(stmt2)
                    if status > 0 then
                        break
                    end
                end
                
                pop_block()
                
                if status == 1 then
                    break
                elseif status == 2 then
                    status = 0
                    break
                end
            end
            
        elseif stmt.type == "forin" then
            local values = pack_values(stmt.values)
            local v1, v2, v3 = table.unpack(values)
            
            while true do
                local tbl = table.pack(v1(v2, v3))
                v3 = tbl[1]
                
                if v3 == nil then
                    break
                end
                
                push_block()
                
                for i, target in ipairs(stmt.targets) do
                    add_local(stmt.targets[i], tbl[i])
                end
                for _, stmt2 in ipairs(stmt.body) do
                    status, results = evaluate_stmt(stmt2)
                    if status > 0 then
                        break
                    end
                end
                
                pop_block()
                
                if status == 1 then
                    break 
                elseif status == 2 then
                    status = 0
                    break
                end
            end
            -- for loop needs to be manually called
            
        elseif stmt.type == "break" then
            status = 2
            
        else
            error("cannot evaluate statement '" .. stmt.type .. "'")
        end
        
        return status, results
    end
    
    local function run_function(...)
        local tbl = table.pack(...)
        --print("called function tbl = ", dump(tbl))
        
        push_block()
        
        if params ~= nil then
            for i, arg in ipairs(params.positional) do
                add_local(arg, tbl[i])
            end
            
            if params.vararg then
                varargs.value = {}
                varargs.value.n = 0
                for i = #params.positional+1, tbl.n do
                    varargs.value.n = varargs.value.n + 1
                    varargs.value[varargs.value.n] = tbl[i]
                end
            end
        end
        
        local status, results
        for _, stmt in ipairs(body) do
            status, results = evaluate_stmt(stmt)
            --print("done", done)
            if status == 1 then
                break
            elseif status > 1 then
                error("unexpected status " .. status)
            end
        end
        
        pop_block()
        if status == 1 then 
            return table.unpack(results)
        end
    end
    
    return run_function
end


create_function_internal = function(body, params, initblocks)
    if initblocks == nil then
        initblocks = { { locals = {} } }
    else
        initblocks  = {table.unpack(initblocks)}
    end
    
    return function(...)
        local instance = create_instance(body, params, initblocks)
        return instance(...)
    end
end

local function create_function(body)
    return create_function_internal(body)
end

return create_function