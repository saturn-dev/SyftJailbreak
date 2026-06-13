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

local DEFAULT_COLOR = Color3.fromRGB(243, 139, 168)
local NAME_COLOR = Color3.fromRGB(255, 255, 255)
local DIST_COLOR = Color3.fromRGB(245, 194, 231)

local FONT = Drawing.Fonts.System
pcall(function() FONT = Drawing.Fonts.SystemBold end)

-- pool[model] = { box, name, dist, part, color }
-- part  = cached representative BasePart (so we don't search every frame)
-- color = cached Post .Color (resolved in the slow scan loop)
local pool = {}
local seen = {}   -- [model] = true  (alert de-dup, one per airdrop)

-- ---------- drawing helpers ----------
local function makeSet()
    local box = Drawing_new("Square")
    box.Thickness = 2
    box.Filled = false
    box.Color = DEFAULT_COLOR
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

    return { box = box, name = name, dist = dist, part = nil, color = nil }
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
    for m, set in pairs(pool) do removeSet(set); pool[m] = nil end
end

-- ---------- helpers ----------
local function isModel(obj)
    local ok, r = pcall(function() return obj:IsA("Model") end)
    return ok and r == true
end

-- representative part to anchor the box on (PrimaryPart > a Post > any BasePart)
local function pickPart(model)
    local ok, pp = pcall(function() return model.PrimaryPart end)
    if ok and pp then return pp end
    local post = model:FindFirstChild("Post", true)
    if post then
        local okp, isp = pcall(function() return post:IsA("BasePart") end)
        if okp and isp == true then return post end
    end
    local bp = model:FindFirstChildWhichIsA("BasePart")
    if bp then return bp end
    return nil
end

-- read .Color off a "Post" part (nil-safe — never index a nil part)
local function pickPostColor(model)
    local posts = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d and d.Name == "Post" then
            local ok, isp = pcall(function() return d:IsA("BasePart") end)
            if ok and isp == true then posts[#posts + 1] = d end
        end
    end
    local post = posts[1]
    if not post then return nil end
    local okc, col = pcall(function() return post.Color end)
    if okc and col and typeof(col) == "Color3" then return col end
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

-- ---------- collect airdrop MODELS only ----------
local function collectDrops(out)
    local container = Workspace:FindFirstChild("Drop")
    if container then
        local anyModel = false
        for _, c in ipairs(container:GetChildren()) do
            if isModel(c) then out[c] = true; anyModel = true end
        end
        -- the container itself is the airdrop model if it has no model children
        if not anyModel and isModel(container) then out[container] = true end
    end
    -- support more than one airdrop spawned directly in Workspace as "Drop"
    for _, c in ipairs(Workspace:GetChildren()) do
        if c ~= container and c.Name == "Drop" and isModel(c) then out[c] = true end
    end
    return out
end

-- ---------- slow scan: membership, alerts, cache part + color ----------
local function scan()
    local current = {}
    collectDrops(current)

    for m, _ in pairs(current) do
        if not seen[m] then
            seen[m] = true
            if M.alertEnabled and notify then
                pcall(notify, "Airdrop spawned!", "Airdrop", 3)
            end
        end
        local set = pool[m]
        if not set then set = makeSet(); pool[m] = set end
        -- refresh cached anchor part + post color (cheap because only 2Hz)
        if not set.part or not set.part.Parent then set.part = pickPart(m) end
        set.color = pickPostColor(m) or DEFAULT_COLOR
        set.box.Color = set.color
        set.dist.Color = set.color
    end

    for m, _ in pairs(seen) do
        if not current[m] then seen[m] = nil end
    end
    for m, set in pairs(pool) do
        if not current[m] then removeSet(set); pool[m] = nil end
    end
end

-- seed silently so existing airdrops don't spam the alert on enable
do
    local current = {}
    collectDrops(current)
    for m, _ in pairs(current) do seen[m] = true end
end

task.spawn(function()
    while M._loaded do
        scan()
        task.wait(0.4)
    end
end)

-- ---------- render: cheap per-frame update (smooth, no flicker) ----------
local renderConn
renderConn = RS.RenderStepped:Connect(function()
    if not M._loaded or not M.enabled then
        hideAll()
        return
    end
    local lpos = getLocalPos()
    for m, set in pairs(pool) do
        local part = set.part
        if part and part.Parent then
            local ok, pos = pcall(function() return part.Position end)
            if ok and pos then
                local ok2, sp, on = pcall(WTS, pos)
                if ok2 and on and sp then
                    local sx = floor(sp.X + 0.5)
                    local sy = floor(sp.Y + 0.5)
                    local sz = 80
                    if lpos then
                        local d = (lpos - pos).Magnitude
                        sz = floor(clamp(4500 / (d > 1 and d or 1), 28, 150) + 0.5)
                        set.dist.Text = fmt("[%d studs]", floor(d))
                        set.dist.Position = Vector2_new(sx, sy + floor(sz / 2) + 4)
                        set.dist.Visible = true
                    else
                        set.dist.Visible = false
                    end
                    local half = floor(sz / 2)
                    set.box.Size = Vector2_new(sz, sz)
                    set.box.Position = Vector2_new(sx - half, sy - half)
                    set.box.Visible = true
                    set.name.Text = (m.Name and m.Name ~= "") and m.Name or "AIRDROP"
                    set.name.Position = Vector2_new(sx, sy - half - 16)
                    set.name.Visible = true
                else
                    hideSet(set)
                end
            else
                hideSet(set)
            end
        else
            -- anchor part gone; drop it from the cache (scan re-resolves)
            set.part = nil
            hideSet(set)
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
end
