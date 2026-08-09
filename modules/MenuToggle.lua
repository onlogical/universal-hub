local MenuToggle = {}

function MenuToggle.shouldToggle(input, gameProcessedEvent, userInputService, configuredKey)
    local keyCode = configuredKey
    if type(keyCode) == "string" then
        keyCode = Enum.KeyCode[keyCode]
    end
    keyCode = keyCode or Enum.KeyCode.RightShift
    if not input or input.KeyCode ~= keyCode or gameProcessedEvent then
        return false
    end

    return not (
        userInputService
        and type(userInputService.GetFocusedTextBox) == "function"
        and userInputService:GetFocusedTextBox()
    )
end

return MenuToggle
