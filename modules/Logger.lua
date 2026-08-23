local Logger = {}
Logger.__index = Logger

local function sanitize(value)
	return tostring(value):gsub("[\r\n]+", " ")
end

local function formatFields(fields)
	if type(fields) ~= "table" then
		return ""
	end
	local keys = {}
	for key in pairs(fields) do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		table.insert(parts, ("%s=%s"):format(key, sanitize(fields[key])))
	end
	return #parts > 0 and " " .. table.concat(parts, " ") or ""
end

local function fileExists(options, path)
	if not options.isFile then
		return false
	end
	local succeeded, exists = pcall(options.isFile, path)
	return succeeded and exists == true
end

local function tryRead(options, path)
	if not options.readFile then
		return nil
	end
	if options.isFile and not fileExists(options, path) then
		return nil
	end
	local succeeded, content = pcall(options.readFile, path)
	return succeeded and type(content) == "string" and content or nil
end

function Logger.new(options)
	options = options or {}
	local directory = options.directory or "universal-hub/logs"
	local latestPath = directory .. "/latest.log"
	if options.makeFolder then
		pcall(options.makeFolder, "universal-hub")
		pcall(options.makeFolder, directory)
	end

	local previous = tryRead(options, latestPath)
	if previous and previous ~= "" and options.writeFile then
		local name = type(options.archiveName) == "function" and options.archiveName() or tostring(os.time())
		local archivePath = directory .. "/" .. sanitize(name) .. ".log"
		local suffix = 2
		while fileExists(options, archivePath) do
			archivePath = directory .. "/" .. sanitize(name) .. "-" .. suffix .. ".log"
			suffix += 1
		end
		pcall(options.writeFile, archivePath, previous)
	end

	local self = setmetatable({
		appendFile = options.appendFile,
		closed = false,
		latestPath = latestPath,
		lines = {},
		maxLines = options.maxLines or 2000,
		now = options.now or os.clock,
		startedAt = (options.now or os.clock)(),
		writeFile = options.writeFile,
	}, Logger)
	if self.writeFile then
		pcall(self.writeFile, self.latestPath, "")
	end
	self:info("logger", "START", { path = self.latestPath })
	return self
end

function Logger:_write(line)
	table.insert(self.lines, line)
	if #self.lines > self.maxLines then
		table.remove(self.lines, 1)
	end
	if self.appendFile then
		local appended = pcall(self.appendFile, self.latestPath, line .. "\n")
		if appended then
			return
		end
	end
	if self.writeFile then
		pcall(self.writeFile, self.latestPath, table.concat(self.lines, "\n") .. "\n")
	end
end

function Logger:log(level, scope, message, fields)
	if self.closed then
		return
	end
	self:_write(
		("[%08.3f] %-5s %-24s %s%s"):format(
			self.now() - self.startedAt,
			sanitize(level),
			sanitize(scope),
			sanitize(message),
			formatFields(fields)
		)
	)
end

function Logger:info(scope, message, fields)
	self:log("INFO", scope, message, fields)
end

function Logger:warn(scope, message, fields)
	self:log("WARN", scope, message, fields)
end

function Logger:error(scope, message, fields)
	self:log("ERROR", scope, message, fields)
end

function Logger:snapshot()
	return table.clone(self.lines)
end

function Logger:close(fields)
	if self.closed then
		return
	end
	self:info("logger", "STOP", fields)
	self.closed = true
end

return Logger
