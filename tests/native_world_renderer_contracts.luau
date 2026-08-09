local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
Color3 = roblox.Color3
Enum = roblox.Enum
UDim = roblox.UDim
UDim2 = roblox.UDim2
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3

local Store = require("../modules/Store")
local NativeWorldRenderer = require("../modules/NativeWorldRenderer")
local rendererSource = fs.readFile("modules/NativeWorldRenderer.lua")
local initSource = fs.readFile("init.lua")
assert(initSource:find('local RunService = game:GetService("RunService")', 1, true)
    and initSource:find("runService = RunService", 1, true),
    "Production context must provide RunService to NativeWorldRenderer")
assert(rendererSource:find("context.runService.Heartbeat:Connect", 1, true),
    "Distance refresh must use one low-frequency Heartbeat accumulator")
assert(rendererSource:find("DISTANCE_REFRESH_INTERVAL = 0.25", 1, true),
    "Distance refresh must be throttled to about 4Hz")
assert(rendererSource:find("HIGHLIGHT_DISTANCE = 1000", 1, true)
    and rendererSource:find("HIGHLIGHT_DISTANCE_HYSTERESIS", 1, true),
    "Per-part Highlights must use a distance boundary with hysteresis")
assert(rendererSource:find("table.sort(candidates", 1, true)
    and rendererSource:find("math.min(#candidates, NativeWorldRenderer.HIGHLIGHT_BUDGET)", 1, true),
    "Nearest in-range subjects must receive the global Highlight budget first")
assert(rendererSource:find("math.floor(NativeWorldRenderer.HIGHLIGHT_BUDGET / poolCount)", 1, true)
    and rendererSource:find("baseBudget * poolCount", 1, true),
    "The distance pool must split the global budget fairly per subject")
assert(rendererSource:find("self:_rebalanceHighlights()", 1, true),
    "Subject membership changes must trigger fair Highlight reallocation")
assert(rendererSource:find("subject.character:GetDescendants()", 1, true)
    and rendererSource:find("for _, part in ipairs(bodyParts)", 1, true)
    and rendererSource:find("for _, part in ipairs(accessoryParts)", 1, true),
    "Per-part allocation must retain recursive discovery and body-before-accessory priority")
assert(not rendererSource:find("RenderStepped", 1, true)
    and not rendererSource:find('GetPropertyChangedSignal("CFrame")', 1, true),
    "Native distance budgeting must not poll every frame or subscribe per part")

local function signal()
    local callbacks = {}
    local value = {}
    function value:Connect(callback)
        table.insert(callbacks, callback)
        local connected = true
        return { Disconnect = function()
            if not connected then return end
            connected = false
            local index = table.find(callbacks, callback)
            if index then table.remove(callbacks, index) end
        end }
    end
    function value:Fire(...)
        for _, callback in ipairs(table.clone(callbacks)) do callback(...) end
    end
    function value:count() return #callbacks end
    return value
end

local function object(className, children)
    local value = {
        ClassName = className,
        ChildAdded = signal(),
        ChildRemoved = signal(),
        children = children or {},
    }
    function value:IsA(name)
        return self.ClassName == name
            or (name == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart"))
    end
    function value:GetChildren() return table.clone(self.children) end
    function value:FindFirstChild(name)
        for _, child in ipairs(self.children) do
            if child.Name == name then return child end
        end
        return nil
    end
    function value:FindFirstChildOfClass(name)
        for _, child in ipairs(self.children) do
            if child:IsA(name) then return child end
        end
        return nil
    end
    function value:add(child)
        table.insert(self.children, child)
        self.ChildAdded:Fire(child)
    end
    function value:remove(child)
        table.remove(self.children, assert(table.find(self.children, child)))
        self.ChildRemoved:Fire(child)
    end
    return value
end

local guiParent = object("ScreenGui")
local created = {}
local function createInstance(className)
    local value = object(className)
    value.Destroyed = false
    function value:Destroy() self.Destroyed = true end
    table.insert(created, value)
    return value
end

local humanoid = object("Humanoid")
humanoid.Health = 25
humanoid.MaxHealth = 100
humanoid.HealthChanged = signal()
local maxHealthChanged = signal()
function humanoid:GetPropertyChangedSignal(name)
    assert(name == "MaxHealth")
    return maxHealthChanged
end
local rootPart = object("Part") rootPart.Name = "HumanoidRootPart" rootPart.Position = Vector3.new(100, 0, 0)
local torso = object("MeshPart") torso.Name = "Torso" torso.Position = rootPart.Position
local accessoryHandle = object("Part") accessoryHandle.Name = "Handle"
local accessory = object("Accessory", { accessoryHandle }) accessory.Name = "Hat"
local character = object("Model", { humanoid, rootPart, torso, accessory })
character.PrimaryPart = rootPart
local player = {
    Name = "Remote",
    Character = character,
    CharacterAdded = signal(),
    CharacterRemoving = signal(),
}
local localRoot = object("Part") localRoot.Name = "HumanoidRootPart" localRoot.Position = Vector3.zero
local localCharacter = object("Model", { localRoot }) localCharacter.PrimaryPart = localRoot
local localPlayer = {
    Name = "Local",
    Character = localCharacter,
    CharacterAdded = signal(),
    CharacterRemoving = signal(),
}
local heartbeat = signal()
local runService = { Heartbeat = heartbeat }
local players = {
    LocalPlayer = localPlayer,
    PlayerAdded = signal(),
    PlayerRemoving = signal(),
}
function players:GetPlayers() return { localPlayer, player } end

local store = Store.new({ settings = {
    worldRenderer = "limn",
    boxes = true,
    chams = true,
    names = true,
    health = true,
    weapon = true,
} })
local renderer = NativeWorldRenderer.new({
    createInstance = createInstance,
    guiParent = guiParent,
    localPlayer = localPlayer,
    players = players,
    runService = runService,
    store = store,
})
assert(#created == 0 and next(renderer.subjects) == nil,
    "Limn mode must allocate no native Instances or active subjects")
assert(heartbeat:count() == 0, "Limn mode must not connect distance refresh")

local extrasAdd, extrasRemove, extrasCleaned
local policyWeapon = "Long Untruncated Weapon Name"
local playerInvalidates, characterInvalidates = {}, {}
local globalInvalidate
local playerCleanupCount, globalCleanupCount = 0, 0
local eligible = true
local playerTone = "enemy"
renderer:setPolicy({
    isPlayerEligible = function(candidate) return candidate ~= localPlayer and eligible end,
    getPlayerTone = function(candidate)
        return candidate ~= localPlayer and eligible and playerTone or nil
    end,
    getWeapon = function() return policyWeapon end,
    connectPlayerChanged = function(candidate, invalidate)
        playerInvalidates[candidate] = invalidate
        return function()
            playerInvalidates[candidate] = nil
            playerCleanupCount = playerCleanupCount + 1
        end
    end,
    connectCharacterChanged = function(candidate, _, invalidate)
        characterInvalidates[candidate] = invalidate
        return { Disconnect = function() characterInvalidates[candidate] = nil end }
    end,
    subscribeChanged = function(invalidate)
        globalInvalidate = invalidate
        return function() globalInvalidate = nil; globalCleanupCount = globalCleanupCount + 1 end
    end,
    subscribeExtras = function(add, remove)
        extrasAdd, extrasRemove = add, remove
        return function() extrasCleaned = true end
    end,
})
store:Patch({ settings = { worldRenderer = "native" } })
local subject = assert(renderer.subjects[player])
assert(renderer.root.ClassName == "Folder" and renderer.root.Parent == guiParent)
assert(#subject.highlights == 1 and subject.highlights[1].Adornee == character,
    "Default chams must use one model Highlight")
assert(heartbeat:count() == 0,
    "Model Highlight mode must not connect the per-part distance refresh")
assert(subject.billboard.Size == UDim2.fromScale(5, 7))
assert(subject.name.TextSize == 13 and subject.healthValue.TextSize == 12 and subject.weapon.TextSize == 12)
assert(subject.name.TextTruncate == Enum.TextTruncate.None
    and subject.healthValue.TextTruncate == Enum.TextTruncate.None
    and subject.weapon.TextTruncate == Enum.TextTruncate.None)
assert(subject.healthTrack.Size == UDim2.new(0, 6, 1, 0)
    and subject.healthTrack:FindFirstChild("Corner") == nil) -- fake parenting is property-only
assert(subject.healthFill.Size == UDim2.new(0, 4, 0.25, 0))
assert(subject.healthFill.BackgroundColor3 == Color3.fromRGB(255, 118, 87):Lerp(Color3.fromRGB(98, 214, 173), 0.5))
assert(subject.weapon.Text == "Long Untruncated Weapon Name")
policyWeapon = "Event Refreshed"
playerInvalidates[player]()
assert(subject.weapon.Text == "Event Refreshed", "Player invalidation must refresh policy weapon state")
policyWeapon = "Character Refreshed"
characterInvalidates[player]()
subject = assert(renderer.subjects[player])
assert(subject.weapon.Text == "Character Refreshed",
    "Character invalidation must refresh without frame polling")
policyWeapon = "Globally Refreshed"
globalInvalidate()
assert(subject.weapon.Text == "Globally Refreshed", "Global policy invalidation must refresh subjects")
eligible = false
playerInvalidates[player]()
assert(not renderer.subjects[player], "Policy invalidation must re-check eligibility")
eligible = true
playerInvalidates[player]()
subject = assert(renderer.subjects[player], "Policy invalidation must restore newly eligible membership")
playerTone = "team"
playerInvalidates[player]()
assert(not renderer.subjects[player], "Teammates must remain hidden by default")
store:Patch({ settings = { showTeammates = true } })
subject = assert(renderer.subjects[player], "The setting event must add eligible teammates without polling")
assert(subject.highlights[1].OutlineColor == Color3.fromRGB(101, 157, 214),
    "Native teammate ESP must consume the generic team tone")
store:Patch({ settings = { showTeammates = false } })
assert(not renderer.subjects[player], "Disabling teammate ESP must remove teammate subjects")
playerTone = "enemy"
playerInvalidates[player]()
subject = assert(renderer.subjects[player], "Opponent membership must remain independent of teammate ESP")
store:Patch({ settings = { showEnemies = false } })
assert(not renderer.subjects[player], "Enemies must be independently removable from the ESP audience")
store:Patch({ settings = { showTeammates = true } })
assert(not renderer.subjects[player], "Allies-only mode must not retain enemy subjects")
playerTone = "team"
playerInvalidates[player]()
assert(renderer.subjects[player], "Allies-only mode must add teammate subjects")
playerTone = "enemy"
store:Patch({ settings = { showEnemies = true, showTeammates = false } })
playerInvalidates[player]()
subject = assert(renderer.subjects[player], "Enemy audience must restore opponent subjects")
store:Patch({ settings = {
    espEnemyOutlineColor = "#123456",
    espEnemyFillColor = "#654321",
    espEnemyNameColor = "#ABCDEF",
    espEnemyWeaponColor = "#FEDCBA",
    espEnemyHealthLowColor = "#110000",
    espEnemyHealthHighColor = "#00EE00",
    espEnemyFillAlpha = 0.73,
} })
subject = assert(renderer.subjects[player])
assert(subject.highlights[1].OutlineColor == Color3.fromRGB(18, 52, 86))
assert(subject.highlights[1].FillColor == Color3.fromRGB(101, 67, 33))
assert(subject.highlights[1].FillTransparency == 0.27)
assert(subject.name.TextColor3 == Color3.fromRGB(171, 205, 239))
assert(subject.weapon.TextColor3 == Color3.fromRGB(254, 220, 186))
assert(subject.healthFill.BackgroundColor3 == Color3.fromRGB(17, 0, 0):Lerp(Color3.fromRGB(0, 238, 0), 0.5))
for _, instance in ipairs(created) do
    if not instance.Destroyed then
        local cursor = instance
        while cursor ~= guiParent and cursor ~= nil do cursor = cursor.Parent end
        assert(cursor == guiParent, instance.ClassName .. " escaped guiParent")
    end
end

humanoid.Health = math.huge
humanoid.MaxHealth = math.huge
humanoid.HealthChanged:Fire(math.huge)
assert(subject.healthValue.Text == "∞ HP" and subject.healthFill.Size == UDim2.new(0, 4, 1, 0),
    "Native infinite health must remain infinite")

store:Patch({ settings = { boxes = true, chams = false, chamsPerPart = true } })
assert(heartbeat:count() == 1, "Relevant per-part mode must own exactly one Heartbeat connection")
assert(#subject.highlights == 3,
    "Per-part mode must adorn direct body parts and accessory handles when Boxes owns the outline")
rootPart.Position = Vector3.new(1101, 0, 0)
heartbeat:Fire(0.24)
assert(#subject.highlights == 3, "Distance refresh must remain throttled below 0.25 seconds")
heartbeat:Fire(0.01)
assert(#subject.highlights == 0 and subject.billboard.Enabled,
    "Out-of-range subjects must lose only per-part Highlights, not labels or membership")
local createdOutOfRange = #created
heartbeat:Fire(0.25)
assert(#created == createdOutOfRange,
    "Stable out-of-range subjects must not repeatedly rebuild empty Highlight sets")
rootPart.Position = Vector3.new(1050, 0, 0)
heartbeat:Fire(0.25)
assert(#subject.highlights == 0, "An out-of-range subject must not re-enter inside the hysteresis band")
rootPart.Position = Vector3.new(999, 0, 0)
heartbeat:Fire(0.25)
assert(#subject.highlights == 3, "A subject inside the enter boundary must regain per-part Highlights")
rootPart.Position = Vector3.new(1050, 0, 0)
heartbeat:Fire(0.25)
assert(#subject.highlights == 3, "An in-range subject must remain allocated inside the hysteresis band")
local stableHighlight = subject.highlights[1]
store:Patch({ status = "unrelated" })
renderer:render({ { player = player, weapon = "Observed" } })
assert(subject.highlights[1] == stableHighlight,
    "Unrelated state and observation updates must not rebuild per-part Highlights")
for _, highlight in ipairs(subject.highlights) do
    assert(highlight.Adornee ~= character and highlight.Adornee:IsA("BasePart"))
end
local replacementPart = object("Part") replacementPart.Name = "Arm"
character:add(replacementPart)
assert(#subject.highlights == 4, "Hierarchy changes must rebuild bounded per-part highlights")
store:Patch({ settings = { chamsExcludeAccessories = true } })
assert(#subject.highlights == 3, "Accessory-excluding chams must omit accessory handles")
assert(#subject.highlights <= NativeWorldRenderer.SUBJECT_HIGHLIGHT_BUDGET
    and renderer.highlightCount <= NativeWorldRenderer.HIGHLIGHT_BUDGET)
store:Patch({ settings = { boxes = false, chams = false } })
assert(heartbeat:count() == 0,
    "Disabling both boxes and chams must synchronously disconnect distance refresh")
store:Patch({ settings = { boxes = true } })
assert(heartbeat:count() == 1, "Re-enabling a relevant visual must reconnect one refresh loop")

player.CharacterRemoving:Fire(character)
assert(not renderer.subjects[player], "CharacterRemoving must remove native membership")
player.CharacterAdded:Fire(character)
subject = assert(renderer.subjects[player], "CharacterAdded must restore eligible native membership")
local secondRoot = object("Part") secondRoot.Name = "HumanoidRootPart"
local secondCharacter = object("Model", { secondRoot }) secondCharacter.PrimaryPart = secondRoot
local secondPlayer = {
    Name = "Second",
    Character = secondCharacter,
    CharacterAdded = signal(),
    CharacterRemoving = signal(),
}
players.PlayerAdded:Fire(secondPlayer)
assert(renderer.subjects[secondPlayer], "PlayerAdded must begin remote character tracking")
players.PlayerRemoving:Fire(secondPlayer)
assert(not renderer.subjects[secondPlayer]
    and secondPlayer.CharacterAdded:count() == 0 and secondPlayer.CharacterRemoving:count() == 0,
    "PlayerRemoving must remove membership and character listeners")

local extraRoot = object("Part")
local extraCharacter = object("Model", { extraRoot }) extraCharacter.PrimaryPart = extraRoot
extrasAdd({ key = "dummy", character = extraCharacter, name = "Dummy", weapon = "Blade" })
assert(renderer.subjects.dummy and renderer.subjects.dummy.name.Text == "Dummy")
renderer:render({ { key = "dummy", weapon = "Updated Blade", presentation = { name = "Target" } } })
assert(renderer.subjects.dummy.weapon.Text == "Updated Blade" and renderer.subjects.dummy.name.Text == "Target")
local preview = { key = "preview-only", presentation = { name = "Preview" } }
local unclaimed = renderer:render({ { key = "dummy", weapon = "Claimed" }, preview })
assert(#unclaimed == 1 and unclaimed[1] == preview,
    "Native rendering must return observations without a native subject")
renderer:render({})
assert(renderer.subjects.dummy, "Observation rendering must not own membership")
extrasRemove("dummy")
assert(not renderer.subjects.dummy)
renderer:setPolicy({
    isPlayerEligible = function(candidate) return candidate ~= localPlayer end,
    getWeapon = function() return "Replacement Policy" end,
})
subject = assert(renderer.subjects[player])
assert(subject.weapon.Text == "Replacement Policy" and globalCleanupCount == 1
    and not globalInvalidate and not playerInvalidates[player] and not characterInvalidates[player],
    "Policy replacement must clean every old policy handle before reconnecting")

store:Patch({ settings = { worldRenderer = "limn" } })
assert(next(renderer.subjects) == nil and renderer.root == nil and extrasCleaned == true)
local limnObservation = { key = player }
local limnUnclaimed = renderer:render({ limnObservation })
assert(#limnUnclaimed == 1 and limnUnclaimed[1] == limnObservation,
    "Inactive native rendering must pass every observation through")
assert(players.PlayerAdded:count() == 0 and players.PlayerRemoving:count() == 0
    and player.CharacterAdded:count() == 0 and player.CharacterRemoving:count() == 0
    and heartbeat:count() == 0)
assert(playerCleanupCount >= 1 and globalCleanupCount == 1 and not globalInvalidate,
    "Policy handles must clean up on deactivation")
for _, instance in ipairs(created) do
    local cursor, destroyedByAncestor = instance, false
    while cursor do
        destroyedByAncestor = destroyedByAncestor or cursor.Destroyed == true
        cursor = cursor.Parent
    end
    assert(destroyedByAncestor, "Deactivation must destroy every native Instance")
end
renderer:destroy()
renderer:destroy()
store:Destroy()
print("native-world-renderer-contracts-ok")
