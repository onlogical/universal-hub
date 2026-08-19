local TeleportBehind = {}

function TeleportBehind.update(settings, frame)
    if settings.teleportBehind ~= true
        or not frame
        or frame.targetDead == true
        or not frame.localRoot
        or not frame.targetRoot
    then
        return false
    end

    local targetLook = frame.targetRoot.CFrame.LookVector
    local flatLook = Vector3.new(targetLook.X, 0, targetLook.Z)
    if flatLook.Magnitude <= 0.001 then
        return false
    end

    local destination = frame.targetRoot.Position
        - flatLook.Unit * (frame.distance or 3)
    frame.localRoot.CFrame = CFrame.lookAt(
        destination,
        Vector3.new(
            frame.targetRoot.Position.X,
            destination.Y,
            frame.targetRoot.Position.Z
        )
    )
    return true
end

return TeleportBehind
