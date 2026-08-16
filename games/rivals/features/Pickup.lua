local Pickup = {}

function Pickup.update(session, runtime)
    local settings = session and session.settings or {}
    if settings.autoPickup ~= true or not runtime then
        return false
    end
    runtime:update()
    return true
end

return Pickup
