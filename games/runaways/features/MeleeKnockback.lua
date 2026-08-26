local MeleeKnockback = {}
MeleeKnockback.__index = MeleeKnockback

local HIT_DELAY_SECONDS = 0.1
local HIT_RADIUS = 4.5

local function isMelee(character)
    local tool = character and character:FindFirstChildWhichIsA("Tool")
    return tool == nil or tool:HasTag("Melee")
end

function MeleeKnockback.new(context)
    assert(context and context.input and context.localPlayer and context.workspace)
    assert(type(context.getSettings) == "function")
    return setmetatable({ context = context, stopped = false }, MeleeKnockback)
end

function MeleeKnockback:_apply()
    local settings = self.context.getSettings()
    if settings.meleeKnockback ~= true then
        return
    end
    local character = self.context.localPlayer.Character
    local localRoot = character and character:FindFirstChild("HumanoidRootPart")
    local npcs = self.context.workspace:FindFirstChild("NPCs")
    if not localRoot or not npcs or not isMelee(character) then
        return
    end
    local force = math.max(tonumber(settings.meleeKnockbackForce) or 120, 0)
    for _, model in ipairs(npcs:GetChildren()) do
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
        if humanoid and humanoid.Health > 0 and root then
            local offset = root.Position - localRoot.Position
            if offset.Magnitude <= HIT_RADIUS and offset.Magnitude > 0 then
                local direction = (offset.Unit + Vector3.new(0, 0.25, 0)).Unit
                root:ApplyImpulse(direction * force * root.AssemblyMass)
            end
        end
    end
end

function MeleeKnockback:start()
    self.connection = self.context.input.InputBegan:Connect(function(input, processed)
        if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end
        task.delay(HIT_DELAY_SECONDS, function()
            if not self.stopped then
                self:_apply()
            end
        end)
    end)
end

function MeleeKnockback:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    if self.connection then
        self.connection:Disconnect()
    end
end

return MeleeKnockback
