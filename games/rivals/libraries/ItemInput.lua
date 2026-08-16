local ItemInput = {}

ItemInput.START_SHOOTING = "StartShooting"
ItemInput.FINISH_SHOOTING = "FinishShooting"
ItemInput.START_AIMING = "StartAiming"
ItemInput.FINISH_AIMING = "FinishAiming"
ItemInput.EQUIP_PRIMARY = "EquipPrimary"
ItemInput.EQUIP_SECONDARY = "EquipSecondary"

function ItemInput.equipAction(item)
    local info = item and item.Info
    if type(info) ~= "table" then
        return nil
    end
    if info.Class == "Secondary" then
        return ItemInput.EQUIP_SECONDARY
    end
    if info.Class == "Primary" then
        return ItemInput.EQUIP_PRIMARY
    end
    return nil
end

function ItemInput.dispatch(fighter, action)
    if type(fighter) ~= "table"
        or type(fighter.Input) ~= "function"
        or type(action) ~= "string"
        or action == ""
    then
        return false
    end
    local succeeded, result = pcall(fighter.Input, fighter, action)
    return succeeded and result ~= false
end

return ItemInput
