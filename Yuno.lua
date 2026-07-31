=====================================================================
-- RAYFIELD LOADER
-- =====================================================================
local Rayfield = loadstring(game:HttpGet('https://raw.githubusercontent.com/shlexware/Rayfield/main/source'))()

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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer

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
                            age = 6,
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
                local record = {
                    trade_id = mockState.trade.trade_id,
                    timestamp = os.time(),
                    sender_user_id = LocalPlayer.UserId,
                    sender_name = LocalPlayer.Name,
                    sender_items = TableUtil.deep_copy(mockState.trade.sender_offer.items),
                    recipient_user_id = mockState.trade.recipient.UserId,
                    recipient_name = CONFIG.PARTNER_NAME,
                    recipient_items = TableUtil.deep_copy(mockState.trade.recipient_offer.items),
                    reported = false,
                    reverted = nil,
                }
                if not mockState.addedTradeIds[record.trade_id] then
                    mockState.addedTradeIds[record.trade_id] = true
                    table.insert(mockState.tradeHistory, record)
                end

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
                    HintApp:hint({ text = "Trade successful!", length = 5, overridable = true })
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
-- RAYFIELD UI
-- =====================================================================
local Window = Rayfield:CreateWindow({
    Name = "OMNI HUB v1.0",
    LoadingTitle = "OMNI HUB",
    LoadingSubtitle = "Loading Adopt Me Tools...",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "OMNIHub",
        FileName = "Settings"
    },
    Discord = {
        Enabled = false,
        Invite = "",
        RememberJoins = true
    },
    KeySystem = false,
    KeySettings = {
        Title = "OMNI HUB",
        Subtitle = "Key System",
        Note = "No key required",
        FileName = "Key",
        SaveKey = false,
        GrabKeyFromSite = false,
        Key = {"Hello"}
    }
})

-- =====================================================================
-- MAIN TAB
-- =====================================================================
local MainTab = Window:CreateTab("Main", 4483362458)

-- Partner Settings Section
local PartnerSection = MainTab:CreateSection("Partner Settings")

MainTab:CreateInput({
    Name = "Partner Username",
    PlaceholderText = "Enter username...",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        if Text ~= "" then
            CONFIG.PARTNER_NAME = Text
            task.spawn(function() updatePartnerFromUsername(Text) end)
        end
    end
})

MainTab:CreateSlider({
    Name = "Auto Accept Delay",
    Range = {0, 10},
    Increment = 0.5,
    Suffix = "s",
    CurrentValue = CONFIG.AUTO_ACCEPT_DELAY,
    Flag = "AcceptDelay",
    Callback = function(Value)
        CONFIG.AUTO_ACCEPT_DELAY = Value
    end
})

MainTab:CreateSlider({
    Name = "Auto Confirm Delay",
    Range = {0, 10},
    Increment = 0.5,
    Suffix = "s",
    CurrentValue = CONFIG.AUTO_CONFIRM_DELAY,
    Flag = "ConfirmDelay",
    Callback = function(Value)
        CONFIG.AUTO_CONFIRM_DELAY = Value
    end
})

MainTab:CreateSlider({
    Name = "Spectator Count",
    Range = {0, 20},
    Increment = 1,
    Suffix = "",
    CurrentValue = CONFIG.SPECTATOR_COUNT,
    Flag = "SpectatorCount",
    Callback = function(Value)
        CONFIG.SPECTATOR_COUNT = Value
        if mockState.trade then
            mockState.trade.subscriber_count = Value
            pcall(function() TradeApp:_update_spectator_count(mockState.trade) end)
        end
    end
})

-- Trade Controls Section
local TradeSection = MainTab:CreateSection("Trade Controls")

MainTab:CreateButton({
    Name = "▶ Start Trade",
    Callback = function()
        task.spawn(function()
            updatePartnerFromUsername(CONFIG.PARTNER_NAME)
            startMockTradeDirectly()
        end)
    end
})

MainTab:CreateButton({
    Name = "✕ Decline Trade",
    Callback = function()
        if mockState.active then
            TradeApp:_decline_trade()
        end
    end
})

-- Partner Controls Section
local PartnerControlsSection = MainTab:CreateSection("Partner Controls")

MainTab:CreateButton({
    Name = "✔ Partner Accept",
    Callback = doPartnerAccept
})

MainTab:CreateButton({
    Name = "✖ Partner Unaccept",
    Callback = doPartnerUnaccept
})

MainTab:CreateButton({
    Name = "🎲 Add Random High Tier",
    Callback = function()
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
    end
})

-- Utility Section
local UtilitySection = MainTab:CreateSection("Utility")

MainTab:CreateButton({
    Name = "🚫 Block Player",
    Callback = doBlockPlayer
})

-- =====================================================================
-- SPAWN TAB
-- =====================================================================
local SpawnTab = Window:CreateTab("Spawn", 4483362458)

-- Pet Spawner Section
local PetSpawnerSection = SpawnTab:CreateSection("Pet Spawner")

SpawnTab:CreateInput({
    Name = "Pet Name",
    PlaceholderText = "Enter pet name...",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        _G.PetName = Text
    end
})

-- Flags
local flagStates = { F = false, R = false, N = false, M = false }

SpawnTab:CreateToggle({
    Name = "Fly",
    CurrentValue = false,
    Flag = "FlyFlag",
    Callback = function(Value)
        flagStates.F = Value
    end
})

SpawnTab:CreateToggle({
    Name = "Ride",
    CurrentValue = false,
    Flag = "RideFlag",
    Callback = function(Value)
        flagStates.R = Value
    end
})

SpawnTab:CreateToggle({
    Name = "Neon",
    CurrentValue = false,
    Flag = "NeonFlag",
    Callback = function(Value)
        flagStates.N = Value
        if Value then
            flagStates.M = false
        end
    end
})

SpawnTab:CreateToggle({
    Name = "Mega Neon",
    CurrentValue = false,
    Flag = "MegaFlag",
    Callback = function(Value)
        flagStates.M = Value
        if Value then
            flagStates.N = false
        end
    end
})

SpawnTab:CreateButton({
    Name = "🐾 Spawn Pet",
    Callback = function()
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
    end
})

-- Mass Spawn Section
local MassSpawnSection = SpawnTab:CreateSection("Mass Spawn")

SpawnTab:CreateButton({
    Name = "🎯 Spawn All High Tiers",
    Callback = function()
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
    end
})

SpawnTab:CreateButton({
    Name = "🎲 Spawn 50 Random Pets",
    Callback = function()
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
    end
})

-- =====================================================================
-- CHATS TAB
-- =====================================================================
local ChatsTab = Window:CreateTab("Chats", 4483362458)

local ChatMessages = {
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

for _, msg in ipairs(ChatMessages) do
    ChatsTab:CreateButton({
        Name = msg,
        Callback = function()
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
        end
    })
end

-- Custom Chat Section
local CustomChatSection = ChatsTab:CreateSection("Custom Message")

ChatsTab:CreateInput({
    Name = "Custom Message",
    PlaceholderText = "Type your message...",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        _G.CustomChatMessage = Text
    end
})

ChatsTab:CreateButton({
    Name = "📤 Send Custom Chat",
    Callback = function()
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
    end
})

-- =====================================================================
-- SETTINGS TAB
-- =====================================================================
local SettingsTab = Window:CreateTab("Settings", 4483362458)

SettingsTab:CreateLabel("⚙ OMNI HUB Settings")
SettingsTab:CreateLabel("")
SettingsTab:CreateLabel("📊 Status")
SettingsTab:CreateLabel("Trade Active: " .. tostring(mockState.active))
SettingsTab:CreateLabel("Partner: " .. CONFIG.PARTNER_NAME)
SettingsTab:CreateLabel("")
SettingsTab:CreateLabel("⌨ Keybinds")
SettingsTab:CreateLabel("T - Start Trade")
SettingsTab:CreateLabel("Y - Partner Accept")
SettingsTab:CreateLabel("U - Partner Unaccept")
SettingsTab:CreateLabel("P - Add Random High Tier")
SettingsTab:CreateLabel("X - Decline Trade")
SettingsTab:CreateLabel("")

SettingsTab:CreateButton({
    Name = "🔄 Refresh Status",
    Callback = function()
        Rayfield:Notify({
            Title = "OMNI HUB",
            Content = "Trade Active: " .. tostring(mockState.active) .. " | Partner: " .. CONFIG.PARTNER_NAME,
            Duration = 3,
        })
    end
})

-- =====================================================================
-- NOTIFICATION ON LOAD
-- =====================================================================
Rayfield:Notify({
    Title = "OMNI HUB",
    Content = "Loaded successfully! Keybinds: T=Trade, Y=Accept, U=Unaccept, P=Add Pet, X=Decline",
    Duration = 5,
})

print("OMNI HUB loaded successfully!")
print("Keybinds: T=Start Trade, Y=Partner Accept, U=Partner Unaccept, P=Add Random High Tier, X=Decline Trade")
