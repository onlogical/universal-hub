local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Changelog = require("../modules/Changelog")

local function decode(source)
    return serde.decode("json", source)
end

local catalog = Changelog.decode(fs.readFile("changelog.json"), decode)
local markdown = Changelog.markdown(catalog)
local args = {}
for _, value in ipairs(process.args) do
    if value ~= "--" then
        table.insert(args, value)
    end
end
local command = args[1] or "--check"

if command == "--write" then
    fs.writeFile("CHANGELOG.md", markdown)
    print("changelog-write-ok")
    return
end

if command == "--notes" then
    local version = args[2] or catalog.current
    local notes = Changelog.releaseNotes(catalog, version)
    assert(notes, "No changelog notes for version " .. tostring(version))
    print(notes)
    return
end

if command == "--current" then
    print(catalog.current)
    return
end

assert(command == "--check", "Unknown changelog command: " .. tostring(command))
assert(fs.isFile("CHANGELOG.md"), "CHANGELOG.md is missing")
local existing = fs.readFile("CHANGELOG.md"):gsub("\r\n", "\n")
assert(existing == markdown, "CHANGELOG.md is out of date. Run: lune run scripts/changelog.luau -- --write")
print("changelog-check-ok")
