local Targeting = {}

local function aliveCharacter(player)
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return character and humanoid and humanoid.Health > 0 and character or nil
end

function Targeting.isOpponent(localPlayer, player)
    return player ~= localPlayer and aliveCharacter(player) ~= nil
end

function Targeting.observations(players, localPlayer, camera)
    local observations = {}
    for _, player in ipairs(players:GetPlayers()) do
        if player ~= localPlayer then
            local character = aliveCharacter(player)
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if root and humanoid then
                local screen, onScreen = camera:WorldToViewportPoint(root.Position)
                local tool = character:FindFirstChildWhichIsA("Tool")
                table.insert(observations, {
                    bounds = onScreen and {
                        position = Vector2.new(screen.X - 30, screen.Y - 60),
                        size = Vector2.new(60, 120),
                    } or nil,
                    character = character,
                    health = humanoid.Health,
                    maxHealth = humanoid.MaxHealth,
                    part = root,
                    player = player,
                    position = root.Position,
                    tone = "enemy",
                    visible = onScreen,
                    weapon = tool and tool.Name or nil,
                })
            end
        end
    end
    return observations
end

return Targeting
