local DuelEscape = {}
DuelEscape.__index = DuelEscape

local DEFAULT_KEY = "End"
local COOLDOWN = 1.5

local function inputKeyName(input)
    local keyCode = input and input.KeyCode
    if type(keyCode) == "string" and keyCode ~= "Unknown" then
        return keyCode
    end
    if type(keyCode) ~= "string" and keyCode and keyCode.Name ~= "Unknown" then
        return keyCode.Name
    end
    local inputType = input and input.UserInputType
    if type(inputType) == "string" then
        return inputType
    end
    return inputType and inputType.Name or nil
end

function DuelEscape.shouldTrigger(input, gameProcessed, settings, duelActive, now, lastEscapeAt)
    if gameProcessed == true or duelActive ~= true then
        return false
    end
    local configuredKey = settings and settings.duelEscapeKey or DEFAULT_KEY
    if type(configuredKey) ~= "string" or configuredKey == "" then
        configuredKey = DEFAULT_KEY
    end
    if inputKeyName(input) ~= configuredKey then
        return false
    end
    return now - (lastEscapeAt or -math.huge) >= COOLDOWN
end

function DuelEscape.new(options)
    assert(type(options) == "table", "DuelEscape requires options")
    assert(options.inputService, "DuelEscape requires UserInputService")
    assert(options.localPlayer, "DuelEscape requires LocalPlayer")
    assert(options.store, "DuelEscape requires a store")

    local self = setmetatable({
        clearTarget = options.clearTarget,
        getRoot = options.getRoot,
        isDuelActive = options.isDuelActive,
        lastEscapeAt = -math.huge,
        localPlayer = options.localPlayer,
        stopMovement = options.stopMovement,
        stopped = false,
        store = options.store,
        workspace = options.workspace or workspace,
    }, DuelEscape)

    self.connection = options.inputService.InputBegan:Connect(function(input, gameProcessed)
        self:_onInput(input, gameProcessed)
    end)
    return self
end

function DuelEscape:_destination()
    local lobbyMap = self.workspace:FindFirstChild("LobbyMap")
    local spawner = lobbyMap and lobbyMap:FindFirstChild("LobbySpawner")
    if not spawner then
        return nil
    end
    if spawner:IsA("BasePart") then
        return spawner.CFrame * CFrame.new(0, spawner.Size.Y / 2 + 4, 0)
    end
    if spawner:IsA("Model") then
        local size = spawner:GetExtentsSize()
        return spawner:GetPivot() * CFrame.new(0, size.Y / 2 + 4, 0)
    end
    return nil
end

function DuelEscape:_onInput(input, gameProcessed)
    if self.stopped then
        return
    end
    local now = os.clock()
    local settings = self.store:Get().settings or {}
    local duelActive = type(self.isDuelActive) == "function" and self.isDuelActive() == true
    if not DuelEscape.shouldTrigger(
        input,
        gameProcessed,
        settings,
        duelActive,
        now,
        self.lastEscapeAt
    ) then
        return
    end

    local root = type(self.getRoot) == "function" and self.getRoot() or nil
    if not root then
        local playerCharacter = self.localPlayer.Character
        root = playerCharacter and playerCharacter:FindFirstChild("HumanoidRootPart")
    end
    local character = root and root:FindFirstAncestorWhichIsA("Model")
    local destination = self:_destination()
    if not character or not root or not destination then
        return
    end

    self.lastEscapeAt = now
    self.store:Patch({ settings = { autoFight = false, autoMovement = false } })
    if type(self.clearTarget) == "function" then
        self.clearTarget()
    end
    if type(self.stopMovement) == "function" then
        self.stopMovement()
    end
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    character:PivotTo(destination)
end

function DuelEscape:stop()
    if self.stopped then
        return
    end
    self.stopped = true
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
end

return DuelEscape
