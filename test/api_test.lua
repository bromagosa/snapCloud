-- API tests
-- ==========
--
-- Some tests of the API.
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
local request = require('lapis.spec.server').request
local use_test_server = require('lapis.spec').use_test_server
local test_util = require 'test/test_util'


describe('The login endpoint', function()
    use_test_server()

    after_each(function()
        test_util.clean_db()
    end)

    local username = 'aaaschmitty'
    local api_password = test_util.hash_for_api('test_123456')

    it('allows a valid user to login', function()
        test_util.create_user(username, api_password, true)

        local status, body, headers = request('/users/' .. username .. '/login', {
            method = 'POST',
            data = api_password
        })

        assert.same(200, status)
        assert.is.truthy(body:find(username))
    end)

    it('returns the days remaining for a user with a valid token', function()
        test_util.create_user(username, api_password, false)
        test_util.create_token(username, 'verify_user', false)

        local status, body, headers = request('/users/' .. username .. '/login', {
            method = 'POST',
            data = api_password
        })

        local resp = test_util.json_decode(body)

        assert.same(200, status)
        assert.same(3, resp.days_left)
    end)

    it('should error for a user with an expired token', function()
        test_util.create_user(username, api_password, false)
        test_util.create_token(username, 'verify_user', true)

        local status, body, headers = request('/users/' .. username .. '/login', {
            method = 'POST',
            data = api_password
        })

        local error = test_util.json_decode(body).errors[1]

        assert.same(401, status)
        assert.is.truthy(error:find('not') and error:find('validated'))
    end)

    it('should error for a user with wrong password', function()
        test_util.create_user(username, api_password, true)

        local status, body, headers = request('/users/' .. username .. '/login', {
            method = 'POST',
            data = api_password .. 'a' -- append an invalid char
        })

        local error = test_util.json_decode(body).errors[1]

        assert.same(401, status)
        assert.same('wrong password', error)
    end)

    it('should error for a non-existent user', function()
        -- don't create user first
        local status, body, headers = request('/users/' .. username .. '/login', {
            method = 'POST',
            data = api_password
        })

        local error = test_util.json_decode(body).errors[1]

        assert.same(401, status)
        assert.is.truthy(error:find('No user') and error:find('exists'))
    end)
    
    it('should error for a non-verified user with no token', function()
        test_util.create_user(username, api_password, false)

        local status, body, headers = request('/users/' .. username .. '/login', {
            method = 'POST',
            data = api_password
        })

        local error = test_util.json_decode(body).errors[1]

        assert.same(401, status)
        assert.is.truthy(error:find('not') and error:find('validated'))
    end)
end)

