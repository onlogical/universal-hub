local fs = require("@lune/fs")
local function read(path) return fs.readFile(path) end
local function contains(source, needle, message)
    assert(string.find(source, needle, 1, true), message or ("missing: " .. needle))
end

local policy = read("modules/NativeVisualPolicy.lua")
contains(policy, "FILL_TRANSPARENCY = 0.42")
contains(policy, "OUTLINE_THICKNESS = 2")

local native = read("modules/NativeWorldRenderer.lua")
contains(native, 'importDependency("modules/NativeVisualPolicy"')
contains(native, "NativeVisualPolicy.FILL_TRANSPARENCY")

local menu = read("modules/NativeMenu.lua")
contains(menu, "previewRenderer = preview.worldRenderer")

local overlay = read("modules/Overlay.lua")
contains(overlay, 'importDependency("modules/NativeVisualPolicy"')
contains(overlay, 'observation.previewRenderer == "native"')
contains(overlay, "_ensureNativeBodyPartOutlines")
contains(overlay, "NATIVE_PREVIEW_FILL_TRANSPARENCY")
contains(overlay, "settings.chamsExcludeAccessories == true")
contains(overlay, "nodes.box.Visible = settings.boxes == true and not nativePreview")

local ui = read("native-ui/src/UniversalHubMenu.tsx")
contains(ui, 'currentPreview?.worldRenderer === "native" && accessoryOwned')
contains(ui, "accessory: accessoryOwned ? true : undefined")
contains(ui, "if (!enabled)", "zero-option preview must not connect projection work")
contains(ui, "UniversalHubPreviewTextureStash", "Native Chams preview must restyle the single ViewportFrame rig")
contains(ui, "preview.chamsColor", "Native Chams rig must consume shared policy color")
contains(overlay, 'observation.previewRenderer ~= "native"', "Native preview Chams must not be duplicated through Limn")
assert(not string.find(ui, "NativePreviewChams", 1, true), "UI must not own a duplicate native Chams policy")
assert(not string.find(ui, "NativePreviewOverlay", 1, true), "UI must not own a duplicate native overlay policy")

print("native-preview-parity-contracts-ok")
