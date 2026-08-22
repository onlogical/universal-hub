local MultiJump = {}
MultiJump.__index = MultiJump

function MultiJump.new(options)
    assert(type(options) == "table", "MultiJump requires options")
    assert(type(options.getHumanoid) == "function", "MultiJump requires getHumanoid")
    assert(options.inputService, "MultiJump requires UserInputService")
    assert(options.store, "MultiJump requires a store")

    local self = setmetatable({
        getHumanoid = options.getHumanoid,
        stopped = false,
        store = options.store,
    }, MultiJump)

    self.connection = options.inputService.JumpRequest:Connect(function()
        self:_jump()
    end)
    return self
end

function MultiJump:_jump()
    if self.stopped then
        return
    end
    local settings = self.store:Get().settings or {}
    if settings.multiJump ~= true then
        return
    end
    local humanoid = self.getHumanoid()
    if not humanoid or humanoid.Health <= 0 then
        return
    end
    humanoid.Jump = true
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end

function MultiJump:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
end

return MultiJump
