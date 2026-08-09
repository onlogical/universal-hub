local Presentation = {}

local OWNER_VALUE_LIMIT = 22
local SAVE_VALUE_LIMIT = 24
local LAYOUT = {
    actionLabelX = 195,
    actionLabelY = 99,
    actionTop = 88,
    contentInset = 20,
    contentWidth = 350,
    dropdownLabelInset = 36,
    dropdownLabelTop = 43,
    dropdownRowHeight = 32,
    dropdownRowTop = 36,
    ownerIndicatorX = 350,
    ownerIndicatorY = 10,
    ownerLabelX = 36,
    ownerRowHeight = 36,
    ownerTextY = 11,
    ownerValueX = 120,
    panelHeight = 216,
    progressContextTop = 184,
    progressLabelInset = 36,
    progressPhaseTop = 168,
    progressTrackTop = 204,
    progressValueX = 350,
    saveLabelX = 36,
    saveRowTop = 44,
    saveTextY = 55,
    saveValueX = 98,
    secondaryHeight = 32,
    secondaryLabelX = 195,
    secondaryLabelY = 142,
    secondaryTop = 132,
    sectionHeaderHeight = 32,
    sectionLineX = 20,
    sectionLineY = 24,
    sectionWidth = 350,
}

local LAYER = {
    background = 202,
    control = 203,
    foreground = 204,
    popup = 212,
    popupLabel = 213,
}

local function compactText(value, limit)
    value = tostring(value or "")
    if #value <= limit then
        return value
    end
    return value:sub(1, math.max(1, limit - 3)) .. "..."
end

local function setVisible(nodes, visible)
    for _, node in pairs(nodes or {}) do
        if type(node) == "table" and (type(node.set) == "function" or node.Visible ~= nil) then
            node.Visible = visible
        elseif type(node) == "table" then
            setVisible(node, visible)
        end
    end
end

local function report(host, message)
    pcall(host.action, host, "reportPlotCopyError", message)
end

local function invoke(host, callbackName)
    local succeeded, accepted, message = pcall(host.action, host, callbackName)
    if not succeeded then
        report(host, "Plot copy action failed")
    elseif accepted == false then
        report(host, message or "Plot copy action could not start")
    end
end

local function createPanel(host)
    local colors = host:theme()
    local tokens = assert(colors.tokens, "Presentation theme requires shared tokens")
    local controls = host:controls()
    local state = {
        connections = {},
        dropdownItems = {},
        dropdownOpen = false,
        saveName = "",
        selectedOwner = nil,
        page = "Tools",
    }
    local function node(kind, properties, pointerEvents)
        local result = host:node(kind, properties, pointerEvents)
        return pointerEvents and host:interactive(result) or result
    end
    local function text(properties)
        return host:text(properties)
    end

    controls.sections.plotCopy = {
        label = text({
            Color = colors.text,
            Size = tokens.type.section,
            Text = "PLOT COPY",
            ZIndex = LAYER.control,
        }),
        line = node("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(LAYOUT.sectionWidth, tokens.control.borderThickness),
            Visible = true,
            ZIndex = LAYER.background,
        }),
    }
    local plotCopy = {
        ownerButton = node("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.ownerRowHeight),
            Visible = true,
            ZIndex = LAYER.background,
        }, true),
        ownerIndicator = text({
            Center = true, Color = colors.secondary, Size = tokens.type.label, Text = "v", ZIndex = LAYER.foreground,
        }),
        ownerLabel = text({
            Color = colors.secondary, Size = tokens.type.row, Text = "PLAYER", ZIndex = LAYER.control,
        }),
        ownerOutline = node("Square", {
            Color = colors.border,
            Filled = false,
            Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.ownerRowHeight),
            Thickness = tokens.control.borderThickness,
            Transparency = tokens.opacity.edge,
            Visible = true,
            ZIndex = LAYER.control,
        }),
        ownerValue = text({
            Color = colors.secondary, Size = tokens.type.label, Text = "Select a plot", ZIndex = LAYER.control,
        }),
        saveButton = node("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.ownerRowHeight),
            Visible = true,
            ZIndex = LAYER.background,
        }, true),
        saveLabel = text({
            Color = colors.secondary, Size = tokens.type.row, Text = "SAVE", ZIndex = LAYER.control,
        }),
        saveOutline = node("Square", {
            Color = colors.border,
            Filled = false,
            Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.ownerRowHeight),
            Thickness = tokens.control.borderThickness,
            Transparency = tokens.opacity.edge,
            Visible = true,
            ZIndex = LAYER.control,
        }),
        saveValue = text({
            Color = colors.secondary, Size = tokens.type.label, Text = "Enter save name", ZIndex = LAYER.control,
        }),
        actionButton = node("Square", {
            Color = colors.accentSurface,
            Filled = true,
            Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.ownerRowHeight),
            Visible = true,
            ZIndex = LAYER.background,
        }, true),
        actionLabel = text({
            Center = true, Color = colors.accent, Size = tokens.type.primary, Text = "Copy & Save", ZIndex = LAYER.control,
        }),
        secondaryButton = node("Square", {
            Color = colors.elevated,
            Filled = true,
            Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.secondaryHeight),
            Visible = false,
            ZIndex = LAYER.background,
        }, true),
        secondaryLabel = text({
            Center = true, Color = colors.secondary, Size = tokens.type.label, Text = "", Visible = false, ZIndex = LAYER.control,
        }),
        progressPhase = text({
            Color = colors.secondary, Size = tokens.type.row, Text = "Ready", ZIndex = LAYER.control,
        }),
        progressContext = text({
            Color = colors.secondary, Size = tokens.type.meta, Text = "", ZIndex = LAYER.control,
        }),
        progressValue = text({
            Center = true, Color = colors.secondary, Size = tokens.type.row, Text = "0%", ZIndex = LAYER.control,
        }),
        progressTrack = node("Square", {
            Color = colors.border,
            Filled = true,
            Size = Vector2.new(LAYOUT.contentWidth, tokens.control.progressTrackHeight),
            Visible = true,
            ZIndex = LAYER.background,
        }),
        progressFill = node("Square", {
            Color = colors.accent,
            Filled = true,
            Size = Vector2.new(0, tokens.control.progressTrackHeight),
            Visible = true,
            ZIndex = LAYER.control,
        }),
    }
    plotCopy.inputLayer = false
    plotCopy.saveInput = false
    plotCopy.secondaryVisible = false
    plotCopy.dropdownItems = state.dropdownItems
    controls.plotCopy = plotCopy

    local function setSaveName(saveName)
        state.saveName = tostring(saveName or "")
        plotCopy.saveValue.Text = state.saveName == ""
                and "Enter save name"
            or compactText(state.saveName, SAVE_VALUE_LIMIT)
        plotCopy.saveValue.Color = state.saveName == "" and colors.secondary or colors.text
    end
    local function clearDropdown()
        for _, item in ipairs(state.dropdownItems) do
            item.row:destroy()
            item.label:destroy()
        end
        table.clear(state.dropdownItems)
    end
    local function selectOwner(ownerName)
        local previousDefault = state.selectedOwner and ("copy_" .. state.selectedOwner) or ""
        state.selectedOwner = ownerName
        plotCopy.ownerValue.Text = compactText(ownerName, OWNER_VALUE_LIMIT)
        plotCopy.ownerValue.Color = colors.text
        if state.saveName == "" or state.saveName == previousDefault then
            setSaveName("copy_" .. ownerName)
            if plotCopy.saveInput then
                plotCopy.saveInput.Text = state.saveName
            end
        end
    end
    local function setDropdownOpen(open)
        clearDropdown()
        state.dropdownOpen = open == true
        plotCopy.ownerIndicator.Text = state.dropdownOpen and "^" or "v"
        if not state.dropdownOpen then
            return
        end
        local succeeded, owners = pcall(host.action, host, "listPlotOwners")
        if not succeeded or type(owners) ~= "table" or #owners == 0 then
            state.dropdownOpen = false
            plotCopy.ownerIndicator.Text = "v"
            plotCopy.ownerValue.Text = "No player plots"
            plotCopy.ownerValue.Color = colors.danger
            report(host, "No other player plots are available")
            return
        end
        if not table.find(owners, state.selectedOwner) then
            selectOwner(owners[1])
        end
        for _, ownerName in ipairs(owners) do
            local row = node("Square", {
                Color = ownerName == state.selectedOwner and colors.accentSurface or colors.elevated,
                Filled = true,
                Size = Vector2.new(LAYOUT.contentWidth, LAYOUT.dropdownRowHeight),
                Visible = true,
                ZIndex = LAYER.popup,
            }, true)
            local label = text({
                Color = ownerName == state.selectedOwner and colors.accent or colors.text,
                Size = tokens.type.label,
                Text = compactText(ownerName, OWNER_VALUE_LIMIT),
                ZIndex = LAYER.popupLabel,
            })
            row:on("click", function()
                selectOwner(ownerName)
                setDropdownOpen(false)
            end)
            table.insert(state.dropdownItems, { label = label, row = row })
        end
        host:requestLayout()
    end

    local function runPrimaryAction()
        local plotCopyState = host:read().plotCopy
        local copyState = plotCopyState and plotCopyState.state or "idle"
        if plotCopyState.localCleanupAvailable then
            invoke(host, "cleanupPlotCopyCheckpoint")
        elseif plotCopyState.retryCleanupAvailable then
            invoke(host, "retryPlotCopyCleanup")
        elseif plotCopyState.resumeAvailable and copyState ~= "awaiting_confirmation" then
            invoke(host, "resumePlotCopy")
        elseif copyState == "awaiting_confirmation" then
            invoke(host, "confirmPlotCopy")
        elseif copyState == "rollback" or copyState == "rollback_incomplete" then
            invoke(host, "retryPlotCopyCleanup")
        elseif copyState == "cleanup_pending" then
            invoke(host, "cleanupPlotCopyCheckpoint")
        elseif copyState == "paused" then
            invoke(host, "resumePlotCopy")
        elseif copyState == "copying"
            or copyState == "preflight"
            or copyState == "reconciling"
            or copyState == "resuming"
        then
            invoke(host, "cancelPlotCopy")
        elseif copyState == "idle" or copyState == "completed" or copyState == "error" then
            if not state.selectedOwner then
                report(host, "Choose a player plot to copy")
            elseif state.saveName == "" then
                report(host, "Enter a save name")
            else
                setDropdownOpen(false)
                local succeeded, accepted, message = pcall(
                    host.action,
                    host,
                    "copyPlot",
                    state.selectedOwner,
                    state.saveName
                )
                if not succeeded then
                    report(host, "Plot copy could not start: " .. tostring(accepted))
                elseif accepted == false then
                    report(host, message or "Plot copy could not start")
                end
            end
        end
    end

    plotCopy.ownerButton:on("click", function()
        setDropdownOpen(not state.dropdownOpen)
    end)
    plotCopy.saveButton:on("click", function()
        setDropdownOpen(false)
        if plotCopy.saveInput then
            plotCopy.saveInput:CaptureFocus()
        end
    end)
    plotCopy.actionButton:on("click", runPrimaryAction)
    plotCopy.secondaryButton:on("click", function()
        local plotCopyState = host:read().plotCopy or {}
        if plotCopyState.state == "awaiting_confirmation" then
            invoke(host, "cancelPlotCopy")
        elseif plotCopyState.state == "paused" then
            invoke(host, "discardPlotCopy")
        end
    end)

    local uiParent = host:uiParent()
    if uiParent then
        local inputLayer = host:createInstance("ScreenGui")
        inputLayer.Name = "UniversalHubPlotCopyInput"
        inputLayer.DisplayOrder = 10000
        inputLayer.IgnoreGuiInset = true
        inputLayer.ResetOnSpawn = false
        inputLayer.Parent = uiParent

        local saveInput = host:createInstance("TextBox")
        saveInput.Name = "SaveName"
        saveInput.BackgroundTransparency = 1
        saveInput.ClearTextOnFocus = false
        saveInput.Position = UDim2.fromOffset(-20, -20)
        saveInput.Size = UDim2.fromOffset(1, 1)
        saveInput.Text = ""
        saveInput.TextTransparency = 1
        saveInput.Parent = inputLayer
        plotCopy.inputLayer = inputLayer
        plotCopy.saveInput = saveInput
        table.insert(state.connections, saveInput:GetPropertyChangedSignal("Text"):Connect(function()
            setSaveName(saveInput.Text)
        end))
        table.insert(state.connections, saveInput.Focused:Connect(function()
            plotCopy.saveOutline.Color = colors.accent
        end))
        table.insert(state.connections, saveInput.FocusLost:Connect(function(enterPressed)
            plotCopy.saveOutline.Color = colors.border
            if enterPressed then
                runPrimaryAction()
            end
        end))
    end

    function state:layout(x, _y, cursor)
        local section = controls.sections.plotCopy
        section.label.Position = Vector2.new(x + LAYOUT.contentInset, cursor)
        section.line.Position = Vector2.new(x + LAYOUT.sectionLineX, cursor + LAYOUT.sectionLineY)
        cursor = cursor + LAYOUT.sectionHeaderHeight

        plotCopy.ownerButton.Position = Vector2.new(x + LAYOUT.contentInset, cursor)
        plotCopy.ownerOutline.Position = plotCopy.ownerButton.Position
        plotCopy.ownerLabel.Position = Vector2.new(x + LAYOUT.ownerLabelX, cursor + LAYOUT.ownerTextY)
        plotCopy.ownerValue.Position = Vector2.new(x + LAYOUT.ownerValueX, cursor + LAYOUT.ownerTextY)
        plotCopy.ownerIndicator.Position = Vector2.new(
            x + LAYOUT.ownerIndicatorX,
            cursor + LAYOUT.ownerIndicatorY
        )
        plotCopy.saveButton.Position = Vector2.new(x + LAYOUT.contentInset, cursor + LAYOUT.saveRowTop)
        plotCopy.saveOutline.Position = plotCopy.saveButton.Position
        plotCopy.saveLabel.Position = Vector2.new(x + LAYOUT.saveLabelX, cursor + LAYOUT.saveTextY)
        plotCopy.saveValue.Position = Vector2.new(x + LAYOUT.saveValueX, cursor + LAYOUT.saveTextY)
        plotCopy.actionButton.Position = Vector2.new(x + LAYOUT.contentInset, cursor + LAYOUT.actionTop)
        plotCopy.actionLabel.Position = Vector2.new(x + LAYOUT.actionLabelX, cursor + LAYOUT.actionLabelY)
        plotCopy.secondaryButton.Position = Vector2.new(x + LAYOUT.contentInset, cursor + LAYOUT.secondaryTop)
        plotCopy.secondaryLabel.Position = Vector2.new(
            x + LAYOUT.secondaryLabelX,
            cursor + LAYOUT.secondaryLabelY
        )
        plotCopy.progressPhase.Position = Vector2.new(
            x + LAYOUT.progressLabelInset,
            cursor + LAYOUT.progressPhaseTop
        )
        plotCopy.progressValue.Position = Vector2.new(
            x + LAYOUT.progressValueX,
            cursor + LAYOUT.progressPhaseTop
        )
        plotCopy.progressContext.Position = Vector2.new(
            x + LAYOUT.progressLabelInset,
            cursor + LAYOUT.progressContextTop
        )
        plotCopy.progressTrack.Position = Vector2.new(
            x + LAYOUT.contentInset,
            cursor + LAYOUT.progressTrackTop
        )
        plotCopy.progressFill.Position = plotCopy.progressTrack.Position
        for index, item in ipairs(self.dropdownItems) do
            local itemOffset = (index - 1) * LAYOUT.dropdownRowHeight
            item.row.Position = Vector2.new(
                x + LAYOUT.contentInset,
                cursor + LAYOUT.dropdownRowTop + itemOffset
            )
            item.label.Position = Vector2.new(
                x + LAYOUT.dropdownLabelInset,
                cursor + LAYOUT.dropdownLabelTop + itemOffset
            )
        end
        return cursor + LAYOUT.panelHeight
    end

    function state:setVisible(visible)
        for name, item in pairs(plotCopy) do
            if name ~= "inputLayer"
                and name ~= "saveInput"
                and name ~= "dropdownItems"
                and name ~= "secondaryButton"
                and name ~= "secondaryLabel"
                and name ~= "secondaryVisible"
            then
                item.Visible = visible
            end
        end
        controls.sections.plotCopy.label.Visible = visible
        controls.sections.plotCopy.line.Visible = visible
        plotCopy.secondaryButton.Visible = visible and plotCopy.secondaryVisible == true
        plotCopy.secondaryLabel.Visible = visible and plotCopy.secondaryVisible == true
        for _, item in ipairs(self.dropdownItems) do
            setVisible(item, visible and self.dropdownOpen)
        end
        if plotCopy.inputLayer then
            plotCopy.inputLayer.Enabled = visible
        end
        if not visible then
            setDropdownOpen(false)
        end
    end

    function state:render(current)
        local plotCopyState = current.plotCopy or {}
        local progress = math.clamp(
            plotCopyState.confirmedProgress or plotCopyState.progress or 0,
            0,
            1
        )
        local active = plotCopyState.active == true
        local copyState = plotCopyState.state or (active and "copying" or "idle")
        local hasError = copyState == "error" or copyState == "rollback_incomplete"
        local primaryLabels = {
            awaiting_confirmation = "Start copy",
            cancel_requested = "Cancelling...",
            cleanup_pending = "Cleanup pending",
            completed = "Copy another",
            copying = "Cancel",
            copy_authorized = "Starting...",
            discarding = "Discarding...",
            error = "Retry",
            idle = "Copy & Save",
            paused = "Resume",
            preflight = "Cancel",
            reconciling = "Cancel",
            resuming = "Cancel",
            rollback = "Cleaning...",
            rollback_incomplete = "Retry cleanup",
            saving = "Saving...",
        }
        local primaryEnabled = copyState == "idle"
            or copyState == "completed"
            or copyState == "error"
            or copyState == "awaiting_confirmation"
            or copyState == "copying"
            or copyState == "preflight"
            or copyState == "reconciling"
            or copyState == "resuming"
            or copyState == "paused"
            or copyState == "rollback_incomplete"
            or copyState == "rollback"
            or copyState == "cleanup_pending"
        local secondaryLabel
        if copyState == "awaiting_confirmation" then
            secondaryLabel = "Cancel"
        elseif copyState == "paused" then
            secondaryLabel = "Discard"
        end
        plotCopy.progressPhase.Text = compactText(plotCopyState.phase or "Ready", 34)
        plotCopy.progressPhase.Color = hasError and colors.danger
            or (active and colors.text or colors.secondary)
        plotCopy.progressContext.Text = plotCopyState.context or ""
        plotCopy.progressContext.Color = hasError and colors.danger or colors.secondary
        plotCopy.progressValue.Text = ("%d%%"):format(math.round(progress * 100))
        plotCopy.progressValue.Color = active and colors.accent or colors.secondary
        plotCopy.progressFill.Size = Vector2.new(
            LAYOUT.contentWidth * progress,
            tokens.control.progressTrackHeight
        )
        plotCopy.progressFill.Color = hasError and colors.danger or colors.accent
        host:setControlColor(
            plotCopy.actionButton,
            primaryEnabled and colors.accentSurface or colors.panel
        )
        plotCopy.actionLabel.Text = plotCopyState.localCleanupAvailable
                and "Clear local recovery"
            or (plotCopyState.retryCleanupAvailable and "Retry cleanup")
            or (
                plotCopyState.resumeAvailable
                    and copyState ~= "awaiting_confirmation"
                    and "Resume"
            )
            or (primaryLabels[copyState] or "Working...")
        plotCopy.actionLabel.Color = primaryEnabled and colors.accent or colors.secondary
        local showSecondary = secondaryLabel ~= nil and current.menuVisible ~= false
        plotCopy.secondaryVisible = secondaryLabel ~= nil
        plotCopy.secondaryButton.Visible = showSecondary
        plotCopy.secondaryLabel.Visible = showSecondary
        plotCopy.secondaryLabel.Text = secondaryLabel or ""
    end

    function state:destroy()
        clearDropdown()
        for _, connection in ipairs(self.connections) do
            connection:Disconnect()
        end
        table.clear(self.connections)
        if plotCopy.inputLayer then
            plotCopy.inputLayer:Destroy()
            plotCopy.inputLayer = nil
            plotCopy.saveInput = nil
        end
    end

    return state
end

function Presentation.mount(host)
    if host:supports("plotCopy") then
        host:register(createPanel(host))
    end
end

return Presentation
