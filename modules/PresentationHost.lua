local PresentationHost = {}

function PresentationHost.mount(facade, presentation)
    assert(type(facade) == "table", "PresentationHost requires a generic Overlay facade")
    assert(type(facade.register) == "function", "PresentationHost requires panel registration")
    assert(type(facade.read) == "function", "PresentationHost requires state reads")
    assert(type(facade.patch) == "function", "PresentationHost requires state patches")
    assert(type(facade.action) == "function", "PresentationHost requires actions")
    assert(type(presentation) == "table" and type(presentation.mount) == "function")
    presentation.mount(facade)
    return facade
end

return PresentationHost
