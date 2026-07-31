local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

-- === GUI ===
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OMNI_AdoptMe"
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 400, 0, 500)
MainFrame.Position = UDim2.new(0.5, -200, 0.5, -250)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
MainFrame.BackgroundTransparency = 0.1
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 40)
Title.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
Title.Text = "OMNI ADOPT ME"
Title.TextColor3 = Color3.fromRGB(255, 50, 50)
Title.TextScaled = true
Title.Font = Enum.Font.GothamBold
Title.Parent = MainFrame

local function MakeButton(text, y, color, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 180, 0, 35)
    btn.Position = UDim2.new(0.5, -90, 0, y)
    btn.BackgroundColor3 = color or Color3.fromRGB(60, 60, 70)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextScaled = true
    btn.Font = Enum.Font.Gotham
    btn.Parent = MainFrame
    btn.MouseButton1Click:Connect(callback)
    return btn
end

local function MakeToggle(text, y, default, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 180, 0, 30)
    frame.Position = UDim2.new(0.5, -90, 0, y)
    frame.BackgroundTransparency = 1
    frame.Parent = MainFrame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 120, 1, 0)
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255,255,255)
    label.TextScaled = true
    label.Font = Enum.Font.Gotham
    label.BackgroundTransparency = 1
    label.Parent = frame

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 50, 1, 0)
    toggle.Position = UDim2.new(1, -55, 0, 0)
    toggle.BackgroundColor3 = default and Color3.fromRGB(0,200,0) or Color3.fromRGB(200,0,0)
    toggle.Text = default and "ON" or "OFF"
    toggle.TextColor3 = Color3.fromRGB(255,255,255)
    toggle.TextScaled = true
    toggle.Font = Enum.Font.Gotham
    toggle.Parent = frame

    local state = default
    toggle.MouseButton1Click:Connect(function()
        state = not state
        toggle.BackgroundColor3 = state and Color3.fromRGB(0,200,0) or Color3.fromRGB(200,0,0)
        toggle.Text = state and "ON" or "OFF"
        callback(state)
    end)
    return function() return state end
end

-- === VARIABLES ===
local Pets = {}
local FakeTradeActive = false
local SpawnerActive = false
local AutoFarmActive = false
local AutoCollectActive = false
local CurrentTarget = nil
local TradePartner = nil

-- === GET PETS ===
local function GetAllPets()
    local petList = {}
    local inventory = LocalPlayer:FindFirstChild("Inventory")
    if inventory then
        for _, child in pairs(inventory:GetChildren()) do
            if child:IsA("Tool") or child:IsA("Model") then
                table.insert(petList, child)
            end
        end
    end
    return petList
end

-- === FAKE TRADES ===
local function StartFakeTrade()
    if FakeTradeActive then
        -- Stop fake trade
        FakeTradeActive = false
        return
    end
    FakeTradeActive = true
    local target = CurrentTarget or LocalPlayer
    local pet = nil
    local pets = GetAllPets()
    if #pets > 0 then
        pet = pets[math.random(1, #pets)]
    end

    -- Simulate trade request UI
    local TradeGui = Instance.new("Frame")
    TradeGui.Size = UDim2.new(0, 300, 0, 200)
    TradeGui.Position = UDim2.new(0.5, -150, 0.5, -100)
    TradeGui.BackgroundColor3 = Color3.fromRGB(30,30,40)
    TradeGui.BorderSizePixel = 0
    TradeGui.Parent = ScreenGui

    local TradeLabel = Instance.new("TextLabel")
    TradeLabel.Size = UDim2.new(1, 0, 0, 40)
    TradeLabel.BackgroundColor3 = Color3.fromRGB(50,50,60)
    TradeLabel.Text = "FAKE TRADE ACTIVE"
    TradeLabel.TextColor3 = Color3.fromRGB(255,200,50)
    TradeLabel.TextScaled = true
    TradeLabel.Font = Enum.Font.GothamBold
    TradeLabel.Parent = TradeGui

    local PetDisplay = Instance.new("TextLabel")
    PetDisplay.Size = UDim2.new(1, 0, 0, 60)
    PetDisplay.Position = UDim2.new(0, 0, 0, 40)
    PetDisplay.Text = pet and pet.Name or "No Pet Selected"
    PetDisplay.TextColor3 = Color3.fromRGB(200,200,255)
    PetDisplay.TextScaled = true
    PetDisplay.Font = Enum.Font.Gotham
    PetDisplay.Parent = TradeGui

    local ConfirmBtn = Instance.new("TextButton")
    ConfirmBtn.Size = UDim2.new(0, 100, 0, 40)
    ConfirmBtn.Position = UDim2.new(0.5, -110, 1, -50)
    ConfirmBtn.BackgroundColor3 = Color3.fromRGB(0,180,0)
    ConfirmBtn.Text = "CONFIRM"
    ConfirmBtn.TextColor3 = Color3.fromRGB(255,255,255)
    ConfirmBtn.TextScaled = true
    ConfirmBtn.Font = Enum.Font.Gotham
    ConfirmBtn.Parent = TradeGui

    local CancelBtn = Instance.new("TextButton")
    CancelBtn.Size = UDim2.new(0, 100, 0, 40)
    CancelBtn.Position = UDim2.new(0.5, 10, 1, -50)
    CancelBtn.BackgroundColor3 = Color3.fromRGB(180,0,0)
    CancelBtn.Text = "CANCEL"
    CancelBtn.TextColor3 = Color3.fromRGB(255,255,255)
    CancelBtn.TextScaled = true
    CancelBtn.Font = Enum.Font.Gotham
    CancelBtn.Parent = TradeGui

    local tradeRunning = true
    ConfirmBtn.MouseButton1Click:Connect(function()
        if pet then
            -- Simulate trade completion
            local notify = Instance.new("TextLabel")
            notify.Size = UDim2.new(0, 200, 0, 30)
            notify.Position = UDim2.new(0.5, -100, 0, 10)
            notify.BackgroundColor3 = Color3.fromRGB(0,200,0)
            notify.Text = "TRADE COMPLETE! " .. pet.Name .. " SENT!"
            notify.TextColor3 = Color3.fromRGB(255,255,255)
            notify.TextScaled = true
            notify.Font = Enum.Font.Gotham
            notify.Parent = ScreenGui
            game:GetService("Debris"):AddItem(notify, 3)
        end
        TradeGui:Destroy()
        FakeTradeActive = false
        tradeRunning = false
    end)

    CancelBtn.MouseButton1Click:Connect(function()
        TradeGui:Destroy()
        FakeTradeActive = false
        tradeRunning = false
    end)

    -- Auto-destroy after 30s if no action
    game:GetService("Debris"):AddItem(TradeGui, 30)
    spawn(function()
        wait(30)
        FakeTradeActive = false
    end)
end

-- === SPAWNER (Pet Spawner) ===
local function SpawnPet()
    local petNames = {"Dog", "Cat", "Unicorn", "Dragon", "Turtle", "Kangaroo", "Owl", "Bat", "Bee", "Cow", "Elephant", "Giraffe", "Lion", "Monkey", "Panda", "Penguin", "Rabbit", "Reindeer", "Shark", "Sloth", "Snake", "Tiger", "Wolf", "Zombie"}
    local petName = petNames[math.random(1, #petNames)]
    local petModel = Instance.new("Model")
    petModel.Name = petName .. "_SPAWNED"
    petModel.Parent = Workspace

    -- Create a basic part as the pet
    local part = Instance.new("Part")
    part.Size = Vector3.new(2, 2, 2)
    part.Position = LocalPlayer.Character and LocalPlayer.Character.HumanoidRootPart.Position + Vector3.new(0, 3, 5) or Vector3.new(0, 10, 0)
    part.BrickColor = BrickColor.random()
    part.Material = Enum.Material.Neon
    part.Anchored = true
    part.Parent = petModel

    local nameTag = Instance.new("BillboardGui")
    nameTag.Size = UDim2.new(0, 200, 0, 50)
    nameTag.Adornee = part
    nameTag.Parent = petModel

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = petName .. " (SPAWNED)"
    label.TextColor3 = Color3.fromRGB(255, 255, 100)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = nameTag

    -- Add to fake inventory
    local inventory = LocalPlayer:FindFirstChild("Inventory")
    if not inventory then
        inventory = Instance.new("Folder")
        inventory.Name = "Inventory"
        inventory.Parent = LocalPlayer
    end
    local clone = part:Clone()
    clone.Name = petName
    clone.Parent = inventory

    -- Notification
    local notify = Instance.new("TextLabel")
    notify.Size = UDim2.new(0, 300, 0, 30)
    notify.Position = UDim2.new(0.5, -150, 0, 50)
    notify.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
    notify.Text = "SPAWNED: " .. petName
    notify.TextColor3 = Color3.fromRGB(255, 255, 255)
    notify.TextScaled = true
    notify.Font = Enum.Font.Gotham
    notify.Parent = ScreenGui
    game:GetService("Debris"):AddItem(notify, 3)
end

-- === AUTO FARM (Collect cash/items) ===
local function AutoFarm()
    if AutoFarmActive then
        AutoFarmActive = false
        return
    end
    AutoFarmActive = true

    spawn(function()
        while AutoFarmActive do
            local character = LocalPlayer.Character
            if not character or not character.HumanoidRootPart then
                wait(1)
                continue
            end
            local hrp = character.HumanoidRootPart

            -- Find nearest cash/collectible
            local nearest = nil
            local dist = math.huge
            for _, obj in pairs(Workspace:GetDescendants()) do
                if obj:IsA("Part") and obj.Name:lower():find("cash") or obj.Name:lower():find("money") or obj.Name:lower():find("collect") then
                    if obj.Parent and obj.Parent:FindFirstChild("Humanoid") == nil then
                        local d = (hrp.Position - obj.Position).Magnitude
                        if d < dist then
                            dist = d
                            nearest = obj
                        end
                    end
                end
            end

            if nearest then
                hrp.CFrame = CFrame.new(nearest.Position + Vector3.new(0, 2, 0))
                wait(0.5)
                -- Simulate collect
                nearest:Destroy()
            else
                -- Move randomly
                hrp.CFrame = hrp.CFrame + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))
            end
            wait(0.5)
        end
    end)
end

-- === AUTO COLLECT (Gifts/eggs) ===
local function AutoCollect()
    if AutoCollectActive then
        AutoCollectActive = false
        return
    end
    AutoCollectActive = true

    spawn(function()
        while AutoCollectActive do
            local character = LocalPlayer.Character
            if not character or not character.HumanoidRootPart then
                wait(1)
                continue
            end
            local hrp = character.HumanoidRootPart

            -- Find eggs/gifts
            for _, obj in pairs(Workspace:GetDescendants()) do
                if obj:IsA("Part") and (obj.Name:lower():find("egg") or obj.Name:lower():find("gift") or obj.Name:lower():find("present")) then
                    local d = (hrp.Position - obj.Position).Magnitude
                    if d < 50 then
                        hrp.CFrame = CFrame.new(obj.Position + Vector3.new(0, 2, 0))
                        wait(0.3)
                        obj:Destroy()
                        local notify = Instance.new("TextLabel")
                        notify.Size = UDim2.new(0, 200, 0, 30)
                        notify.Position = UDim2.new(0.5, -100, 0, 80)
                        notify.BackgroundColor3 = Color3.fromRGB(200, 100, 0)
                        notify.Text = "COLLECTED: " .. obj.Name
                        notify.TextColor3 = Color3.fromRGB(255, 255, 255)
                        notify.TextScaled = true
                        notify.Font = Enum.Font.Gotham
                        notify.Parent = ScreenGui
                        game:GetService("Debris"):AddItem(notify, 2)
                        break
                    end
                end
            end
            wait(1)
        end
    end)
end

-- === TP TO PLAYER ===
local function TeleportToPlayer(playerName)
    for _, player in pairs(Players:GetPlayers()) do
        if player.Name:lower():find(playerName:lower()) or player.DisplayName:lower():find(playerName:lower()) then
            local char = player.Character
            if char and char.HumanoidRootPart then
                local hrp = LocalPlayer.Character and LocalPlayer.Character.HumanoidRootPart
                if hrp then
                    hrp.CFrame = CFrame.new(char.HumanoidRootPart.Position + Vector3.new(0, 3, 2))
                end
                CurrentTarget = player
                return true
            end
        end
    end
    return false
end

-- === BUILD UI ===
MakeButton("FAKE TRADE", 50, Color3.fromRGB(200, 100, 0), function()
    StartFakeTrade()
end)

MakeButton("SPAWN PET", 95, Color3.fromRGB(0, 100, 200), function()
    SpawnPet()
end)

MakeButton("SPAWN MASS PETS", 140, Color3.fromRGB(150, 0, 200), function()
    for i = 1, 5 do
        SpawnPet()
        wait(0.3)
    end
end)

MakeToggle("AUTO FARM", 185, false, function(state)
    AutoFarmActive = state
    if state then AutoFarm() end
end)

MakeToggle("AUTO COLLECT", 225, false, function(state)
    AutoCollectActive = state
    if state then AutoCollect() end
end)

-- TP Input
local TpFrame = Instance.new("Frame")
TpFrame.Size = UDim2.new(0, 180, 0, 35)
TpFrame.Position = UDim2.new(0.5, -90, 0, 265)
TpFrame.BackgroundTransparency = 1
TpFrame.Parent = MainFrame

local TpInput = Instance.new("TextBox")
TpInput.Size = UDim2.new(0, 120, 1, 0)
TpInput.PlaceholderText = "Player Name"
TpInput.TextColor3 = Color3.fromRGB(255, 255, 255)
TpInput.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
TpInput.TextScaled = true
TpInput.Font = Enum.Font.Gotham
TpInput.Parent = TpFrame

local TpBtn = Instance.new("TextButton")
TpBtn.Size = UDim2.new(0, 50, 1, 0)
TpBtn.Position = UDim2.new(1, -55, 0, 0)
TpBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
TpBtn.Text = "TP"
TpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TpBtn.TextScaled = true
TpBtn.Font = Enum.Font.Gotham
TpBtn.Parent = TpFrame
TpBtn.MouseButton1Click:Connect(function()
    if TpInput.Text ~= "" then
        TeleportToPlayer(TpInput.Text)
    end
end)

-- === KEYBINDS ===
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.F then
        StartFakeTrade()
    elseif input.KeyCode == Enum.KeyCode.G then
        SpawnPet()
    elseif input.KeyCode == Enum.KeyCode.T then
        -- Toggle Auto Farm
        AutoFarmActive = not AutoFarmActive
        if AutoFarmActive then AutoFarm() end
    elseif input.KeyCode == Enum.KeyCode.R then
        -- Reset character
        LocalPlayer.Character = nil
        LocalPlayer:LoadCharacter()
    end
end)

-- === INFINITE YIELD PROTECTION ===
local function AntiAfk()
    local vu = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        vu:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        wait(1)
        vu:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    end)
end
AntiAfk()

-- === ADMIN/DEV CONSOLE ===
print("OMNI Adopt Me Script Loaded Successfully")
print("Keybinds: F=Fake Trade, G=Spawn Pet, T=Toggle Auto Farm, R=Reset")
print("OMNI ONLINE - All features active")

-- Keep alive
while wait(60) do
    -- Heartbeat
end
