loadstring(game:HttpGet("https://raw.githubusercontent.com/saturn-dev/syft-library/refs/heads/main/main/__syft_LuaU.lua"))()
repeat wait() until SyftLib

local UI = SyftLib.new("Syft Jailbreak")
UI:Search()

local tab = UI:Tab("aimbot")
local sec = tab:Section("targeting")
sec:Label("just sybauu")
sec:Label("hover me", "this is a tooltip hjahaa")
sec:Divider("movement")
sec:Toggle("silent aim", false, function(v) print("silent aim:", v) end)
sec:Slider("fov radius", 1, 360, 90, "deg", function(v) print("fov:", v) end)
sec:Divider("visual")
sec:Dropdown("bone target", {"head","neck","chest","pelvis"}, function(v) print("bone:", v) end)
sec:MultiDropdown("hitbox parts", {"head","neck","chest","arms","legs"}, function(t) print("parts:", table.concat(t,", ")) end)
sec:ColorPicker("esp color", Color3.fromHex("#cba6f7"), function(c) print("color:", c) end)

local sec2 = tab:Section("misc")
sec2:Button("teleport to target", function() print("tp!") end)
sec2:Divider("input")
sec2:TextBox("player name", "type name...", function(v) print("name:", v) end)
sec2:Keybind("toggle aimbot", "X", function(kc, name) print("key:", name) end)
sec2:Divider("options")
sec2:Toggle("triggerbot", true, function(v) print("triggerbot:", v) end)
sec2:Slider("smoothness", 1, 100, 25, "%", function(v) print("smooth:", v) end)

local __ESPTab = UI:Tab("ESP")
local __ESPSec = __ESPTab:Section("ESP")

local __ESPBase = "https://raw.githubusercontent.com/saturn-dev/SyftJailbreak/refs/heads/main/source/scripts/ESP/"

local function __ensureAirdropLoaded()
    if not _G.SyftAirdropESP or not _G.SyftAirdropESP._loaded then
        local ok, src = pcall(game.HttpGet, game, __ESPBase .. "__airdropESP.lua")
        if ok and type(src) == "string" and #src > 50 then
            local fn = loadstring(src)
            if fn then pcall(fn) end
        end
    end
end

__ESPSec:Toggle("airdrop ESP", false, function(v)
    if v then __ensureAirdropLoaded() end
    if _G.SyftAirdropESP and _G.SyftAirdropESP.SetEnabled then
        _G.SyftAirdropESP.SetEnabled(v)
    end
end)

__ESPSec:Toggle("airdrop alert", false, function(v)
    if v then __ensureAirdropLoaded() end
    if _G.SyftAirdropESP and _G.SyftAirdropESP.SetAlertEnabled then
        _G.SyftAirdropESP.SetAlertEnabled(v)
    end
end)

__ESPSec:Button("test alert", function()
    if _G.alert then
        _G.alert("Airdrop spawned!", "Airdrop", 3, "#8B0000", "https://github.com/saturn-dev/SyftJailbreak/raw/refs/heads/main/notification.mp3")
    end
end)


local stab = UI:Tab("Settings")
local ssec = stab:Section("appearance")
ssec:ColorPicker("GUI Color", Color3.fromHex("#cba6f7"), function(c) print("color:", c) end)


local ssec2 = stab:Section("menu")
ssec2:Label("press Insert to toggle")
ssec2:Keybind("toggle key", "Insert", function(kc, name)
    UI.toggleKey = kc  -- THIS is what makes the toggle key work
    print("toggle key set to:", name)
end)
ssec2:Divider()
ssec2:Toggle("show on start", true, function(v) print("show:", v) end)
ssec2:Button("close & unload", function() UI:Close() end)

UI:Open()