if _G.SyftAirdropESP and _G.SyftAirdropESP._loaded then
    return
end

local RS = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- localized globals (perf)
local Drawing_new = Drawing.new
local Vector2_new = Vector2.new
local floor = math.floor
local clamp = math.clamp
local fmt = string.format
local WTS = WorldToScreen

local M = {}
_G.SyftAirdropESP = M
M._loaded = true
M.enabled = false
M.alertEnabled = false

local BOX_COLOR  = Color3.fromRGB(243, 139, 168)
local NAME_COLOR = Color3.fromRGB(255, 255, 255)

-- ZIndex above the menu (cards use 10-16) so they never z-fight (flicker fix).
local Z_FILL = 100
local Z_BOX  = 101
local Z_TEXT = 102

local FONT = Drawing.Fonts.System
pcall(function() FONT = Drawing.Fonts.SystemBold end)

-- Keyed by a STABLE string id (instance wrappers are not stable across calls
-- in Matcha, so we cannot use the instance itself as a table key).
local pool = {}   -- [id] = { fill, box, name, dist, model, part, miss }
local seen = {}   -- [id] = true  (alert de-dup, exactly one per airdrop)

-- ---------- stable identity ----------
local function keyOf(inst)
    local ok, addr = pcall(function() return inst.Address end)
    if ok and addr then return tostring(addr) end
    return tostring(inst)
end

-- ---------- drawing helpers ----------
local function makeSet()
    local fill = Drawing_new("Square")
    fill.Filled = true
    fill.Color = BOX_COLOR
    fill.Transparency = 0.4
    fill.Visible = false
    fill.ZIndex = Z_FILL

    local box = Drawing_new("Square")
    box.Filled = false
    box.Thickness = 1.5
    box.Color = BOX_COLOR
    box.Transparency = 1
    box.Visible = false
    box.ZIndex = Z_BOX

    local name = Drawing_new("Text")
    name.Font = FONT
    name.Size = 13
    name.Center = true
    name.Outline = true
    name.Color = NAME_COLOR
    name.Visible = false
    name.ZIndex = Z_TEXT
    name.Text = "AIRDROP"

    local dist = Drawing_new("Text")
    dist.Font = FONT
    dist.Size = 12
    dist.Center = true
    dist.Outline = true
    dist.Color = BOX_COLOR
    dist.Visible = false
    dist.ZIndex = Z_TEXT

    return { fill = fill, box = box, name = name, dist = dist, model = nil, part = nil, miss = 0 }
end

local function hideSet(set)
    if not set then return end
    set.fill.Visible = false
    set.box.Visible = false
    set.name.Visible = false
    set.dist.Visible = false
end

local function removeSet(set)
    if not set then return end
    pcall(function() set.fill:Remove() end)
    pcall(function() set.box:Remove() end)
    pcall(function() set.name:Remove() end)
    pcall(function() set.dist:Remove() end)
end

local function hideAll()
    for _, set in pairs(pool) do hideSet(set) end
end

local function clearAll()
    for id, set in pairs(pool) do removeSet(set); pool[id] = nil end
end

local function applyColor(set, c)
    set.fill.Color = c
    set.box.Color = c
    set.dist.Color = c
end

-- ---------- helpers ----------
local function isModel(obj)
    local ok, r = pcall(function() return obj:IsA("Model") end)
    return ok and r == true
end

local function partValid(p)
    if not p then return false end
    local ok, par = pcall(function() return p.Parent end)
    return ok and par ~= nil
end

-- airdrop = a Workspace model named "Drop" with no Humanoid (excludes players)
local function isAirdrop(c)
    if not c then return false end
    local okN, nm = pcall(function() return c.Name end)
    if not okN or nm ~= "Drop" then return false end
    if not isModel(c) then return false end
    local okH, hum = pcall(function() return c:FindFirstChildOfClass("Humanoid") end)
    if okH and hum then return false end
    return true
end

-- anchor part: PrimaryPart, then a "Walls" BasePart, then any BasePart (descendants)
local function pickPart(model)
    local ok, pp = pcall(function() return model.PrimaryPart end)
    if ok and pp then return pp end
    local okD, descs = pcall(function() return model:GetDescendants() end)
    if okD and descs then
        local fallback
        for _, d in ipairs(descs) do
            local okp, isp = pcall(function() return d:IsA("BasePart") end)
            if okp and isp == true then
                local okn, dn = pcall(function() return d.Name end)
                if okn and dn == "Walls" then return d end
                if not fallback then fallback = d end
            end
        end
        if fallback then return fallback end
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

-- ---------- collect airdrops ----------
local function collectDrops()
    local out = {}
    local ok, children = pcall(function() return Workspace:GetChildren() end)
    if ok and children then
        for _, c in ipairs(children) do
            if isAirdrop(c) then out[#out + 1] = c end
        end
    end
    return out
end

-- ---------- slow scan: membership, alerts, cache anchor part ----------
local function scan()
    local drops = collectDrops()
    local current = {}
    for _, m in ipairs(drops) do
        local id = keyOf(m)
        current[id] = true
        if not seen[id] then
            seen[id] = true
            if M.alertEnabled and notify then
                pcall(notify, "Airdrop spawned!", "Airdrop", 3)
            end
        end
        local set = pool[id]
        if not set then set = makeSet(); applyColor(set, BOX_COLOR); pool[id] = set end
        set.model = m
        if not partValid(set.part) then set.part = pickPart(m) end
    end

    for id, _ in pairs(seen) do
        if not current[id] then seen[id] = nil end
    end
    for id, set in pairs(pool) do
        if not current[id] then removeSet(set); pool[id] = nil end
    end
end

-- seed silently so existing airdrops don't spam the alert on enable
do
    for _, m in ipairs(collectDrops()) do seen[keyOf(m)] = true end
end

task.spawn(function()
    while M._loaded do
        scan()
        task.wait(0.4)
    end
end)

-- ---------- render: cheap per-frame, integer-rounded, anti-flicker grace ----------
local renderConn
renderConn = RS.RenderStepped:Connect(function()
    if not M._loaded or not M.enabled then
        hideAll()
        return
    end
    local lpos = getLocalPos()
    for _, set in pairs(pool) do
        local part = set.part
        local pos
        if partValid(part) then
            local ok, p = pcall(function() return part.Position end)
            if ok and p then pos = p end
        else
            set.part = nil
        end

        local drew = false
        if pos then
            local ok2, sp, on = pcall(WTS, pos)
            if ok2 and on and sp then
                local sx = floor(sp.X + 0.5)
                local sy = floor(sp.Y + 0.5)
                local sz = 44
                if lpos then
                    local d = (lpos - pos).Magnitude
                    sz = floor(clamp(2600 / (d > 1 and d or 1), 18, 70) + 0.5)
                    set.dist.Text = fmt("[%d studs]", floor(d))
                end
                local half = floor(sz / 2)
                local size = Vector2_new(sz, sz)
                local posv = Vector2_new(sx - half, sy - half)
                set.fill.Size = size; set.fill.Position = posv; set.fill.Visible = true
                set.box.Size = size; set.box.Position = posv; set.box.Visible = true
                set.name.Position = Vector2_new(sx, sy - half - 15); set.name.Visible = true
                if lpos then
                    set.dist.Position = Vector2_new(sx, sy + half + 3); set.dist.Visible = true
                else
                    set.dist.Visible = false
                end
                set.miss = 0
                drew = true
            end
        end

        if not drew then
            set.miss = (set.miss or 0) + 1
            if set.miss > 4 then hideSet(set) end
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

function M.SetColor(c)
    if typeof(c) ~= "Color3" then return end
    BOX_COLOR = c
    for _, set in pairs(pool) do applyColor(set, c) end
end

function M.Unload()
    M.enabled = false
    M.alertEnabled = false
    M._loaded = false
    if renderConn then pcall(function() renderConn:Disconnect() end); renderConn = nil end
    clearAll()
    seen = {}
end
