local Bloxstrike = {}

function Bloxstrike.new(context)
    assert(type(context) == "table", "Bloxstrike adapter requires context")
    local base = assert(context.tacticalAdapter, "Bloxstrike requires the shared tactical adapter")
    local preview = assert(context.bloxstrikePreview, "Bloxstrike requires its preview adapter")
    local adapter = base.new(context)
    preview.install(adapter, context)
    return adapter
end

return Bloxstrike
