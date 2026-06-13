if _G.SyftAirdropESP and _G.SyftAirdropESP._loaded then
    _G.SyftAirdropESP.SetEnabled(true)
    return
end

local RS = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local M = {}
_G.SyftAirdropESP = M
M._loaded = true
M.enabled = true
M._seenIds = {}
M._draws = {}

local AUDIO_URL = "https://github.com/saturn-dev/SyftJailbreak/raw/refs/heads/main/notification.mp3"
local BAR_COLOR = "#8B0000"

local function newDrawSet()
    local box = Drawing.new("Square")
    box.Color = Color3.fromRGB(243, 139, 168)
    box.Thickness = 1.5
    box.Filled = false
    box.Visible = false
    box.ZIndex = 10

    local lbl = Drawing.new("Text")
    lbl.Font = Drawing.Fonts.SystemBold
    lbl.Size = 14
    lbl.Color = Color3.fromRGB(243, 139, 168)
    lbl.Outline = true
    lbl.Center = true
    lbl.Visible = false
    lbl.ZIndex = 11
    lbl.Text = "AIRDROP"

    local dist = Drawing.new("Text")
    dist.Font = Drawing.Fonts.System
    dist.Size = 12
    dist.Color = Color3.fromRGB(245, 194, 231)
    dist.Outline = true
    dist.Center = true
    dist.Visible = false
    dist.ZIndex = 11

    return { box = box, lbl = lbl, dist = dist }
end

local function killSet(set)
    if not set then return end
    pcall(function() set.box:Remove() end)
    pcall(function() set.lbl:Remove() end)
    pcall(function() set.dist:Remove() end)
end

local function hideSet(set)
    if not set then return end
    set.box.Visible = false; set.lbl.Visible = false; set.dist.Visible = false
end

local function findAirdrops()
    local found = {}
    local d = Workspace:FindFirstChild("Drop")
    if d then table.insert(found, d) end
    for _, child in ipairs(Workspace:GetChildren()) do
        local nm = (child.Name or ""):lower()
        if (nm:find("drop") or nm:find("airdrop") or nm:find("crate")) and child ~= d then
            table.insert(found, child)
        end
    end
    return found
end

local function getPart(obj)
    if not obj then return nil end
    local cls = obj.ClassName
    if cls == "Part" or cls == "MeshPart" or cls == "UnionOperation" or cls == "BasePart" then
        return obj
    end
    local p = obj:FindFirstChildWhichIsA("BasePart")
    if p then return p end
    return obj:FindFirstChild("Hitbox") or obj:FindFirstChild("PrimaryPart")
end

local function getLocalPos()
    local lp = Players.LocalPlayer
    if not lp then return nil end
    local char = lp.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    return hrp.Position
end

-- Scan loop: detect new airdrops + fire alert
spawn(function()
    while M._loaded do
        wait(0.5)
        if M.enabled then
            local list = findAirdrops()
            local nowIds = {}
            for _, a in ipairs(list) do
                local id = tostring(a)
                nowIds[id] = a
                if not M._seenIds[id] then
                    M._seenIds[id] = true
                    M._draws[id] = newDrawSet()
                    if _G.alert then
                        _G.alert("Airdrop spawned!", "Airdrop", 3, BAR_COLOR, AUDIO_URL)
                    end
                end
            end
            for id, _ in pairs(M._seenIds) do
                if not nowIds[id] then
                    M._seenIds[id] = nil
                    killSet(M._draws[id]); M._draws[id] = nil
                end
            end
        end
    end
end)

-- Render loop: draw ESP each frame
RS.RenderStepped:Connect(function()
    if not M.enabled then
        for _, set in pairs(M._draws) do hideSet(set) end
        return
    end
    local localPos = getLocalPos()
    for _, child in ipairs(Workspace:GetChildren()) do
        local id = tostring(child)
        local set = M._draws[id]
        if set then
            local part = getPart(child)
            if part and part.Position then
                local ok, screenPos, onScreen = pcall(WorldToScreen, part.Position)
                if ok and onScreen and screenPos then
                    local sz = 90
                    set.box.Size = Vector2.new(sz, sz)
                    set.box.Position = Vector2.new(screenPos.X - sz / 2, screenPos.Y - sz / 2)
                    set.box.Visible = true
                    set.lbl.Position = Vector2.new(screenPos.X, screenPos.Y - sz / 2 - 18)
                    set.lbl.Visible = true
                    if localPos then
                        local d = (localPos - part.Position).Magnitude
                        set.dist.Text = string.format("[%d studs]", math.floor(d))
                        set.dist.Position = Vector2.new(screenPos.X, screenPos.Y + sz / 2 + 4)
                        set.dist.Visible = true
                    else
                        set.dist.Visible = false
                    end
                else
                    hideSet(set)
                end
            else
                hideSet(set)
            end
        end
    end
end)

function M.SetEnabled(v)
    M.enabled = v == true
    if not M.enabled then
        for _, set in pairs(M._draws) do hideSet(set) end
    end
end

function M.Unload()
    M.enabled = false
    M._loaded = false
    for id, set in pairs(M._draws) do killSet(set); M._draws[id] = nil end
    M._seenIds = {}
end
