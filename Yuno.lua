
getgenv().DemoHub = getgenv().DemoHub or {}

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService    = game:GetService("RunService")
local player        = Players.LocalPlayer

-- ================= CONFIG =================
local CONFIG = {
    ThemeColor  = Color3.fromRGB(108, 75, 171),
    PanelSize   = UDim2.new(0, 220, 0, 480),
    SpawnPart   = true,
    SpawnModel  = false,
}

-- ================= UI =================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DemoHub"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = CONFIG.PanelSize
mainFrame.Position = UDim2.new(0.5, -110, 0.5, -240)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

-- Title
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 24)
title.BackgroundTransparency = 1
title.Text = "Demo Hub"
title.Font = Enum.Font.FredokaOne
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(240, 240, 255)
title.Parent = mainFrame

-- Drag (whole frame)
local dragging, dragStart, startPos
mainFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local delta = input.Position - dragStart
    mainFrame.Position = UDim2.new(
        startPos.X.Scale, startPos.X.Offset + delta.X,
        startPos.Y.Scale, startPos.Y.Offset + delta.Y
    )
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

-- ================= TABS =================
local tabs = { "Spawner", "Settings" }
local tabButtons, tabFrames, currentTab = {}, {}, "Spawner"

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(0.9, 0, 0, 22)
tabBar.Position = UDim2.new(0.05, 0, 0, 26)
tabBar.BackgroundTransparency = 1
tabBar.Parent = mainFrame

for i, name in ipairs(tabs) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1 / #tabs, -2, 1, 0)
    btn.Position = UDim2.new((i - 1) / #tabs, 0, 0, 0)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    btn.Text = name
    btn.Font = Enum.Font.FredokaOne
    btn.TextSize = 10
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Parent = tabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0.9, 0, 1, -54)
    frame.Position = UDim2.new(0.05, 0, 0, 54)
    frame.BackgroundTransparency = 1
    frame.Visible = (name == currentTab)
    frame.Parent = mainFrame

    tabButtons[name] = btn
    tabFrames[name] = frame

    btn.MouseButton1Click:Connect(function()
        currentTab = name
        for n, b in pairs(tabButtons) do
            b.BackgroundColor3 = (n == name) and Color3.fromRGB(55, 45, 75) or Color3.fromRGB(40, 40, 50)
        end
        for n, f in pairs(tabFrames) do
            f.Visible = (n == name)
        end
    end)
end

-- ================= HELPERS =================
local function makeButton(parent, text, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 24)
    btn.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
    btn.Text = text
    btn.Font = Enum.Font.FredokaOne
    btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.LayoutOrder = order
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = CONFIG.ThemeColor
    stroke.Thickness = 1.5
    stroke.Parent = btn
    return btn
end

local function makeToggle(parent, label, order, startOn)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 22)
    row.BackgroundTransparency = 1
    row.LayoutOrder = order
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -50, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.Font = Enum.Font.SourceSansSemibold
    lbl.TextSize = 11
    lbl.TextColor3 = Color3.fromRGB(200, 200, 210)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 44, 1, 0)
    btn.Position = UDim2.new(1, -44, 0, 0)
    btn.BackgroundColor3 = startOn and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(60, 30, 30)
    btn.Text = startOn and "ON" or "OFF"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.TextColor3 = startOn and Color3.fromRGB(80, 255, 130) or Color3.fromRGB(255, 120, 120)
    btn.Parent = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    return btn
end

-- ================= SPAWNER TAB =================
local spawnFrame = tabFrames["Spawner"]
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 5)
layout.Parent = spawnFrame

local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, 0, 0, 26)
nameBox.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
nameBox.PlaceholderText = "Model / part name..."
nameBox.Font = Enum.Font.SourceSans
nameBox.TextSize = 12
nameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
nameBox.PlaceholderColor3 = Color3.fromRGB(90, 90, 110)
nameBox.ClearTextOnFocus = false
nameBox.LayoutOrder = 1
nameBox.Parent = spawnFrame
Instance.new("UICorner", nameBox).CornerRadius = UDim.new(0, 4)

local function getSpawnCFrame()
    local char = player.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        return char.HumanoidRootPart.CFrame * CFrame.new(0, 3, -5)
    end
    return CFrame.new(0, 10, 0)
end

local function spawnPart()
    local part = Instance.new("Part")
    part.Name = "Spawned_" .. os.clock()
    part.Size = Vector3.new(4, 1, 4)
    part.Anchored = true
    part.CFrame = getSpawnCFrame()
    part.Color = CONFIG.ThemeColor
    part.Material = Enum.Material.Neon
    part.Parent = workspace
    return part
end

local function spawnModel(name)
    local src = game:GetService("ReplicatedStorage"):FindFirstChild(name)
    if not src then return nil end
    local clone = src:Clone()
    local primary = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
    if primary then
        clone:PivotTo(getSpawnCFrame())
    end
    clone.Parent = workspace
    return clone
end

local spawnPartBtn = makeButton(spawnFrame, "Spawn Part", 2)
spawnPartBtn.MouseButton1Click:Connect(function()
    spawnPart()
end)

local spawnModelBtn = makeButton(spawnFrame, "Spawn Model", 3)
spawnModelBtn.MouseButton1Click:Connect(function()
    local name = nameBox.Text
    if name == "" then return end
    local ok, result = pcall(spawnModel, name)
    if not result then
        warn("Model not found in ReplicatedStorage: " .. name)
    end
end)

local clearBtn = makeButton(spawnFrame, "Clear Spawned", 4)
clearBtn.MouseButton1Click:Connect(function()
    for _, v in ipairs(workspace:GetChildren()) do
        if v.Name:find("^Spawned_") then
            v:Destroy()
        end
    end
end)

-- ================= SETTINGS TAB =================
local settingsFrame = tabFrames["Settings"]
local settingsLayout = Instance.new("UIListLayout")
settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
settingsLayout.Padding = UDim.new(0, 5)
settingsLayout.Parent = settingsFrame

makeToggle(settingsFrame, "Spawn Part", 1, CONFIG.SpawnPart).MouseButton1Click:Connect(function(btn)
    CONFIG.SpawnPart = not CONFIG.SpawnPart
    btn.Text = CONFIG.SpawnPart and "ON" or "OFF"
    btn.BackgroundColor3 = CONFIG.SpawnPart and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(60, 30, 30)
    btn.TextColor3 = CONFIG.SpawnPart and Color3.fromRGB(80, 255, 130) or Color3.fromRGB(255, 120, 120)
end)

-- Keep hub visible on respawn
player.CharacterAdded:Connect(function()
    task.wait(2)
    screenGui.Parent = player:WaitForChild("PlayerGui")
end)
