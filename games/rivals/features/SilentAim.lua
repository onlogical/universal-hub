local SilentAim = {}

function SilentAim.point(aligned, origin, distance)
    local solution = aligned
        and (aligned.slingshot
            or aligned.splashImpact
            or aligned.projectileAim
            or aligned.ricochet)
    if solution and typeof(solution.direction) == "Vector3" then
        return origin + solution.direction.Unit * distance
    end
    return aligned and aligned.position
end

function SilentAim.clear(session, presentation)
    if presentation and type(presentation.clear) == "function" then
        presentation:clear()
    end
    if session then
        session.presented = nil
    end
end

function SilentAim.update(session, presentation, libs)
    libs = libs or {}
    local settings = session and session.settings or {}
    if settings.shotAim ~= true then
        SilentAim.clear(session, presentation)
        return
    end
    local origin = session.cameraOrigin
    local point = origin
        and SilentAim.point(session.aligned, origin, libs.maxDistance)
    if not point or not presentation then
        SilentAim.clear(session, presentation)
        return
    end
    presentation:update(libs.targeting.rotationToward(origin, point), session.aligned)
    session.presented = presentation:getPresentedTarget()
end

return SilentAim
