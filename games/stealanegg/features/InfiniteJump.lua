local InfiniteJump = {}
InfiniteJump.__index = InfiniteJump

function InfiniteJump.new(options)
    assert(options and options.inputService and options.localPlayer)
    return setmetatable({
        inputService = options.inputService,
        localPlayer = options.localPlayer,
        enabled = false,
    }, InfiniteJump)
end

function InfiniteJump:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then return end
    self.enabled = enabled
    if enabled then
        self.connection = self.inputService.JumpRequest:Connect(function()
            local character = self.localPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    elseif self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
end

function InfiniteJump:stop()
    self:setEnabled(false)
end

return InfiniteJump
