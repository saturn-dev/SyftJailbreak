if _G.SyftAirdropESP and _G.SyftAirdropESP._loaded then
    return
end

local Workspace = game:GetService("Workspace")

local M = {}
_G.SyftAirdropESP = M
M._loaded = true
M.enabled = false
M.alertEnabled = false
M._highlights = {}
M._dropFolder = nil
M._addedConn = nil
M._removedConn = nil
M._wsConn = nil

local AUDIO_URL = "https://github.com/saturn-dev/SyftJailbreak/raw/refs/heads/main/notification.mp3"
local BAR_COLOR = "#8B0000"
local FILL_COLOR = Color3.fromRGB(243, 139, 168)
local OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)

local function clearOne(child)
    local hl = M._highlights[child]
    if hl then
        pcall(function() hl:Destroy() end)
        M._highlights[child] = nil
    end
end

local function clearAll()
    for c, _ in pairs(M._highlights) do
        local hl = M._highlights[c]
        if hl then pcall(function() hl:Destroy() end) end
    end
    M._highlights = {}
end

local function addHighlight(child)
    if not child or not child.Parent then return end
    if M._highlights[child] then return end
    local ok, hl = pcall(function()
        local h = Instance.new("Highlight")
        h.Name = "SyftAirdropHL"
        h.FillColor = FILL_COLOR
        h.FillTransparency = 0.55
        h.OutlineColor = OUTLINE_COLOR
        h.OutlineTransparency = 0
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Adornee = child
        h.Parent = child
        return h
    end)
    if ok and hl then
        M._highlights[child] = hl
    end
end

local function refreshHighlights()
    clearAll()
    if not M.enabled then return end
    if not M._dropFolder or not M._dropFolder.Parent then return end
    for _, c in ipairs(M._dropFolder:GetChildren()) do
        addHighlight(c)
    end
end

local function disconnectFolder()
    if M._addedConn then pcall(function() M._addedConn:Disconnect() end); M._addedConn = nil end
    if M._removedConn then pcall(function() M._removedConn:Disconnect() end); M._removedConn = nil end
end

local function bindToDrop(folder)
    disconnectFolder()
    M._dropFolder = folder
    if not folder then return end

    M._addedConn = folder.ChildAdded:Connect(function(child)
        if M.alertEnabled and _G.alert then
            pcall(_G.alert, "Airdrop spawned!", "Airdrop", 3, BAR_COLOR, AUDIO_URL)
        end
        if M.enabled then
            wait(0.1)
            addHighlight(child)
        end
    end)

    M._removedConn = folder.ChildRemoved:Connect(function(child)
        clearOne(child)
    end)

    if M.enabled then refreshHighlights() end
end

if M._wsConn then pcall(function() M._wsConn:Disconnect() end) end
M._wsConn = Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Drop" and (not M._dropFolder or not M._dropFolder.Parent) then
        bindToDrop(child)
    end
end)

spawn(function()
    while M._loaded do
        local cur = Workspace:FindFirstChild("Drop")
        if cur and cur ~= M._dropFolder then
            bindToDrop(cur)
        elseif not cur and M._dropFolder then
            disconnectFolder()
            M._dropFolder = nil
            clearAll()
        end
        wait(1)
    end
end)

function M.SetEnabled(v)
    M.enabled = v == true
    if M.enabled then
        refreshHighlights()
    else
        clearAll()
    end
end

function M.SetAlertEnabled(v)
    M.alertEnabled = v == true
end

function M.Unload()
    M.enabled = false
    M.alertEnabled = false
    M._loaded = false
    clearAll()
    disconnectFolder()
    if M._wsConn then pcall(function() M._wsConn:Disconnect() end); M._wsConn = nil end
    M._dropFolder = nil
end
