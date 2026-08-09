local fs = require("@lune/fs")
local function read(path) return fs.readFile(path) end
local function contains(source, needle, message)
    assert(string.find(source, needle, 1, true), message or ("missing: " .. needle))
end

local catalog = read("modules/presentation/Catalog.lua")
for _, field in ipairs({
    "worldRenderer", "nameLabel", "boxes", "chams", "names", "health", "weapon",
    "chamsExcludeAccessories", "chamsPerPart",
}) do
    contains(catalog, "preview." .. field, "Preview model must publish " .. field)
end
contains(catalog, "parent = option.parent", "Catalog must retain suboption ownership")

local contracts = read("native-ui/src/contracts.ts")
contains(contracts, 'readonly worldRenderer?: "limn" | "native";')
contains(contracts, "readonly parent?: string;")
contains(contracts, "readonly chamsExcludeAccessories?: boolean;")
contains(contracts, "readonly chamsPerPart?: boolean;")

local menu = read("native-ui/src/UniversalHubMenu.tsx")
contains(menu, "previewRef.current = preview", "Projection callback must observe the current preview publisher")
contains(menu, "restyle the single owned preview rig")
contains(menu, "UniversalHubPreviewTextureStash")
contains(menu, "if (!enabled)", "Disabled preview must not own a RenderStepped connection")
contains(menu, "currentPreview?.publish === undefined")
contains(menu, 'currentPreview?.worldRenderer === "native" && accessoryOwned', "Native projection must preserve accessory ownership")
assert(not string.find(menu, "NativePreviewChams", 1, true), "Preview must not maintain a second Chams renderer")
contains(menu, "ChamsPopover")
contains(menu, "SlidersButton")
contains(menu, "closeOnOutsidePress", "Chams settings must use Prism click-away dismissal")
contains(menu, "suboptions={control.id === \"chams\" ? visualSuboptions : []}")
contains(menu, "control.parent === undefined")
contains(menu, "ESP PREVIEW")
contains(menu, "styleControl={styleSection?.controls[0]}", "Style selector must live in the preview header")
contains(menu, "audienceControls={audienceControls}", "Multi-select audience control must live with the preview")
contains(menu, "AudienceMultiSelect")
contains(menu, 'text="VISIBILITY"', "World ESP membership control must be labeled Visibility")
assert(not string.find(menu, 'text="AUDIENCE"', 1, true), "Audience must not remain as the visible label")
contains(menu, 'control.id === "showEnemies"')
contains(menu, 'control.id === "showTeammates"')
contains(menu, "Enable a visual to preview", "zero-option preview must not mount the 3D rig")
contains(menu, "Drag to rotate")
contains(menu, "stopRotation")
contains(menu, "UserInputService.InputChanged.Connect", "Rotation listeners must be gesture-scoped")
contains(menu, 'reserveAction={page.preview?.worldRenderer === "native" && index % 2 === 1}', "Classic toggles must reclaim the Chams action slot")
contains(menu, "reserveAction ? -42 : -10", "Column toggles must retain consistent alignment")
contains(menu, "position={new UDim2(1, -10, 0.5, 0)}", "Chams settings must sit to the right of its toggle")
contains(menu, 'label: "ESP Colors"', "Visuals must expose the dedicated ESP Colors view")
contains(menu, "function EspColorsView", "Color customization must live on its dedicated page")
contains(menu, 'alphaEnabled={fill}', "Only Fill may expose alpha")
assert(not string.find(menu, 'text="COLORS"', 1, true), "The old inline Colors row must not remain above the preview")
contains(menu, "Position={UDim2.fromOffset(0, 84)}", "Preview must retain breathing room below its selectors")

print("native-renderer-preview-contracts-ok")
