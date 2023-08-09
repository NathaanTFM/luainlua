if not pcall(require, "_bios") then argv = {...} end

local utils = require("utils")
local print = utils.print
local dump = utils.dump

local LuaLexer = require("lexer")
local LuaParser = require("parser")
local create_function = require("compiler")

if io.open ~= nil then
    local file = nil
    if file == nil and argv[1] ~= nil then
        file = io.open(argv[1], "r")
    end
    if file == nil then
        file = io.open("input.lua", "r")
    end
    if file == nil then
        file = io.open("../input.lua", "r")
    end

    GlobalScript = file:read("*all")
    file:close()
end

local script = GlobalScript

local parser = LuaParser(script)

local func = create_function(parser.body)

table.remove(_G.arg, 1)
func()