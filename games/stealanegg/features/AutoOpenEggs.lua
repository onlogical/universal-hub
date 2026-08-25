local AutoOpenEggs = {}
AutoOpenEggs.__index = AutoOpenEggs

local SCAN_INTERVAL = 0.25

function AutoOpenEggs.new(options)
    assert(
        options
            and options.eggCmds
            and options.renderer
            and options.localPlayer
            and options.runService
    )
    return setmetatable({
        eggCmds = options.eggCmds,
        renderer = options.renderer,
        localPlayer = options.localPlayer,
        plotCmds = options.plotCmds,
        runService = options.runService,
        isIndexed = options.isIndexed or function()
            return true
        end,
        spawn = options.spawn or task.spawn,
        opening = {},
        placing = {},
        completeIndex = false,
        elapsed = 0,
        enabled = false,
    }, AutoOpenEggs)
end

local function category(record)
    return record.Item and record.Item.Category or record.AssetCategory
end

function AutoOpenEggs:_findPlacement(records)
    local plot = self.plotCmds and self.plotCmds.GetPlotData()
    if not plot then
        return nil
    end
    local occupied = {}
    for _, record in pairs(records) do
        local placement = record.Placement
        if placement and typeof(placement.LocalCFrame) == "CFrame" then
            table.insert(occupied, placement.LocalCFrame.Position)
        end
    end
    local half = plot.PetArea.Size * 0.5
    for x = -half.X + 5, half.X - 5, 10 do
        for z = -half.Z + 5, half.Z - 5, 10 do
            local world = plot.PetArea.CFrame:PointToWorldSpace(Vector3.new(x, half.Y, z))
            local localCFrame = plot.CenterPoint.CFrame:ToObjectSpace(CFrame.new(world))
            local clear = true
            for _, position in ipairs(occupied) do
                if (position - localCFrame.Position).Magnitude < 8 then
                    clear = false
                    break
                end
            end
            if clear then
                return localCFrame
            end
        end
    end
    return nil
end

function AutoOpenEggs:_scan()
    local records = self.eggCmds.GetOwnerRuntimeRecords(self.localPlayer.UserId)
    for uid in pairs(self.opening) do
        if not records[uid] or not self.eggCmds.IsLocalEggReady(uid) then
            self.opening[uid] = nil
        end
    end
    for uid in pairs(self.placing) do
        if not records[uid] or records[uid].Placement then
            self.placing[uid] = nil
        end
    end
    if self.completeIndex then
        for uid, record in pairs(records) do
            local assetCategory = category(record)
            if
                not record.Placement
                and not self.placing[uid]
                and assetCategory
                and not self.isIndexed(assetCategory)
            then
                local placement = self:_findPlacement(records)
                if placement then
                    self.placing[uid] = true
                    self.spawn(function()
                        if not self.enabled or not self.completeIndex then
                            return
                        end
                        local placed = self.eggCmds.RequestPlaceEgg(uid, placement)
                        if placed then
                            if type(self.renderer.Refresh) == "function" then
                                self.renderer.Refresh()
                            end
                        else
                            self.placing[uid] = nil
                        end
                    end)
                end
                break
            end
        end
    end
    for uid, record in pairs(records) do
        if record.Placement and self.eggCmds.IsLocalEggReady(uid) and not self.opening[uid] then
            self.opening[uid] = true
            self.spawn(function()
                if not self.enabled then
                    return
                end
                if not self.renderer.ActivateLocalEgg(uid) then
                    self.opening[uid] = nil
                end
            end)
        end
    end
end

function AutoOpenEggs:setCompleteIndex(enabled)
    self.completeIndex = enabled == true
    if self.enabled then
        self:_scan()
    end
end

function AutoOpenEggs:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then
        return
    end
    self.enabled = enabled
    if enabled then
        self:_scan()
        self.connection = self.runService.Heartbeat:Connect(function(deltaTime)
            self.elapsed += deltaTime
            if self.elapsed >= SCAN_INTERVAL then
                self.elapsed = 0
                self:_scan()
            end
        end)
        return
    end
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
    table.clear(self.opening)
    table.clear(self.placing)
    self.elapsed = 0
end

function AutoOpenEggs:stop()
    self:setEnabled(false)
end

return AutoOpenEggs
