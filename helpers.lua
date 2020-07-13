-- Application Helpers
-- ===================
-- Utilies that don't yet have a better place.
--
-- A cloud backend for Snap!
--
-- Written by Bernat Romagosa and Michael Ball
--
-- Copyright (C) 2019 by Bernat Romagosa and Michael Ball
--
-- This file is part of Snap Cloud.
--
-- Snap Cloud is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as
-- published by the Free Software Foundation, either version 3 of
-- the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

local helpers = {}

-- This function is extracted from lapis-exceptions by @leafo
-- https://github.com/leafo/lapis-exceptions/blob/master/lapis/exceptions/models/exception_types.lua#L6
local grammar = nil
local make_grammar
make_grammar = function()
local P, R, Cs
do
  local _obj_0 = require("lpeg")
  P, R, Cs = _obj_0.P, _obj_0.R, _obj_0.Cs
end
local make_str
make_str = function(delim)
  local d = P(delim)
  return d * (P([[\]]) * d + (P(1) - d)) ^ 0 * d
end
local rep
rep = function(name)
  return function()
    return "[" .. tostring(name) .. "]"
  end
end
local num = R("09") ^ 1 * (P(".") * R("09") ^ 1) ^ -1
local str = make_str([[']]) + make_str([["]])
local line_no = P(":") * num * P(":")
local string = P("'") * (P(1) - P("'")) * P("'")
grammar = Cs((line_no + (num / rep("NUMBER")) + (str / rep("STRING")) + P(1)) ^ 0)
end

helpers.normalize_error = function(str)
    if not (grammar) then
        make_grammar()
    end
    local first = str:match("^[^\n]+")
    local result = grammar:match(first) or first
    -- Additionally, trim the fat of standard paths
    return string.gsub(result, '/usr/local/share/lua/%[NUMBER%]/lapis/', '')
end

return helpers
