return {
    buildId = [[64f70c03]],
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
local MeleeKnockback = importDependency(
    "games/runaways/features/MeleeKnockback",
    "./features/MeleeKnockback"
)
local VehicleFly = importDependency("games/runaways/features/VehicleFly", "./features/VehicleFly")
local InstantPrompt = importDependency(
    "games/runaways/features/InstantPrompt",
    "./features/InstantPrompt"
)

local Adapter = {}

function Adapter.new(context)
    assert(context and context.store and context.render, "RUNAWAYS adapter requires a store and renderer")

    local Players = context.players or game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = context.workspace or workspace
    local LocalPlayer = context.localPlayer or Players.LocalPlayer
    local movement = Movement.new()
    local meleeKnockback = MeleeKnockback.new({
        input = UserInputService,
        localPlayer = LocalPlayer,
        workspace = Workspace,
        getSettings = function()
            return context.store:Get().settings
        end,
    })
    meleeKnockback:start()
    local vehicleFly = VehicleFly.new()
    local instantPrompt = InstantPrompt.new({
        getSettings = function()
            return context.store:Get().settings
        end,
        service = game:GetService("ProximityPromptService"),
    })
    instantPrompt:start()
    local stopped = false

    local connection = RunService.Heartbeat:Connect(function()
        if stopped then
            return
        end
        local camera = Workspace.CurrentCamera
        local settings = context.store:Get().settings
        movement:update(settings, LocalPlayer.Character, camera, UserInputService)
        vehicleFly:update(settings, LocalPlayer.Character, camera, UserInputService)
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
            "instantPrompt",
            "meleeKnockback",
            "meleeKnockbackForce",
            "speed",
            "vehicleFly",
            "vehicleFlySpeed",
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
            meleeKnockback:stop()
            vehicleFly:stop()
            instantPrompt:stop()
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
    host:number("movement", "flySpeed", "Fly Speed", { min = 0, parent = "fly" })
    host:option("movement", 2, "speed", "Speed")
    host:number("movement", "walkSpeed", "Walk Speed", { min = 0, parent = "speed" })
    host:option("movement", 3, "vehicleFly", "Vehicle Fly")
    host:number("movement", "vehicleFlySpeed", "Vehicle Fly Speed", {
        min = 0,
        parent = "vehicleFly",
    })

    host:section("Combat", "combat", "MELEE", 70)
    host:option("combat", 1, "meleeKnockback", "Melee Knockback")
    host:number("combat", "meleeKnockbackForce", "Knockback Force", {
        min = 0,
        parent = "meleeKnockback",
    })

    host:section("Tools", "automation", "AUTOMATION", 70)
    host:option("automation", 1, "instantPrompt", "Instant Prompt")
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
        ["games/runaways/features/InstantPrompt.lua"] = [[local InstantPrompt = {}
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
]],
        ["games/runaways/features/MeleeKnockback.lua"] = [[local MeleeKnockback = {}
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
        local desired = math.max(tonumber(settings.walkSpeed) or 32, 0)
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
    local speed = math.max(tonumber(settings.flySpeed) or 60, 0)
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
        ["games/runaways/features/VehicleFly.lua"] = [[local VehicleFly = {}
VehicleFly.__index = VehicleFly

function VehicleFly.new()
    return setmetatable({ root = nil, stopped = false }, VehicleFly)
end

function VehicleFly:release()
    if self.root and self.root.Parent then
        self.root.AssemblyLinearVelocity = Vector3.zero
        self.root.AssemblyAngularVelocity = Vector3.zero
    end
    self.root = nil
end

function VehicleFly:update(settings, character, camera, input)
    if self.stopped then
        return
    end
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local seat = humanoid and humanoid.SeatPart
    if
        settings.vehicleFly ~= true
        or not camera
        or not seat
        or not (seat:IsA("Seat") or seat:IsA("VehicleSeat"))
        or seat.Occupant ~= humanoid
    then
        self:release()
        return
    end
    local root = seat.AssemblyRootPart or seat
    self.root = root

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
    local speed = math.max(tonumber(settings.vehicleFlySpeed) or 100, 0)
    root.AssemblyLinearVelocity = direction.Magnitude > 1e-3 and direction.Unit * speed
        or Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

function VehicleFly:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    self:release()
end

return VehicleFly
]],
    },
}
