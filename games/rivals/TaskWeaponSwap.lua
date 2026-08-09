local TaskWeaponSwap = {}
TaskWeaponSwap.__index = TaskWeaponSwap

local function ammo(item)
    if type(item) ~= "table" then return nil end
    if type(item.Get) == "function" then
        local succeeded, value = pcall(item.Get, item, "Ammo")
        if succeeded and type(value) == "number" then return value end
    end
    local data = item.Data
    return type(data) == "table" and type(data.Ammo) == "number" and data.Ammo or nil
end

function TaskWeaponSwap.new(options)
    return setmetatable({
        clock = options.clock or os.clock,
        equip = options.equip or function(fighter, item)
            return fighter:EquipItem(item)
        end,
        nextAt = 0,
        pendingItem = nil,
        pendingAttempts = 0,
        pendingAt = 0,
        release = options.release or function() end,
        weaponPolicy = assert(options.weaponPolicy),
    }, TaskWeaponSwap)
end

function TaskWeaponSwap:update(active, fighter, target, distance)
    local now = self.clock()
    local current = fighter and fighter.EquippedItem
    if self.pendingItem then
        if current == self.pendingItem then
            self.pendingItem = nil
            self.pendingAttempts = 0
        elseif active == true and fighter and now >= self.pendingAt then
            self.release()
            self.pendingAttempts += 1
            pcall(self.equip, fighter, self.pendingItem)
            self.pendingAt = now + 0.12
            self.nextAt = self.pendingAt
            if self.pendingAttempts >= 6 then
                self.pendingItem = nil
                self.pendingAttempts = 0
            end
            return true
        else
            return active == true
        end
    end
    local currentAmmo = ammo(current)
    if active ~= true or now < self.nextAt or not fighter
        or type(fighter.EquipItem) ~= "function"
    then
        return false
    end
    local targetHealth = target and target.health
    if type(targetHealth) ~= "number" then targetHealth = 150 end
    local currentInfo = current and current.Info
    local empty = currentAmmo == 0
    local maximumAmmo = type(currentInfo) == "table" and currentInfo.MaxAmmo or nil
    local lowMagazine = type(currentAmmo) == "number"
        and type(maximumAmmo) == "number"
        and currentAmmo <= math.max(2, math.floor(maximumAmmo * 0.3))
    local tacticalSecondary = not empty
        and lowMagazine
        and type(targetHealth) == "number"
        and type(currentInfo) == "table"
        and currentInfo.Class == "Primary"
    if not empty and not tacticalSecondary then return false end
    local candidates = fighter.Items
    if type(candidates) ~= "table" and type(fighter.GetEquippedItems) == "function" then
        local succeeded, equipped = pcall(fighter.GetEquippedItems, fighter)
        if succeeded and type(equipped) == "table" then candidates = equipped end
    end
    if type(candidates) ~= "table" then return false end
    for key, candidate in pairs(candidates) do
        if type(candidate) ~= "table" then
            if type(key) == "table" then
                candidate = key
            elseif type(fighter.GetItem) == "function" then
                local identifier = candidate ~= true and candidate or key
                local succeeded, item = pcall(fighter.GetItem, fighter, identifier)
                if succeeded then candidate = item end
            end
        end
        local candidateInfo = type(candidate) == "table" and candidate.Info or nil
        local candidateAmmo = ammo(candidate)
        local candidateDamage = type(candidateInfo) == "table"
            and candidateInfo.ShootDamage
            or nil
        if type(candidateDamage) ~= "number" and type(candidate) == "table" then
            candidateDamage = self.weaponPolicy.damageAtDistance(candidate, target, distance)
        end
        local canFinishClip = empty
            or type(targetHealth) == "number"
                and type(candidateDamage) == "number"
                and type(candidateAmmo) == "number"
                and candidateDamage * candidateAmmo >= targetHealth
        local desiredClass = type(currentInfo) == "table"
            and currentInfo.Class == "Secondary"
            and "Primary"
            or "Secondary"
        local eligibleSlot = type(candidateInfo) == "table"
            and candidateInfo.Class == desiredClass
        if type(candidate) == "table"
            and candidate ~= current
            and eligibleSlot
            and canFinishClip
            and self.weaponPolicy.automationPolicy(candidate).cameraAim == true
            and candidateAmmo ~= nil
            and candidateAmmo > 0
        then
            self.release()
            self.pendingItem = candidate
            self.pendingAttempts = 1
            self.pendingAt = now + 0.12
            self.nextAt = self.pendingAt
            pcall(self.equip, fighter, candidate)
            if fighter.EquippedItem == candidate then
                self.pendingItem = nil
                self.pendingAttempts = 0
            end
            return true
        end
    end
    self.nextAt = now + 0.25
    return false
end

return TaskWeaponSwap
