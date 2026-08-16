local fs = require("@lune/fs")
local function read(path) return fs.readFile(path) end
local function contains(source, needle, message)
    assert(string.find(source, needle, 1, true), message or ("missing: " .. needle))
end

local policy = read("ui/esp/VisualPolicy.lua")
contains(policy, "FILL_TRANSPARENCY = 0.42")
contains(policy, "OUTLINE_THICKNESS = 2")

local native = read("ui/esp/HighlightRenderer.lua")
contains(native, 'importDependency("ui/esp/VisualPolicy"')
contains(native, "VisualPolicy.FILL_TRANSPARENCY")

local menu = read("ui/Menu.lua")
contains(menu, "previewRenderer = preview.worldRenderer")
contains(menu, "setthreadidentity", "Prism mount must restore executor identity before Instance work")
contains(menu, "withExecutorScheduler", "Prism mount must keep React scheduler callbacks on an executor thread")
contains(menu, "screenGui.Enabled = context.menuEnabled ~= false", "HubMenu must not be clickable before the session exists")

local index = read("ui/src/index.tsx")
contains(index, "createLegacyRoot", "Prism menu must mount on a legacy root so Instance work stays on the caller thread")
assert(not string.find(index, "createRoot(", 1, true), "Concurrent createRoot schedules Instance work onto a Plugin-capability-stripped thread")

local menu = read("ui/dist/Menu.lua")
contains(menu, "createLegacyRoot(parent)", "The live Wax bundle must match the legacy-root mount")
assert(
    menu:match("local function wrapPerformWorkWithCoroutine%(performWork%)%s+return performWork%s+end") ~= nil,
    "Compiled React scheduler must not hop Instance work onto a coroutine that lacks Plugin capability"
)

local overlay = read("ui/esp/DrawingRenderer.lua")
contains(overlay, 'importDependency("ui/esp/VisualPolicy"')
contains(overlay, 'observation.previewRenderer == "native"')
contains(overlay, "_ensureNativeBodyPartOutlines")
contains(overlay, "NATIVE_PREVIEW_FILL_TRANSPARENCY")
contains(overlay, "settings.chamsExcludeAccessories == true")
contains(overlay, "nodes.box.Visible = settings.boxes == true and not nativePreview")

local ui = read("ui/src/UniversalHubMenu.tsx")
contains(ui, 'currentPreview?.worldRenderer === "native" && accessoryOwned')
contains(ui, "accessory: accessoryOwned ? true : undefined")
contains(ui, "if (!enabled)", "zero-option preview must not connect projection work")
contains(ui, "preview.chamsColor", "Native Chams rig must consume shared policy color")
contains(ui, "UniversalHubPreviewChams", "Viewport Highlights must be mocked as a fill overlay, not Neon restyle")
contains(ui, "stylePreviewChamsOverlay", "Overlay clones must stay SmoothPlastic so hair is not emissive")
contains(ui, "LocalTransparencyModifier = 1", "Dummy surfaces must hide so overlay fill cannot Z-fight")
contains(ui, "preview.chams !== true", "3D overlay is Chams-only; hitboxes must not create a shell")
contains(ui, "Hitboxes use SelectionBox strokes", "Hitboxes must stay stroke-only ViewportFrame outlines")
contains(ui, 'new Instance("SelectionBox")', "Preview hitboxes must use SelectionBox, not a filled mesh")
contains(ui, "UniversalHubPreviewHitboxes", "Hitboxes must parent stroke outlines into the preview WorldModel")
contains(ui, "SurfaceTransparency = 1", "SelectionBox hitboxes must be stroke-only, not filled")
contains(ui, "preview.boxes !== true", "Hitbox outlines must only exist while Hitboxes is on")
assert(not string.find(ui, "_ChamsOutline", 1, true), "Hitboxes must not weld a 3D outline shell")
contains(ui, "Color3.fromRGB(0, 0, 0)", "Highlight preview lighting must be unlit")
assert(not string.find(menu, "_ChamsOutline", 1, true), "Compiled preview must not weld a 3D hitbox shell")
contains(menu, "UniversalHubPreviewHitboxes", "Compiled preview must mount SelectionBox hitboxes")
contains(menu, 'Instance.new("SelectionBox")', "Compiled preview must create stroke-only SelectionBoxes")
contains(menu, "SurfaceTransparency = 1", "Compiled SelectionBoxes must not fill")
assert(not string.find(ui, "Enum.Material.Neon", 1, true), "Preview Chams must not paint the dummy Neon")
assert(not string.find(ui, "UniversalHubPreviewTextureStash", 1, true), "Preview must not strip the dummy's clothing textures")
contains(overlay, 'observation.previewRenderer ~= "native"', "Native preview Chams must not be duplicated through Limn")
assert(not string.find(ui, "NativePreviewChams", 1, true), "UI must not own a duplicate native Chams policy")
assert(not string.find(ui, "NativePreviewOverlay", 1, true), "UI must not own a duplicate native overlay policy")

print("native-preview-parity-contracts-ok")
