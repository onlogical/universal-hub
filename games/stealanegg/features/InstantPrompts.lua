local InstantPrompts = {}
InstantPrompts.__index = InstantPrompts

function InstantPrompts.new(root)
    assert(root, "Instant Prompts requires a root instance")
    return setmetatable({
        root = root,
        entries = {},
        enabled = false,
    }, InstantPrompts)
end

function InstantPrompts:_apply(instance)
    if not self.enabled or not instance:IsA("ProximityPrompt") then
        return
    end

    local entry = self.entries[instance]
    if not entry then
        entry = {
            original = instance.HoldDuration,
        }
        self.entries[instance] = entry
        entry.connection = instance:GetPropertyChangedSignal("HoldDuration"):Connect(function()
            if not self.enabled or instance.HoldDuration == 0 then
                return
            end
            entry.original = instance.HoldDuration
            instance.HoldDuration = 0
        end)
    end
    instance.HoldDuration = 0
end

function InstantPrompts:_forget(instance)
    local entry = self.entries[instance]
    if not entry then
        return
    end
    pcall(entry.connection.Disconnect, entry.connection)
    self.entries[instance] = nil
end

function InstantPrompts:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled

    if enabled then
        for _, instance in ipairs(self.root:GetDescendants()) do
            self:_apply(instance)
        end
        self.addedConnection = self.root.DescendantAdded:Connect(function(instance)
            self:_apply(instance)
        end)
        self.removingConnection = self.root.DescendantRemoving:Connect(function(instance)
            self:_forget(instance)
        end)
        return
    end

    local addedConnection = self.addedConnection
    local removingConnection = self.removingConnection
    self.addedConnection = nil
    self.removingConnection = nil
    if addedConnection then
        pcall(addedConnection.Disconnect, addedConnection)
    end
    if removingConnection then
        pcall(removingConnection.Disconnect, removingConnection)
    end
    for prompt, entry in pairs(self.entries) do
        pcall(entry.connection.Disconnect, entry.connection)
        if prompt.Parent then
            pcall(function()
                prompt.HoldDuration = entry.original
            end)
        end
    end
    table.clear(self.entries)
end

function InstantPrompts:stop()
    self:setEnabled(false)
end

return InstantPrompts
