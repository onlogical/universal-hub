local AutoDeflect = {}

AutoDeflect.LOOK_COSINE = math.cos(math.rad(16))

function AutoDeflect.lookFrom(character)
    local head = character and character.Head
    if not head and character and type(character.FindFirstChild) == "function" then
        head = character:FindFirstChild("Head")
    end
    local frame = head and head.CFrame
    local position = frame and frame.Position
    local look = frame and frame.LookVector
    if position == nil or look == nil then
        return nil
    end
    return position, look
end

function AutoDeflect.bodyPoint(character)
    local root = character
        and (character.HumanoidRootPart or character.RootPart or character.PrimaryPart)
    if not root and character and type(character.FindFirstChild) == "function" then
        root = character:FindFirstChild("HumanoidRootPart")
    end
    return root and root.Position or nil
end

function AutoDeflect.looksAt(origin, look, point, cosine)
    if typeof(origin) ~= "Vector3" or typeof(look) ~= "Vector3" or typeof(point) ~= "Vector3" then
        return false
    end
    local delta = point - origin
    if delta.Magnitude < 1 then
        return true
    end
    return look.Unit:Dot(delta.Unit) >= (cosine or AutoDeflect.LOOK_COSINE)
end

function AutoDeflect.lethalShot(item, health, distance, weaponPolicy)
    if type(health) ~= "number" or health <= 0 or type(weaponPolicy) ~= "table" then
        return false
    end
    local observation = {
        part = { Name = "HitboxHead" },
        health = health,
    }
    local damage = type(weaponPolicy.finishingDamage) == "function"
        and weaponPolicy.finishingDamage(item, observation, distance)
    if type(damage) ~= "number" and type(weaponPolicy.damageAtDistance) == "function" then
        damage = weaponPolicy.damageAtDistance(item, observation, distance)
    end
    return type(damage) == "number" and damage >= health
end

function AutoDeflect.ready(item, itemNow)
    if type(item) ~= "table" then
        return false
    end
    if
        type(itemNow) == "number"
        and type(item._deflect_cooldown) == "number"
        and itemNow < item._deflect_cooldown
    then
        return false
    end
    return true
end

function AutoDeflect.shouldBlock(localFighter, opponent, ctx)
    ctx = ctx or {}
    local WeaponPolicy = ctx.weaponPolicy
    local item = localFighter and localFighter.EquippedItem
    if
        type(WeaponPolicy) ~= "table"
        or type(WeaponPolicy.isDeflector) ~= "function"
        or WeaponPolicy.isDeflector(item) ~= true
        or (type(WeaponPolicy.isActivelyDeflecting) == "function" and WeaponPolicy.isActivelyDeflecting(
            item
        ))
        or not AutoDeflect.ready(item, ctx.itemClock and ctx.itemClock())
    then
        return false
    end

    local theirItem = opponent and opponent.EquippedItem
    local ourHealth = ctx.health
    local origin, look = AutoDeflect.lookFrom(opponent and opponent.character)
    local point = AutoDeflect.bodyPoint(ctx.character)
    local distance = ctx.distance
    if type(distance) ~= "number" and origin and point then
        distance = (point - origin).Magnitude
    end
    if
        not AutoDeflect.lethalShot(theirItem, ourHealth, distance, WeaponPolicy)
        or not AutoDeflect.looksAt(origin, look, point, ctx.lookCosine)
    then
        return false
    end
    if type(ctx.hasLine) == "function" then
        return ctx.hasLine(origin, point, opponent.character) == true
    end
    return true
end

function AutoDeflect.update(settings, ctx)
    if
        settings.autoDeflect ~= true
        or ctx.inputCaptured
        or not ctx.fighterActive
        or not ctx.inCombat
    then
        return false
    end
    local fighter = ctx.getFighter and ctx.getFighter()
    if not fighter then
        return false
    end
    for _, opponent in ipairs(ctx.opponents or {}) do
        if AutoDeflect.shouldBlock(fighter, opponent, ctx) then
            if type(ctx.aimClick) == "function" then
                ctx.aimClick()
            end
            if ctx.taskDebug then
                ctx.taskDebug.autoDeflectStage = "blocked"
            end
            return true
        end
    end
    return false
end

return AutoDeflect
