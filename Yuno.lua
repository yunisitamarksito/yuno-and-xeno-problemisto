
-- =====================================================================
-- CORE SETUP
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
local LocalPlayer = Players.LocalPlayer

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
-- LOAD MODULES
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

if not TradeApp then
    warn("TradeApp not found - waiting...")
    task.wait(5)
    TradeApp = UIManager.apps.TradeApp
    if not TradeApp then return end
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
        sender = LocalPlayer,
        recipient = mockPartner,
        sender_offer = { items = {}, player_name = LocalPlayer.Name, negotiated = false, confirmed = false },
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
        sender_user_id = LocalPlayer.UserId,
        sender_name = LocalPlayer.Name,
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
        if HintApp then
            HintApp:hint({ text = "Trade started with " .. CONFIG.PARTNER_NAME, length = 3, overridable = true })
        end
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
    if HintApp then
        HintApp:hint({ text = "Partner accepted", length = 2, overridable = true })
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
    if HintApp then
        HintApp:hint({ text = "Partner unaccepted", length = 2, overridable = true })
    end
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
        StarterGui:SetCore('PromptBlockPlayer', targetPlayer)
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
        if HintApp then
            HintApp:hint({ text = "Blocked " .. CONFIG.PARTNER_NAME, length = 2, overridable = true })
        end
    end)
end

-- =====================================================================
-- PET SPAWNER FUNCTIONS
-- =====================================================================
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
        _source = "omni_xeno",
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

-- =====================================================================
-- STORE ORIGINAL TRADE FUNCTIONS
-- =====================================================================
local function storeOriginals()
    local names = {
        "_get_local_trade_state", "_overwrite_local_trade_state", "_change_local_trade_state",
        "_get_my_offer", "_get_partner_offer", "_get_my_player", "_get_partner",
        "_get_current_trade_stage", "_on_accept_pressed", "_on_confirm_pressed",
        "_on_unaccept_pressed", "_decline_trade", "_add_item_to_my_offer",
        "_remove_item_from_my_offer", "_lock_trade_for_appropriate_time",
        "_get_lock_time", "refresh_all", "_evaluate_trade_fairness"
    }
    for _, n in ipairs(names) do
        if TradeApp[n] then
            mockState.originalFunctions[n] = TradeApp[n]
        end
    end
end
storeOriginals()

-- =====================================================================
-- HOOK TRADE FUNCTIONS
-- =====================================================================
local function hookTradeFunctions()
    TradeApp._get_local_trade_state = function(self)
        if mockState.active and mockState.trade then
            return TableUtil.deep_copy(mockState.trade)
        end
        return mockState.originalFunctions._get_local_trade_state(self)
    end

    TradeApp._overwrite_local_trade_state = function(self, newState)
        if mockState._blockRefreshAll then return end
        if mockState.active then
            if newState then
                mockState.trade = newState
                self.local_trade_state = newState
                if mockState.trade then
                    mockState.trade.subscriber_count = CONFIG.SPECTATOR_COUNT
                end
                if self._on_local_trade_state_changed then
                    pcall(function() self:_on_local_trade_state_changed(newState, newState) end)
                end
                if self.refresh_all then
                    pcall(function() self:refresh_all() end)
                end
            else
                mockState.trade = nil
                mockState.active = false
                mockState.isAddingItem = false
                mockState.partnerActionPending = false
                mockState.tradeCompleting = false
                self.local_trade_state = nil
            end
        else
            return mockState.originalFunctions._overwrite_local_trade_state(self, newState)
        end
    end

    TradeApp._get_my_offer = function(self)
        local state = self:_get_local_trade_state()
        if mockState.active and state then
            if LocalPlayer == state.sender then
                return state.sender_offer, "sender_offer"
            else
                return state.recipient_offer, "recipient_offer"
            end
        end
        return mockState.originalFunctions._get_my_offer(self)
    end

    TradeApp._get_partner_offer = function(self)
        local state = self:_get_local_trade_state()
        if mockState.active and state then
            if LocalPlayer == state.sender then
                return state.recipient_offer, "recipient_offer"
            else
                return state.sender_offer, "sender_offer"
            end
        end
        return mockState.originalFunctions._get_partner_offer(self)
    end

    TradeApp._get_my_player = function(self)
        if mockState.active then return LocalPlayer end
        return mockState.originalFunctions._get_my_player(self)
    end

    TradeApp._get_partner = function(self)
        if mockState.active and mockState.trade then
            return mockState.trade.recipient
        end
        return mockState.originalFunctions._get_partner(self)
    end

    TradeApp._get_current_trade_stage = function(self)
        if mockState.active and mockState.trade then
            return mockState.trade.current_stage
        end
        return mockState.originalFunctions._get_current_trade_stage(self)
    end

    TradeApp._get_lock_time = function(self)
        if mockState.active and mockState.trade then
            if self:_get_current_trade_stage() == "negotiation" then
                return CONFIG.NEGOTIATION_LOCK
            else
                return math.clamp(
                    CONFIG.CONFIRMATION_LOCK_PER_ITEM *
                    (#mockState.trade.sender_offer.items + #mockState.trade.recipient_offer.items),
                    5, 15
                )
            end
        end
        return mockState.originalFunctions._get_lock_time(self)
    end

    TradeApp._lock_trade_for_appropriate_time = function(self)
        if mockState.active then
            pcall(function()
                if self.lock_countdown then
                    self.lock_countdown:stop()
                    self.lock_countdown:set_duration(self:_get_lock_time())
                    self.lock_countdown:start()
                end
            end)
        else
            return mockState.originalFunctions._lock_trade_for_appropriate_time(self)
        end
    end

    TradeApp._add_item_to_my_offer = function(self)
        if mockState.active and mockState.trade then
            if mockState.isAddingItem then return end
            mockState.isAddingItem = true

            local picked = BackpackApp:pick_item({
                keep_cached_scroll_positions_on_open = true,
                allow_callback = function() return true end
            })

            if picked and mockState.trade then
                local already = false
                for _, item in ipairs(mockState.trade.sender_offer.items) do
                    if item.unique == picked.unique then
                        already = true
                        break
                    end
                end
                if not already then
                    table.insert(mockState.trade.sender_offer.items, picked)
                    mockState.trade.sender_offer.negotiated = false
                    mockState.trade.recipient_offer.negotiated = false

                    if mockState.trade.current_stage == "confirmation" then
                        mockState.trade.current_stage = "negotiation"
                        mockState.trade.sender_offer.confirmed = false
                        mockState.trade.recipient_offer.confirmed = false
                    end

                    mockState.trade.offer_version = mockState.trade.offer_version + 1
                    pcall(function() self:_overwrite_local_trade_state(mockState.trade) end)
                    pcall(function() self:_lock_trade_for_appropriate_time() end)
                end
            end
            mockState.isAddingItem = false
        else
            return mockState.originalFunctions._add_item_to_my_offer(self)
        end
    end

    TradeApp._remove_item_from_my_offer = function(self, item)
        if mockState.active and mockState.trade then
            for i, v in ipairs(mockState.trade.sender_offer.items) do
                if v.unique == item.unique then
                    table.remove(mockState.trade.sender_offer.items, i)
                    mockState.trade.sender_offer.negotiated = false
                    mockState.trade.recipient_offer.negotiated = false

                    if mockState.trade.current_stage == "confirmation" then
                        mockState.trade.current_stage = "negotiation"
                        mockState.trade.recipient_offer.negotiated = false
                        mockState.trade.sender_offer.confirmed = false
                        mockState.trade.recipient_offer.confirmed = false
                    end

                    mockState.trade.offer_version = mockState.trade.offer_version + 1
                    self:_overwrite_local_trade_state(mockState.trade)
                    pcall(function()
                        if self._lock_trade_for_appropriate_time then
                            self:_lock_trade_for_appropriate_time()
                        end
                    end)
                    break
                end
            end
        else
            return mockState.originalFunctions._remove_item_from_my_offer(self, item)
        end
    end

    TradeApp._on_accept_pressed = function(self)
        if mockState.active and mockState.trade then
            if mockState.trade.sender_offer.negotiated then
                mockState.trade.sender_offer.negotiated = false
                mockState.trade.offer_version = mockState.trade.offer_version + 1
                self:_overwrite_local_trade_state(mockState.trade)
            else
                mockState.trade.sender_offer.negotiated = true
                if mockState.trade.recipient_offer.negotiated then
                    mockState.trade.current_stage = "confirmation"
                    mockState.trade.offer_version = mockState.trade.offer_version + 1
                    self:_overwrite_local_trade_state(mockState.trade)
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
                    self:_overwrite_local_trade_state(mockState.trade)
                end
            end
        else
            return mockState.originalFunctions._on_accept_pressed(self)
        end
    end

    TradeApp._on_confirm_pressed = function(self)
        if mockState.active and mockState.trade then
            mockState.trade.sender_offer.confirmed = true
            mockState.trade.offer_version = mockState.trade.offer_version + 1
            self:_overwrite_local_trade_state(mockState.trade)
        else
            return mockState.originalFunctions._on_confirm_pressed(self)
        end
    end

    TradeApp._on_unaccept_pressed = function(self)
        if mockState.active and mockState.trade then
            if mockState.trade.current_stage == "confirmation" then
                if mockState.tradeCompleting or
                   (mockState.trade.sender_offer.confirmed and mockState.trade.recipient_offer.confirmed) then
                    return
                end
                mockState.trade.sender_offer.confirmed = false
                mockState.trade.recipient_offer.confirmed = false
                mockState.partnerActionPending = false
                mockState.tradeCompleting = false
            else
                mockState.trade.sender_offer.negotiated = false
            end
            mockState.trade.offer_version = mockState.trade.offer_version + 1
            self:_overwrite_local_trade_state(mockState.trade)
        else
            return mockState.originalFunctions._on_unaccept_pressed(self)
        end
    end

    TradeApp._decline_trade = function(self, silent)
        if mockState.active then
            if mockState.trade and mockState.trade.current_stage == "confirmation" and not silent then
                if mockState.tradeCompleting or
                   (mockState.trade.sender_offer.confirmed and mockState.trade.recipient_offer.confirmed) then
                    return
                end
                mockState.trade.sender_offer.confirmed = false
                mockState.trade.recipient_offer.confirmed = false
                mockState.trade.offer_version = mockState.trade.offer_version + 1
                mockState.partnerActionPending = false
                mockState.tradeCompleting = false
                self:_overwrite_local_trade_state(mockState.trade)
                pcall(function() self:_cancel_infinite_confirmation_detection() end)
                pcall(function() self:_set_confirmation_arrow_rotating(false) end)
                pcall(function() self:_refresh_lock_related_ui() end)
                return
            end
            pcall(function() if self.lock_countdown then self.lock_countdown:stop() end end)
            mockState.active = false
            mockState.trade = nil
            mockState.isAddingItem = false
            mockState.partnerActionPending = false
            mockState.tradeCompleting = false
            self:_overwrite_local_trade_state(nil)
            UIManager.set_app_visibility("TradeApp", false)
            if HintApp then
                HintApp:hint({ text = "Trade declined", length = 2, overridable = true })
            end
        else
            return mockState.originalFunctions._decline_trade(self, silent)
        end
    end

    TradeApp._evaluate_trade_fairness = function(self)
        if mockState.active and mockState.trade and not mockState.scamWarningShown then
            local myItems = #mockState.trade.sender_offer.items
            local partnerItems = #mockState.trade.recipient_offer.items
            if myItems > 0 and partnerItems == 0 then
                mockState.scamWarningShown = true
                if DialogApp then
                    DialogApp:dialog({ text = "This trade seems unbalanced. Be careful!", button = "Next", yields = false })
                    DialogApp:dialog({ text = "Any items lost to scams WILL NOT be returned!", button = "I understand", yields = false })
                end
            end
        else
            if mockState.originalFunctions._evaluate_trade_fairness then
                return mockState.originalFunctions._evaluate_trade_fairness(self)
            end
        end
    end
end
hookTradeFunctions()

-- =====================================================================
-- CHAT MESSAGES
-- =====================================================================
local CHAT_MESSAGES = {
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

-- =====================================================================
-- DESKTOP GUI
-- =====================================================================
local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "OMNI_XENO"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 100
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- Main Window
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 480, 0, 600)
    mainFrame.Position = UDim2.new(0.5, -240, 0.5, -300)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 38)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 14)

    -- Window Stroke
    local mainStroke = Instance.new("UIStroke")
    mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    mainStroke.Color = Color3.fromRGB(108, 75, 171)
    mainStroke.Thickness = 2.5
    mainStroke.Parent = mainFrame

    -- Title Bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 42)
    titleBar.BackgroundColor3 = Color3.fromRGB(108, 75, 171)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = mainFrame
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 14, 0, 0)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -90, 1, 0)
    titleLabel.Position = UDim2.new(0, 14, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "☀ OMNI XENO v2.0"
    titleLabel.Font = Enum.Font.FredokaOne
    titleLabel.TextSize = 18
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = titleBar

    -- Close Button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 34, 0, 34)
    closeBtn.Position = UDim2.new(1, -40, 0.5, -17)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    closeBtn.BackgroundTransparency = 0.8
    closeBtn.Text = "✕"
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 16
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.Parent = titleBar
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

    closeBtn.MouseButton1Click:Connect(function()
        screenGui:Destroy()
    end)

    -- Minimize Button
    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 34, 0, 34)
    minBtn.Position = UDim2.new(1, -78, 0.5, -17)
    minBtn.BackgroundColor3 = Color3.fromRGB(200, 200, 50)
    minBtn.BackgroundTransparency = 0.8
    minBtn.Text = "−"
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 16
    minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minBtn.Parent = titleBar
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 8)

    local minimized = false
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        mainFrame.Size = minimized and UDim2.new(0, 480, 0, 42) or UDim2.new(0, 480, 0, 600)
        mainFrame.Position = minimized and UDim2.new(0.5, -240, 0.5, -21) or UDim2.new(0.5, -240, 0.5, -300)
        for _, child in ipairs(mainFrame:GetChildren()) do
            if child ~= titleBar then
                child.Visible = not minimized
            end
        end
    end)

    -- Tab System
    local tabContainer = Instance.new("Frame")
    tabContainer.Size = UDim2.new(1, -20, 0, 38)
    tabContainer.Position = UDim2.new(0, 10, 0, 48)
    tabContainer.BackgroundTransparency = 1
    tabContainer.Parent = mainFrame

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, 4)
    tabLayout.Parent = tabContainer

    local tabNames = {"Main", "Spawn", "Chats", "Settings"}
    local tabButtons = {}
    local tabFrames = {}
    local currentTab = "Main"

    for i, name in ipairs(tabNames) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 85, 1, 0)
        btn.BackgroundColor3 = i == 1 and Color3.fromRGB(50, 50, 70) or Color3.fromRGB(35, 35, 55)
        btn.Text = name
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Parent = tabContainer
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

        local stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color = i == 1 and Color3.fromRGB(108, 75, 171) or Color3.fromRGB(60, 60, 85)
        stroke.Thickness = i == 1 and 2 or 1
        stroke.Parent = btn

        tabButtons[name] = { btn = btn, stroke = stroke }

        -- Content frame
        local content = Instance.new("ScrollingFrame")
        content.Size = UDim2.new(1, -20, 1, -100)
        content.Position = UDim2.new(0, 10, 0, 92)
        content.BackgroundTransparency = 1
        content.BorderSizePixel = 0
        content.CanvasSize = UDim2.new(0, 0, 0, 0)
        content.AutomaticCanvasSize = Enum.AutomaticSize.Y
        content.ScrollBarThickness = 4
        content.ScrollBarImageColor3 = Color3.fromRGB(108, 75, 171)
        content.Visible = i == 1
        content.Parent = mainFrame

        tabFrames[name] = content

        btn.MouseButton1Click:Connect(function()
            if currentTab == name then return end
            currentTab = name

            for tabName, data in pairs(tabButtons) do
                local isActive = tabName == name
                data.btn.BackgroundColor3 = isActive and Color3.fromRGB(50, 50, 70) or Color3.fromRGB(35, 35, 55)
                data.stroke.Color = isActive and Color3.fromRGB(108, 75, 171) or Color3.fromRGB(60, 60, 85)
                data.stroke.Thickness = isActive and 2 or 1
                tabFrames[tabName].Visible = isActive
            end
        end)
    end

    -- Helper UI functions
    local function createSection(parent, title)
        local section = Instance.new("Frame")
        section.Size = UDim2.new(1, 0, 0, 32)
        section.BackgroundTransparency = 1
        section.Parent = parent

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = title
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.TextColor3 = Color3.fromRGB(180, 180, 220)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = section

        local line = Instance.new("Frame")
        line.Size = UDim2.new(1, 0, 0, 1.5)
        line.Position = UDim2.new(0, 0, 1, -2)
        line.BackgroundColor3 = Color3.fromRGB(60, 60, 90)
        line.BackgroundTransparency = 0.4
        line.Parent = section

        return section
    end

    local function createButton(parent, text, callback)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 32)
        btn.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
        btn.Text = text
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Parent = parent
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

        local stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color = Color3.fromRGB(108, 75, 171)
        stroke.Thickness = 1.5
        stroke.Transparency = 0.3
        stroke.Parent = btn

        btn.MouseButton1Click:Connect(callback)
        return btn
    end

    local function createInput(parent, placeholder, callback)
        local box = Instance.new("TextBox")
        box.Size = UDim2.new(1, 0, 0, 30)
        box.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
        box.PlaceholderText = placeholder
        box.Font = Enum.Font.Gotham
        box.TextSize = 12
        box.TextColor3 = Color3.fromRGB(255, 255, 255)
        box.PlaceholderColor3 = Color3.fromRGB(100, 100, 140)
        box.ClearTextOnFocus = false
        box.Parent = parent
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)

        local stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color = Color3.fromRGB(60, 60, 85)
        stroke.Thickness = 1
        stroke.Parent = box

        box:GetPropertyChangedSignal("Text"):Connect(function()
            if box.Text ~= "" then
                stroke.Color = Color3.fromRGB(108, 75, 171)
                stroke.Thickness = 1.5
            else
                stroke.Color = Color3.fromRGB(60, 60, 85)
                stroke.Thickness = 1
            end
        end)

        box.FocusLost:Connect(function()
            if callback then callback(box.Text) end
        end)

        return box
    end

    local function createSlider(parent, label, min, max, step, default, callback)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 52)
        container.BackgroundTransparency = 1
        container.Parent = parent

        local labelText = Instance.new("TextLabel")
        labelText.Size = UDim2.new(0.7, 0, 0, 22)
        labelText.BackgroundTransparency = 1
        labelText.Text = label .. ": " .. tostring(default)
        labelText.Font = Enum.Font.Gotham
        labelText.TextSize = 12
        labelText.TextColor3 = Color3.fromRGB(200, 200, 230)
        labelText.TextXAlignment = Enum.TextXAlignment.Left
        labelText.Parent = container

        local valueText = Instance.new("TextLabel")
        valueText.Size = UDim2.new(0.3, 0, 0, 22)
        valueText.Position = UDim2.new(0.7, 0, 0, 0)
        valueText.BackgroundTransparency = 1
        valueText.Text = tostring(default)
        valueText.Font = Enum.Font.GothamBold
        valueText.TextSize = 12
        valueText.TextColor3 = Color3.fromRGB(108, 75, 171)
        valueText.TextXAlignment = Enum.TextXAlignment.Right
        valueText.Parent = container

        local slider = Instance.new("Frame")
        slider.Size = UDim2.new(1, 0, 0, 6)
        slider.Position = UDim2.new(0, 0, 0, 26)
        slider.BackgroundColor3 = Color3.fromRGB(45, 45, 65)
        slider.Parent = container
        Instance.new("UICorner", slider).CornerRadius = UDim.new(0, 3)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(108, 75, 171)
        fill.Parent = slider
        Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

        local button = Instance.new("TextButton")
        button.Size = UDim2.new(0, 18, 0, 18)
        button.Position = UDim2.new((default - min) / (max - min), -9, 0.5, -9)
        button.BackgroundColor3 = Color3.fromRGB(108, 75, 171)
        button.Text = ""
        button.Parent = slider
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 9)

        local dragging = false
        button.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

            local absPos = slider.AbsolutePosition
            local absSize = slider.AbsoluteSize
            local mouseX = input.Position.X

            local percent = math.clamp((mouseX - absPos.X) / absSize.X, 0, 1)
            local value = min + (max - min) * percent
            value = math.round(value / step) * step
            value = math.clamp(value, min, max)

            fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
            button.Position = UDim2.new((value - min) / (max - min), -9, 0.5, -9)
            valueText.Text = tostring(value)

            if callback then callback(value) end
        end)

        return container
    end

    -- =============================================================
    -- MAIN TAB
    -- =============================================================
    local mainContent = tabFrames["Main"]

    createSection(mainContent, "Partner Settings")
    local partnerInput = createInput(mainContent, "Partner username...", function(text)
        if text ~= "" then
            CONFIG.PARTNER_NAME = text
            task.spawn(function() updatePartnerFromUsername(text) end)
        end
    end)
    partnerInput.Text = CONFIG.PARTNER_NAME

    createSlider(mainContent, "Auto Accept Delay", 0, 10, 0.5, CONFIG.AUTO_ACCEPT_DELAY, function(v)
        CONFIG.AUTO_ACCEPT_DELAY = v
    end)

    createSlider(mainContent, "Auto Confirm Delay", 0, 10, 0.5, CONFIG.AUTO_CONFIRM_DELAY, function(v)
        CONFIG.AUTO_CONFIRM_DELAY = v
    end)

    createSlider(mainContent, "Spectator Count", 0, 20, 1, CONFIG.SPECTATOR_COUNT, function(v)
        CONFIG.SPECTATOR_COUNT = v
        if mockState.trade then
            mockState.trade.subscriber_count = v
            pcall(function() TradeApp:_update_spectator_count(mockState.trade) end)
        end
    end)

    local spacer = Instance.new("Frame")
    spacer.Size = UDim2.new(1, 0, 0, 8)
    spacer.BackgroundTransparency = 1
    spacer.Parent = mainContent

    createSection(mainContent, "Trade Controls")
    createButton(mainContent, "▶ Start Trade", function()
        task.spawn(function()
            updatePartnerFromUsername(CONFIG.PARTNER_NAME)
            startMockTradeDirectly()
        end)
    end)

    createButton(mainContent, "✕ Decline Trade", function()
        if mockState.active then
            TradeApp:_decline_trade()
        end
    end)

    createSection(mainContent, "Partner Controls")
    createButton(mainContent, "✔ Partner Accept", doPartnerAccept)
    createButton(mainContent, "✖ Partner Unaccept", doPartnerUnaccept)
    createButton(mainContent, "🎲 Add Random High Tier", function()
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
        task.spawn(function() addPetToPartnerOffer(petName, nil) end)
    end)

    createSection(mainContent, "Utility")
    createButton(mainContent, "🚫 Block Player", doBlockPlayer)

    -- =============================================================
    -- SPAWN TAB
    -- =============================================================
    local spawnContent = tabFrames["Spawn"]

    createSection(spawnContent, "Pet Spawner")
    local petNameInput = createInput(spawnContent, "Enter pet name...", function(text)
        _G.PetName = text
    end)

    -- Flag Toggles
    local flagContainer = Instance.new("Frame")
    flagContainer.Size = UDim2.new(1, 0, 0, 38)
    flagContainer.BackgroundTransparency = 1
    flagContainer.Parent = spawnContent

    local flagLayout = Instance.new("UIListLayout")
    flagLayout.FillDirection = Enum.FillDirection.Horizontal
    flagLayout.SortOrder = Enum.SortOrder.LayoutOrder
    flagLayout.Padding = UDim.new(0, 8)
    flagLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    flagLayout.Parent = flagContainer

    local flagStates = { F = false, R = false, N = false, M = false }
    local flagButtons = {}

    local flagDefs = {
        { key = "F", label = "Fly", color = Color3.fromRGB(50, 100, 220) },
        { key = "R", label = "Ride", color = Color3.fromRGB(200, 50, 50) },
        { key = "N", label = "Neon", color = Color3.fromRGB(30, 180, 90) },
        { key = "M", label = "Mega", color = Color3.fromRGB(130, 50, 210) },
    }

    for _, def in ipairs(flagDefs) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 52, 1, 0)
        btn.BackgroundColor3 = Color3.fromRGB(35, 35, 55)
        btn.Text = def.label
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.TextColor3 = Color3.fromRGB(180, 180, 210)
        btn.Parent = flagContainer
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

        local stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color = Color3.fromRGB(60, 60, 85)
        stroke.Thickness = 1.5
        stroke.Parent = btn

        flagButtons[def.key] = { btn = btn, stroke = stroke, def = def }

        btn.MouseButton1Click:Connect(function()
            if def.key == "M" and not flagStates.M then flagStates.N = false end
            if def.key == "N" and not flagStates.N then flagStates.M = false end
            flagStates[def.key] = not flagStates[def.key]

            for k, data in pairs(flagButtons) do
                local on = flagStates[k]
                data.btn.BackgroundColor3 = on and data.def.color or Color3.fromRGB(35, 35, 55)
                data.btn.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 210)
                data.stroke.Color = on and data.def.color or Color3.fromRGB(60, 60, 85)
                data.stroke.Thickness = on and 2.5 or 1.5
            end
        end)
    end

    createButton(spawnContent, "🐾 Spawn Pet", function()
        local name = _G.PetName or ""
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
            flyable = flagStates.F,
            rideable = flagStates.R,
            neon = flagStates.N,
            mega_neon = flagStates.M,
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

    local spacer2 = Instance.new("Frame")
    spacer2.Size = UDim2.new(1, 0, 0, 8)
    spacer2.BackgroundTransparency = 1
    spacer2.Parent = spawnContent

    createSection(spawnContent, "Mass Spawn")
    createButton(spawnContent, "🎯 Spawn All High Tiers", function()
        task.spawn(function()
            local count = 0
            local variants = {
                { F = true, R = true, N = false, M = true },
                { F = true, R = true, N = true, M = false },
                { F = true, R = true, N = false, M = false },
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
                end
            end

            if HintApp then
                HintApp:hint({ text = count .. " pets spawned!", length = 3, overridable = true })
            end
        end)
    end)

    createButton(spawnContent, "🎲 Spawn 50 Random Pets", function()
        task.spawn(function()
            local allPetKinds = {}
            for id, item in pairs(InventoryDB.pets or {}) do
                if item.name then
                    table.insert(allPetKinds, id)
                end
            end

            if #allPetKinds == 0 then
                return
            end

            for _ = 1, 50 do
                local id = allPetKinds[math.random(1, #allPetKinds)]
                createInventoryItem(id, "pets", {
                    flyable = flagStates.F,
                    rideable = flagStates.R,
                    neon = flagStates.N,
                    mega_neon = flagStates.M,
                    age = 6,
                    xp = 0,
                    rp_name = "",
                })
            end

            if HintApp then
                HintApp:hint({ text = "50 random pets spawned!", length = 3, overridable = true })
            end
        end)
    end)

    -- =============================================================
    -- CHATS TAB
    -- =============================================================
    local chatsContent = tabFrames["Chats"]

    createSection(chatsContent, "Quick Chat Messages")

    for _, msg in ipairs(CHAT_MESSAGES) do
        createButton(chatsContent, msg, function()
            if not mockState.active or not mockState.trade then
                if HintApp then
                    HintApp:hint({ text = "Start a trade first.", length = 2, overridable = true })
                end
                return
            end
            pcall(function()
                if TradeApp._render_message_in_trade_chat then
                    TradeApp:_render_message_in_trade_chat(nil, CONFIG.PARTNER_NAME .. ": " .. msg, true)
                end
            end)
        end)
    end

    local spacer3 = Instance.new("Frame")
    spacer3.Size = UDim2.new(1, 0, 0, 8)
    spacer3.BackgroundTransparency = 1
    spacer3.Parent = chatsContent

    createSection(chatsContent, "Custom Message")
    local customInput = createInput(chatsContent, "Type your message...", function(text)
        _G.CustomChatMessage = text
    end)

    createButton(chatsContent, "📤 Send Custom Chat", function()
        if not mockState.active or not mockState.trade then
            if HintApp then
                HintApp:hint({ text = "Start a trade first.", length = 2, overridable = true })
            end
            return
        end
        local msg = _G.CustomChatMessage or ""
        if msg == "" then
            if HintApp then
                HintApp:hint({ text = "Type a message first.", length = 2, overridable = true })
            end
            return
        end
        pcall(function()
            if TradeApp._render_message_in_trade_chat then
                TradeApp:_render_message_in_trade_chat(nil, CONFIG.PARTNER_NAME .. ": " .. msg, true)
            end
        end)
    end)

    -- =============================================================
    -- SETTINGS TAB
    -- =============================================================
    local settingsContent = tabFrames["Settings"]

    createSection(settingsContent, "Status")

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0, 26)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Trade Active: " .. tostring(mockState.active)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 12
    statusLabel.TextColor3 = Color3.fromRGB(200, 200, 230)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = settingsContent

    local partnerLabel = Instance.new("TextLabel")
    partnerLabel.Size = UDim2.new(1, 0, 0, 26)
    partnerLabel.BackgroundTransparency = 1
    partnerLabel.Text = "Partner: " .. CONFIG.PARTNER_NAME
    partnerLabel.Font = Enum.Font.Gotham
    partnerLabel.TextSize = 12
    partnerLabel.TextColor3 = Color3.fromRGB(200, 200, 230)
    partnerLabel.TextXAlignment = Enum.TextXAlignment.Left
    partnerLabel.Parent = settingsContent

    createSection(settingsContent, "Keybinds")

    local keybinds = {
        "T - Start Trade",
        "Y - Partner Accept",
        "U - Partner Unaccept",
        "P - Add Random High Tier",
        "X - Decline Trade",
    }

    for _, kb in ipairs(keybinds) do
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 22)
        lbl.BackgroundTransparency = 1
        lbl.Text = kb
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 11
        lbl.TextColor3 = Color3.fromRGB(180, 180, 210)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = settingsContent
    end

    createSection(settingsContent, "Actions")
    createButton(settingsContent, "🔄 Refresh Status", function()
        statusLabel.Text = "Trade Active: " .. tostring(mockState.active)
        partnerLabel.Text = "Partner: " .. CONFIG.PARTNER_NAME
        if HintApp then
            HintApp:hint({ text = "Status refreshed!", length = 2, overridable = true })
        end
    end)

    createButton(settingsContent, "❌ Close Hub", function()
        screenGui:Destroy()
    end)

    -- =============================================================
    -- DRAGGING
    -- =============================================================
    local dragData = { dragging = false, startPos = nil, startMouse = nil }

    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragData.dragging = true
            dragData.startMouse = input.Position
            dragData.startPos = mainFrame.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragData.dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

        local delta = input.Position - dragData.startMouse
        mainFrame.Position = UDim2.new(
            dragData.startPos.X.Scale,
            dragData.startPos.X.Offset + delta.X,
            dragData.startPos.Y.Scale,
            dragData.startPos.Y.Offset + delta.Y
        )
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragData.dragging = false
        end
    end)
end

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

-- =====================================================================
-- LAUNCH
-- =====================================================================
task.spawn(function()
    task.wait(0.5)
    createGUI()

    if HintApp then
        HintApp:hint({
            text = "☀ OMNI XENO loaded! Keybinds: T=Trade, Y=Accept, U=Unaccept, P=Add Pet, X=Decline",
            length = 5,
            overridable = true
        })
    end

    print("☀ OMNI XENO loaded successfully!")
    print("Keybinds: T=Start Trade, Y=Partner Accept, U=Partner Unaccept, P=Add Random High Tier, X=Decline Trade")
end)
