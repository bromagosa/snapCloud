-- Site tests
-- ==========
--
-- Some tests of the site.
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
local request = require("lapis.spec.server").request
local use_test_server = require("lapis.spec").use_test_server
local test_util = 'test/test_util'

describe("The site", function()
    use_test_server()

    it("Should redirect to home page", function()
        local status, body, headers = request("/")
        assert.same(302, status)
    end)
end)

