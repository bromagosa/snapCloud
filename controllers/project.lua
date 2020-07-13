-- Project API controller
-- ======================
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

local util = package.loaded.util
local validate = package.loaded.validate
local db = package.loaded.db
local cached = package.loaded.cached
local yield_error = package.loaded.yield_error
local cjson = require('cjson')

local Projects = package.loaded.Projects
local Users = package.loaded.Users
local DeletedProjects = package.loaded.DeletedProjects
local Remixes = package.loaded.Remixes
local CollectionMemberships = package.loaded.CollectionMemberships

local disk = package.loaded.disk

require 'responses'
require 'validation'

ProjectController = {
    GET = {
        projects = cached({
            -- GET /projects
            -- Description: Get a list of published projects.
            -- Parameters:  page, pagesize, matchtext, withthumbnail, filtered
            exptime = 30, -- cache expires after 30 seconds
            function (self)
                local query = 'where ispublished'

                -- Apply where clauses
                if self.params.matchtext then
                    query = query ..
                        db.interpolate_query(
                            ' and (projectname ILIKE ? or notes ILIKE ?)',
                            self.params.matchtext,
                            self.params.matchtext
                        )
                end

                -- Apply project name filter to hide projects with typical
                -- BJC or Teals names.
                if self.params.filtered then
                    query = query .. db.interpolate_query(course_name_filter())
                end

                local paginator =
                    Projects:paginated(
                        query .. ' order by firstpublished desc',
                        { per_page = self.params.pagesize or 16 }
                    )

                local projects = self.params.page and
                    paginator:get_page(self.params.page) or paginator:get_all()

                if self.params.withthumbnail == 'true' then
                    disk:process_thumbnails(projects)
                end

                return jsonResponse({
                    pages = self.params.page and paginator:num_pages() or nil,
                    projects = projects
                })
            end
        }),

        user_projects = function (self)
            -- GET /projects/:username
            -- Description: Get metadata for a project list by a user.
            --              Response will depend on parameters and query issuer
            --              permissions.
            -- Parameters:  ispublished, page, pagesize, matchtext,
            --              withthumbnail, updatingnotes
            local order = 'lastupdated'

            if not (users_match(self)) then
                if not self.current_user or not self.current_user:isadmin() then
                    self.params.ispublished = 'true'
                    order = 'firstpublished'
                end
            end

            assert_user_exists(self)

            local query = db.interpolate_query('where username = ?',
                self.queried_user.username)

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
                        ' and (projectname ILIKE ? or notes ILIKE ?)',
                        self.params.matchtext,
                        self.params.matchtext
                    )
            end

            local paginator = Projects:paginated(query .. ' order by ' ..
                order .. ' desc', { per_page = self.params.pagesize or 16 })
            local projects = self.params.page and
                paginator:get_page(self.params.page) or paginator:get_all()

            if self.params.updatingnotes == 'true' then
                disk:process_notes(projects)
            end
            if self.params.withthumbnail == 'true' then
                disk:process_thumbnails(projects)
            end

            return jsonResponse({
                pages = self.params.page and paginator:num_pages() or nil,
                projects = projects
            })
        end,

        project = function (self)
            -- GET /projects/:username/:projectname
            -- Description: Get a particular project.
            --              Response will depend on query issuer permissions.
            -- Parameters:  delta, ispublic, ispublished
            local project =
                Projects:find(self.params.username, self.params.projectname)

            if not project then yield_error(err.nonexistent_project) end
            if not (project.ispublic or users_match(self)) then
                assert_admin(self, err.nonexistent_project)
            end

            -- self.params.delta is a version indicator
            -- delta = null will fetch the current version
            -- delta = -1 will fetch the previous saved version
            -- delta = -2 will fetch the last version before today

            return xmlResponse(
                -- if users don't match, this project is being remixed and we
                -- need to attach its ID
                '<snapdata' .. (users_match(self) and '>' or ' remixID="' ..
                    project.id .. '">') ..
                    (disk:retrieve(
                        project.id, 'project.xml', self.params.delta) or
                            '<project></project>') ..
                    (disk:retrieve(
                        project.id, 'media.xml', self.params.delta) or
                            '<media></media>') ..
                    '</snapdata>'
            )
        end,

        project_meta = function (self)
            -- GET /projects/:username/:projectname/metadata
            -- Description: Get a project metadata.
            -- Parameters:  projectname, ispublic, ispublished, lastupdated,
            --              lastshared
            local project =
                Projects:find(self.params.username, self.params.projectname)

            if not project then yield_error(err.nonexistent_project) end
            if not project.ispublic then
                assert_users_match(self, err.nonexistent_project)
            end

            local remixed_from =
                Remixes:select('where remixed_project_id = ?', project.id)[1]

            if CollectionMemberships:find(0, project.id) then
                project.flagged = true
            end

            if remixed_from then
                if remixed_from.original_project_id then
                    local original_project = Projects:select(
                        'where id = ?', remixed_from.original_project_id)[1]
                    project.remixedfrom = {
                        username = original_project.username,
                        projectname = original_project.projectname
                    }
                else
                    project.remixedfrom = {
                        username = nil,
                        projectname = nil
                    }
                end
            end

            return jsonResponse(project)
        end,

        project_versions = function (self)
            -- GET /projects/:username/:projectname/versions
            -- Description: Get info about backed up project versions.
            -- Body:        versions
            local project =
                Projects:find(self.params.username, self.params.projectname)

            if not project then yield_error(err.nonexistent_project) end
            if not project.ispublic then
                assert_users_match(self, err.nonexistent_project)
            end

            -- seconds since last modification
            local query = db.select(
                'extract(epoch from age(now(), ?::timestamp))',
                project.lastupdated)[1]

            return jsonResponse({
                {
                    lastupdated = query.date_part,
                    thumbnail = disk:retrieve(project.id, 'thumbnail') or
                        disk:generate_thumbnail(project.id),
                    notes = disk:parse_notes(project.id),
                    delta = 0
                },
                disk:get_version_metadata(project.id, -1),
                disk:get_version_metadata(project.id, -2)
            })
        end,

        project_remixes = function (self)
            -- GET /projects/:username/:projectname/remixes
            -- Description: Get a list of all published remixes from a project.
            -- Parameters:  page, pagesize
            local project =
                Projects:find(self.params.username, self.params.projectname)

            if not project then yield_error(err.nonexistent_project) end
            if not project.ispublic then
                assert_users_match(self, err.nonexistent_project)
            end

            --TODO fetch only remixes of non-deleted projects. Otherwise
            --     page count includes deleted remixes!
            local paginator =
                Remixes:paginated(
                    'where original_project_id = ?',
                    project.id,
                    { per_page = self.params.pagesize or 16 }
                )

            local remixes_metadata = self.params.page and
                paginator:get_page(self.params.page) or
                paginator:get_all()
            local remixes = {}

            for i, remix in pairs(remixes_metadata) do
                remixed_project = Projects:select(
                    'where id = ? and ispublished',
                    remix.remixed_project_id)[1];
                if (remixed_project) then
                    -- Lazy Thumbnail generation
                    remixed_project.thumbnail =
                        disk:retrieve(
                            remix.remixed_project_id,
                            'thumbnail') or
                                disk:generate_thumbnail(
                                    remix.remixed_project_id)
                    table.insert(remixes, remixed_project)
                end
            end

            return jsonResponse({
                pages = self.params.page and paginator:num_pages() or nil,
                projects = remixes
            })
        end,

        project_collections = cached({
            -- GET /projects/:username/:projectname/collections
            -- Description: Get a list of all collections this project belongs
            --              to
            -- Parameters:  page, pagesize
            exptime = 60, -- cache expires after 60 seconds
            function (self)
                local project =
                    Projects:find(self.params.username, self.params.projectname)

                if not project then yield_error(err.nonexistent_project) end
                if not project.ispublic then
                    assert_users_match(self, err.nonexistent_project)
                end

                -- This logic is extremely convoluted. It needs to be rethought.
                local query = db.interpolate_query(
                    'inner join collections on ' ..
                    'collection_memberships.collection_id = collections.id ' ..
                    'inner join users on collections.creator_id = users.id ' ..
                    'where collection_memberships.project_id = ? ' ..
                    'and (collections.published or ' ..
                    '(collections.shared and ?) or ' ..
                    '(not collections.shared and not ?)' ..
                        (self.current_user
                            and
                                (' or (collections.creator_id = ?) or ' ..
                                '(collections.editor_ids @> array[?]))')
                            or
                                ')'),
                    project.id,
                    project.ispublic,
                    project.ispublic,
                    self.current_user and self.current_user.id or nil,
                    self.current_user and self.current_user.id or nil
                )

                paginator = CollectionMemberships:paginated(
                    query,
                    {
                        fields = 'collections.creator_id, collections.name, ' ..
                            'collection_memberships.project_id, '..
                            'collections.thumbnail_id, collections.shared, ' ..
                            'collections.published, users.username',
                        per_page = self.params.pagesize or 16
                    })

                local collections = self.params.page and
                    paginator:get_page(self.params.page) or
                    paginator:get_all()

                disk:process_thumbnails(collections, 'thumbnail_id')

                return jsonResponse({
                    pages = self.params.page and paginator:num_pages() or nil,
                    collections = collections
                })
            end
        }),

        project_thumbnail = cached({
            -- GET /projects/:username/:projectname/thumbnail
            -- Description: Get a project thumbnail.
            exptime = 30, -- cache expires after 30 seconds
            function (self)
                local project =
                    Projects:find(self.params.username, self.params.projectname)
                if not project then yield_error(err.nonexistent_project) end

                if not users_match(self)
                    and not project.ispublic then
                    yield_error(err.nonexistent_project)
                end

                -- Lazy Thumbnail generation
                return rawResponse(
                    disk:retrieve(project.id, 'thumbnail') or
                        disk:generate_thumbnail(project.id))
            end
        })
    },

    POST = {
        project = function (self)
            -- POST /projects/:username/:projectname
            -- Description: Add/update a particular project.
            --              Response will depend on query issuer permissions.
            -- Body:        xml, notes, thumbnail
            validate.assert_valid(self.params, {
                { 'projectname', exists = true },
                { 'username', exists = true }
            })

            assert_all({assert_user_exists, assert_users_match}, self)

            -- Read request body and parse it into JSON
            ngx.req.read_body()
            local body_data = ngx.req.get_body_data()
            local body = body_data and util.from_json(body_data) or nil

            validate.assert_valid(body, {
                { 'xml', exists = true },
                { 'thumbnail', exists = true },
                { 'media', exists = true }
            })

            local project =
                Projects:find(self.params.username, self.params.projectname)

            if (project) then
                local shouldUpdateSharedDate =
                    ((not project.lastshared and self.params.ispublic)
                    or (self.params.ispublic and not project.ispublic))

                disk:backup_project(project.id)

                project:update({
                    lastupdated = db.format_date(),
                    lastshared =
                        shouldUpdateSharedDate and db.format_date() or nil,
                    firstpublished =
                        project.firstpublished or
                        (self.params.ispublished and db.format_date()) or
                        nil,
                    notes = body.notes,
                    ispublic = self.params.ispublic or project.ispublic,
                    ispublished = self.params.ispublished or project.ispublished
                })
            else
                -- Users are automatically verified the first time
                -- they save a project
                if (not self.queried_user.verified) then
                    self.queried_user:update({ verified = true })
                    self.session.verified = true
                end

                -- A project flagged as "deleted" with the same name may exist
                -- in the DB.
                -- We need to check for that and delete it for real this time
                local deleted_project = DeletedProjects:find(
                    self.params.username, self.params.projectname)
                if deleted_project then deleted_project:delete() end

                Projects:create({
                    projectname = self.params.projectname,
                    username = self.params.username,
                    created = db.format_date(),
                    lastupdated = db.format_date(),
                    lastshared = self.params.ispublic and
                        db.format_date() or nil,
                    firstpublished = self.params.ispublished
                        and db.format_date() or nil,
                    notes = body.notes,
                    ispublic = self.params.ispublic or false,
                    ispublished = self.params.ispublished or false
                })
                project =
                    Projects:find(self.params.username, self.params.projectname)

                if (body.remixID and body.remixID ~= cjson.null) then
                    -- user is remixing a project
                    Remixes:create({
                        original_project_id = body.remixID,
                        remixed_project_id = project.id,
                        created = db.format_date()
                    })
                end
            end

            disk:save(project.id, 'project.xml', body.xml)
            disk:save(project.id, 'thumbnail', body.thumbnail)
            disk:save(project.id, 'media.xml', body.media)

            if not (disk:retrieve(project.id, 'project.xml')
                and disk:retrieve(project.id, 'thumbnail')
                and disk:retrieve(project.id, 'media.xml')) then
                yield_error('Could not save project ' ..
                    self.params.projectname)
            else
                return okResponse('project ' .. self.params.projectname ..
                    ' saved')
            end
        end,

        project_meta = function (self)
            -- POST /projects/:username/:projectname/metadata
            -- Description: Add/update a project metadata. When admins and
            --              moderators unpublish somebody else's project, they
            --              also provide a reason that will be emailed to the
            --              project owner.
            -- Parameters:  projectname, ispublic, ispublished, lastupdated,
            --              lastshared, reason
            -- Body:        notes, projectname
            if not users_match(self) then assert_admin(self) end

            if self.current_user:isbanned() and self.params.ispublished then
                yield_error(err.banned)
            end

            local project =
                Projects:find(self.params.username, self.params.projectname)
            if not project then yield_error(err.nonexistent_project) end

            if self.params.ispublished == 'false' and self.params.reason then
                send_mail(
                    self.queried_user.email,
                    mail_subjects.project_unpublished .. project.projectname,
                    mail_bodies.project_unpublished .. self.current_user.role ..
                        '.</p><p>' .. self.params.reason .. '</p>')
            end

            local shouldUpdateSharedDate =
                ((not project.lastshared and self.params.ispublic)
                or (self.params.ispublic and not project.ispublic))

            -- Read request body and parse it into JSON
            -- TODO: Replace this with json_params() after updating the projectname key.
            ngx.req.read_body()
            local body_data = ngx.req.get_body_data()
            local body = body_data and util.from_json(body_data) or nil
            --local new_name = body and body.projectname and body.projectname ~= project.projectname
            --local new_notes = body and body.notes and body.notes ~= project.notes

            local result, error = project:update({
                --projectname = new_name and body.projectname or project.projectname,
                lastupdated = db.format_date(),
                lastshared = shouldUpdateSharedDate and db.format_date() or nil,
                firstpublished =
                    project.firstpublished or
                    (self.params.ispublished and db.format_date()) or
                    nil,
                --notes = new_notes and body.notes or project.notes,
                ispublic = self.params.ispublic or project.ispublic,
                ispublished = self.params.ispublished or project.ispublished
            })

            if error then yield_error({ msg = error, status = 422 }) end

            --[[
            -- save new notes and project name into the project XML
            if new_notes or new_name then
                disk:update_metadata(project.id, project.projectname, project.notes)
            end
            --]]

            return okResponse('project ' .. self.params.projectname .. ' updated')
        end
    },

    DELETE = {
        project = function (self)
            -- DELETE /projects/:username/:projectname
            -- Description: Delete a particular project. When admins and
            --              moderators delete somebody else's project, they
            --              also provide a reason that will be emailed to the
            --              project owner.
            --              Response will depend on query issuer permissions.
            -- Parameters:  reason
            assert_all({'project_exists', 'user_exists'}, self)
            if not users_match(self) then
                assert_has_one_of_roles(self, { 'admin', 'moderator' })
            end

            local project =
                Projects:find(self.params.username, self.params.projectname)

            if self.params.reason then
                send_mail(
                    self.queried_user.email,
                    mail_subjects.project_deleted .. project.projectname,
                    mail_bodies.project_deleted .. self.current_user.role ..
                        '.</p><p>' .. self.params.reason .. '</p>')
            end

            -- Do not actually delete the project; flag it as deleted.
            if not (project:update({ deleted = db.format_date() })) then
                yield_error('Could not delete project ' ..
                    self.params.projectname)
            else
                return okResponse('Project ' .. self.params.projectname
                    .. ' has been removed.')
            end
        end
    }
}
