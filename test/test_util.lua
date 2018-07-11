-- Test Utilities
-- ==========
--
-- Simple utilites like creating users/projects
-- and mocks for common objects or services.
--
-- Written by Andrew Schmitt
--
-- Copyright (C) 2018 by Bernat Romagosa
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
local app = require 'app'
local db = package.loaded.db
local Users = package.loaded.Users
local Tokens = package.loaded.Tokens
local json_util = require('JSON')
local test_util = {}

function test_util.json_decode(json_str)
    return json_util:decode(json_str)
end

function test_util.json_encode(lua_obj)
    return json_util:encode(lua_obj)
end

-- Deletes all users and tokens from the database.
function test_util.clean_db()
    db.delete('tokens')
    db.delete('users')
end

local ten_days = 60 * 60 * 24 * 10

-- Create a token for the specified user with the specified purpose
-- @param expired whether the created token should be expired
function test_util.create_token(username, purpose, expired)
    local created_date = db.format_date()
    if expired then
        created_date = db.format_date(os.time() - ten_days)
    end
    Tokens:create({
        username = username,
        created = created_date,
        value = secure_token(),
        purpose = purpose
    })
end

-- Creates a single user with a default email assigned: <username>@snap.berkeley.edu
-- @return the user model of the created user
function test_util.create_user(username, password, verified)
    local salt = secure_salt()
    return Users:create({
        created = db.format_date(),
        username = username,
        salt = salt,
        password = hash_password(password, salt),
        email = username .. '@snap.berkeley.edu',
        verified = verified,
        isadmin = false
    })
end

-- The api expects passwords to be sent prehashed.
-- @return a hashed password that can be sent in api requests
function test_util.hash_for_api(password)
    return hash_password(password, '')
end

return test_util