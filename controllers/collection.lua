-- Collections API controller
-- ==========================
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

local db = package.loaded.db
local cached = package.loaded.cached
local util = package.loaded.util
local validate = package.loaded.validate
local json_params = package.loaded.app_helpers.json_params
local yield_error = package.loaded.app_helpers.yield_error
local assert_error = package.loaded.app_helpers.assert_error
local disk = package.loaded.disk

local Users = package.loaded.Users
local Projects = package.loaded.Projects
local Collections = package.loaded.Collections
local CollectionMemberships = package.loaded.CollectionMemberships

require 'responses'
require 'validation'

-- a simple helper for conditionally setting the timestamp fields
-- TODO: move to a more useful location.
local current_time_or_nil = function (option)
    if option == true then
        return db.raw('now()')
    end
    return nil
end

CollectionController = {
    GET = {
        collections = cached({
            -- GET /collections
            -- Description: Get a paginated list of all published collections
            --              with name matching matchtext, if provided.
            -- Parameters:  matchtext, page, pagesize
            exptime = 30, -- cache expires after 30 seconds
            function (self)
                local query =
                    'JOIN active_users on (active_users.id = collections.creator_id) ' ..
                    'WHERE published '

                -- Apply where clauses
                if self.params.matchtext then
                    query = query ..
                        db.interpolate_query(
                            ' and (name ILIKE ? or description ILIKE ?)',
                            self.params.matchtext,
                            self.params.matchtext
                        )
                end

                local paginator =
                    Collections:paginated(
                        query .. ' order by collections.published_at desc',
                        {
                            per_page = self.params.pagesize or 16,
                            fields =
                                'collections.id, creator_id, collections.created_at, published, ' ..
                                'collections.published_at, shared, collections.shared_at, ' .. 'collections.updated_at, name, ' ..
                                'description, thumbnail_id, username, editor_ids'
                        })

                local collections = self.params.page and
                    paginator:get_page(self.params.page) or paginator:get_all()

                disk:process_thumbnails(collections, 'thumbnail_id')

                return jsonResponse({
                    pages = self.params.page and paginator:num_pages() or nil,
                    collections = collections
                })
            end
        }),

        user_collections = function (self)
            -- GET /users/:username/collections
            -- Description: Get a paginated list of all a particular user's
            --              collections with name or description matching
            --              matchtext, if provided.
            --              Returns only public collections, if another user.
            -- Parameters:  username, matchtext, page, pagesize

            assert_user_exists(self)

            local order = 'updated_at'

            if not (users_match(self)) then
                if not self.current_user or not self.current_user:isadmin() then
                    self.params.published = 'true'
                    order = 'published_at'
                end
            end

            assert_user_exists(self)

            local query = db.interpolate_query(
                'join active_users on (active_users.id = collections.creator_id) ' ..
                    'where (creator_id = ? or editor_ids @> array[?])',
                self.queried_user.id,
                self.queried_user.id)

            -- Apply where clauses
            if self.params.published ~= nil then
                query = query ..
                    db.interpolate_query(
                        ' and published = ?',
                        self.params.published == 'true'
                    )
            end

            if self.params.matchtext then
                query = query ..
                    db.interpolate_query(
                        ' and (name ILIKE ? or description ILIKE ?)',
                        self.params.matchtext,
                        self.params.matchtext
                    )
            end

            local paginator = Collections:paginated(
                query .. ' order by ' .. order .. ' desc',
                {
                    per_page = self.params.pagesize or 16,
                    fields =
                        'collections.id, creator_id, collections.created_at, published, ' ..
                        'collections.published_at, shared, shared_at, collections.updated_at, name, ' ..
                        'description, thumbnail_id, username, editor_ids'
                })

            local collections = self.params.page and
                paginator:get_page(self.params.page) or paginator:get_all()

            disk:process_thumbnails(collections, 'thumbnail_id')

            return jsonResponse({
                pages = self.params.page and paginator:num_pages() or nil,
                collections = collections
            })
        end,

        collection_meta = function (self)
            -- GET /users/:username/collections/:name/metadata
            -- Description: Get info about a collection.
            -- Parameters:  username, name
            local collection = assert_collection_exists(self)
            assert_can_view_collection(self, collection)
            collection.projects_count = collection:count_projects()
            local creator =
                Users:select(
                    'where id = ?', collection.creator_id,
                    { fields = 'username, id' })[1]
            collection.username = creator.username
            if collection.thumbnail_id then
                collection.thumbnail =
                    disk:retrieve_thumbnail(collection.thumbnail_id)
            end
            if collection.editor_ids then
                collection.editors = Users:find_all(
                    collection.editor_ids,
                    { fields = 'username, id' })
            end

            return jsonResponse(collection)
        end,

        collection_projects = function (self)
            -- GET /users/:username/collections/:name/projects
            -- Description: Get a paginated list of all projects in a
            --              collection.
            -- Parameters:  username, name, withthumbnail, pagesize
            local collection = assert_collection_exists(self)
            assert_can_view_collection(self, collection)
            local paginator

            if self.current_user and
                    self.current_user.id == collection.creator_id then
                paginator = collection:get_projects()
            elseif collection.published then
                paginator = collection:get_published_projects()
            elseif collection.shared or
                    can_edit_collection(self, collection) then
                paginator = collection:get_shared_and_published_projects()
            elseif collection.id == 0 then
                -- flagged collection can be seen by anyone
                paginator = collection:get_projects()
            end

            paginator.per_page = self.params.pagesize or 16
            local projects = paginator:get_page(self.params.page or 1)

            if self.params.withthumbnail == 'true' then
                disk:process_thumbnails(projects)
            end

            return jsonResponse({
                pages = self.params.page and paginator:num_pages() or nil,
                projects = projects
            })
        end,

        collection_project = function (self)
            -- GET /users/:username/collections/:name/projects/:project_id
            -- Description: Get a project belonging to a collection
            -- Parameters:  username, name
            local collection = assert_collection_exists(self)
            return jsonResponse(CollectionMemberships:find(collection.id,
                self.params.project_id))
        end
    },

    POST = {
        collection = json_params(function (self)
            -- POST /users/:username/collections/:name
            -- Description: Create a collection.
            -- Parameters:  username, ...

            assert_users_match(self)
            local params = self.params
            local collection =
                Collections:find(self.queried_user.id, params.name)

            if collection then
                -- TODO: I think we can extract these into functions.
                local published = params.published ~= nil and
                    params.published == true
                local published_at = (published and collection.published_at) or
                    current_time_or_nil(published)
                local shared = params.shared ~= nil and params.shared == true
                local shared_at = (shared and collection.shared_at) or
                    current_time_or_nil(shared)

                collection:update({
                    name = params.name or collection.name,
                    description = params.description or collection.description,
                    published = published,
                    published_at = published_at,
                    shared = shared,
                    shared_at = shared_at,
                    thumbnail_id = params.thumbnail_id or
                        collection.thumbnail_id
                })

                return jsonResponse(collection)
            end

            return jsonResponse(assert_error(Collections:create({
                name = params.name,
                creator_id = self.queried_user.id,
                description = params.description,
                published = params.published == true,
                published_at = current_time_or_nil(params.published),
                shared = params.shared == true,
                shared_at = current_time_or_nil(params.shared),
                thumbnail_id = params.thumbnail_id
            })))
        end),

        collection_meta = function (self)
            -- POST /users/:username/collections/:name/metadata
            -- Description: Change metadata from a collection
            -- Parameters:  shared, published
            -- Body:        description, name
            if not users_match(self) then assert_admin(self) end

            if self.current_user:isbanned() and self.params.published then
                yield_error(err.banned)
            end

            ngx.req.read_body()
            local body_data = ngx.req.get_body_data()
            local body = body_data and util.from_json(body_data) or nil

            local collection = assert_collection_exists(self)

            local shouldUpdateSharedDate =
                ((not collection.shared_at and self.params.shared)
                or (self.params.shared and not collection.shared))

            local new_name = body and body.name or nil
            local new_description = body and body.description or nil

            collection:update({
                name = new_name or collection.name,
                description = new_description or collection.description,
                published = self.params.published or collection.published,
                shared = self.params.shared or collection.shared,
                published_at = collection.published_at or
                    (self.params.published and db.format_date()) or
                    nil,
                shared_at = shouldUpdateSharedDate and db.format_date() or nil
            })

            return okResponse('collection ' .. self.params.name .. ' updated')
        end,

        collection_editors = json_params(function (self)
            -- POST /users/:username/collections/:name/editors
            -- Description: Add an editor to a collection
            -- Body:        editor_username
            if not users_match(self) then assert_admin(self) end

            local editor = Users:find(
                { username = self.params.editor_username })
            if not editor then yield_error(err.nonexistent_user) end

            local collection = assert_collection_exists(self)

            collection:update({
                editor_ids =
                    db.raw(db.interpolate_query(
                        'array_append(editor_ids, ?)',
                        editor.id))
            })

            return okResponse('added ' .. self.params.editor_username ..
                ' as an editor')
        end),

        collection_projects = function (self)
            -- POST /users/:username/collections/:name/projects
            -- Description: Add a project to a collection.
            -- Body: projectname, username (project author)
            ngx.req.read_body()
            local body_data = ngx.req.get_body_data()
            local body = body_data and util.from_json(body_data) or nil

            local collection = assert_collection_exists(self)
            local project = Projects:find(body.username, body.projectname)

            -- Should let us add a project twice into the "Flagged" collection
            assert_project_not_in_collection(self, project, collection)
            assert_can_add_project_to_collection(self, project, collection)

            if not collection.thumbnail_id then
                collection:update({
                    thumbnail_id = project.id
                })
            end

            return jsonResponse(assert_error(CollectionMemberships:create({
                collection_id = collection.id,
                project_id = project.id,
                user_id = self.queried_user.id
            })))
        end,

        collection_thumbnail = function (self)
            -- POST /users/:username/collections/:name/thumbnail
            -- Description: Sets the collection thumbnail
            -- Parameters: id
            local collection = assert_collection_exists(self)
            local project = Projects:find({ id = self.params.id })

            assert_can_add_project_to_collection(self, project, collection)

            collection:update({
                thumbnail_id = self.params.id
            })

            return okResponse('Thumbnail set')
        end
    },

    DELETE = {
        collection = function (self)
            -- DELETE /users/:username/collections/:name
            -- Description: Delete a particular collection.
            local collection = assert_collection_exists(self)
            if not users_match(self) then
                assert_has_one_of_roles(self, { 'moderator', 'admin' })
            end
            return jsonResponse(assert_error(collection:delete()))
        end,

        collection_project = function (self)
            -- DELETE /users/:username/collections/:name/projects/:project_id
            -- Description: Remove a project from a collection.
            -- Parameters:  username, name
            local collection = assert_collection_exists(self)
            assert_can_remove_project_from_collection(self, collection)
            local membership =
                CollectionMemberships:find(
                    collection.id,
                    self.params.project_id)
            return jsonResponse(assert_error(membership:delete()))
        end,

        collection_editors = function (self)
            -- DELETE /users/:username/collections/:name
            --            /editors/:editor_username
            -- Description: Remove an editor from a collection
            if not users_match(self) then assert_admin(self) end

            local editor = Users:find(
                { username = self.params.editor_username })
            if not editor then yield_error(err.nonexistent_user) end

            local collection = assert_collection_exists(self)

            collection:update({
                editor_ids =
                    db.raw(db.interpolate_query(
                        'array_remove(editor_ids, ?)',
                        editor.id))
            })

            return okResponse(self.params.editor_username ..
                ' removed from collection editors')
        end,
    }
}
