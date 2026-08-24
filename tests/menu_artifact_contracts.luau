local fs = require("@lune/fs")

assert(fs.isFile("scripts/build_menu.cjs"), "Menu emit must be produced by scripts/build_menu.cjs")
assert(fs.isFile("ui/dist/Menu.lua"), "Compiled Prism menu must live at ui/dist/Menu.lua")
assert(fs.isFile("ui/package.json"), "ui/package.json must exist")

local packageJson = fs.readFile("ui/package.json")
assert(
    string.find(packageJson, "scripts/build_menu.cjs", 1, true),
    "ui build must invoke scripts/build_menu.cjs"
)
assert(
    not string.find(packageJson, "build_native_menu.cjs", 1, true),
    "native-ui build script name is gone"
)

local buildScript = fs.readFile("scripts/build_menu.cjs")
local prismTsconfig = fs.readFile("ui/tsconfig.prism.json")
local visualsSource = fs.readFile("ui/src/visuals/VisualsPage.tsx")
assert(
    string.find(buildScript, "normalizeLf", 1, true),
    "Menu generation must normalize emitted line endings"
)
assert(
    string.find(buildScript, "virtualImports.includes", 1, true),
    "Generated import rewrites must verify their postcondition"
)
assert(
    string.find(buildScript, "entrypointPatched.endsWith(entrypoint)", 1, true),
    "Generated entrypoint rewrites must verify their postcondition"
)
assert(
    string.find(buildScript, "schedulerPatched === entrypointPatched", 1, true),
    "Generated scheduler rewrites must fail when no rewrite occurred"
)
assert(
    not fs.isFile("ui/src/prismCompat.tsx"),
    "Universal Hub must not masquerade app controls as Prism exports"
)
assert(
    not string.find(buildScript, '"@prism":', 1, true),
    "Menu build must not remap the Prism package root"
)
assert(
    not string.find(prismTsconfig, '"@prism":', 1, true),
    "Prism tsconfig must not remap the package root"
)
assert(
    string.find(visualsSource, 'from "../components/EspColorPicker"', 1, true),
    "Visuals must own its ESP color picker explicitly"
)
assert(
    string.find(visualsSource, 'from "../components/AudienceMultiSelect"', 1, true),
    "Visuals must own its audience selector explicitly"
)
assert(
    not string.find(visualsSource, 'from "@prism"', 1, true),
    "Visuals must import Prism modules directly"
)
local artifactPath = "ui/dist/Menu.lua"
local artifact = fs.readFile(artifactPath)
local chunk, compileError = loadstring(artifact, artifactPath)
assert(chunk, compileError)
assert(
    string.find(artifact, "mountUniversalHubMenu", 1, true),
    "Menu artifact must contain the source entrypoint"
)
assert(
    string.find(artifact, "AudienceMultiSelect", 1, true),
    "Menu artifact must contain the app-owned audience control"
)
assert(
    string.find(artifact, "EspColorPicker", 1, true),
    "Menu artifact must contain the app-owned color control"
)
assert(
    not string.find(artifact, "prismCompat", 1, true),
    "Menu artifact must not retain the deleted compatibility shim"
)

local localLoader = fs.readFile("local.lua")
assert(
    string.find(localLoader, "ui/dist/Menu.lua", 1, true),
    "local.lua must load ui/dist/Menu.lua"
)
assert(
    string.find(localLoader, "loadfile", 1, true),
    "local.lua must prefer Volt loadfile for workspace modules"
)
assert(
    string.find(localLoader, "configuration.ReloadMenu", 1, true),
    "Local loader must restage the compiled menu without init knowing the artifact path"
)
assert(
    string.find(localLoader, "configuration.MenuStampPath", 1, true),
    "Local loader must expose a cheap stamp for compiled-menu hot reload"
)
assert(
    not string.find(localLoader, "vendor/UniversalHubMenu.lua", 1, true),
    "vendor/UniversalHubMenu.lua must not be the menu path"
)
assert(
    not string.find(localLoader, "NativeMenu", 1, true),
    "configuration.NativeMenu is configuration.Menu"
)

local hubLoader = fs.readFile("hub.lua")
assert(string.find(hubLoader, "ui/dist/Menu.lua", 1, true), "hub.lua must fetch ui/dist/Menu.lua")
assert(
    not string.find(hubLoader, "ReloadMenu", 1, true),
    "Packaged hub.lua must not hot-reload the compiled menu"
)
assert(
    not string.find(hubLoader, "vendor/UniversalHubMenu.lua", 1, true),
    "hub.lua must not fetch vendor/UniversalHubMenu.lua"
)

local init = fs.readFile("init.lua")
assert(string.find(init, "configuration.Menu", 1, true), "init.lua must consume configuration.Menu")
assert(
    string.find(init, "configuration.ReloadMenu", 1, true),
    "init.lua must restage the compiled menu through the loader seam"
)
assert(
    string.find(init, "overlayContext.prismMenu = nextMenu", 1, true),
    "A compiled-menu reload must remount through the existing HubMenu context"
)
assert(
    string.find(init, "configuration.MenuStampPath", 1, true),
    "Hot reload must watch the loader-provided menu stamp"
)
assert(
    not string.find(init, "ui/dist/Menu.lua", 1, true),
    "init.lua must not hardcode the compiled menu path"
)
assert(
    not string.find(init, "configuration.NativeMenu", 1, true),
    "init.lua must not read configuration.NativeMenu"
)
assert(
    string.find(init, "rbxthumb://type=GameIcon&id=%d&w=150&h=150", 1, true),
    "Game UI must use the uploaded Roblox game icon"
)
assert(not string.find(init, "/assets/games/", 1, true), "Game UI must not load local game icons")
assert(not fs.isDir("assets/games"), "Local game icon directory must be removed")
assert(
    string.find(init, "menuEnabled = false", 1, true),
    "Menu must stay disabled until the hub session exists"
)
assert(
    string.find(init, "if not current then", 1, true),
    "Option callbacks must not index a nil session"
)

local hubMenu = fs.readFile("ui/Menu.lua")
assert(
    string.find(hubMenu, "screenGui.Enabled = context.menuEnabled ~= false", 1, true),
    "HubMenu must honor menuEnabled before parenting the ScreenGui"
)

Color3 = {
    fromRGB = function()
        return {}
    end,
}
local HubMenu = require("../ui/Menu")
local identity
setthreadidentity = function(value)
    identity = value
end
local menu = setmetatable({ destroyed = false, gui = { Enabled = false } }, HubMenu)
menu:setEnabled(true)
assert(
    identity == 8 and menu.gui.Enabled == true,
    "Prism visibility must restore executor identity"
)
setthreadidentity = nil

assert(not fs.isFile("vendor/UniversalHubMenu.lua"), "vendor/UniversalHubMenu.lua must not remain")
assert(
    not fs.isFile("scripts/build_native_menu.cjs"),
    "the missing native-ui build script must not be referenced as a live path"
)

print("menu-artifact-contracts-ok")
