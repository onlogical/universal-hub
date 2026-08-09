local roblox = require("@lune/roblox")
Color3 = roblox.Color3

local Policy = require("../modules/EspColorPolicy")
local fallback = Color3.fromRGB(1, 2, 3)

assert(Policy.parseHex("#C76559") == Color3.fromRGB(199, 101, 89))
assert(Policy.parseHex("#0f8") == Color3.fromRGB(0, 255, 136))
assert(Policy.parseHex("bad-value") == nil)
assert(Policy.toHex(Color3.fromRGB(199, 101, 89)) == "#C76559")
assert(Policy.color({ espOutlineColor = "" }, "outline", fallback) == fallback)
assert(Policy.color({ espOutlineColor = "#FFFFFF" }, "outline", fallback) == Color3.fromRGB(255, 255, 255))
assert(Policy.color({ espEnemyOutlineColor = "#112233", espOutlineColor = "#FFFFFF" }, "outline", fallback, "enemy") == Color3.fromRGB(17, 34, 51))
assert(Policy.color({ espTeammateOutlineColor = "#445566" }, "outline", fallback, "team") == Color3.fromRGB(68, 85, 102))
assert(Policy.color({ espEnemyOutlineColor = "", espOutlineColor = "#FFFFFF" }, "outline", fallback, "enemy") == fallback)

local alpha, customized = Policy.fillAlpha({ espFillAlpha = -1 }, 0.58)
assert(alpha == 0.58 and customized == false)
alpha, customized = Policy.fillAlpha({ espFillAlpha = 0.25 }, 0.58)
assert(alpha == 0.25 and customized == true)

assert(Policy.healthColor({}, 0, Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 255, 0)) == Color3.fromRGB(255, 0, 0))
assert(Policy.healthColor({}, 1, Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 255, 0)) == Color3.fromRGB(0, 255, 0))
print("esp-color-policy-contracts-ok")
