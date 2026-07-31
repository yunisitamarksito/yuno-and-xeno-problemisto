
-- =====================================================================
-- OMNI HUB CORE
-- =====================================================================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")

-- =====================================================================
-- IDENTITY FIX (Required for Xeno PC)
-- =====================================================================
local function setIdentity(level)
    pcall(function()
        if setthreadidentity then
            setthreadidentity(level)
        elseif setidentity then
            setidentity(level)
        end
    end)
end
setIdentity(2)

-- =====================================================================
-- LOAD MODULES SAFELY
-- =====================================================================
local Fsys = ReplicatedStorage:WaitForChild("Fsys")
local function load(name)
    return Fsys.load(name)
end

local UIManager = load("UIManager")
local ClientData = load("ClientData")
local TableUtil = load("TableUtil")
local InventoryDB = load("InventoryDB")
local KindDB = load("KindDB")
local RouterClient = load("RouterClient")

-- Wait for UI
if UIManager.wait_for_initialization then
    UIManager:wait_for_initialization()
else
    task.wait(2)
end

local TradeApp = UIManager.apps.TradeApp
local BackpackApp = UIManager.apps.BackpackApp
local DialogApp = UIManager.apps.DialogApp
local HintApp = UIManager.apps.HintApp
local TradeHistoryApp = UIManager.apps.TradeHistoryApp

if not TradeApp then
    warn("TradeApp not found")
    return
end

-- =====================================================================
-- HIGH TIER PETS
-- =====================================================================
local HIGH_TIER_PETS = {
    "Bat Dragon", "Shadow Dragon", "Giraffe", "Frost Dragon",
    "Owl", "Parrot", "Balloon Unicorn", "Crow",
    "African Wild Dog", "Giant Panda", "HaeTae", "Cryptid",
    "Evil Unicorn", "Blazing Lion", "Hedgehog", "Orchid Butterfly",
    "Diamond Butterfly", "Dalmatian", "Arctic Reindeer", "Mini Pig",
    "Jekyll Hydra", "Hot Doggo", "Mermicorn", "Pelican",
    "Cow", "Strawberry Shortcake Bat Dragon", "Goose",
    "Chocolate Chip Bat Dragon", "Cabbit", "Turtle",
    "Peppermint Penguin", "Monkey King", "Undead Jousting Horse",
    "Flamingo", "Kangaroo",
}

-- =====================================================================
-- CONFIG
-- =====================================================================
local CONFIG = {
    PARTNER_NAME = "Player123",
    PARTNER_USER_ID = 0,
    AUTO_ACCEPT_DELAY = 2,
    AUTO_CONFIRM_DELAY = 1.5,
    SPECTATOR_COUNT = 0,
    AUTO_PARTNER = true,
    NEGOTIATION_LOCK = 5,
    CONFIRMATION_LOCK_PER_ITEM = 3,
    FRIEND_PARTNER = true,
}

-- =====================================================================
-- MOCK STATE
-- =====================================================================
local mockState = {
    active = false,
    trade = nil,
    isAddingItem = false,
    partnerActionPending = false,
    tradeCompleting = false,
    scamWarningShown = true,
    originalFunctions = {},
    tradeHistory = {},
    addedTradeIds = {},
    blockedTradeRequests = {},
    pendingTradeRequest = false,
    canShowTradeRequest = true,
    tradeRequestBlocked = false,
    isMockTradeDialog = false,
}

-- =====================================================================
-- FAKE PARTNER
-- =====================================================================
local mockPartner
local function createMockPartner()
    mockPartner = setmetatable({
        Name = CONFIG.PARTNER_NAME,
        DisplayName = CONFIG.PARTNER_NAME,
        UserId = CONFIG.PARTNER_USER_ID,
        ClassName = "Player",
        AccountAge = 365,
        MembershipType = Enum.MembershipType.None,
        Neutral = true,
        TeamColor = BrickColor.new("White"),
        CharacterAdded = Instance.new("BindableEvent"),
        CharacterRemoving = Instance.new("BindableEvent"),
    }, {
        __index = function(t, k)
            if k == "Parent" then return Players end
            if k == "IsA" then return function(_, c) return c == "Player" or c == "Instance" end end
            if k == "GetAttribute" then return function() return nil end end
            if k == "FindFirstChild" then return function() return nil end end
            if k == "WaitForChild" then return function() return nil end end
            return rawget(t, k)
        end,
        __tostring = function() return CONFIG.PARTNER_NAME end,
        __eq = function(a, b)
            if type(b) == "table" then return rawget(a, "UserId") == rawget(b, "UserId") end
            local ok, uid = pcall(function() return b.UserId end)
            return ok and uid and rawget(a, "UserId") == uid or false
        end,
    })
    return mockPartner
end
createMockPartner()

local function updatePartnerFromUsername(username)
    local ok, uid = pcall(function() return Players:GetUserIdFromNameAsync(username) end)
    if ok and uid then
        CONFIG.PARTNER_USER_ID = uid
        CONFIG.PARTNER_NAME = username
        createMockPartner()
        return true
    end
    return false
end

-- =====================================================================
-- MOCK TRADE FACTORY
-- =====================================================================
local function createMockTrade()
    return {
        trade_id = "MOCK_" .. tick(),
        sender = Players.LocalPlayer,
        recipient = mockPartner,
        sender_offer = { items = {}, player_name = Players.LocalPlayer.Name, negotiated = false, confirmed = false },
        recipient_offer = { items = {}, player_name = CONFIG.PARTNER_NAME, negotiated = false, confirmed = false },
        current_stage = "negotiation",
        offer_version = 1,
        sender_has_trade_license = true,
        recipient_has_trade_license = true,
        busy_indicators = {},
        subscriber_count = CONFIG.SPECTATOR_COUNT,
    }
end

-- =====================================================================
-- TRADE HISTORY
-- =====================================================================
local function createTradeHistoryRecord(trade)
    return {
        trade_id = trade.trade_id,
        timestamp = os.time(),
        sender_user_id = Players.LocalPlayer.UserId,
        sender_name = Players.LocalPlayer.Name,
        sender_items = TableUtil.deep_copy(trade.sender_offer.items),
        recipient_user_id = trade.recipient.UserId,
        recipient_name = CONFIG.PARTNER_NAME,
        recipient_items = TableUtil.deep_copy(trade.recipient_offer.items),
        reported = false,
        reverted = nil,
    }
end

local function appendToTradeHistory(record)
    if mockState.addedTradeIds[record.trade_id] then return end
    mockState.addedTradeIds[record.trade_id] = true
    table.insert(mockState.tradeHistory, record)
end

-- =====================================================================
-- BUSY INDICATORS
-- =====================================================================
local function update_busy_indicators(val)
    pcall(function()
        local partnerUserId = tostring(CONFIG.PARTNER_USER_ID)
        mockState.trade.busy_indicators[partnerUserId] = val
        TradeApp.partner_negotiation_offer_pane:display_busy(val)
    end)
end

-- =====================================================================
-- ADD PET TO PARTNER OFFER
-- =====================================================================
local function generateRandomFlags()
    local roll = math.random(1, 10)
    if roll <= 2 then
        return { F = false, R = false, N = false, M = false }
    elseif roll <= 4 then
        return { F = true, R = false, N = false, M = false }
    elseif roll <= 6 then
        return { F = true, R = true, N = false, M = false }
    elseif roll <= 8 then
        return { F = true, R = true, N = true, M = false }
    else
        return { F = true, R = true, N = false, M = true }
    end
end

local function getRandomAge(flags)
    if flags.M or flags.N then
        local ages = {1, 1, 2, 2, 3, 4, 5, 6}
        return ages[math.random(1, #ages)]
    else
        local ages = {1, 2, 3, 4, 5, 6, 6, 6}
        return ages[math.random(1, #ages)]
    end
end

local function addPetToPartnerOffer(petName, flags)
    if not mockState.active or not mockState.trade then return false end
    if mockState.trade.current_stage == "confirmation" then return false end
    if #mockState.trade.recipient_offer.items >= 18 then return false end

    update_busy_indicators({ picking = true })
    task.wait(0.5)

    if not mockState.active or not mockState.trade then
        update_busy_indicators({ picking = false })
        return false
    end

    local petFlags = flags or generateRandomFlags()
    local age = getRandomAge(petFlags)

    for catName, catTable in pairs(InventoryDB) do
        if catName == "pets" then
            for id, item in pairs(catTable) do
                if item.name == petName then
                    local petItem = {
                        category = "pets",
                        kind = id,
                        unique = HttpService:GenerateGUID(),
                        properties = {
                            flyable = petFlags.F,
                            rideable = petFlags.R,
                            neon = petFlags.N,
                            mega_neon = petFlags.M,
                            age = age,
                        }
                    }
                    table.insert(mockState.trade.recipient_offer.items, petItem)
                    mockState.trade.sender_offer.negotiated = false
                    mockState.trade.recipient_offer.negotiated = false

                    if mockState.trade.current_stage == "confirmation" then
                        mockState.trade.current_stage = "negotiation"
                        mockState.trade.sender_offer.confirmed = false
                        mockState.trade.recipient_offer.confirmed = false
                    end

                    mockState.trade.offer_version = mockState.trade.offer_version + 1
                    TradeApp:_overwrite_local_trade_state(mockState.trade)
                    pcall(function()
                        if TradeApp._lock_trade_for_appropriate_time then
                            TradeApp:_lock_trade_for_appropriate_time()
                        end
                    end)
                    pcall(function()
                        if TradeApp._render_message_in_trade_chat then
                            TradeApp:_render_message_in_trade_chat(nil, CONFIG.PARTNER_NAME .. " added " .. petName .. ".", true)
                        end
                    end)
                    update_busy_indicators({ picking = false })
                    return true
                end
            end
        end
    end
    update_busy_indicators({ picking = false })
    return false
end

-- =====================================================================
-- PARTNER AUTO ACTION
-- =====================================================================
local function partnerAutoAction()
    if not mockState.active or not mockState.trade or mockState.partnerActionPending then return end
    mockState.partnerActionPending = true

    while TradeApp.lock_countdown and TradeApp.lock_countdown.is_going and TradeApp.lock_countdown:is_going() do
        task.wait(0.1)
    end

    if mockState.trade and mockState.trade.current_stage == "negotiation" then
        task.wait(CONFIG.AUTO_ACCEPT_DELAY)
        if mockState.active and mockState.trade then
            mockState.trade.recipient_offer.negotiated = true
            if mockState.trade.sender_offer.negotiated then
                mockState.trade.current_stage = "confirmation"
                mockState.trade.offer_version = mockState.trade.offer_version + 1
                TradeApp:_overwrite_local_trade_state(mockState.trade)
                pcall(function()
                    if TradeApp._evaluate_trade_fairness then
                        TradeApp:_evaluate_trade_fairness()
                    end
                end)
                pcall(function()
                    if TradeApp._lock_trade_for_appropriate_time then
                        TradeApp:_lock_trade_for_appropriate_time()
                    end
                end)
            else
                mockState.trade.offer_version = mockState.trade.offer_version + 1
                TradeApp:_overwrite_local_trade_state(mockState.trade)
            end
        end
    elseif mockState.trade and mockState.trade.current_stage == "confirmation" then
        task.wait(CONFIG.AUTO_CONFIRM_DELAY)
        if mockState.active and mockState.trade then
            mockState.trade.recipient_offer.confirmed = true
            mockState.trade.offer_version = mockState.trade.offer_version + 1
            TradeApp:_overwrite_local_trade_state(mockState.trade)

            if mockState.trade.sender_offer.confirmed and not mockState.tradeCompleting then
                mockState.tradeCompleting = true
                task.wait(3)
                local record = createTradeHistoryRecord(mockState.trade)
                appendToTradeHistory(record)

                local receivedItems = {}
                for _, item in ipairs(mockState.trade.recipient_offer.items) do
                    table.insert(receivedItems, {
                        kind = item.kind or item.id,
                        properties = table.clone(item.properties or {})
                    })
                end

                task.spawn(function()
                    setIdentity(2)
                    local inv = ClientData.get("inventory")
                    setIdentity(8)
                    if inv and inv.pets then
                        for _, item in ipairs(receivedItems) do
                            local kindKey = item.kind
                            local uid = HttpService:GenerateGUID(false)
                            local itemData = {
                                unique = uid,
                                category = "pets",
                                id = kindKey,
                                kind = kindKey,
                                newness_order = math.huge,
                                properties = item.properties,
                                _source = "mock_trade_gui",
                            }
                            setIdentity(2)
                            local inv2 = ClientData.get("inventory")
                            if inv2 and inv2.pets then
                                inv2.pets[uid] = itemData
                            end
                            setIdentity(8)
                        end
                    end
                    pcall(function() UIManager.apps.BackpackApp:refresh_rendered_items() end)
                end)

                mockState.active = false
                mockState.trade = nil
                mockState.tradeCompleting = false
                UIManager.set_app_visibility("TradeApp", false)
                if HintApp then
                    HintApp:hint({ text = "The trade was successful!", length = 5, overridable = true })
                end
            end
        end
    end
    mockState.partnerActionPending = false
end

-- =====================================================================
-- TRADE START
-- =====================================================================
local function startMockTradeDirectly()
    if mockState.active then return end

    pcall(function()
        mockState.active = false
        mockState.trade = nil
        mockState.isAddingItem = false
        mockState.partnerActionPending = false
        mockState.tradeCompleting = false
        mockState.scamWarningShown = true
        mockState.tradeRequestBlocked = true
        mockState.blockedTradeRequests = {}

        mockPartner = createMockPartner()
        mockState.trade = createMockTrade()
        mockState.active = true

        pcall(function() UIManager.set_app_visibility("TradeApp", false) end)
        task.wait(0.02)
        pcall(function() TradeApp:_overwrite_local_trade_state(mockState.trade) end)
        pcall(function() UIManager.set_app_visibility("TradeApp", true) end)
        pcall(function()
            if TradeApp._show_intro_message then
                TradeApp:_show_intro_message()
            end
        end)
        task.wait(0.02)
        pcall(function()
            if TradeApp.refresh_all then
                TradeApp:refresh_all()
            end
        end)
    end)
end

-- =====================================================================
-- PARTNER CONTROLS
-- =====================================================================
local function doPartnerAccept()
    if not mockState.active or not mockState.trade then return end

    if mockState.trade.current_stage == "negotiation" then
        mockState.trade.recipient_offer.negotiated = true
        if mockState.trade.sender_offer.negotiated then
            mockState.trade.current_stage = "confirmation"
            pcall(function()
                if TradeApp._evaluate_trade_fairness then
                    TradeApp:_evaluate_trade_fairness()
                end
            end)
            pcall(function()
                if TradeApp._lock_trade_for_appropriate_time then
                    TradeApp:_lock_trade_for_appropriate_time()
                end
            end)
        end
        mockState.trade.offer_version = mockState.trade.offer_version + 1
        TradeApp:_overwrite_local_trade_state(mockState.trade)
    elseif mockState.trade.current_stage == "confirmation" then
        mockState.trade.recipient_offer.confirmed = true
        mockState.trade.offer_version = mockState.trade.offer_version + 1
        TradeApp:_overwrite_local_trade_state(mockState.trade)
        if mockState.trade.sender_offer.confirmed and not mockState.tradeCompleting then
            task.spawn(partnerAutoAction)
        end
    end
end

local function doPartnerUnaccept()
    if not mockState.active or not mockState.trade then return end

    if mockState.trade.current_stage == "confirmation" then
        if mockState.tradeCompleting or
           (mockState.trade.sender_offer.confirmed and mockState.trade.recipient_offer.confirmed) then
            return
        end
        mockState.trade.recipient_offer.confirmed = false
        mockState.trade.sender_offer.confirmed = false
        mockState.partnerActionPending = false
        mockState.tradeCompleting = false
    else
        mockState.trade.recipient_offer.negotiated = false
    end
    mockState.trade.offer_version = mockState.trade.offer_version + 1
    TradeApp:_overwrite_local_trade_state(mockState.trade)
end

-- =====================================================================
-- BLOCK PLAYER
-- =====================================================================
local function doBlockPlayer()
    local targetPlayer = Players:FindFirstChild(CONFIG.PARTNER_NAME)
    if not targetPlayer then
        if HintApp then
            HintApp:hint({ text = "Player not in server.", length = 2, overridable = true })
        end
        return
    end

    task.spawn(function()
        setIdentity(8)
        game:GetService('StarterGui'):SetCore('PromptBlockPlayer', targetPlayer)
        local startTime = tick()
        local modal = nil

        while not modal do
            RunService.Heartbeat:Wait()
            if tick() - startTime > 10 then
                setIdentity(2)
                return
            end
            local overlay = CoreGui:FindFirstChild('FoundationOverlay')
            if overlay then
                modal = overlay:FindFirstChild("BlockingModalScreen", true)
            end
        end

        local function hideModal()
            pcall(function()
                modal.BackgroundTransparency = 1
                for _, desc in ipairs(modal:GetDescendants()) do
                    pcall(function()
                        if desc:IsA('ImageLabel') or desc:IsA('ImageButton') then
                            desc.ImageTransparency = 1
                            desc.BackgroundTransparency = 1
                        end
                        if desc:IsA('TextLabel') or desc:IsA('TextButton') then
                            desc.TextTransparency = 1
                            desc.BackgroundTransparency = 1
                        end
                        if desc:IsA('Frame') then
                            desc.BackgroundTransparency = 1
                        end
                        if desc:IsA('UIStroke') then
                            desc.Transparency = 1
                        end
                    end)
                end
            end)
        end

        hideModal()
        local posConn
        posConn = RunService.Heartbeat:Connect(function()
            pcall(function()
                if modal and modal.Parent then
                    hideModal()
                else
                    posConn:Disconnect()
                end
            end)
        end)

        local blockBtn = nil
        pcall(function()
            blockBtn = modal.BlockingModalContainerWrapper.BlockingModal.AlertModal.AlertContents.Footer.Buttons['3']
        end)

        if not blockBtn then
            pcall(function()
                local buttonsContainer = modal:FindFirstChild("Buttons", true)
                if buttonsContainer then
                    for _, btn in ipairs(buttonsContainer:GetChildren()) do
                        if btn:IsA('ImageButton') or btn:IsA('TextButton') then
                            local textLabel = btn:FindFirstChild("Text")
                            if textLabel and textLabel:IsA('TextLabel') and textLabel.Text == "Block" then
                                blockBtn = btn
                                break
                            end
                        end
                    end
                    if not blockBtn then
                        blockBtn = buttonsContainer:FindFirstChild('3')
                    end
                end
            end)
        end

        if blockBtn then
            local attempts = 0
            while attempts < 20 do
                attempts = attempts + 1
                pcall(function() game:GetService('GuiService').SelectedObject = blockBtn end)
                task.wait()
                pcall(function()
                    if game:GetService('GuiService').SelectedObject == blockBtn then
                        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
                    end
                end)
                task.wait(0.1)
                pcall(function()
                    local absPos = blockBtn.AbsolutePosition
                    local absSize = blockBtn.AbsoluteSize
                    local cx = absPos.X + absSize.X / 2
                    local cy = absPos.Y + absSize.Y / 2
                    VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
                    task.wait()
                    VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
                end)
                pcall(function()
                    if firesignal then
                        firesignal(blockBtn.MouseButton1Click)
                    end
                end)
                pcall(function()
                    if fireclick then
                        fireclick(blockBtn)
                    end
                end)
                task.wait(0.2)

                local overlay = CoreGui:FindFirstChild('FoundationOverlay')
                if not overlay or not overlay:FindFirstChild("BlockingModalScreen", true) then
                    break
                end
            end
            pcall(function() game:GetService('GuiService').SelectedObject = nil end)
        end

        pcall(function()
            if posConn then
                posConn:Disconnect()
            end
        end)

        local timeout = tick() + 10
        while tick() < timeout do
            local overlay = CoreGui:FindFirstChild('FoundationOverlay')
            if not overlay or not overlay:FindFirstChild("BlockingModalScreen", true) then
                break
            end
            RunService.Heartbeat:Wait()
        end

        setIdentity(2)
    end)
end

-- =====================================================================
-- SUGGEST BUTTON TEXT
-- =====================================================================
local SUGGEST_BTN_TEXT = "Suggest"

-- =====================================================================
-- GUI
-- =====================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "OMNIHub"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 10
screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local blackFrame = Instance.new("Frame")
blackFrame.Name = "BlackFrame"
blackFrame.Size = UDim2.new(0, 206, 0, 706)
blackFrame.Position = UDim2.new(0, 10, 0.5, -353)
blackFrame.BackgroundColor3 = Color3.new(0,0,0)
blackFrame.BorderSizePixel = 0
blackFrame.ZIndex = 0
blackFrame.Parent = screenGui
Instance.new("UICorner", blackFrame).CornerRadius = UDim.new(0, 10)

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 200, 0, 700)
mainFrame.Position = UDim2.new(0, 13, 0.5, -350)
mainFrame.BackgroundColor3 = Color3.fromRGB(30,30,40)
mainFrame.BorderSizePixel = 0
mainFrame.ZIndex = 1
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local mainStroke = Instance.new("UIStroke")
mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
mainStroke.Color = Color3.fromRGB(108,75,171)
mainStroke.Thickness = 1.5
mainStroke.Parent = mainFrame

-- Title
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1,0,0,22)
titleLabel.Position = UDim2.new(0,0,0,3)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.FredokaOne
titleLabel.TextSize = 12
titleLabel.TextColor3 = Color3.fromRGB(240,240,255)
titleLabel.Text = "OMNI HUB v1.0"
titleLabel.Parent = mainFrame

-- Drag Toggle
local dragEnabled = true
local dragToggleBtn = Instance.new("TextButton")
dragToggleBtn.Size = UDim2.new(0,36,0,16)
dragToggleBtn.Position = UDim2.new(1,-38,0,5)
dragToggleBtn.BackgroundColor3 = Color3.fromRGB(30,80,50)
dragToggleBtn.Text = "drag"
dragToggleBtn.Font = Enum.Font.GothamBold
dragToggleBtn.TextSize = 8
dragToggleBtn.TextColor3 = Color3.fromRGB(80,255,130)
dragToggleBtn.ZIndex = 10
dragToggleBtn.Parent = mainFrame
Instance.new("UICorner", dragToggleBtn).CornerRadius = UDim.new(0,4)

local dragToggleStroke = Instance.new("UIStroke")
dragToggleStroke.Color = Color3.fromRGB(0,200,80)
dragToggleStroke.Thickness = 1
dragToggleStroke.Parent = dragToggleBtn

dragToggleBtn.MouseButton1Click:Connect(function()
    dragEnabled = not dragEnabled
    if dragEnabled then
        dragToggleBtn.Text = "drag"
        dragToggleBtn.BackgroundColor3 = Color3.fromRGB(30,80,50)
        dragToggleBtn.TextColor3 = Color3.fromRGB(80,255,130)
        dragToggleStroke.Color = Color3.fromRGB(0,200,80)
    else
        dragToggleBtn.Text = "lock"
        dragToggleBtn.BackgroundColor3 = Color3.fromRGB(60,30,30)
        dragToggleBtn.TextColor3 = Color3.fromRGB(255,100,100)
        dragToggleStroke.Color = Color3.fromRGB(160,50,50)
    end
end)

-- =====================================================================
-- TAB SYSTEM
-- =====================================================================
local tabContainer = Instance.new("Frame")
tabContainer.Size = UDim2.new(0.9,0,0,22)
tabContainer.Position = UDim2.new(0.05,0,0,28)
tabContainer.BackgroundTransparency = 1
tabContainer.Parent = mainFrame

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Padding = UDim.new(0,3)
tabLayout.Parent = tabContainer

local tabs = {"Control","Trade","Spawn","Chats"}
local tabButtons = {}
local tabFrames = {}
local currentTab = nil

local function setActiveTab(tabName)
    if currentTab == tabName then return end
    currentTab = tabName

    for name, data in pairs(tabButtons) do
        local isActive = name == tabName
        data.button.BackgroundColor3 = isActive and Color3.fromRGB(50,50,60) or Color3.fromRGB(40,40,50)
        data.stroke.Color = isActive and Color3.fromRGB(108,75,171) or Color3.fromRGB(80,80,80)
        data.stroke.Thickness = isActive and 1.0 or 0.7
    end

    for name, frame in pairs(tabFrames) do
        frame.Visible = name == tabName
    end
end

for i, tabName in ipairs(tabs) do
    local tabButton = Instance.new("TextButton")
    tabButton.Size = UDim2.new(1/#tabs,-1,1,0)
    tabButton.BackgroundColor3 = i==1 and Color3.fromRGB(50,50,60) or Color3.fromRGB(40,40,50)
    tabButton.Text = tabName
    tabButton.Font = Enum.Font.FredokaOne
    tabButton.TextSize = 9
    tabButton.TextColor3 = Color3.fromRGB(255,255,255)
    tabButton.Parent = tabContainer
    Instance.new("UICorner", tabButton).CornerRadius = UDim.new(0,4)

    local tabStroke = Instance.new("UIStroke")
    tabStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    tabStroke.Color = i==1 and Color3.fromRGB(108,75,171) or Color3.fromRGB(80,80,80)
    tabStroke.Thickness = i==1 and 1.0 or 0.7
    tabStroke.Transparency = 0.3
    tabStroke.Parent = tabButton

    tabButtons[tabName] = { button = tabButton, stroke = tabStroke }

    local tabFrame = Instance.new("Frame")
    tabFrame.Size = UDim2.new(0.9,0,1,-56)
    tabFrame.Position = UDim2.new(0.05,0,0,56)
    tabFrame.BackgroundTransparency = 1
    tabFrame.Visible = i==1
    tabFrame.Parent = mainFrame
    tabFrames[tabName] = tabFrame

    tabButton.MouseButton1Click:Connect(function()
        setActiveTab(tabName)
    end)
end

-- =====================================================================
-- CONTROL TAB
-- =====================================================================
local controlFrame = tabFrames["Control"]

local controlLayout = Instance.new("UIListLayout")
controlLayout.SortOrder = Enum.SortOrder.LayoutOrder
controlLayout.Padding = UDim.new(0,3)
controlLayout.Parent = controlFrame

local controlPadding = Instance.new("UIPadding")
controlPadding.PaddingTop = UDim.new(0,5)
controlPadding.Parent = controlFrame

local function makeSectionLabel(text, order)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,0,0,13)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.Font = Enum.Font.SourceSansSemibold
    lbl.TextSize = 11
    lbl.TextColor3 = Color3.fromRGB(180,180,180)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.LayoutOrder = order
    lbl.Parent = controlFrame
    return lbl
end

local function makeFullBtn(labelText, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,22)
    btn.BackgroundColor3 = Color3.fromRGB(35,35,48)
    btn.Text = labelText
    btn.Font = Enum.Font.FredokaOne
    btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.LayoutOrder = order
    btn.Parent = controlFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,4)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = Color3.fromRGB(108,75,171)
    s.Thickness = 2
    s.Transparency = 0.3
    s.Parent = btn
    return btn
end

local function createSettingRow(labelText, defaultValue, order)
    local heading = Instance.new("TextLabel")
    heading.Size = UDim2.new(1,0,0,13)
    heading.BackgroundTransparency = 1
    heading.Text = labelText
    heading.Font = Enum.Font.SourceSansSemibold
    heading.TextSize = 11
    heading.TextColor3 = Color3.fromRGB(180,180,180)
    heading.TextXAlignment = Enum.TextXAlignment.Left
    heading.LayoutOrder = order
    heading.Parent = controlFrame

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1,0,0,22)
    box.BackgroundColor3 = Color3.fromRGB(40,40,50)
    box.Text = tostring(defaultValue)
    box.Font = Enum.Font.SourceSans
    box.TextSize = 12
    box.TextColor3 = Color3.fromRGB(255,255,255)
    box.ClearTextOnFocus = false
    box.TextXAlignment = Enum.TextXAlignment.Center
    box.LayoutOrder = order+1
    box.Parent = controlFrame
    Instance.new("UICorner", box).CornerRadius = UDim.new(0,4)

    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = Color3.fromRGB(100,100,100)
    stroke.Thickness = 0.7
    stroke.Transparency = 0.5
    stroke.Parent = box

    return box
end

local partnerBox = createSettingRow("Partner Username", CONFIG.PARTNER_NAME, 1)
local acceptBox = createSettingRow("Accept Delay (s)", CONFIG.AUTO_ACCEPT_DELAY, 3)
local confirmBox = createSettingRow("Confirm Delay (s)", CONFIG.AUTO_CONFIRM_DELAY, 5)
local spectatorBox = createSettingRow("Spectator Count", CONFIG.SPECTATOR_COUNT, 7)

partnerBox.FocusLost:Connect(function()
    local n = partnerBox.Text
    if n ~= "" then
        CONFIG.PARTNER_NAME = n
        task.spawn(updatePartnerFromUsername, n)
    end
end)

acceptBox.FocusLost:Connect(function()
    local v = tonumber(acceptBox.Text)
    if v and v >= 0 then
        CONFIG.AUTO_ACCEPT_DELAY = v
    else
        acceptBox.Text = tostring(CONFIG.AUTO_ACCEPT_DELAY)
    end
end)

confirmBox.FocusLost:Connect(function()
    local v = tonumber(confirmBox.Text)
    if v and v >= 0 then
        CONFIG.AUTO_CONFIRM_DELAY = v
    else
        confirmBox.Text = tostring(CONFIG.AUTO_CONFIRM_DELAY)
    end
end)

spectatorBox.FocusLost:Connect(function()
    local v = tonumber(spectatorBox.Text)
    if v and v >= 0 then
        CONFIG.SPECTATOR_COUNT = v
        if mockState.trade then
            mockState.trade.subscriber_count = v
            pcall(function() TradeApp:_update_spectator_count(mockState.trade) end)
        end
    else
        spectatorBox.Text = tostring(CONFIG.SPECTATOR_COUNT)
    end
end)

local spacer = Instance.new("Frame")
spacer.Size = UDim2.new(1,0,0,4)
spacer.BackgroundTransparency = 1
spacer.LayoutOrder = 9
spacer.Parent = controlFrame

makeSectionLabel("Trading Control", 10)

local startTradeBtn = makeFullBtn("Start Trade", 11)
startTradeBtn.MouseButton1Click:Connect(function()
    local n = partnerBox.Text
    if n ~= "" then
        CONFIG.PARTNER_NAME = n
    end
    task.spawn(function()
        updatePartnerFromUsername(CONFIG.PARTNER_NAME)
        startMockTradeDirectly()
    end)
end)

makeSectionLabel("Partner Controls", 12)

local partnerBtnRow = Instance.new("Frame")
partnerBtnRow.Size = UDim2.new(1,0,0,22)
partnerBtnRow.BackgroundTransparency = 1
partnerBtnRow.LayoutOrder = 13
partnerBtnRow.Parent = controlFrame

local function makeHalfBtn(labelText, xPos, parent)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.48,0,1,0)
    btn.Position = UDim2.new(xPos,0,0,0)
    btn.BackgroundColor3 = Color3.fromRGB(35,35,48)
    btn.Text = labelText
    btn.Font = Enum.Font.FredokaOne
    btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(255,255,255)
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,4)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = Color3.fromRGB(108,75,171)
    s.Thickness = 2
    s.Transparency = 0.3
    s.Parent = btn
    return btn
end

local partnerAcceptBtn = makeHalfBtn("Partner Accept", 0, partnerBtnRow)
local partnerUnacceptBtn = makeHalfBtn("Partner Unaccept", 0.52, partnerBtnRow)

partnerAcceptBtn.MouseButton1Click:Connect(doPartnerAccept)
partnerUnacceptBtn.MouseButton1Click:Connect(doPartnerUnaccept)

makeSectionLabel("Blocking Control", 14)

local blockBtn = makeFullBtn("Block Player", 15)
blockBtn.MouseButton1Click:Connect(doBlockPlayer)

makeSectionLabel("Adding Control", 16)

local addHighTierBtn = makeFullBtn("Add Random High Tier", 17)
addHighTierBtn.MouseButton1Click:Connect(function()
    if not mockState.active or not mockState.trade then
        if HintApp then
            HintApp:hint({ text = "Start a trade first.", length = 2, overridable = true })
        end
        return
    end
    if mockState.trade.current_stage == "confirmation" then
        if HintApp then
            HintApp:hint({ text = "Cannot modify during confirmation.", length = 2, overridable = true })
        end
        return
    end
    local petName = HIGH_TIER_PETS[math.random(1, #HIGH_TIER_PETS)]
    task.spawn(function()
        addPetToPartnerOffer(petName, nil)
    end)
end)

makeSectionLabel("Trade Controls", 18)

local declineBtn = makeFullBtn("Decline Trade", 19)
declineBtn.MouseButton1Click:Connect(function()
    if mockState.active then
        TradeApp:_decline_trade()
    end
end)

-- =====================================================================
-- SPAWN TAB - Pet Spawner
-- =====================================================================
local spawnFrame = tabFrames["Spawn"]

local spawnLayout = Instance.new("UIListLayout")
spawnLayout.SortOrder = Enum.SortOrder.LayoutOrder
spawnLayout.Padding = UDim.new(0,4)
spawnLayout.Parent = spawnFrame

local spawnPadding = Instance.new("UIPadding")
spawnPadding.PaddingTop = UDim.new(0,4)
spawnPadding.PaddingLeft = UDim.new(0,4)
spawnPadding.PaddingRight = UDim.new(0,4)
spawnPadding.Parent = spawnFrame

-- Pet name input
local petNameBox = Instance.new("TextBox")
petNameBox.Size = UDim2.new(1,0,0,26)
petNameBox.BackgroundColor3 = Color3.fromRGB(35,35,45)
petNameBox.Text = ""
petNameBox.PlaceholderText = "Pet name..."
petNameBox.Font = Enum.Font.SourceSans
petNameBox.TextSize = 12
petNameBox.TextColor3 = Color3.fromRGB(255,255,255)
petNameBox.PlaceholderColor3 = Color3.fromRGB(90,90,110)
petNameBox.ClearTextOnFocus = false
petNameBox.TextXAlignment = Enum.TextXAlignment.Left
petNameBox.LayoutOrder = 1
petNameBox.Parent = spawnFrame
Instance.new("UICorner", petNameBox).CornerRadius = UDim.new(0,5)

local petNamePad = Instance.new("UIPadding")
petNamePad.PaddingLeft = UDim.new(0,8)
petNamePad.PaddingRight = UDim.new(0,8)
petNamePad.Parent = petNameBox

local petNameStroke = Instance.new("UIStroke")
petNameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
petNameStroke.Color = Color3.fromRGB(80,80,100)
petNameStroke.Thickness = 1
petNameStroke.Parent = petNameBox

-- Flags
local petFlags = { F = false, R = false, N = false, M = false }

local flagsRow = Instance.new("Frame")
flagsRow.Size = UDim2.new(1,0,0,28)
flagsRow.BackgroundTransparency = 1
flagsRow.LayoutOrder = 2
flagsRow.Parent = spawnFrame

local flagsLayout = Instance.new("UIListLayout")
flagsLayout.FillDirection = Enum.FillDirection.Horizontal
flagsLayout.SortOrder = Enum.SortOrder.LayoutOrder
flagsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
flagsLayout.Padding = UDim.new(0,8)
flagsLayout.Parent = flagsRow

local flagDefs = {
    { key="F", label="Fly",  off=Color3.fromRGB(30,30,45), on=Color3.fromRGB(50,100,220) },
    { key="R", label="Ride", off=Color3.fromRGB(30,30,45), on=Color3.fromRGB(200,50,50) },
    { key="N", label="Neon", off=Color3.fromRGB(30,30,45), on=Color3.fromRGB(30,180,90) },
    { key="M", label="Mega", off=Color3.fromRGB(30,30,45), on=Color3.fromRGB(130,50,210) },
}

local flagRefs = {}

for _, def in ipairs(flagDefs) do
    local isOn = petFlags[def.key]
    local fb = Instance.new("TextButton")
    fb.Size = UDim2.new(0,40,1,0)
    fb.BackgroundColor3 = isOn and def.on or def.off
    fb.Text = def.label
    fb.Font = Enum.Font.GothamBold
    fb.TextSize = 10
    fb.TextColor3 = isOn and Color3.fromRGB(255,255,255) or Color3.fromRGB(120,120,140)
    fb.Parent = flagsRow
    Instance.new("UICorner", fb).CornerRadius = UDim.new(0,5)

    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = isOn and def.on or Color3.fromRGB(60,60,80)
    s.Thickness = 1
    s.Parent = fb

    flagRefs[def.key] = { btn = fb, stroke = s, def = def }

    fb.MouseButton1Click:Connect(function()
        if def.key == "M" and not petFlags.M then petFlags.N = false end
        if def.key == "N" and not petFlags.N then petFlags.M = false end
        petFlags[def.key] = not petFlags[def.key]

        for k, ref in pairs(flagRefs) do
            local on = petFlags[k]
            ref.btn.BackgroundColor3 = on and ref.def.on or ref.def.off
            ref.btn.TextColor3 = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(120,120,140)
            ref.stroke.Color = on and ref.def.on or Color3.fromRGB(60,60,80)
        end
    end)
end

-- Spawn button
local spawnBtn = Instance.new("TextButton")
spawnBtn.Size = UDim2.new(1,0,0,24)
spawnBtn.BackgroundColor3 = Color3.fromRGB(35,35,48)
spawnBtn.Text = "Spawn Pet"
spawnBtn.Font = Enum.Font.FredokaOne
spawnBtn.TextSize = 11
spawnBtn.TextColor3 = Color3.fromRGB(255,255,255)
spawnBtn.LayoutOrder = 3
spawnBtn.Parent = spawnFrame
Instance.new("UICorner", spawnBtn).CornerRadius = UDim.new(0,4)

local spawnStroke = Instance.new("UIStroke")
spawnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
spawnStroke.Color = Color3.fromRGB(108,75,171)
spawnStroke.Thickness = 1.5
spawnStroke.Transparency = 0.3
spawnStroke.Parent = spawnBtn

-- Spawn All Variants button
local spawnAllBtn = Instance.new("TextButton")
spawnAllBtn.Size = UDim2.new(1,0,0,24)
spawnAllBtn.BackgroundColor3 = Color3.fromRGB(35,35,48)
spawnAllBtn.Text = "Spawn All High Tiers"
spawnAllBtn.Font = Enum.Font.FredokaOne
spawnAllBtn.TextSize = 11
spawnAllBtn.TextColor3 = Color3.fromRGB(255,255,255)
spawnAllBtn.LayoutOrder = 4
spawnAllBtn.Parent = spawnFrame
Instance.new("UICorner", spawnAllBtn).CornerRadius = UDim.new(0,4)

local spawnAllStroke = Instance.new("UIStroke")
spawnAllStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
spawnAllStroke.Color = Color3.fromRGB(50,180,80)
spawnAllStroke.Thickness = 1.5
spawnAllStroke.Transparency = 0.3
spawnAllStroke.Parent = spawnAllBtn

-- Spawn Random Pets button
local spawnRandBtn = Instance.new("TextButton")
spawnRandBtn.Size = UDim2.new(1,0,0,24)
spawnRandBtn.BackgroundColor3 = Color3.fromRGB(35,35,48)
spawnRandBtn.Text = "Spawn 50 Random Pets"
spawnRandBtn.Font = Enum.Font.FredokaOne
spawnRandBtn.TextSize = 11
spawnRandBtn.TextColor3 = Color3.fromRGB(255,255,255)
spawnRandBtn.LayoutOrder = 5
spawnRandBtn.Parent = spawnFrame
Instance.new("UICorner", spawnRandBtn).CornerRadius = UDim.new(0,4)

local spawnRandStroke = Instance.new("UIStroke")
spawnRandStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
spawnRandStroke.Color = Color3.fromRGB(60,130,200)
spawnRandStroke.Thickness = 1.5
spawnRandStroke.Transparency = 0.3
spawnRandStroke.Parent = spawnRandBtn

-- Spawn functions
local function findPetKind(name)
    for catName, catTable in pairs(InventoryDB) do
        if catName == "pets" then
            for id, item in pairs(catTable) do
                if item.name:lower() == name:lower() then
                    return id
                end
            end
        end
    end
    return nil
end

local function createInventoryItem(itemId, category, properties)
    local uniqueId = HttpService:GenerateGUID(false)
    local kd = KindDB[itemId]
    if not kd then return nil end

    local itemData = {
        unique = uniqueId,
        category = category,
        id = itemId,
        kind = kd.kind or itemId,
        newness_order = math.random(100000, 999999),
        properties = properties or {},
        _source = "omni_hub",
    }

    setIdentity(2)
    local inv = ClientData.get("inventory")
    if inv and inv[category] then
        inv[category][uniqueId] = itemData
    end
    setIdentity(8)

    task.defer(function()
        pcall(function() UIManager.apps.BackpackApp:refresh_rendered_items() end)
    end)

    return itemData
end

spawnBtn.MouseButton1Click:Connect(function()
    local name = petNameBox.Text
    if name == "" then
        if HintApp then
            HintApp:hint({ text = "Enter a pet name first.", length = 2, overridable = true })
        end
        return
    end

    local foundKind = findPetKind(name)
    if not foundKind then
        if HintApp then
            HintApp:hint({ text = "Pet not found: " .. name, length = 3, overridable = true })
        end
        return
    end

    local props = {
        flyable = petFlags.F,
        rideable = petFlags.R,
        neon = petFlags.N,
        mega_neon = petFlags.M,
        age = 6,
        xp = 0,
        rp_name = "",
    }

    local item = createInventoryItem(foundKind, "pets", props)
    if item then
        if HintApp then
            HintApp:hint({ text = name .. " spawned! Check backpack.", length = 3, overridable = true })
        end
    end
end)

local spawnAllBusy = false
spawnAllBtn.MouseButton1Click:Connect(function()
    if spawnAllBusy then return end
    spawnAllBusy = true
    spawnAllBtn.Text = "Spawning..."

    task.spawn(function()
        local count = 0
        local variants = {
            { F=true, R=true, N=false, M=true },
            { F=true, R=true, N=true, M=false },
            { F=true, R=true, N=false, M=false },
        }

        for _, petName in ipairs(HIGH_TIER_PETS) do
            local foundKind = findPetKind(petName)
            if foundKind then
                for _, flags in ipairs(variants) do
                    createInventoryItem(foundKind, "pets", {
                        flyable = flags.F,
                        rideable = flags.R,
                        neon = flags.N,
                        mega_neon = flags.M,
                        age = 6,
                        xp = 0,
                        rp_name = "",
                    })
                    count = count + 1
                end
                -- Add 2 random variants
                for _ = 1, 2 do
                    local randFlags = {
                        F = math.random(0,1) == 1,
                        R = math.random(0,1) == 1,
                        N = math.random(1,3) == 2,
                        M = math.random(1,3) == 3,
                    }
                    createInventoryItem(foundKind, "pets", {
                        flyable = randFlags.F,
                        rideable = randFlags.R,
                        neon = randFlags.N,
                        mega_neon = randFlags.M,
                        age = 6,
                        xp = 0,
                        rp_name = "",
                    })
                    count = count + 1
                end
            end
        end

        if HintApp then
            HintApp:hint({ text = count .. " pets spawned!", length = 3, overridable = true })
        end
        spawnAllBtn.Text = "Spawn All High Tiers"
        spawnAllBusy = false
    end)
end)

local spawnRandBusy = false
spawnRandBtn.MouseButton1Click:Connect(function()
    if spawnRandBusy then return end
    spawnRandBusy = true

    local allPetKinds = {}
    for id, item in pairs(InventoryDB.pets or {}) do
        if item.name then
            table.insert(allPetKinds, id)
        end
    end

    if #allPetKinds == 0 then
        spawnRandBusy = false
        return
    end

    for _ = 1, 50 do
        local id = allPetKinds[math.random(1, #allPetKinds)]
        createInventoryItem(id, "pets", {
            flyable = petFlags.F,
            rideable = petFlags.R,
            neon = petFlags.N,
            mega_neon = petFlags.M,
            age = 6,
            xp = 0,
            rp_name = "",
        })
    end

    if HintApp then
        HintApp:hint({ text = "50 random pets spawned!", length = 3, overridable = true })
    end
    spawnRandBusy = false
end)

-- =====================================================================
-- CHATS TAB
-- =====================================================================
local chatMessages = {
    "Can I boost this??",
    "GIRL I DONT WANT THAT",
    "Can I spin this??",
    "broke and unknown",
    "BITCHHHH",
    "Low Tiers please!",
    "U RICH OMGG",
    "Pick any of my pets!",
    "Inside of my inventory is a bat dragon, can I spin it?",
    "Now can I please have my dream pet",
    "Tell me what I can get from boosting this please!!!!",
    "OH PUT IT DOWN",
    "RICH OMGGGG",
    "can we be besties",
    "friend zoned",
}

local chatsFrame = tabFrames["Chats"]

local chatListFrame = Instance.new("ScrollingFrame")
chatListFrame.Size = UDim2.new(1,0,1,0)
chatListFrame.BackgroundColor3 = Color3.fromRGB(25,25,35)
chatListFrame.BackgroundTransparency = 0.5
chatListFrame.BorderSizePixel = 0
chatListFrame.ScrollBarThickness = 3
chatListFrame.ScrollBarImageColor3 = Color3.fromRGB(100,100,100)
chatListFrame.CanvasSize = UDim2.new(0,0,0,0)
chatListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
chatListFrame.Parent = chatsFrame
Instance.new("UICorner", chatListFrame).CornerRadius = UDim.new(0,6)

local chatListLayout = Instance.new("UIListLayout")
chatListLayout.SortOrder = Enum.SortOrder.LayoutOrder
chatListLayout.Padding = UDim.new(0,4)
chatListLayout.Parent = chatListFrame

local chatListPadding = Instance.new("UIPadding")
chatListPadding.PaddingTop = UDim.new(0,6)
chatListPadding.PaddingBottom = UDim.new(0,6)
chatListPadding.PaddingLeft = UDim.new(0,6)
chatListPadding.PaddingRight = UDim.new(0,6)
chatListPadding.Parent = chatListFrame

for i, msg in ipairs(chatMessages) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,-4,0,0)
    btn.AutomaticSize = Enum.AutomaticSize.Y
    btn.BackgroundColor3 = Color3.fromRGB(40,40,50)
    btn.BackgroundTransparency = 0.2
    btn.Text = msg
    btn.Font = Enum.Font.SourceSans
    btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(220,220,235)
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.TextWrapped = true
    btn.LayoutOrder = i
    btn.Parent = chatListFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,5)

    local btnPad = Instance.new("UIPadding")
    btnPad.PaddingLeft = UDim.new(0,7)
    btnPad.PaddingRight = UDim.new(0,7)
    btnPad.PaddingTop = UDim.new(0,5)
    btnPad.PaddingBottom = UDim.new(0,5)
    btnPad.Parent = btn

    local btnStroke = Instance.new("UIStroke")
    btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    btnStroke.Color = Color3.fromRGB(108,75,171)
    btnStroke.Thickness = 1.0
    btnStroke.Transparency = 0.3
    btnStroke.Parent = btn

    btn.MouseEnter:Connect(function()
        TweenService:Create(btnStroke, TweenInfo.new(0.12), { Transparency = 0 }):Play()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(55,50,75) }):Play()
    end)

    btn.MouseLeave:Connect(function()
        TweenService:Create(btnStroke, TweenInfo.new(0.12), { Transparency = 0.3 }):Play()
        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(40,40,50) }):Play()
    end)

    local capturedMsg = msg
    btn.MouseButton1Click:Connect(function()
        if not mockState.active or not mockState.trade then
            if HintApp then
                HintApp:hint({ text = "Start a trade first.", length = 2, overridable = true })
            end
            return
        end
        pcall(function()
            if TradeApp._render_message_in_trade_chat then
                TradeApp:_render_message_in_trade_chat(nil, CONFIG.PARTNER_NAME .. ": " .. capturedMsg, true)
            end
        end)
        TweenService:Create(btnStroke, TweenInfo.new(0.15), { Color = Color3.fromRGB(0,220,100), Transparency = 0 }):Play()
        task.delay(0.5, function()
            TweenService:Create(btnStroke, TweenInfo.new(0.2), { Color = Color3.fromRGB(108,75,171), Transparency = 0.3 }):Play()
        end)
    end)
end

-- =====================================================================
-- HOOK TRADE FUNCTIONS (continued from earlier)
-- =====================================================================
hookTradeFunctions()

-- =====================================================================
-- STARTUP - Set first tab active
-- =====================================================================
setActiveTab("Control")

-- =====================================================================
-- DRAGGING
-- =====================================================================
local dragging, dragStart, startPos

mainFrame.InputBegan:Connect(function(input)
    if not dragEnabled then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or
       input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and
       input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end
    local delta = input.Position - dragStart
    mainFrame.Position = UDim2.new(
        startPos.X.Scale,
        startPos.X.Offset + delta.X,
        startPos.Y.Scale,
        startPos.Y.Offset + delta.Y
    )
    blackFrame.Position = UDim2.new(
        mainFrame.Position.X.Scale,
        mainFrame.Position.X.Offset - 3,
        mainFrame.Position.Y.Scale,
        mainFrame.Position.Y.Offset - 3
    )
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or
       input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- =====================================================================
-- KEYBINDS
-- =====================================================================
local KEYBINDS = {
    { key = Enum.KeyCode.T, action = function()
        task.spawn(function()
            updatePartnerFromUsername(CONFIG.PARTNER_NAME)
            startMockTradeDirectly()
        end)
    end},
    { key = Enum.KeyCode.Y, action = doPartnerAccept },
    { key = Enum.KeyCode.U, action = doPartnerUnaccept },
    { key = Enum.KeyCode.P, action = function()
        if mockState.active and mockState.trade then
            local petName = HIGH_TIER_PETS[math.random(1, #HIGH_TIER_PETS)]
            task.spawn(function() addPetToPartnerOffer(petName, nil) end)
        end
    end},
    { key = Enum.KeyCode.X, action = function()
        if mockState.active then
            TradeApp:_decline_trade()
        end
    end},
}

local keyMap = {}
for _, def in ipairs(KEYBINDS) do
    keyMap[def.key] = def
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if UserInputService:GetFocusedTextBox() then return end
    local def = keyMap[input.KeyCode]
    if def then
        pcall(def.action)
    end
end)

print("OMNI HUB loaded successfully!")
print("Keybinds: T=Start Trade, Y=Partner Accept, U=Partner Unaccept, P=Add Random High Tier, X=Decline Trade")
