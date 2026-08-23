local BestEggHighlight = {}
BestEggHighlight.__index = BestEggHighlight

local SCORE_NAMES = {
    value = true, worth = true, price = true, income = true,
    cash = true, money = true, profit = true, multiplier = true,
}
local SUFFIX = { K = 1e3, M = 1e6, B = 1e9, T = 1e12 }

local function numberFromText(text)
    local best = 0
    text = string.upper(tostring(text):gsub(",", ""))
    for raw, suffix in text:gmatch("([%d%.]+)%s*([KMBT]?)") do
        local value = tonumber(raw)
        if value then best = math.max(best, value * (SUFFIX[suffix] or 1)) end
    end
    return best
end

local function isEgg(item)
    if not (item:IsA("Model") or item:IsA("BasePart")) then return false end
    if not item.Name:lower():find("egg", 1, true) then return false end
    local parent = item.Parent
    while parent and parent ~= workspace do
        if (parent:IsA("Model") or parent:IsA("BasePart"))
            and parent.Name:lower():find("egg", 1, true) then
            return false
        end
        parent = parent.Parent
    end
    return true
end

local function containerFor(egg)
    local fallback = egg.Parent
    local current = egg.Parent
    while current and current ~= workspace do
        local name = current.Name:lower()
        if name:find("nest", 1, true) or name:find("plot", 1, true)
            or name:find("pen", 1, true) or name:find("base", 1, true) then
            return current
        end
        current = current.Parent
    end
    return fallback
end

local function score(egg)
    local best = 0
    for name, value in pairs(egg:GetAttributes()) do
        if SCORE_NAMES[name:lower()] then
            best = math.max(best, type(value) == "number" and value or numberFromText(value))
        end
    end
    for _, item in ipairs(egg:GetDescendants()) do
        if SCORE_NAMES[item.Name:lower()] then
            if item:IsA("NumberValue") or item:IsA("IntValue") then
                best = math.max(best, item.Value)
            elseif item:IsA("StringValue") then
                best = math.max(best, numberFromText(item.Value))
            end
        end
        if item:IsA("TextLabel") or item:IsA("TextButton") then
            best = math.max(best, numberFromText(item.Text))
        end
    end
    return best
end

local function recordScore(value, key, visited)
    local valueType = type(value)
    if valueType == "number" then
        return key and SCORE_NAMES[tostring(key):lower()] and value or 0
    end
    if valueType == "string" then
        return key and SCORE_NAMES[tostring(key):lower()] and numberFromText(value) or 0
    end
    if valueType ~= "table" or visited[value] then return 0 end
    visited[value] = true
    local best = 0
    for childKey, childValue in pairs(value) do
        best = math.max(best, recordScore(childValue, childKey, visited))
    end
    return best
end

local function uidMatches(item, uid)
    local target = tostring(uid)
    if item.Name == target then return true end
    for _, name in ipairs({ "Uid", "UID", "EggUid", "EggUID", "EggId", "EggID" }) do
        if tostring(item:GetAttribute(name)) == target then return true end
    end
    return false
end

function BestEggHighlight.new(options)
    assert(options and options.workspace and options.runService and options.coreGui and options.eggCmds)
    local folder = Instance.new("Folder")
    folder.Name = "UniversalHubBestEggs"
    folder.Parent = options.coreGui
    return setmetatable({
        workspace = options.workspace,
        eggCmds = options.eggCmds,
        runService = options.runService,
        folder = folder,
        elapsed = 0,
        enabled = false,
    }, BestEggHighlight)
end

function BestEggHighlight:_scan()
    self.folder:ClearAllChildren()
    local groups = {}
    local uidInstances = {}
    local snapshot = self.eggCmds.GetAreaEggSnapshot()
    local records = snapshot and snapshot.Records or {}
    for _, item in ipairs(self.workspace:GetDescendants()) do
        for _, record in ipairs(records) do
            if record.Uid and not uidInstances[record.Uid] and uidMatches(item, record.Uid) then
                uidInstances[record.Uid] = item
            end
        end
        if isEgg(item) then
            local container = containerFor(item)
            local candidate = { egg = item, score = score(item) }
            if not groups[container] or candidate.score > groups[container].score then
                groups[container] = candidate
            end
        end
    end
    for _, record in ipairs(records) do
        local egg = uidInstances[record.Uid]
        if egg and (egg:IsA("Model") or egg:IsA("BasePart")) then
            local group = tostring(record.AreaId) .. ":" .. tostring(record.NestId)
            local candidate = {
                egg = egg,
                score = math.max(score(egg), recordScore(record, nil, {})),
            }
            if not groups[group] or candidate.score > groups[group].score then
                groups[group] = candidate
            end
        end
    end
    for _, result in pairs(groups) do
        local highlight = Instance.new("Highlight")
        highlight.Name = "BestEgg"
        highlight.Adornee = result.egg
        highlight.FillColor = Color3.fromRGB(255, 205, 40)
        highlight.FillTransparency = 0.2
        highlight.OutlineColor = Color3.new(1, 1, 1)
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = self.folder
    end
end

function BestEggHighlight:setEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then return end
    self.enabled = enabled
    if enabled then
        self:_scan()
        self.connection = self.runService.Heartbeat:Connect(function(deltaTime)
            self.elapsed += deltaTime
            if self.elapsed >= 1 then
                self.elapsed = 0
                self:_scan()
            end
        end)
    else
        if self.connection then self.connection:Disconnect() self.connection = nil end
        self.folder:ClearAllChildren()
        self.elapsed = 0
    end
end

function BestEggHighlight:stop()
    self:setEnabled(false)
    if self.folder.Parent then self.folder:Destroy() end
end

return BestEggHighlight
