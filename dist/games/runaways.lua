return {
    buildId = [[41e56994]],
    id = [[runaways]],
    sources = {
        ["games/runaways/Adapter.lua"] = [[local function importDependency(path, relativePath)
    if type(getgenv) == "function" then
        local environment = getgenv()
        local configuration = environment and environment.UniversalHubConfig
        if configuration and type(configuration.Import) == "function" then
            return configuration.Import(path)
        end
    end
    return require(relativePath)
end

local Targeting = importDependency("games/runaways/Targeting", "./Targeting")
local Movement = importDependency("games/runaways/features/Movement", "./features/Movement")

local Adapter = {}

function Adapter.new(context)
    assert(context and context.store and context.render, "RUNAWAYS adapter requires a store and renderer")

    local Players = context.players or game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = context.workspace or workspace
    local LocalPlayer = context.localPlayer or Players.LocalPlayer
    local movement = Movement.new()
    local stopped = false

    local connection = RunService.Heartbeat:Connect(function()
        if stopped then
            return
        end
        local camera = Workspace.CurrentCamera
        local settings = context.store:Get().settings
        movement:update(settings, LocalPlayer.Character, camera, UserInputService)
        context.render(
            camera and Targeting.observations(Players, LocalPlayer, camera) or {},
            UserInputService:GetMouseLocation(),
            {}
        )
    end)

    return {
        capabilities = {
            "boxes",
            "chams",
            "showEnemies",
            "showTeammates",
            "names",
            "health",
            "weapon",
            "fly",
            "flySpeed",
            "speed",
            "walkSpeed",
        },
        isOpponent = function(player)
            return Targeting.isOpponent(LocalPlayer, player)
        end,
        stop = function()
            if stopped then
                return
            end
            stopped = true
            connection:Disconnect()
            movement:stop()
        end,
    }
end

return Adapter
]],
        ["games/runaways/Presentation.lua"] = [[local Presentation = {}

function Presentation.mount(host)
    host:section("Visuals", "visuals", "PLAYERS", 70, false, 1, { treatment = "grid" })
    host:option("visuals", 1, "boxes", "Hitboxes")
    host:option("visuals", 1, "chams", "Chams")
    host:option("visuals", 2, "names", "Names")
    host:option("visuals", 2, "health", "Health")
    host:option("visuals", 3, "weapon", "Held Items")
    host:option("visuals", 20, "showEnemies", "Players", "audience")

    host:section("Movement", "movement", "MOVEMENT", 70)
    host:option("movement", 1, "fly", "Fly")
    if type(host.slider) == "function" then
        host:slider("movement", "flySpeed", "Fly Speed", {
            min = 20,
            max = 500,
            step = 10,
            parent = "fly",
        })
    end
    host:option("movement", 2, "speed", "Speed")
    if type(host.slider) == "function" then
        host:slider("movement", "walkSpeed", "Walk Speed", {
            min = 16,
            max = 100,
            step = 2,
            parent = "speed",
        })
    end
end

return Presentation
]],
        ["games/runaways/Targeting.lua"] = [[local Targeting = {}

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
]],
        ["games/runaways/features/Movement.lua"] = [[local Movement = {}
Movement.__index = Movement

local function humanoidAndRoot(character)
    return character and character:FindFirstChildOfClass("Humanoid"),
        character and character:FindFirstChild("HumanoidRootPart")
end

function Movement.new()
    return setmetatable({ stopped = false }, Movement)
end

function Movement:releaseFly()
    local humanoid = self.flyHumanoid
    if humanoid and humanoid.Parent then
        humanoid.PlatformStand = self.flyPlatformStand == true
    end
    if self.flyRoot and self.flyRoot.Parent then
        self.flyRoot.AssemblyLinearVelocity = Vector3.zero
    end
    self.flyHumanoid = nil
    self.flyPlatformStand = nil
    self.flyRoot = nil
end

function Movement:releaseSpeed()
    local humanoid = self.speedHumanoid
    if humanoid and humanoid.Parent and humanoid.WalkSpeed == self.appliedWalkSpeed then
        humanoid.WalkSpeed = self.speedOriginal
    end
    self.speedHumanoid = nil
    self.speedOriginal = nil
    self.appliedWalkSpeed = nil
end

function Movement:update(settings, character, camera, input)
    if self.stopped then
        return
    end
    local humanoid, root = humanoidAndRoot(character)

    if settings.speed == true and humanoid then
        local desired = math.clamp(tonumber(settings.walkSpeed) or 32, 16, 100)
        if self.speedHumanoid ~= humanoid then
            self:releaseSpeed()
            self.speedHumanoid = humanoid
            self.speedOriginal = humanoid.WalkSpeed
        end
        humanoid.WalkSpeed = desired
        self.appliedWalkSpeed = desired
    else
        self:releaseSpeed()
    end

    if settings.fly ~= true or not humanoid or not root or not camera then
        self:releaseFly()
        return
    end
    if self.flyHumanoid ~= humanoid then
        self:releaseFly()
        self.flyHumanoid = humanoid
        self.flyPlatformStand = humanoid.PlatformStand
        self.flyRoot = root
    end

    humanoid.PlatformStand = true
    local direction = Vector3.zero
    if input:IsKeyDown(Enum.KeyCode.W) then
        direction += camera.CFrame.LookVector
    end
    if input:IsKeyDown(Enum.KeyCode.S) then
        direction -= camera.CFrame.LookVector
    end
    if input:IsKeyDown(Enum.KeyCode.D) then
        direction += camera.CFrame.RightVector
    end
    if input:IsKeyDown(Enum.KeyCode.A) then
        direction -= camera.CFrame.RightVector
    end
    if input:IsKeyDown(Enum.KeyCode.Space) then
        direction += Vector3.yAxis
    end
    if input:IsKeyDown(Enum.KeyCode.LeftControl) then
        direction -= Vector3.yAxis
    end
    local speed = math.clamp(tonumber(settings.flySpeed) or 60, 20, 500)
    root.AssemblyLinearVelocity = direction.Magnitude > 1e-3 and direction.Unit * speed
        or Vector3.zero
end

function Movement:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:releaseFly()
    self:releaseSpeed()
end

return Movement
]],
    },
}
