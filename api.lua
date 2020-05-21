-- API module
-- ==========
--
-- See static/API for API description
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

local api_version = 'v1'

local app = package.loaded.app
local capture_errors = package.loaded.capture_errors
local respond_to = package.loaded.respond_to

require 'controllers.user'
require 'controllers.project'
require 'controllers.collection'

-- Wraps all API endpoints in standard behavior.
-- All API routes are nested under /api/v1,
-- which is currently an optional prefix.
local function api_route(name, path, controller, methods)
    tbl = { OPTIONS = cors_options }
    -- methods is a table describing which REST methods this endpoint accepts
    for _, method in pairs(methods) do
        -- ex: tbl['GET'] =
        --      capture_errors(UserController['GET']['current_user'])
        -- equivalent to:
        --      (...) GET = capture_errors(UserController.GET.current_user)
        tbl[method] = capture_errors(controller[method][name])
    end
    return name, '(/api/' .. api_version .. ')' .. path, respond_to(tbl)
end

APIController = {
    GET = {
        version = function (self)
            return jsonResponse({
                name = 'Snap! Cloud',
                version = api_version
            })
        end
    },
    POST = {
        init = function (self)
            if not self.session.username or
                (self.session.username and
                    self.cookies.persist_session == 'false') then
                self.session.username = ''
            end
        end
    }
}

-- API Endpoints
-- =============
app:match(api_route('version', '/version', APIController, { 'GET' }))
app:match(api_route('init', '/init', APIController, { 'POST' }))

-- Users
-- =====
app:match(api_route('current_user', '/users/c', UserController, { 'GET' }))
app:match(api_route('user_list', '/users', UserController, { 'GET' }))
app:match(api_route('user', '/users/:username', UserController, { 'GET', 'POST', 'DELETE' }))
app:match(api_route('with_email', '/users/email/:email', UserController, { 'GET' }))
app:match(api_route('new_password', '/users/:username/newpassword', UserController, { 'POST' }))
app:match(api_route('resend_verification', '/users/:username/resendverification', UserController, { 'POST' }))
app:match(api_route('password_reset', '/users/:username/password_reset(/:token)', UserController, { 'GET', 'POST' }))
app:match(api_route('login', '/users/:username/login', UserController, { 'POST' }))
app:match(api_route('verify_user', '/users/:username/verify_user/:token', UserController, { 'GET' }))
app:match(api_route('logout', '/logout', UserController, { 'POST' }))
app:match(api_route('send_message', '/users/:username/message', UserController, { 'POST' }))
-- Zombie users
app:match(api_route('zombies', '/zombies', UserController, { 'GET' }))
app:match(api_route('revive', '/zombies/:username/revive', UserController, { 'POST' }))
app:match(api_route('zombie', '/zombies/:username', UserController, { 'DELETE' }))

-- Projects
-- ========
app:match(api_route('projects', '/projects', ProjectController, { 'GET' }))
app:match(api_route('user_projects', '/projects/:username', ProjectController, { 'GET' }))
app:match(api_route('project', '/projects/:username/:projectname', ProjectController, { 'GET', 'POST', 'DELETE' }))
app:match(api_route('project_meta', '/projects/:username/:projectname/metadata', ProjectController, { 'GET', 'POST' }))
app:match(api_route('project_versions', '/projects/:username/:projectname/versions', ProjectController, { 'GET' }))
app:match(api_route('project_remixes', '/projects/:username/:projectname/remixes', ProjectController, { 'GET' }))
app:match(api_route('project_collections', '/projects/:username/:projectname/collections', ProjectController, { 'GET' }))
app:match(api_route('project_thumbnail', '/projects/:username/:projectname/thumbnail', ProjectController, { 'GET' }))
app:match(api_route('project_comments', '/projects/:username/:projectname/comments', ProjectController, { 'GET' }))
app:match(api_route('project_comment', '/projects/:username/:projectname/comment', ProjectController, { 'POST', 'DELETE' }))

-- Collections
-- ===========
app:match(api_route('collections', '/collections', CollectionController, { 'GET' }))
app:match(api_route('user_collections', '/users/:username/collections', CollectionController, { 'GET' }))
app:match(api_route('collection', '/users/:username/collections/:name', CollectionController, { 'POST', 'DELETE' }))
app:match(api_route('collection_meta', '/users/:username/collections/:name/metadata', CollectionController, { 'GET', 'POST' }))
app:match(api_route('collection_projects', '/users/:username/collections/:name/projects', CollectionController, { 'GET', 'POST' }))
app:match(api_route('collection_project', '/users/:username/collections/:name/projects/:project_id', CollectionController, { 'GET', 'POST', 'DELETE' }))
app:match(api_route('collection_thumbnail', '/users/:username/collections/:name/thumbnail', CollectionController, { 'POST' }))
app:match(api_route('collection_editors', '/users/:username/collections/:name/editors(/:editor_username)', CollectionController, { 'POST', 'DELETE' }))
