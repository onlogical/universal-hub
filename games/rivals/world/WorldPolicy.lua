local WorldPolicy = {}

local function disconnect(connection)
    if connection and type(connection.Disconnect) == "function" then
        connection:Disconnect()
    end
end

local function connect(signal, callback)
    if signal and type(signal.Connect) == "function" then
        local ok, connection = pcall(signal.Connect, signal, callback)
        return ok and connection or nil
    end
    local event = signal and signal.Event
    if event and type(event.Connect) == "function" then
        local ok, connection = pcall(event.Connect, event, callback)
        return ok and connection or nil
    end
    return nil
end

local function value(fighter, key)
    if type(fighter) ~= "table" then
        return nil
    end
    if type(fighter.Get) == "function" then
        local ok, result = pcall(fighter.Get, fighter, key)
        if ok and result ~= nil then
            return result
        end
    end
    local data = fighter.Data
    return type(data) == "table" and data[key] or nil
end

local function connectFighterValue(fighter, key, callback)
    local events = type(fighter) == "table" and fighter._value_changed_events
    return type(events) == "table" and connect(events[key], callback) or nil
end

function WorldPolicy.new(options)
    assert(type(options) == "table", "RIVALS world policy requires options")
    assert(options.workspace, "RIVALS world policy requires Workspace")
    assert(type(options.getLocalFighter) == "function", "RIVALS world policy requires a fighter getter")
    assert(type(options.isOpponent) == "function", "RIVALS world policy requires opponent policy")
    assert(type(options.getPlayerTone) == "function", "RIVALS world policy requires player-tone policy")
    assert(type(options.getWeapon) == "function", "RIVALS world policy requires weapon labels")

    local workspace = options.workspace
    local getLocalFighter = options.getLocalFighter
    return {
        isPlayerEligible = options.isOpponent,
        getPlayerTone = options.getPlayerTone,
        getWeapon = options.getWeapon,
        connectPlayerChanged = function(player, invalidate)
            local connections = {}
            if player and player.GetAttributeChangedSignal then
                table.insert(connections, player:GetAttributeChangedSignal("EnvironmentID"):Connect(invalidate))
                table.insert(connections, player:GetAttributeChangedSignal("TeamID"):Connect(invalidate))
            end
            local fighter = type(options.getFighter) == "function" and options.getFighter(player) or nil
            local equippedChanged = fighter and fighter.EquippedItemChanged
            local equippedConnection = connect(equippedChanged, invalidate)
            if equippedConnection then
                table.insert(connections, equippedConnection)
            end
            return function()
                for _, connection in ipairs(connections) do
                    disconnect(connection)
                end
            end
        end,
        subscribeChanged = function(invalidate)
            local player = options.localPlayer
            if not player or not player.GetAttributeChangedSignal then
                return nil
            end
            local connections = {
                player:GetAttributeChangedSignal("EnvironmentID"):Connect(invalidate),
                player:GetAttributeChangedSignal("TeamID"):Connect(invalidate),
            }
            return function()
                for _, connection in ipairs(connections) do
                    disconnect(connection)
                end
            end
        end,
        subscribeExtras = function(onAdd, onRemove)
            assert(type(onAdd) == "function" and type(onRemove) == "function")
            local stopped = false
            local connections = {}
            local entityConnections = {}
            local entities = {}
            local emitted = {}
            local folder

            local function remember(connection, target)
                if connection then
                    table.insert(target or connections, connection)
                end
            end

            local function removeEmission(entity)
                if emitted[entity] then
                    emitted[entity] = nil
                    onRemove(entity)
                end
            end

            local function descriptor(entity)
                if not entity or type(entity.IsA) ~= "function" or not entity:IsA("Model") then
                    return nil
                end
                local humanoid = entity:FindFirstChildOfClass("Humanoid")
                local rootPart = entity:FindFirstChild("HumanoidRootPart")
                if not humanoid or not rootPart or type(humanoid.Health) ~= "number" or humanoid.Health <= 0 then
                    return nil
                end
                local fighter = getLocalFighter()
                local environmentID = value(fighter, "EnvironmentID")
                local entityEnvironmentID = entity:GetAttribute("EnvironmentID")
                if environmentID ~= nil and entityEnvironmentID ~= environmentID then
                    return nil
                end
                return {
                    key = entity,
                    character = entity,
                    humanoid = humanoid,
                    rootPart = rootPart,
                    name = entity.Name,
                }
            end

            local function active()
                return value(getLocalFighter(), "IsInShootingRange") == true
            end

            local function syncEntity(entity)
                if stopped or not entities[entity] then
                    return
                end
                local nextDescriptor = active() and descriptor(entity) or nil
                if nextDescriptor then
                    if not emitted[entity] then
                        emitted[entity] = true
                        onAdd(nextDescriptor)
                    end
                else
                    removeEmission(entity)
                end
            end

            local function untrackEntity(entity)
                entities[entity] = nil
                removeEmission(entity)
                for _, connection in ipairs(entityConnections[entity] or {}) do
                    disconnect(connection)
                end
                entityConnections[entity] = nil
            end

            local function trackEntity(entity)
                if stopped or entities[entity] then
                    return
                end
                entities[entity] = true
                local owned = {}
                entityConnections[entity] = owned
                if entity.GetAttributeChangedSignal then
                    remember(connect(entity:GetAttributeChangedSignal("EnvironmentID"), function()
                        syncEntity(entity)
                    end), owned)
                end
                if entity.ChildAdded then
                    remember(connect(entity.ChildAdded, function()
                        syncEntity(entity)
                    end), owned)
                end
                if entity.ChildRemoved then
                    remember(connect(entity.ChildRemoved, function()
                        syncEntity(entity)
                    end), owned)
                end
                local humanoid = entity.FindFirstChildOfClass and entity:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    if humanoid.HealthChanged then
                        remember(connect(humanoid.HealthChanged, function()
                            syncEntity(entity)
                        end), owned)
                    elseif humanoid.GetPropertyChangedSignal then
                        remember(connect(humanoid:GetPropertyChangedSignal("Health"), function()
                            syncEntity(entity)
                        end), owned)
                    end
                    if humanoid.Died then
                        remember(connect(humanoid.Died, function()
                            syncEntity(entity)
                        end), owned)
                    end
                end
                syncEntity(entity)
            end

            local folderConnections = {}
            local activeConnections = {}
            local rangeActive = false
            local function detachFolder()
                for _, connection in ipairs(folderConnections) do
                    disconnect(connection)
                end
                table.clear(folderConnections)
                local tracked = {}
                for entity in pairs(entities) do
                    table.insert(tracked, entity)
                end
                for _, entity in ipairs(tracked) do
                    untrackEntity(entity)
                end
                folder = nil
            end

            local function attachFolder(nextFolder)
                if not rangeActive or folder == nextFolder then
                    return
                end
                detachFolder()
                folder = nextFolder
                if not folder then
                    return
                end
                if folder.ChildAdded then
                    remember(connect(folder.ChildAdded, trackEntity), folderConnections)
                end
                if folder.ChildRemoved then
                    remember(connect(folder.ChildRemoved, untrackEntity), folderConnections)
                end
                for _, entity in ipairs(folder:GetChildren()) do
                    trackEntity(entity)
                end
            end

            local function syncAll()
                if stopped or not rangeActive then
                    return
                end
                for entity in pairs(entities) do
                    syncEntity(entity)
                end
            end

            local function deactivateRange()
                if not rangeActive then
                    return
                end
                rangeActive = false
                detachFolder()
                for _, connection in ipairs(activeConnections) do
                    disconnect(connection)
                end
                table.clear(activeConnections)
            end

            local function activateRange()
                if rangeActive or stopped then
                    return
                end
                rangeActive = true
                if workspace.ChildAdded then
                    remember(connect(workspace.ChildAdded, function(child)
                        if child.Name == "ShootingRangeEntities" then
                            attachFolder(child)
                        end
                    end), activeConnections)
                end
                if workspace.ChildRemoved then
                    remember(connect(workspace.ChildRemoved, function(child)
                        if child == folder then
                            detachFolder()
                        end
                    end), activeConnections)
                end
                attachFolder(workspace:FindFirstChild("ShootingRangeEntities"))
            end

            local function syncActive()
                if stopped then
                    return
                end
                if active() then
                    activateRange()
                else
                    deactivateRange()
                end
            end

            local fighter = getLocalFighter()
            remember(connectFighterValue(fighter, "IsInShootingRange", syncActive))
            remember(connectFighterValue(fighter, "EnvironmentID", function()
                syncActive()
                syncAll()
            end))
            syncActive()

            return function()
                if stopped then
                    return
                end
                deactivateRange()
                stopped = true
                for _, connection in ipairs(connections) do
                    disconnect(connection)
                end
                table.clear(connections)
            end
        end,
    }
end

return WorldPolicy
