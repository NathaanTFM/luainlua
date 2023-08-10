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

local function dump_stmt(stmt)
    gen.buffer = ""
    gen.add_statement(stmt)
    return gen.buffer
end

local create_function_internal

local function create_instance(body, params, initblocks, globals, debugging)
    -- blocks
    local blocks = {unpack(initblocks)}
    
    local varargs = nil
    
    local evaluate_expr, evaluate_stmt
    
    local debuginfo = {
        stmt = nil
    }
    
    if globals == nil then
        globals = _ENV or _G
    end
    
    local function run_error(msg)
        error(debuginfo.stmt._chunk .. ":" .. debuginfo.stmt._row .. ": " .. msg, 0)
    end
    
    local function check_type(op, value, types, expr)
        local typ = type(value)
        for _, elt in pairs(types) do
            if elt == typ then
                return
            end
        end
        local msg = "attempt to " .. op .. " a " .. typ .. " value"
        if expr ~= nil then
            msg = msg .. " (" .. dump_expr(expr) .. ")"
        end
        run_error(msg)
    end
    
    local function check_arithmetic(left, right, expr_left, expr_right)
        -- if any meta-method is defined, then we can't just check the type
        -- and we cannot trust getmetatable, so we're stuck here
        if getmetatable(left) ~= nil or getmetatable(right) ~= nil then
            return
        end 
    
        check_type("perform arithmetic on", left, {"number"}, expr_left)
        check_type("perform arithmetic on", right, {"number"}, expr_right)
    end
    
    local function check_compare(left, right)
        -- if any meta-method is defined, then we can't just check the type
        -- and we cannot trust getmetatable, so we're stuck here
        if getmetatable(left) ~= nil or getmetatable(right) ~= nil then
            return
        end 
        
        local type_left = type(left)
        local type_right = type(right)
        
        if type_left ~= type_right then
            run_error("attempt to compare " .. type_left .. " with " .. type_right)
        
        elseif type_left ~= "string" and type_left ~= "number" then
            run_error("attempt to compare two " .. type_left .. " values")
        end
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
    
    local function search_name(name)
        local loc = search_local(name)
        if loc ~= nil then
            return loc.value
        else
            return globals[name]
        end
    end
    
    local function store_name(name, value)
        local loc = search_local(name)
        if loc ~= nil then
            loc.value = value
        else
            globals[name] = value
        end
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
                    local packed = pack(evaluate_expr(value))
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
            
            if debugging and getmetatable(value) == nil then
                check_type("index", value, {"table"}, expr.value)
            end
            
            if expr.name ~= nil then
                return value[expr.name]
            else
                local expr = evaluate_expr(expr.expr)
                return value[expr]
            end
            
        elseif expr.type == "name" then            
            return search_name(expr.name)
            
        elseif expr.type == "unary" then
            local value = evaluate_expr(expr.value)
            if expr.uop == "-" then
                -- is there a metatable field for negation?
                if debugging and getmetatable(value) == nil then
                    check_type("perform arithmetic on", value, {"number"}, expr.value)
                end
                
                return -value
                
            elseif expr.uop == "#" then
                if debugging and getmetatable(value) == nil then
                    check_type("get length of", value, {"string", "table"}, expr.value)
                end
                
                return #value
                
            elseif expr.uop == "not" then
                return not value
                
            end
            
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
            
            if expr.op == "+" then
                if debugging then check_arithmetic(left, right, expr.left, expr.right) end
                return left + right
                
            elseif expr.op == "-" then
                if debugging then check_arithmetic(left, right, expr.left, expr.right) end
                return left - right
                
            elseif expr.op == "*" then
                if debugging then check_arithmetic(left, right, expr.left, expr.right) end
                return left * right
                
            elseif expr.op == "%" then
                if debugging then check_arithmetic(left, right, expr.left, expr.right) end
                return left % right
                
            elseif expr.op == "^" then
                if debugging then check_arithmetic(left, right, expr.left, expr.right) end
                return left ^ right
                
            elseif expr.op == "/" then
                if debugging then check_arithmetic(left, right, expr.left, expr.right) end
                return left / right
                
            elseif expr.op == ".." then
                if debugging and getmetatable(left) == nil and getmetatable(right) == nil then
                    check_type("concatenate", left, {"string", "number"}, expr.left)
                    check_type("concatenate", right, {"string", "number"}, expr.right)
                end
                return left .. right
                
            elseif expr.op == "==" then
                return left == right
                
            elseif expr.op == "<" then
                if debugging then check_compare(left, right) end
                return left < right
                
            elseif expr.op == "<=" then
                if debugging then check_compare(left, right) end
                return left <= right
                
            elseif expr.op == "~=" then
                return left ~= right
                
            elseif expr.op == ">" then
                if debugging then check_compare(left, right) end
                return left > right
                
            elseif expr.op == ">=" then
                if debugging then check_compare(left, right) end
                return left >= right
            end
            
            error("op: " .. expr.op)
            
        elseif expr.type == "constant" then
            return expr.value
            
        elseif expr.type == "table" then
            local ret = {}
            local k = 1
            for i, field in ipairs(expr.fields) do
                -- special case if it's the last one
                if i == #expr.fields and field.type == "value" then
                    local values = pack(evaluate_expr(field.value))
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
            return create_function_internal(expr.body, expr.params, blocks, globals, debugging)
            
        elseif expr.type == "call" then
            local func = evaluate_expr(expr.value)
            local args = pack_values(expr.args)
            
            if debugging and getmetatable(func) == nil then
                check_type("call", func, {"function"}, expr.value)
            end
            
            return func(unpack(args))
            
        elseif expr.type == "invoke" then
            local value = evaluate_expr(expr.value)
            
            if debugging and getmetatable(value) == nil then
                check_type("index", value, {"table"}, expr.value)
            end
            
            local func = value[expr.name]
            
            if debugging and getmetatable(func) == nil and type(func) ~= "function" then
                run_error("attempt to call method '" .. expr.name .. "' (a " .. type(func) .. " value)")
            end
            
            local args = pack_values(expr.args)
            return func(value, unpack(args))
            
        elseif expr.type == "vararg" then
            if varargs ~= nil then
                return unpack(varargs)
            else
                run_error("cannot use '...' outside a vararg function")
            end
            
        else
            error("cannot evaluate " .. expr.type)
        end
    end
    
    evaluate_stmt = function(stmt)
        debuginfo.stmt = stmt
        
        local code = 0
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
                    store_name(target.name, tbl[i])
                    
                elseif target.type == "index" then
                    local value = evaluate_expr(target.value)
                    
                    if debugging and getmetatable(value) == nil then
                        check_type("index", value, {"table"}, target.value)
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
                    code, results = evaluate_stmt(stmt2)
                    if code > 0 then
                        break
                    end
                end
                pop_block()
            end
            
        elseif stmt.type == "while" or stmt.type == "repeat" then
            local cond
            if stmt.type == "while" then
                cond = evaluate_expr(stmt.cond)
            else
                cond = true
            end
            
            local body = stmt.body
            
            while cond do
                push_block()
                for _, stmt2 in ipairs(stmt.body) do
                    code, results = evaluate_stmt(stmt2)
                    if code > 0 then
                        break
                    end
                end
                pop_block()
                
                if code == 1 then
                    break
                elseif code == 2 then
                    code = 0
                    break
                end
                
                cond = evaluate_expr(stmt.cond)
            end
            
        elseif stmt.type == "do" then
            push_block()
            for _, stmt2 in ipairs(stmt.body) do
                code, results = evaluate_stmt(stmt2)
                if code > 0 then
                    break
                end
            end
            pop_block()
            
        elseif stmt.type == "expr" then
            evaluate_expr(stmt.expr)
            
        elseif stmt.type == "local_function" then
            add_local(stmt.name, create_function_internal(stmt.body, stmt.params, blocks, globals, debugging))
            
        elseif stmt.type == "function" then
            local params = {positional = {}, vararg = stmt.params.vararg}
            
            if stmt.method then
                table.insert(params.positional, "self")
            end
                
            for k,v in pairs(stmt.params.positional) do
                table.insert(params.positional, v)
            end
            
            local func = create_function_internal(stmt.body, params, blocks, globals, debugging)
            if #stmt.name == 1 then
                store_name(stmt.name[1], func)
                
            else
                -- function a.b.c()
                local tbl = search_name(stmt.name[1])
                for i = 2, #stmt.name-1 do
                    tbl = tbl[stmt.name[i]]
                end
                tbl[stmt.name[#stmt.name]] = func
            end
            
        elseif stmt.type == "return" then
            code = 1
            results = pack_values(stmt.values)
            
        elseif stmt.type == "fornum" then
            local start = evaluate_expr(stmt.start)
            local stop = evaluate_expr(stmt.stop)
            local step = 1
            if stmt.step ~= nil then
                step = evaluate_expr(stmt.step)
            end
            
            if debugging then
                if type(start) ~= "number" then
                    run_error("'for' initial value must be a number")
                elseif type(stop) ~= "number" then
                    run_error("'for' limit must be a number")
                elseif type(step) ~= "number" then
                    run_error("'for' step must be a number")
                end
            end
            
            for i = start, stop, step do
                push_block()
                add_local(stmt.target, i)
                
                for _, stmt2 in ipairs(stmt.body) do
                    code, results = evaluate_stmt(stmt2)
                    if code > 0 then
                        break
                    end
                end
                
                pop_block()
                
                if code == 1 then
                    break
                elseif code == 2 then
                    code = 0
                    break
                end
            end
            
        elseif stmt.type == "forin" then
            local values = pack_values(stmt.values)
            local v1, v2, v3 = unpack(values)
            
            while true do
                local tbl = pack(v1(v2, v3))
                v3 = tbl[1]
                
                if v3 == nil then
                    break
                end
                
                push_block()
                
                for i, target in ipairs(stmt.targets) do
                    add_local(stmt.targets[i], tbl[i])
                end
                for _, stmt2 in ipairs(stmt.body) do
                    code, results = evaluate_stmt(stmt2)
                    if code > 0 then
                        break
                    end
                end
                
                pop_block()
                
                if code == 1 then
                    break 
                elseif code == 2 then
                    code = 0
                    break
                end
            end
            -- for loop needs to be manually called
            
        elseif stmt.type == "break" then
            code = 2
            
        else
            error("cannot evaluate statement '" .. stmt.type .. "'")
        end
        
        return code, results
    end
    
    local function run_function(...)
        local tbl = pack(...)        
        push_block()
        
        if params ~= nil then
            for i, arg in ipairs(params.positional) do
                add_local(arg, tbl[i])
            end
            
            if params.vararg then
                varargs = {}
                varargs.n = 0
                for i = #params.positional+1, tbl.n do
                    varargs.n = varargs.n + 1
                    varargs[varargs.n] = tbl[i]
                end
            end
        end
        for _, stmt in ipairs(body) do
            code, results = evaluate_stmt(stmt)
            if code == 1 then
                break
            elseif code > 1 then
                error("unexpected code " .. code)
            end
        end
        
        pop_block()
        
        if code == 1 then 
            return unpack(results)
        end
    end
    
    return run_function
end


create_function_internal = function(body, params, initblocks, globals)
    if initblocks == nil then
        initblocks = { { locals = {} } }
    else
        initblocks  = {unpack(initblocks)}
    end
    
    return function(...)
        local instance = create_instance(body, params, initblocks, globals, true)
        return instance(...)
    end
end

local function create_function(body, globals)
    return create_function_internal(body, nil, nil, globals)
end

return create_function