local fs = require("@lune/fs")

assert(fs.isFile("scripts/stage-volt.ts"), "Volt staging must use Node 24 native TypeScript")
assert(not fs.isFile("scripts/stage-volt.cjs"), "The rejected CommonJS staging script must not remain")

local staging = fs.readFile("scripts/stage-volt.ts")

assert(
    string.find(staging, '"ls-files", "-z", "--cached", "--others", "--exclude-standard"', 1, true),
    "Volt staging must copy the tracked runtime tree, including binary assets"
)
assert(
    string.find(staging, '"universal-hub", "local"', 1, true),
    "Volt staging must preserve the local loader root"
)
assert(string.find(staging, "VOLT_WORKSPACE", 1, true), "Volt staging must support a portable workspace override")
assert(string.find(staging, 'file.startsWith("dumps/")', 1, true), "Volt staging must exclude local dumps")
assert(string.find(staging, "relative(source, destination)", 1, true), "Volt staging must reject a destination inside the source")
assert(string.find(staging, "rmSync(destination", 1, true), "Volt staging must remove stale destination files")
assert(string.find(staging, "copyFileSync", 1, true), "Volt staging must produce a plain copied tree")
assert(not string.find(staging, "worktree", 1, true), "Volt staging must not create a Git worktree")
assert(
    not string.find(staging, "ReplicatedStorage", 1, true),
    "Volt staging must not expose dependencies through the live DataModel"
)

print("volt-asset-staging-contracts-ok")
