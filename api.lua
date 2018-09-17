-- API module
-- ==========
--
-- See static/API for API description
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

local app = package.loaded.app
local db = package.loaded.db
local app_helpers = package.loaded.db
local capture_errors = package.loaded.capture_errors
local yield_error = package.loaded.yield_error
local validate = package.loaded.validate
local Model = package.loaded.Model
local util = package.loaded.util
local respond_to = package.loaded.respond_to
local json_params = package.loaded.json_params
local cached = package.loaded.cached
local Users = package.loaded.Users
local Projects = package.loaded.Projects
local Tokens = package.loaded.Tokens

require 'disk'
require 'responses'
require 'validation'
require 'passwords'

-- API Endpoints
-- =============

app:match('init', '/init', respond_to({
    OPTIONS = cors_options,
    POST = function (self)
        if not self.session.username or
            (self.session.username and self.cookies.persist_session == 'false') then
            self.session.username = ''
        end
    end
}))


app:match('current_user', '/users/c', respond_to({
    -- Methods:     GET
    -- Description: Get the currently logged user's username and credentials.

    OPTIONS = cors_options,
    GET = function (self)

        if (self.session.username ~= nil and self.session.username ~= '' and not self.session.verified) then
            self.session.verified = (Users:find(self.session.username)).verified
        elseif self.session.username == '' then
            self.session.isadmin = false
            self.session.verified = false
        end

        return jsonResponse({
            username = self.session.username,
            isadmin = self.session.isadmin,
            verified = self.session.verified
        })
    end
}))


app:match('user', '/users/:username', respond_to({
    -- Methods:     GET, DELETE, POST
    -- Description: Get info about a user, or delete/add a user.
    -- Parameters:  username, password, password_repeat, email

    OPTIONS = cors_options,
    GET = capture_errors(function (self)
        if not users_match(self) then assert_admin(self) end
        return jsonResponse(
            Users:select(
                'where username = ? limit 1',
                self.params.username,
                { fields = 'username, location, about, created, isadmin, email' })[1])
    end),

    DELETE = capture_errors(function (self)
        assert_all({'logged_in', 'admin'}, self)

        local user = Users:find(self.params.username)
        if not user then
            yield_error(err.nonexistent_user)
        end

        if not (user:delete()) then
            yield_error('Could not delete user ' .. self.params.username)
        else
            return okResponse('User ' .. self.params.username .. ' has been removed.')
        end
    end),

    POST = capture_errors(function (self)
        validate.assert_valid(self.params, {
            { 'username', exists = true, min_length = 4, max_length = 200 },
            { 'password', exists = true, min_length = 6 },
            { 'password_repeat', equals = self.params.password, 'passwords do not match' },
            { 'email', exists = true, min_length = 5 },
        })

        if Users:find(self.params.username) then
            yield_error('User ' .. self.params.username .. ' already exists');
        end

        local salt = secure_salt()
        Users:create({
            created = db.format_date(),
            username = self.params.username,
            salt = salt,
            password = hash_password(self.params.password, salt), -- see validation.lua >> hash_password
            email = self.params.email,
            verified = false,
            isadmin = false
        })

        -- Create a verify_user-type token and send an email to the user asking to
        -- verify the account.
        -- We check these on login.
        create_token(self, 'verify_user', self.params.username, self.params.email)
        return okResponse(
            'User ' .. self.params.username ..
            ' created.\nPlease check your email and validate your\naccount within the next 3 days.')
    end)

}))


app:match('newpassword', '/users/:username/newpassword', respond_to({
    -- Methods:     POST
    -- Description: Sets a new password for a user.
    -- Parameters:  oldpassword, password_repeat, newpassword

    OPTIONS = cors_options,
    POST = capture_errors(function (self)
        local user = Users:find(self.params.username)

        assert_all({'user_exists', 'users_match'}, self)

        if user.password ~= hash_password(self.params.oldpassword, user.salt) then
            yield_error('wrong password')
        end

        validate.assert_valid(self.params, {
            { 'password_repeat', equals = self.params.newpassword, 'passwords do not match' },
            { 'newpassword', exists = true, min_length = 6 }
        })

        user:update({
            password = hash_password(self.params.newpassword, user.salt)
        })

        return okResponse('Password updated')
    end)
}))

app:match('resendverification', '/users/:username/resendverification', respond_to({
    -- Methods:     GET
    -- Description: Resends user verification email

    OPTIONS = cors_options,
    POST = capture_errors(function (self)
        local user = Users:find(self.params.username)
        if not user then yield_error(err.nonexistent_user) end
        if user.verified then
            return okResponse('User ' .. self.params.username .. ' is already verified.\nThere is no need for you to do anything.\n')
        end
        create_token(self, 'verify_user', self.params.username, user.email)
        return okResponse(
            'Verification email for ' .. self.params.username ..
            ' sent.\nPlease check your email and validate your\n' ..
            'account within the next 3 days.')
    end)
}))

app:match('password_reset', '/users/:username/password_reset(/:token)', respond_to({
    -- Methods:     GET, POST
    -- Description: Handles password reset requests.
    --              The route name should match the database token purpose.
    -- @see validation.create_token

    OPTIONS = cors_options,
    GET = capture_errors(function (self)
        return check_token(
            self.params.token,
            'password_reset',
            function (user)
                local password, prehash = random_password()
                user:update({ password = hash_password(prehash, user.salt) })
                send_mail(
                    user.email,
                    mail_subjects.new_password .. user.username,
                    mail_bodies.new_password .. '<p><h2>' .. password .. '</h2></p>')

                return htmlPage(
                    'Password reset',
                    '<p>A new random password has been generated for your account <strong>' .. user.username .. '</strong> and sent to your email address. Please check your inbox.</p>' ..
                    '<p>After logging in, please proceed to <strong>change your password</strong> as soon as possible.</p>'
                )
            end
        )
    end),
    POST = capture_errors(function (self)
        local user = Users:find(self.params.username)
        if not user then yield_error(err.nonexistent_user) end
        create_token(self, 'password_reset', self.params.username, user.email)
        return okResponse('Password reset request sent.\nPlease check your email.')
    end)
}))


app:match('login', '/users/:username/login', respond_to({
    -- Methods:     POST
    -- Description: Logs a user into the system.
    -- Body:        password.

    OPTIONS = cors_options,
    POST = capture_errors(function (self)
        local user = Users:find(self.params.username)

        if not user then yield_error(err.nonexistent_user) end

        ngx.req.read_body()
        local password = ngx.req.get_body_data()

        if (hash_password(password, user.salt) == user.password) then
            if not user.verified then
                -- Check whether verification token is still unused and valid
                local token =
                    Tokens:find({
                        username = user.username,
                        purpose = 'verify_user'
                    })
                if token then
                    local query = db.select("date_part('day', now() - ?::timestamp)", token.created)[1]
                    if query.date_part > 3 then
                        token:delete()
                        yield_error(err.nonvalidated_user)
                    else
                        user.days_left = 3 - query.date_part
                    end
                else
                    yield_error(err.nonvalidated_user)
                end
            end
            self.session.username = user.username
            self.session.isadmin = user.isadmin
            self.session.verified = user.verified
            self.cookies.persist_session = self.params.persist
            if user.verified then
                return okResponse('User ' .. self.params.username .. ' logged in')
            else
                return jsonResponse({ days_left = user.days_left })
            end
        else
            yield_error('wrong password')
        end
    end)
}))


app:match('verify_user', '/users/:username/verify_user/:token', respond_to({
    -- Methods:     GET
    -- Description: Verifies a user's email by means of a token, or removes
    --              that token if it has expired
    --              Returns a success message if the user is already verified.
    --              The route name should match the database token purpose.
    -- @see validation.create_token

    GET = capture_errors(function (self)
        local user_page = function (user)
            return htmlPage(
                'User verified | Welcome to Snap<em>!</em>',
                '<p>Your account <strong>' .. user.username .. '</strong> has been verified.</p>' ..
                '<p>Thank you!</p>' ..
                '<p><a href="https://snap.berkeley.edu/run">Take me to Snap<i>!</i></a></p>'
            )
        end
        local user = assert_user_exists(self)
        if user.verified then
            return user_page(user)
        end

        return check_token(
            self.params.token,
            'verify_user',
            function (user)
                -- success callback
                user:update({ verified = true })
                return user_page(user)
            end
        )
    end)
}))


app:match('logout', '/logout', respond_to({
    -- Methods:     POST
    -- Description: Logs out the current user from the system.

    OPTIONS = cors_options,
    POST = capture_errors(function (self)
        self.session.username = ''
        self.cookies.persist_session = 'false'
        return okResponse('logged out')
    end)
}))


-- TODO refactor the following two, as they share most of the code

app:match('projects', '/projects', respond_to({
    -- Methods:     GET
    -- Description: Get a list of published projects.
    -- Parameters:  page, pagesize, matchtext, withthumbnail.

    OPTIONS = cors_options,
    GET = cached({
        exptime = 30, -- cache expires after 30 seconds
        function (self)
            local query = 'where ispublished'

            -- Apply where clauses
            if self.params.matchtext then
                query = query ..
                    db.interpolate_query(
                        ' and (projectname ~* ? or notes ~* ?)',
                        self.params.matchtext,
                        self.params.matchtext
                    )
            end

            local paginator = Projects:paginated(query .. ' order by firstpublished desc', { per_page = self.params.pagesize or 16 })
            local projects = self.params.page and paginator:get_page(self.params.page) or paginator:get_all()

            if self.params.withthumbnail == 'true' then
                for _, project in pairs(projects) do
                    -- Lazy Thumbnail generation
                    project.thumbnail =
                        retrieve_from_disk(project.id, 'thumbnail') or
                            generate_thumbnail(project.id)
                end
            end

            return jsonResponse({
                pages = self.params.page and paginator:num_pages() or nil,
                projects = projects
            })
        end
    })
}))


app:match('user_projects', '/projects/:username', respond_to({
    -- Methods:     GET
    -- Description: Get metadata for a project list by a user.
    --              Response will depend on parameters and query issuer permissions.
    -- Parameters:  ispublished, page, pagesize, matchtext, withthumbnail, updatingnotes.

    OPTIONS = cors_options,
    GET = function (self)
        local order = 'lastshared'
        assert_user_exists(self)

        if self.session.username ~= self.params.username then
            local visitor = Users:find(self.session.username)
            if not visitor or not visitor.isadmin then
                self.params.ispublished = 'true'
                order = 'firstpublished'
            end
        end

        local query = db.interpolate_query('where username = ?', self.params.username)

        -- Apply where clauses
        if self.params.ispublished ~= nil then
            query = query ..
                db.interpolate_query(
                    ' and ispublished = ?',
                    self.params.ispublished == 'true'
                )
        end

        if self.params.matchtext then
            query = query ..
                db.interpolate_query(
                    ' and (projectname ~* ? or notes ~* ?)',
                    self.params.matchtext,
                    self.params.matchtext
                )
        end

        local paginator = Projects:paginated(query .. ' order by ' .. order .. ' desc', { per_page = self.params.pagesize or 16 })
        local projects = self.params.page and paginator:get_page(self.params.page) or paginator:get_all()

	-- Lazy Notes generation
        if self.params.updatingnotes == 'true' then
            for _, project in pairs(projects) do
                if (project.notes == nil or project.notes == '') then
                    local notes = parse_notes(project.id)
                    if notes then
                        project:update({ notes = notes })
                        project.notes = notes
                    end
                end
            end
        end

        if self.params.withthumbnail == 'true' then
            for _, project in pairs(projects) do
                -- Lazy Thumbnail generation
                project.thumbnail =
                    retrieve_from_disk(project.id, 'thumbnail') or
                        generate_thumbnail(project.id)
            end
        end

        return jsonResponse({
            pages = self.params.page and paginator:num_pages() or nil,
            projects = projects,
        })
    end
}))


app:match('project', '/projects/:username/:projectname', respond_to({
    -- Methods:     GET, DELETE, POST
    -- Description: Get/delete/add/update a particular project.
    --              Response will depend on query issuer permissions.
    -- Parameters:  delta, ispublic, ispublished
    -- Body:        xml, notes, thumbnail

    OPTIONS = cors_options,
    GET = capture_errors(function (self)
        local project = Projects:find(self.params.username, self.params.projectname)

        if not project then yield_error(err.nonexistent_project) end
        if not (project.ispublic or users_match(self)) then assert_admin(self, err.not_public_project) end

        -- self.params.delta is a version indicator
        -- delta = null will fetch the current version
        -- delta = -1 will fetch the previous saved version
        -- delta = -2 will fetch the last version before today

        return rawResponse(
            '<snapdata>' ..
            (retrieve_from_disk(project.id, 'project.xml', self.params.delta) or '<project></project>') ..
            (retrieve_from_disk(project.id, 'media.xml', self.params.delta) or '<media></media>') ..
            '</snapdata>'
        )
    end),
    DELETE = capture_errors(function (self)
        assert_all({'project_exists', 'user_exists'}, self)
        if not users_match(self) then assert_admin(self) end

        local project = Projects:find(self.params.username, self.params.projectname)
        delete_directory(project.id)
        if not (project:delete()) then
            yield_error('Could not delete user ' .. self.params.username)
        else
            return okResponse('User ' .. self.params.username .. ' has been removed.')
        end
    end),
    POST = capture_errors(function (self)
        validate.assert_valid(self.params, {
            { 'projectname', exists = true },
            { 'username', exists = true }
        })

        assert_all({'user_exists', 'users_match'}, self)

        -- Read request body and parse it into JSON
        ngx.req.read_body()
        local body_data = ngx.req.get_body_data()
        local body = body_data and util.from_json(body_data) or nil

        if (not body.xml) then
            yield_error('Empty project contents')
        end

        local project = Projects:find(self.params.username, self.params.projectname)

        if (project) then
            local shouldUpdateSharedDate =
                ((not project.lastshared and self.params.ispublic)
                or (self.params.ispublic and not project.ispublic))

            backup_project(project.id)

            project:update({
                lastupdated = db.format_date(),
                lastshared = shouldUpdateSharedDate and db.format_date() or nil,
                firstpublished =
                    project.firstpublished or
                    (self.params.ispublished and db.format_date()) or
                    nil,
                notes = body.notes,
                ispublic = self.params.ispublic or project.ispublic,
                ispublished = self.params.ispublished or project.ispublished
            })
        else
            Projects:create({
                projectname = self.params.projectname,
                username = self.params.username,
                created = db.format_date(),
                lastupdated = db.format_date(),
                lastshared = self.params.ispublic and db.format_date() or nil,
                firstpublished = self.params.ispublished and db.format_date() or nil,
                notes = body.notes,
                ispublic = self.params.ispublic or false,
                ispublished = self.params.ispublished or false
            })
            project = Projects:find(self.params.username, self.params.projectname)
        end

        save_to_disk(project.id, 'project.xml', body.xml)
        save_to_disk(project.id, 'thumbnail', body.thumbnail)
        save_to_disk(project.id, 'media.xml', body.media)

        if not (retrieve_from_disk(project.id, 'project.xml')
            and retrieve_from_disk(project.id, 'thumbnail')
            and retrieve_from_disk(project.id, 'media.xml')) then
            yield_error('Could not save project ' .. self.params.projectname)
        else
            return okResponse('project ' .. self.params.projectname .. ' saved')
        end

    end)
}))


app:match('project_meta', '/projects/:username/:projectname/metadata', respond_to({
    -- Methods:     GET, DELETE, POST
    -- Description: Get/add/update a project metadata.
    -- Parameters:  projectname, ispublic, ispublished, lastupdated, lastshared.
    -- Body:        notes, projectname

    OPTIONS = cors_options,
    GET = capture_errors(function (self)
        local project = Projects:find(self.params.username, self.params.projectname)

        if not project then yield_error(err.nonexistent_project) end
        if not project.ispublic then assert_users_match(self, err.not_public_project) end

        return jsonResponse(project)
    end),
    POST = capture_errors(function (self)
        assert_user_exists(self)
        if not users_match(self) then assert_admin(self) end

        local project = Projects:find(self.params.username, self.params.projectname)
        if not project then yield_error(err.nonexistent_project) end

        local shouldUpdateSharedDate =
            ((not project.lastshared and self.params.ispublic)
            or (self.params.ispublic and not project.ispublic))

        -- Read request body and parse it into JSON
        ngx.req.read_body()
        local body_data = ngx.req.get_body_data()
        local body = body_data and util.from_json(body_data) or nil
        local new_name = body and body.projectname or nil
        local new_notes = body and body.notes or nil

        project:update({
            projectname = new_name or project.projectname,
            lastupdated = db.format_date(),
            lastshared = shouldUpdateSharedDate and db.format_date() or nil,
            firstpublished =
                project.firstpublished or
                (self.params.ispublished and db.format_date()) or
                nil,
            notes = new_notes or project.notes,
            ispublic = self.params.ispublic or project.ispublic,
            ispublished = self.params.ispublished or project.ispublished
        })

        return okResponse('project ' .. self.params.projectname .. ' updated')
    end)
}))

app:match('project_versions', '/projects/:username/:projectname/versions', respond_to({
    -- Methods:     GET, DELETE, POST
    -- Description: Get info about backed up project versions.
    -- Parameters:
    -- Body:        versions

    OPTIONS = cors_options,
    GET = capture_errors(function (self)
        local project = Projects:find(self.params.username, self.params.projectname)

        if not project then yield_error(err.nonexistent_project) end
        if not project.ispublic then assert_users_match(self, err.not_public_project) end

        -- seconds since last modification
        local query = db.select('extract(epoch from age(now(), ?::timestamp))', project.lastupdated)[1]

        return jsonResponse({
            {
                lastupdated = query.date_part,
                thumbnail = retrieve_from_disk(project.id, 'thumbnail') or
                    generate_thumbnail(project.id),
                notes = parse_notes(project.id),
                delta = 0
            },
            version_metadata(project.id, -1),
            version_metadata(project.id, -2)
        })
    end)
}))


app:match('project_thumb', '/projects/:username/:projectname/thumbnail', respond_to({
    -- Methods:     GET
    -- Description: Get a project thumbnail.

    OPTIONS = cors_options,
    GET = capture_errors(
    cached({
        exptime = 30, -- cache expires after 30 seconds
        function (self)
            local project = Projects:find(self.params.username, self.params.projectname)
            if not project then yield_error(err.nonexistent_project) end

            if self.params.username ~= self.session.username
                and not project.ispublic then
                yield_error(err.auth)
            end

            -- Lazy Thumbnail generation
            return rawResponse(
                retrieve_from_disk(project.id, 'thumbnail') or
                    generate_thumbnail(project.id))
        end
    }))
}))


app:match('remix', '/projects/:username/:projectname/remix', respond_to({
    -- Methods:     POST
    -- Description: Remix a project as the currently logged in user.

    OPTIONS = cors_options,
    POST = capture_errors(function(self)
        local original_project = Projects:find(self.params.username, self.params.projectname)
        if not original_project then yield_error(err.nonexistent_project) end

        local visitor = Users:find(self.session.username)
        if not visitor then yield_error(err.not_logged_in) end

        Projects:create({
                projectname = original_project.projectname,
                username = visitor.username,
                created = db.format_date(),
                lastupdated = db.format_date(),
                lastshared = db.format_date(),
                firstpublished = original_project.ispublished and db.format_date() or nil,
                notes = original_project.notes,
                ispublic = original_project.ispublic,
                ispublished = original_project.ispublished,
                remixes = table.insert(original_project.remixes or {}, original_project.id)
            })
        project = Projects:find(self.params.username, self.params.projectname)

        save_to_disk(
            project.id,
            'project.xml',
            retrieve_from_disk(original_project.id, 'project.xml')
        )
        save_to_disk(
            project.id,
            'thumbnail',
            retrieve_from_disk(original_project.id, 'thumbnail')
        )
        save_to_disk(
            project.id,
            'media.xml',
            retrieve_from_disk(original_project.id, 'media.xml')
        )
        if not (retrieve_from_disk(project.id, 'project.xml')
            and retrieve_from_disk(project.id, 'thumbnail')
            and retrieve_from_disk(project.id, 'media.xml')) then
            project:delete()
            yield_error('Could not remix project ' .. self.params.projectname)
        else
            return okResponse('project ' .. self.params.projectname .. ' remixed')
        end
    end)
}))
