local Adapter = {}

function Adapter.new(context)
    assert(type(context) == "table", "Simple game adapter requires a context")
    return {
        stop = function() end,
    }
end

return Adapter
