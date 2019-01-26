-- Validation and errors
-- =====================
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

local capture_errors = package.loaded.capture_errors
local yield_error = package.loaded.yield_error
local db = package.loaded.db
local Collections = package.loaded.Collections
local Users = package.loaded.Users
local Projects = package.loaded.Projects
local Tokens = package.loaded.Tokens
local url = require 'socket.url'

require 'responses'
require 'email'

err = {
    not_logged_in = { msg = 'You are not logged in', status = 401 },
    auth = { msg = 'You do not have permission to perform this action', status = 403 },
    nonexistent_user = { msg = 'No user with this username exists', status = 404 },
    nonexistent_project = { msg = 'This project does not exist', status = 404 },
    nonexistent_collection = { msg = 'This collection does not exist',
                              status = 404 },
    not_public_project = { msg = 'This project is not public', status = 403 },
    expired_token = { msg = 'This token has expired', status = 401 },
    invalid_token = { msg = 'This token is either invalid or has expired', status = 401 },
    nonvalidated_user = { msg = 'This user has not been validated within the first 3 days after its creation.\nPlease use the cloud menu to ask for a new validation link.', status = 401 },
    invalid_role = { msg = 'This user role is not valid', status = 401 },
    banned = { msg = 'Your user has been banned', status = 403 },
    unparseable_xml = { msg = 'Project file could not be parsed', status = 500 },
    file_not_found = { msg = 'Project file not found', status = 404 },
    mail_body_empty = { msg = 'Missing email body contents', status = 400 }
}

assert_all = function (assertions, self)
    for _, assertion in pairs(assertions) do
        if (type(assertion) == 'string') then
            _G['assert_' .. assertion](self)
        else
            assertion(self)
        end
    end
end

-- User permissions and roles

assert_logged_in = function (self, message)
    if not self.session.username then
        yield_error(message or err.not_logged_in)
    end
end

-- User roles:
-- standard:  Can view published and shared projects, can do anything to own projects,
--            can see basic user profile data. Can delete oneself.
-- reviewer:  Same as standard, plus: Can unpublish projects.
-- moderator: Same as reviewer, plus: Can delete published and shared projects.
--            Can block users. Can delete users. Can verify users.
-- admin:     Can do everything.
-- banned:    Same as a standard user, but can't modify or add anything.

assert_role = function (self, role, message)
    if not (self.current_user and self.current_user.role == role) then
        yield_error(message or err.auth)
    end
end

assert_has_one_of_roles = function (self, roles)
    if not self.current_user or not self.current_user:has_one_of_roles(roles) then
        yield_error(err.auth)
    end
end

assert_admin = function (self, message)
    assert_role(self, 'admin', message)
end

assert_can_set_role = function (self, role)
    local can_set = {
        admin = {
            admin = { admin = true, moderator = true, reviewer = true, standard = true, banned = true },
            moderator = { admin = true, moderator = true, reviewer = true, standard = true, banned = true },
            reviewer = { admin = true, moderator = true, reviewer = true, standard = true, banned = true },
            standard = { admin = true, moderator = true, reviewer = true, standard = true, banned = true },
            banned = { admin = true, moderator = true, reviewer = true, standard = true, banned = true }
        },
        moderator = {
            admin = {}, moderator = {},
            reviewer = { moderator = true, reviewer = true, standard = true, banned = true },
            standard = { moderator = true, reviewer = true, standard = true, banned = true },
            banned = { moderator = true, reviewer = true, standard = true, banned = true }
        },
        reviewer = {
            admin = {}, moderator = {}, reviewer = {}, banned = {},
            standard = { reviewer = true, standard = true }
        },
        standard = { admin = {}, moderator = {}, reviewer = {}, standard = {}, banned = {} },
        banned = { admin = {}, moderator = {}, reviewer = {}, standard = {}, banned = {} }
    }
    if not can_set[self.current_user.role][self.queried_user.role][role] then
        yield_error(err.auth)
    end
end

users_match = function (self)
    return (self.session.username == self.params.username) or (self.current_user and self.current_user:isadmin())
end

assert_users_match = function (self, message)
    if (not users_match(self)) then
        -- Someone is trying to impersonate someone else
        yield_error(message or err.auth)
    end
end

assert_user_exists = function (self, message)
    if not self.queried_user then
        yield_error(message or err.nonexistent_user)
    end
    return self.queried_user
end

-- Projects

assert_project_exists = function (self, message)
    if not (Projects:find(self.params.username, self.params.projectname)) then
        yield_error(message or err.nonexistent_project)
    end
end

-- Users can add their own projects and published projects to any collection
-- Admins can add any project to a collection.
-- Users can't add shared projects to a collection.
assert_user_can_add_project_to_collection = function (self, project)
    if (self.current_user:isadmin() or project.ispublished
        or project.username == self.current_user.username) then
        return
    end

    if project.isshared == true then
        yield_error(err.auth)
    end
    yield_error(err.nonexistent_project)
end

-- Tokens

check_token = function (token_value, purpose, on_success)
    local token = Tokens:find(token_value)
    if token then
        local query = db.select("date_part('day', now() - ?::timestamp)", token.created)[1]
        if query.date_part < 4 and token.purpose == purpose then
            -- TODO: use self.queried_user and assert matches token.username
            local user = Users:find(token.username)
            token:delete()
            return on_success(user)
        elseif token.purpose ~= purpose then
            -- We simply ignore tokens with different purposes
            return htmlPage('Invalid token', '<p>' .. err.invalid_token.msg .. '</p>')
        else
            -- We delete expired tokens with 'verify_user' purpose
            token:delete()
            return htmlPage('Expired token', '<p>' .. err.expired_token.msg .. '</p>')
        end
    else
        -- This token does not exist anymore, or never existed in the first place
        return htmlPage('Invalid token', '<p>' .. err.invalid_token.msg .. '</p>')
    end
end

--- Creates a token and sends an email
-- @param self: request object
-- @param purpose string: token purpose and route name
-- @param username string
-- @param email string
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
        self:build_url(self:url_for(
            purpose,
            {
                username = url.build_path({username}),
                token = url.build_path({token_value}),
            }
        ))
    )
end

-- Collections
assert_collection_exists = function (self)
    local collection = Collections.find(self.params.username,
                                       self.params.collection_slug)

    if not collection or
        (collection.published == false and not users_match(self)) then
        yield_error(err.nonexistent_collection)
    end

    return collection
end
