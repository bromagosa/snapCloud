-- Discourse SSO module
-- ====================
--
-- Implements a login endpoint for the Discourse forum.
-- SSO will use the current user session if one exists
-- Otherwise, it will redirect the user to the login page.
-- Once the request is verified, the user is redirected to the forum.
-- https://meta.discourse.org/t/official-single-sign-on-for-discourse-sso/13045
--
--
-- Written by Michael Ball
--
-- Copyright (C) 2018 by Michael Ball
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

local app = package.loaded.app
local Users = package.loaded.Users
local capture_errors = package.loaded.capture_errors
local yield_error = package.loaded.yield_error
local util = package.loaded.util
local hmac = require('openssl.hmac')
local config = package.loaded.config
local encoding = require("lapis.util.encoding")

local sso_secret = config.discourse_sso_secret

app:get('/discourse-sso', capture_errors(function(self)
    if self.session.username == '' then
        local signin_url = '/site/login.html?redirect_to='
        local redirect_path = util.escape('/discourse-sso?' .. util.encode_query_string(self.params))
        return { redirect_to = signin_url .. redirect_path }
    end

    -- params are automatically unescaped.
    local payload = self.params.sso
    local signature = self.params.sig

    if not signature or not payload then
        local message = 'Please go back and try again. '
        if not signature then
            message = message .. '(Request signature is missing.)'
        else
            message = message .. '(Request payload is missing.)'
        end
        yield_error({msg = message, status = 422})
    end

    local computed_signature = create_signature(payload)
    if computed_signature ~= signature then
        yield_error({msg = 'Signature does not match. Please try again.',
                     status = 422})
    end

    local request_payload = extract_payload(payload)
    local user = Users:select('where username = ? limit 1',
            self.session.username,
            { fields = 'id, username, verified, isadmin, email' })[1]
    local response_payload = build_payload(user, request_payload.nonce)
    local final_url = create_redirect_url(request_payload.return_sso_url,
                                          response_payload)

    -- don't redirect in development so you don't mess up your forum account.
    if config._name == 'development' then return final_url end
    return { redirect_to = final_url }
end))

function create_signature(payload)
    local digest = hmac.new(config.discourse_sso_secret, 'sha256')
    digest:update(payload)
    return encoding.encode_base64(digest:final())
end

function extract_payload(payload)
    return util.parse_query_string(encoding.decode_base64(payload))
end

-- Base64 encode the required discourse params.
-- "require_activation" is a special discourse flag,
-- for user's whose email is not verified. It enables additional restrictions.
function build_payload(user, nonce)
    local params = {
        external_id = user.id,
        username = user.username,
        email = user.email,
        require_activation = not user.verified,
        admin = user.isadmin,
        nonce = nonce
    }
    return encoding.encode_base64(util.encode_query_string(params))
end

function create_redirect_url(discourse_url, payload)
    local encoded_payload = util.escape(payload)
    local signature = create_signature(payload)
    return discourse_url .. '?sso=' .. encoded_payload .. '&sig=' .. signature
end
