local NoScope = {}

function NoScope.enabled(settings)
    return settings and settings.alwaysScoped == true
end

function NoScope.shouldRefresh(settings)
    return NoScope.enabled(settings) or settings and settings.shotAim == true
end

return NoScope
