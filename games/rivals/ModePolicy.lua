local ModePolicy = {}

local function replicatedValue(replica, key)
    if type(replica) ~= "table" then
        return nil
    end
    if type(replica.Get) == "function" then
        local succeeded, value = pcall(replica.Get, replica, key)
        if succeeded and value ~= nil then
            return value
        end
    end
    local data = replica.Data
    if type(data) == "table" then
        return data[key]
    end
    return nil
end

function ModePolicy.resolve(clientDuel)
    local isGunGame = replicatedValue(clientDuel, "IsGunGame")
    if isGunGame == true then
        return "gun-game"
    end
    if isGunGame == false then
        return "standard"
    end
    return nil
end

function ModePolicy.fromController(duelController, player)
    if type(duelController) ~= "table" or type(duelController.GetDuel) ~= "function" then
        return nil
    end
    local succeeded, clientDuel = pcall(duelController.GetDuel, duelController, player)
    if not succeeded then
        return nil
    end
    return ModePolicy.resolve(clientDuel)
end

function ModePolicy.isGunGame(clientDuel)
    return ModePolicy.resolve(clientDuel) == "gun-game"
end

function ModePolicy.controllerIsGunGame(duelController, player)
    return ModePolicy.fromController(duelController, player) == "gun-game"
end

return ModePolicy
