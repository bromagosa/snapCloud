-- Disk storage utils
-- ==================
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


-- we store max 1000 projects per dir

local xml = require("xml")
local config = package.loaded.config
local yield_error = package.loaded.yield_error

local disk = {}

function disk:timestamp_command(dir)
    return 'stat ' .. config.stat_arguments .. ' ' .. dir .. '/project.xml'
end

function disk:directory_for_id (id)
    return config.store_path .. '/' .. math.floor(id / 1000) .. '/' .. id
end

function disk:save (id, filename, contents)
    local dir = self:directory_for_id(id)
    os.execute('mkdir -p ' .. dir)
    local file = io.open(dir .. '/' .. filename, 'w+')
    if (file) then
        file:write(contents)
        file:close()
    end
end

function disk:retrieve (id, filename, delta)
    local dir = self:directory_for_id(id)
    -- if delta exists, we look for a previous version of the file
    -- under dir/d[delta]
    if (delta) then dir = dir .. '/d' .. delta end
    local file = io.open(dir .. '/' .. filename, 'r')
    if (file) then
        local contents = file:read("*all")
        file:close()
        return contents
    else
        return nil
    end
end

function disk:retrieve_thumbnail (id)
    return self:retrieve(id, 'thumbnail')
end

function disk:generate_thumbnail (id)
    local project_file = io.open(self:directory_for_id(id) .. '/project.xml')
    if (project_file) then
        local project = xml.load(project_file:read('*all'))
        local thumbnail = xml.find(project, 'thumbnail')[1]
        project_file:close()
        self:save(id, 'thumbnail', thumbnail)
        return thumbnail
    else
        return false
    end
end

function disk:parse_notes (id, delta)
    local dir = self:directory_for_id(id)
    -- if delta exists, we look for a previous version of the file
    -- under dir/d[delta]
    if (delta) then dir = dir .. '/d' .. delta end
    local project_file = io.open(dir .. '/project.xml', 'r')
    local notes
    if (project_file) then
        if pcall(
            function ()
                local project = xml.load(project_file:read('*all'))
                notes = xml.find(project, 'notes')[1]
            end) then
            project_file:close()
            return notes or ''
        else
            project_file:close()
            return ''
        end
    else
        return ''
    end
end

function disk:update_notes (id, notes)
    self:update_xml(id, function (project)
        local old_notes = xml.find(project, 'notes')
        old_notes[1] = notes
    end)
end

function disk:update_name(id, name)
    self:update_xml(id, function (project)
        project.name = name
    end)
end

function disk:update_metadata(id, name, notes)
    self:update_xml(id, function (project)
        project.name = name
        local old_notes = xml.find(project, 'notes')
        old_notes[1] = notes
    end)
end

function disk:update_xml(id, update_function)
    local dir = self:directory_for_id(id)
    local project_file = io.open(dir .. '/project.xml', 'r')
    if (project_file) then
        local success, message = pcall(
            function ()
                local project = xml.load(project_file:read('*all'))
                project_file:close()
                self:backup_project(id)
                update_function(project)
                project_file = io.open(dir .. '/project.xml', 'w+')
                project_file:write(xml.dump(project))
                project_file:close()
            end)
        if success then
            project_file = io.open(dir .. '/project.xml', 'r')
            local contents = project_file:read('*all')
            if #contents == 0 then
                -- File length is zero! File got corrupted somehow.
                -- Let's recover the previous delta, which was backed up right
                -- before attempting to update the XML.
                project_file = io.open(dir .. '/project.xml', 'w+')
                local backup = self:retrieve(id, 'project.xml', '-1')
                project_file:write(backup)
                project_file:close()
                yield_error(err.update_project_fail)
            else
                project_file:close()
            end
        else
            if project_file then project_file:close() end
            ngx.log(message)
            yield_error(err.unparseable_xml .. tostring(message))
        end
    else
        yield_error(err.file_not_found)
    end
end

function disk:get_version_metadata(id, delta)
    local dir = self:directory_for_id(id) .. '/d' .. delta
    local project_file = io.open(dir .. '/project.xml', 'r')
    if (project_file) then
        local command = io.popen(self:timestamp_command(dir))
        local last_modified = tonumber(command:read())
        command:close()
        return {
            notes = self:parse_notes(id, delta),
            thumbnail = self:retrieve(id, 'thumbnail', delta),
            -- seconds since last modification
            lastupdated = os.time() - last_modified,
            delta = delta
        }
    else
        return nil
    end
end

function disk:backup_project(id)
    -- This function is called right before saving a project
    local dir = self:directory_for_id(id)

    -- We always save the current copy into the /d-1 folder
    os.execute('mkdir -p ' .. dir .. '/d-1')
    os.execute('cp -p ' .. dir .. '/*.xml ' .. dir .. '/thumbnail ' ..
        dir .. '/d-1')
    -- If the current project was modified more than 12 hours ago,
    -- we save it into the /d-2 folder
    local command = io.popen(self:timestamp_command(dir))
    local last_modified = tonumber(command:read())
    command:close()
    if (os.time() - last_modified > 43200) then
        os.execute('mkdir -p ' .. dir .. '/d-2')
        os.execute('cp -p ' .. dir .. '/*.xml ' .. dir .. '/thumbnail ' .. dir .. '/d-2')
    end
end

function disk:process_notes (projects)
    -- Lazy Notes generation
    for _, project in pairs(projects) do
        if (project.notes == nil) then
            local notes = self:parse_notes(project.id)
            if notes then
                project:update({ notes = notes })
                project.notes = notes
            end
        end
    end
end

function disk:process_thumbnails (items, id_selector)
    -- Lazy Thumbnail generation
    for _, item in pairs(items) do
        if (item[id_selector or 'id']) then
            item.thumbnail =
                self:retrieve_thumbnail(item[id_selector or 'id']) or
                self:generate_thumbnail(item[id_selector or 'id'])
        end
    end
end

return disk
