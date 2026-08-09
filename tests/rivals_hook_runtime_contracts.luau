local HookRuntime = require("../games/rivals/HookRuntime")

local runtime = HookRuntime.new({ capabilities = {} })
runtime:refresh()
assert(runtime.presentation:update() == false)
runtime:stop()

local succeeded = pcall(HookRuntime.new, { capabilities = { "shotAim" } })
assert(not succeeded, "declared hook features must require their executor seam")

print("rivals-hook-runtime-contracts-ok")
