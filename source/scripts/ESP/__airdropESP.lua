if _G.SyftAirdropESP and _G.SyftAirdropESP._loaded then
    return
end

local RS = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- localized globals (perf)
local Drawing_new = Drawing.new
local Vector2_new = Vector2.new
local Vector3_new = Vector3.new
local WTS = WorldToScreen
local floor = math.floor
local clamp = math.clamp
local fmt = string.format

local M = {}
_G.SyftAirdropESP = M
M._loaded = true
M.enabled = false
M.alertEnabled = false

local BOX_COLOR  = Color3.fromRGB(243, 139, 168)
local NAME_COLOR = Color3.fromRGB(255, 255, 255)
local DIST_COLOR = Color3.fromRGB(245, 194, 231)

local FONT = Drawing.Fonts.System
pcall(function() FONT = Drawing.Fonts.SystemBold end)

local pool   = {}   -- [child] = {box, name, dist}
local present = {}  -- [child] = true  (currently under Workspace.Drop)
local seen   = {}   -- [child] = true  (for alert de-dup)

-- ---------- drawing helpers ----------
local function makeSet()
    local box = Drawing_new("Square")
    box.Thickness = 1.5
    box.Filled = false
    box.Color = BOX_COLOR
    box.Visible = false
    box.ZIndex = 10

    local name = Drawing_new("Text")
    name.Font = FONT
    name.Size = 14
    name.Center = true
    name.Outline = true
    name.Color = NAME_COLOR
    name.Visible = false
    name.ZIndex = 11
    name.Text = "AIRDROP"

    local dist = Drawing_new("Text")
    dist.Font = FONT
    dist.Size = 12
    dist.Center = true
    dist.Outline = true
    dist.Color = DIST_COLOR
    dist.Visible = false
    dist.ZIndex = 11

    return { box = box, name = name, dist = dist }
end

local function hideSet(set)
    if not set then return end
    set.box.Visible = false
    set.name.Visible = false
    set.dist.Visible = false
end

local function removeSet(set)
    if not set then return end
    pcall(function() set.box:Remove() end)
    pcall(function() set.name:Remove() end)
    pcall(function() set.dist:Remove() end)
end

local function hideAll()
    for _, set in pairs(pool) do hideSet(set) end
end

local function clearAll()
    for c, set in pairs(pool) do removeSet(set); pool[c] = nil end
end

-- ---------- position helpers ----------
local function getPos(obj)
    if not obj then return nil end
    local ok, p = pcall(function() return obj.Position end)
    if ok and p and typeof(p) == "Vector3" then return p end
    local bp = obj:FindFirstChildWhichIsA("BasePart")
    if bp then
        local ok2, p2 = pcall(function() return bp.Position end)
        if ok2 and p2 then return p2 end
    end
    local prim = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("PrimaryPart")
    if prim then
        local ok3, p3 = pcall(function() return prim.Position end)
        if ok3 and p3 then return p3 end
    end
    return nil
end

local function getLocalPos()
    local lp = Players.LocalPlayer
    if not lp then return nil end
    local char = lp.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local ok, p = pcall(function() return hrp.Position end)
    if ok then return p end
    return nil
end

-- ---------- scan: track Workspace.Drop children + fire alerts ----------
local function scan()
    local drop = Workspace:FindFirstChild("Drop")
    local current = {}
    if drop then
        for _, c in ipairs(drop:GetChildren()) do
            current[c] = true
            if not seen[c] then
                seen[c] = true
                if M.alertEnabled and notify then
                    pcall(notify, "Airdrop spawned!", "Airdrop", 3)
                end
            end
        end
    end

    for c, _ in pairs(seen) do
        if not current[c] then seen[c] = nil end
    end
    for c, set in pairs(pool) do
        if not current[c] then removeSet(set); pool[c] = nil end
    end

    present = current
end

-- seed silently so existing drops don't spam the alert on first enable
do
    local drop = Workspace:FindFirstChild("Drop")
    if drop then
        for _, c in ipairs(drop:GetChildren()) do seen[c] = true end
    end
end

task.spawn(function()
    while M._loaded do
        scan()
        task.wait(0.5)
    end
end)

-- ---------- render: box + name + distance ----------
local renderConn
renderConn = RS.RenderStepped:Connect(function()
    if not M._loaded or not M.enabled then
        hideAll()
        return
    end
    local lpos = getLocalPos()
    for c, _ in pairs(present) do
        if c and c.Parent then
            local set = pool[c]
            if not set then set = makeSet(); pool[c] = set end
            local pos = getPos(c)
            if pos then
                local ok, sp, on = pcall(WTS, pos)
                if ok and on and sp then
                    local sz = 80
                    if lpos then
                        local d = (lpos - pos).Magnitude
                        sz = clamp(4500 / (d > 1 and d or 1), 26, 150)
                        set.dist.Text = fmt("[%d studs]", floor(d))
                        set.dist.Position = Vector2_new(sp.X, sp.Y + sz / 2 + 4)
                        set.dist.Visible = true
                    else
                        set.dist.Visible = false
                    end
                    local half = sz / 2
                    set.box.Size = Vector2_new(sz, sz)
                    set.box.Position = Vector2_new(sp.X - half, sp.Y - half)
                    set.box.Visible = true
                    set.name.Text = (c.Name and c.Name ~= "") and c.Name or "AIRDROP"
                    set.name.Position = Vector2_new(sp.X, sp.Y - half - 16)
                    set.name.Visible = true
                else
                    hideSet(set)
                end
            else
                hideSet(set)
            end
        else
            local set = pool[c]
            if set then removeSet(set) end
            pool[c] = nil
            present[c] = nil
        end
    end
end)

-- ---------- public API ----------
function M.SetEnabled(v)
    M.enabled = v == true
    if not M.enabled then hideAll() end
end

function M.SetAlertEnabled(v)
    M.alertEnabled = v == true
end

function M.Unload()
    M.enabled = false
    M.alertEnabled = false
    M._loaded = false
    if renderConn then pcall(function() renderConn:Disconnect() end); renderConn = nil end
    clearAll()
    seen = {}
    present = {}
end
