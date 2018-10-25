local schema = require("lapis.db.schema")
local types = schema.types

return {
    -- TODO add the initial tables as a schema.
  [00000100] = function()
    schema.rename_column('users', 'created', 'created_at')
    schema.rename_column('projects', 'created', 'created_at')
    schema.rename_column('tokens', 'created', 'created_at')
    schema.rename_column('projects', 'lastupdated', 'updated_at')
    schema.rename_column('projects', 'lastshared', 'shared_at')
    schema.rename_column('projects', 'firstpublished', 'first_published_at')
  end,

  [00000101] = function()
    schema.add_column('users', 'updated_at', types.time({ timezone = true, null = true }))
  end
}