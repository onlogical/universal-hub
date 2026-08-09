local TrajectoryRenderer = {}
TrajectoryRenderer.__index = TrajectoryRenderer

function TrajectoryRenderer.new(options)
    local canvas
    if options.limn and options.limn:supportsPrimitive("Line") then
        canvas = options.limn:createCanvas()
    end
    return setmetatable({
        canvas = canvas,
        lines = {},
        projectileAim = options.projectileAim,
        workspace = options.workspace,
    }, TrajectoryRenderer)
end

function TrajectoryRenderer:render(path)
    if not self.canvas or path == nil and #self.lines == 0 then
        return
    end
    local camera = self.workspace.CurrentCamera
    local segments = camera and path and self.projectileAim.projectTrajectory(camera, path) or {}
    for index, segment in ipairs(segments) do
        local line = self.lines[index]
        if not line then
            line = self.canvas:create("Line")
            self.lines[index] = line
        end
        line:patch({
            Color = Color3.fromRGB(92, 214, 255),
            From = segment.from,
            Thickness = 2,
            To = segment.to,
            Transparency = 0.9,
            Visible = true,
            ZIndex = 20,
        })
    end
    for index = #segments + 1, #self.lines do
        self.lines[index]:patch({ Visible = false })
    end
end

function TrajectoryRenderer:stop()
    if self.canvas then
        self.canvas:destroy()
        self.canvas = nil
    end
    table.clear(self.lines)
end

return TrajectoryRenderer
