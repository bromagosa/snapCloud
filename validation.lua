-- Validation and errors
-- =====================
--
-- Written by Bernat Romagosa
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

local yield_error = package.loaded.yield_error
local db = package.loaded.db
local Users = package.loaded.Users
local Projects = package.loaded.Projects
local Tokens = package.loaded.Tokens

require 'responses'
require 'email'

err = {
    not_logged_in = 'You are not logged in',
    auth = 'You do not have permission to perform this action',
    nonexistent_user = 'No user with this username exists',
    nonexistent_project = 'This project does not exist',
    not_public_project = 'This project is not public',
    expired_token = 'This token has expired',
    invalid_token = 'This token is either invalid or has expired',
    nonvalidated_user = 'This user has not been validated within the first 3 days after its creation.\nPlease use the cloud menu to ask for a new validation link.'
}

assert_all = function (assertions, self)
    for k, assertion in pairs(assertions) do
        _G['assert_' .. assertion](self)
    end
end

assert_logged_in = function (self, message)
    if not self.session.username then
        yield_error(message or err.not_logged_in)
    end
end

assert_admin = function (self, message)
    local user = Users:find(self.session.username)
    if not (user and user.isadmin) then
        yield_error(message or err.auth)
    end
end

assert_users_match = function (self, message)
    if (not users_match(self)) then
        -- Someone is trying to impersonate someone else
        yield_error(message or err.auth)
    end
end

users_match = function (self)
    return (self.session.username == self.params.username)
end

assert_user_exists = function (self, message)
    if not Users:find(self.params.username) then
        yield_error(message or err.nonexistent_user)
    end
end

assert_project_exists = function (self, message)
    if not (Projects:find(self.params.username, self.params.projectname)) then
        yield_error(message or err.nonexistent_project)
    end
end

check_token = function (token_value, purpose, on_success)
    local token = Tokens:find(token_value)
    if token then
        local query = db.select("date_part('day', now() - ?::timestamp)", token.created)[1]
        if query.date_part < 4 and token.purpose == purpose then
            local user = Users:find(token.username)
            token:delete()
            return on_success(user)
        elseif token.purpose ~= purpose then
            -- We simply ignore tokens with different purposes
            return htmlPage('Invalid token', '<p>' .. err.invalid_token .. '</p>')
        else
            -- We delete expired tokens with 'verify_user' purpose
            token:delete()
            return htmlPage('Expired token', '<p>' .. err.expired_token .. '</p>')
        end
    else
        -- This token does not exist anymore, or never existed in the first place
        return htmlPage('Invalid token', '<p>' .. err.invalid_token .. '</p>')
    end
end

create_token = function (self, purpose, username, email)
    local token_value = secure_token()
    Tokens:create({
        username = username,
        created = db.format_date(),
        value = token_value,
        purpose = purpose
    })
    send_mail(
        email,
        mail_subjects[purpose] .. username,
        mail_bodies[purpose],
        self:build_url('/users/' .. username .. '/' .. purpose .. '/' .. token_value))
end
