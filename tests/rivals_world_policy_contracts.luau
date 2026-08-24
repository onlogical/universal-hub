local WorldPolicy = require("../games/rivals/world/WorldPolicy")
local Definition = require("../games/rivals/Definition")
local fs = require("@lune/fs")

assert(
    table.find(Definition.sources, "games/rivals/world/WorldPolicy") ~= nil,
    "RIVALS must register its native world policy source"
)
local adapterSource = fs.readFile("games/rivals/Adapter.lua")
assert(
    adapterSource:find("self.worldPolicy = WorldPolicy.new({", 1, true),
    "RIVALS adapter must export the native world policy"
)

local function signal()
    local callbacks = {}
    local value = {}
    function value:Connect(callback)
        callbacks[callback] = true
        return {
            Disconnect = function()
                callbacks[callback] = nil
            end,
        }
    end
    function value:Fire(...)
        local pending = {}
        for callback in pairs(callbacks) do
            table.insert(pending, callback)
        end
        for _, callback in ipairs(pending) do
            callback(...)
        end
    end
    function value:Count()
        local count = 0
        for _ in pairs(callbacks) do
            count += 1
        end
        return count
    end
    return value
end

local function container(name, children)
    local value = {
        Name = name,
        children = children or {},
        ChildAdded = signal(),
        ChildRemoved = signal(),
    }
    function value:GetChildren()
        return self.children
    end
    function value:FindFirstChild(childName)
        for _, child in ipairs(self.children) do
            if child.Name == childName then
                return child
            end
        end
        return nil
    end
    function value:add(child)
        table.insert(self.children, child)
        self.ChildAdded:Fire(child)
    end
    function value:remove(child)
        local index = table.find(self.children, child)
        if index then
            table.remove(self.children, index)
            self.ChildRemoved:Fire(child)
        end
    end
    return value
end

local function dummy(name, environmentID, health)
    local humanoid = {
        Health = health,
        MaxHealth = 150,
        HealthChanged = signal(),
        Died = signal(),
    }
    local root = { Name = "HumanoidRootPart" }
    local environmentChanged = signal()
    local value = container(name, { humanoid, root })
    value.humanoid = humanoid
    value.root = root
    value.environmentID = environmentID
    function value:IsA(className)
        return className == "Model"
    end
    function value:FindFirstChildOfClass(className)
        return className == "Humanoid" and self.humanoid or nil
    end
    function value:FindFirstChild(childName)
        return childName == "HumanoidRootPart" and self.root or nil
    end
    function value:GetAttribute(attribute)
        return attribute == "EnvironmentID" and self.environmentID or nil
    end
    function value:GetAttributeChangedSignal(attribute)
        assert(attribute == "EnvironmentID")
        return environmentChanged
    end
    value.environmentChanged = environmentChanged
    return value
end

local eligible = dummy("Eligible", "PracticeA", 71)
local wrongEnvironment = dummy("OtherEnvironment", "PracticeB", 80)
local dead = dummy("Dead", "PracticeA", 0)
local folder = container("ShootingRangeEntities", { eligible, wrongEnvironment, dead })
local workspace = container("Workspace", { folder })
local fighter = {
    Data = {
        EnvironmentID = "PracticeA",
        IsInShootingRange = false,
    },
    _value_changed_events = {
        EnvironmentID = signal(),
        IsInShootingRange = signal(),
    },
}
local weaponCalls = 0
local policy = WorldPolicy.new({
    workspace = workspace,
    getLocalFighter = function()
        return fighter
    end,
    isOpponent = function(player, character)
        return player.Name == "Enemy" and character ~= nil
    end,
    getPlayerTone = function(player, character)
        if not character then
            return nil
        end
        return player.Name == "Friend" and "team" or "enemy"
    end,
    getWeapon = function(player)
        weaponCalls += 1
        return player.weapon
    end,
})

assert(policy.isPlayerEligible({ Name = "Enemy" }, {}) == true)
assert(policy.isPlayerEligible({ Name = "Friend" }, {}) == false)
assert(policy.getPlayerTone({ Name = "Friend" }, {}) == "team")
assert(policy.getWeapon({ weapon = "Rifle" }) == "Rifle" and weaponCalls == 1)

local added = {}
local removed = {}
local cleanup = policy.subscribeExtras(function(descriptor)
    added[descriptor.key] = descriptor
end, function(key)
    removed[key] = (removed[key] or 0) + 1
    added[key] = nil
end)
assert(next(added) == nil, "Range entities must not emit while native range state is false")
assert(workspace.ChildAdded:Count() == 0 and workspace.ChildRemoved:Count() == 0)
assert(folder.ChildAdded:Count() == 0 and folder.ChildRemoved:Count() == 0)
assert(
    eligible.environmentChanged:Count() == 0 and eligible.humanoid.HealthChanged:Count() == 0,
    "Inactive range policy must not retain folder or entity subscriptions"
)

fighter.Data.IsInShootingRange = true
fighter._value_changed_events.IsInShootingRange:Fire(true)
assert(added[eligible] ~= nil, "Activation must seed eligible existing range children")
assert(workspace.ChildAdded:Count() == 1 and folder.ChildAdded:Count() == 1)
assert(
    eligible.environmentChanged:Count() == 1 and eligible.humanoid.HealthChanged:Count() >= 1,
    "Active range policy must attach native folder and entity subscriptions"
)
assert(added[wrongEnvironment] == nil and added[dead] == nil)
assert(added[eligible].humanoid == eligible.humanoid)
assert(
    added[eligible].health == nil and added[eligible].maxHealth == nil,
    "Policy descriptors must retain the native Humanoid instead of fabricating health"
)

eligible.humanoid.Health = 0
eligible.humanoid.HealthChanged:Fire(0)
assert(
    added[eligible] == nil and removed[eligible] == 1,
    "Native Humanoid health changes must remove dead extras"
)
eligible.humanoid.Health = 44
eligible.humanoid.HealthChanged:Fire(44)
assert(added[eligible] ~= nil, "Native health changes must restore a live range extra")

eligible.environmentID = "PracticeB"
eligible.environmentChanged:Fire()
assert(added[eligible] == nil, "Entity EnvironmentID changes must re-evaluate membership")
fighter.Data.EnvironmentID = "PracticeB"
fighter._value_changed_events.EnvironmentID:Fire("PracticeB")
assert(
    added[eligible] ~= nil and added[wrongEnvironment] ~= nil,
    "Fighter native EnvironmentID signals must resync all range membership"
)

local late = dummy("Late", "PracticeB", math.huge)
folder:add(late)
assert(
    added[late] ~= nil and added[late].humanoid.Health == math.huge,
    "ChildAdded must preserve native infinite health without substitution"
)
folder:remove(late)
assert(added[late] == nil, "ChildRemoved must remove emitted extras")

fighter.Data.IsInShootingRange = false
fighter._value_changed_events.IsInShootingRange:Fire(false)
assert(next(added) == nil, "Range deactivation must remove every emitted extra")
assert(workspace.ChildAdded:Count() == 0 and folder.ChildAdded:Count() == 0)
assert(
    eligible.environmentChanged:Count() == 0 and eligible.humanoid.HealthChanged:Count() == 0,
    "Range deactivation must detach all feature-scoped native subscriptions"
)
cleanup()
cleanup()
fighter.Data.IsInShootingRange = true
fighter._value_changed_events.IsInShootingRange:Fire(true)
assert(next(added) == nil, "Cleanup must disconnect native subscriptions")

print("rivals world policy contracts passed")
