local InstantPrompt = {}
InstantPrompt.__index = InstantPrompt

local function executorFirePrompt()
    if type(getgenv) ~= "function" then
        return nil
    end
    local environment = getgenv()
    return type(environment.fireproximityprompt) == "function"
            and environment.fireproximityprompt
        or nil
end

function InstantPrompt.new(context)
    assert(context and context.service and type(context.getSettings) == "function")
    return setmetatable({ context = context, stopped = false }, InstantPrompt)
end

function InstantPrompt:_fire(prompt)
    if self.context.getSettings().instantPrompt ~= true or not prompt.Enabled then
        return
    end
    local firePrompt = executorFirePrompt()
    if firePrompt then
        pcall(firePrompt, prompt, 0)
        return
    end

    local originalDuration = prompt.HoldDuration
    prompt.HoldDuration = 0
    prompt:InputHoldBegin()
    task.defer(function()
        pcall(prompt.InputHoldEnd, prompt)
        if prompt.Parent then
            prompt.HoldDuration = originalDuration
        end
    end)
end

function InstantPrompt:start()
    self.connection = self.context.service.PromptShown:Connect(function(prompt)
        if not self.stopped then
            self:_fire(prompt)
        end
    end)
end

function InstantPrompt:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    if self.connection then
        self.connection:Disconnect()
    end
end

return InstantPrompt
