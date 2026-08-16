local TaskCamera = {}

function TaskCamera.commit(camera, rotation)
    if not camera or typeof(rotation) ~= "Vector2" then
        return false
    end
    local frame = camera.CFrame
    if typeof(frame) ~= "CFrame" then
        return false
    end
    camera.CFrame = CFrame.new(frame.Position)
        * CFrame.Angles(0, rotation.Y, 0)
        * CFrame.Angles(rotation.X, 0, 0)
    return true
end

return TaskCamera
