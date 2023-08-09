local utils = require("utils")
local print = utils.print
local dump = utils.dump

local function LuaGenerator()
    local self = {}
    
    self.buffer = ""
    
    local indent = 0
    local add_expr
    
    local function append(data)
        self.buffer = self.buffer .. string.gsub(data, "\n", "\n" .. string.rep(" ", indent))
    end
    
    local function add_indent(value)
        value = indent + value * 4
        
        if string.sub(self.buffer, -indent-1) == ("\n" .. string.rep(" ", indent)) then
            self.buffer = string.sub(self.buffer, 0, -indent-1)
            self.buffer = self.buffer .. string.rep(" ", value)
        end
            
        indent = value
    end
    
    local function add_params(params)
        append("(")
        for i, name in ipairs(params.positional) do
            if i ~= 1 then
                append(", ")
            end
            append(name)
        end
        
        if params.vararg then
            if #params.positional > 0 then
                append(", ")
            end
            append("...")
        end
        append(")")
    end
    
    local function add_values(values)
        for i, value in ipairs(values) do
            if i ~= 1 then
                append(", ")
            end
            add_expr(value)
        end
    end

    local function add_body(body)
        add_indent(1)
        for _, stmt in ipairs(body) do
            self.add_statement(stmt)
        end
        add_indent(-1)
    end
    
    local function add_expr_function(expr)
        append("function")
        add_params(expr.params)
        append("\n")
        add_body(expr.body)
        append("end")
    end

    local function add_expr_name(expr)
        append(expr.name)
    end

    local function add_expr_table(expr)
        if next(expr.fields) == nil then
            append("{}")
            return
        end
        
        append("{\n")
        add_indent(1)
        for i, field in ipairs(expr.fields) do
            if i ~= 1 then
                append(",\n")
            end
            
            if field.type == "name" then
                append(field.name .. " = ")
            elseif field.type == "expr" then
                append("[")
                add_expr(field.expr)
                append("] = ")
            end
            add_expr(field.value)
        end
        append("\n")
        add_indent(-1)
        append("}")
    end
    
    local function add_expr_unary(expr)
        append(expr.uop)
        if #expr.uop > 1 then
            append(" ")
        end
        append("(")
        add_expr(expr.value)
        append(")")
    end
    
    local function add_expr_binary(expr)
        append("(")
        add_expr(expr.left)
        append(" " .. expr.op .. " ")
        add_expr(expr.right)
        append(")")
    end
    
    local function add_expr_call(expr)
        add_expr(expr.value)
        append("(")
        add_values(expr.args)
        append(")")
    end
    
    local function add_expr_invoke(expr)
        add_expr(expr.value)
        append(":")
        append(expr.name)
        append("(")
        add_values(expr.args)
        append(")")
    end
    
    local function add_expr_index(expr)
        add_expr(expr.value)
        if expr.name ~= nil then
            append("." .. expr.name)
        else
            append("[")
            add_expr(expr.expr)
            append("]")
        end
    end
    
    local function add_expr_constant(expr)
        append(dump(expr.value))
    end
    
    local function add_expr_vararg(expr)
        append("...")
    end

    add_expr = function(expr)
        if expr.type == "function" then
            add_expr_function(expr)
            
        elseif expr.type == "name" then
            add_expr_name(expr)
            
        elseif expr.type == "table" then
            add_expr_table(expr)
            
        elseif expr.type == "unary" then
            add_expr_unary(expr)
            
        elseif expr.type == "binary" then
            add_expr_binary(expr)
            
        elseif expr.type == "call" then
            add_expr_call(expr)
            
        elseif expr.type == "invoke" then
            add_expr_invoke(expr)
            
        elseif expr.type == "index" then
            add_expr_index(expr)
            
        elseif expr.type == "constant" then
            add_expr_constant(expr)
            
        elseif expr.type == "vararg" then
            add_expr_vararg(expr)
            
        else
            error("cannot dump expr '" .. expr.type .. "'")
        end
    end

    local function add_stmt_assign(stmt)
        for i, target in ipairs(stmt.targets) do
            if i ~= 1 then
                append(", ")
            end
            add_expr(target)
        end
        
        append(" = ")
        add_values(stmt.values)
        append("\n")
    end

    local function add_stmt_local_assign(stmt)
        append("local ")
        for i, target in ipairs(stmt.targets) do
            if i ~= 1 then
                append(", ")
            end
            append(target)
        end
        
        if stmt.values ~= nil then
            append(" = ")
            add_values(stmt.values)
        end
        
        append("\n")
    end

    local function add_stmt_function(stmt)
        append("function ")
        for i, v in ipairs(stmt.name) do
            if i == #stmt.name and stmt.vararg then
                append(":")
            elseif i ~= 1 then
                append(".")
            end
            
            append(v)
        end
        
        add_params(stmt.params)
        append("\n")
        add_body(stmt.body)
        append("end\n")
    end

    local function add_stmt_local_function(stmt)
        append("local function ")
        append(stmt.name)
        add_params(stmt.params)
        append("\n")
        add_body(stmt.body)
        append("end\n")
    end
    
    local function add_stmt_if(stmt)
        append("if ")
        add_expr(stmt.cond)
        append(" then\n")
        add_body(stmt.body)
        for i, elt in ipairs(stmt.elseifs) do
            append("elseif ")
            add_expr(elt.cond)
            append(" then\n")
            add_body(elt.body)
        end
        if stmt.elsebody ~= nil then
            append("else\n")
            add_body(stmt.elsebody)
        end
        append("end\n")
    end
    
    local function add_stmt_expr(stmt)
        add_expr(stmt.expr)
        append("\n")
    end
    
    local function add_stmt_return(stmt)
        append("return ")
        add_values(stmt.values)
        append("\n")
    end
    
    local function add_stmt_do(stmt)
        append("do\n")
        add_body(stmt.body)
        append("end\n")
    end
    
    local function add_stmt_while(stmt)
        append("while ")
        add_expr(stmt.cond)
        append(" do\n")
        add_body(stmt.body)
        append("end\n")
    end
    
    local function add_stmt_break(stmt)
        append("break\n")
    end
    
    local function add_stmt_fornum(stmt)
        append("for ")
        append(stmt.target)
        append(" = ")
        add_expr(stmt.start)
        append(", ")
        add_expr(stmt.stop)
        if stmt.step ~= nil then
            append(", ")
            add_expr(stmt.step)
        end
        append(" do\n")
        add_body(stmt.body)
        append("end\n")
    end
    
    local function add_stmt_forin(stmt)
        append("for ")
        for i, target in ipairs(stmt.targets) do
            if i ~= 1 then
                append(", ")
            end
            append(target)
        end
        append(" in ")
        add_values(stmt.values)
        append(" do\n")
        add_body(stmt.body)
        append("end\n")
    end
    
    local function add_stmt_repeat(stmt)
        append("repeat\n")
        add_body(stmt.body)
        append("until")
        add_expr(stmt.cond)
        append("\n")
    end
    
    self.add_expression = function(expr)
        add_expr(expr)
    end
    
    self.add_statement = function(stmt)
        if stmt.type == "assign" then
            add_stmt_assign(stmt)
            
        elseif stmt.type == "local_assign" then
            add_stmt_local_assign(stmt)
            
        elseif stmt.type == "function" then
            add_stmt_function(stmt)
            
        elseif stmt.type == "local_function" then
            add_stmt_local_function(stmt)
            
        elseif stmt.type == "if" then
            add_stmt_if(stmt)
            
        elseif stmt.type == "expr" then
            add_stmt_expr(stmt)
            
        elseif stmt.type == "return" then
            add_stmt_return(stmt)
            
        elseif stmt.type == "do" then
            add_stmt_do(stmt)
            
        elseif stmt.type == "while" then
            add_stmt_while(stmt)
            
        elseif stmt.type == "break" then
            add_stmt_break(stmt)
            
        elseif stmt.type == "forin" then
            add_stmt_forin(stmt)
            
        elseif stmt.type == "fornum" then
            add_stmt_fornum(stmt)
            
        elseif stmt.type == "repeat" then
            add_stmt_repeat(stmt)
            
        else
            error("cannot add stmt '" .. stmt.type .. "'")
        end
    end
    
    return self
end

return LuaGenerator