local _, addon = ...
local L = addon.L
local History, Window = addon.History, addon.Window

local function secret(...)
    return HasAnySecretValues and HasAnySecretValues(...)
end

function Whispr:Command(text)
    text = strtrim(text or "")
    if text == "settings" then
        self:ShowSettings()
    elseif text == "demo" or text == "screenshots" then
        if addon.developmentMode then
            if text == "demo" then
                self:CreateDemoConversation()
            else
                addon.Screenshots:Create()
            end
        end
    elseif text ~= "" then
        local name, draft = addon.Client.ParseCommand(text)
        if name then
            Window:Open(name, draft)
        end
    elseif Window.frame and Window.frame:IsShown() and not Window.closing then
        Window:Close()
    else
        Window:Open()
    end
end

-- Seed directly so testing does not evict real chats or change retention settings.
function Whispr:CreateDemoConversation()
    if not addon.developmentMode then
        return
    end

    local data = self.db.char
    local key = "demo:whispr"
    local created = data.conversations[key] == nil
    local conversation = { key = key, name = L["Whispr Demo"], demo = true, unread = 0, messages = {} }
    local samples = {
        L["Hey! Ready for tonight's dungeon run? :)"],
        L["Almost ready, just sorting my bags."],
        L["Let's meet by the inn in ten minutes."],
        L["Sounds good! I'll bring food and potions."],
        L["That last boss was close! :D"],
        L["Yes! Next time let's clear the adds before we pull, then save our cooldowns for the final phase. That should make things a lot smoother for everyone."],
        L["Taking a quick break. Back in a minute."],
        L["Thanks for the group! See you tomorrow."],
    }

    local now = time()
    for index = 1, 100 do
        data.sequence = data.sequence + 1
        conversation.messages[index] = {
            id = data.sequence,
            text = string.format(L["[%d/100] %s"], index, samples[(index - 1) % #samples + 1]),
            outgoing = index % 3 == 0,
            time = now - math.floor((100 - index) / 23) * 86400 - ((100 - index) % 23) * 120,
        }
    end

    conversation.updated = data.sequence
    data.conversations[key] = conversation
    if created and addon.Extensions then
        addon.Extensions:ConversationEvent("CONVERSATION_CREATED", conversation)
    end

    Window:Open(key)
    -- Let the initial bottom-follow layout finish, then simulate reading just
    -- above three new whispers so the card's unread state remains visible.
    local window = Window.detached and Window.detached[key] or Window
    C_Timer.After(0, function()
        if
            data.conversations[key] ~= conversation
            or window.active ~= key
            or not window.frame
            or not window.frame:IsShown()
        then
            return
        end

        window.following = false
        window.scroll:SetVerticalScroll(math.max(0, window.scroll:GetVerticalScrollRange() - 180))
        conversation.unread = 3
        window.latest:Show()
        window:RefreshList()
        if window.owner then
            window.owner:RefreshList()
        end
    end)
end

function Whispr:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("WhisprSettings", addon.defaults, true)
    addon.Database:MigrateSettings(self.db)
    addon.Locale:Initialize(self.db.global)
    addon.Database:RemoveCharacterLocations(self.db)
    if not addon.developmentMode then
        addon.Database:RemoveDemoConversations(self.db)
    end

    History.RemoveEmpty(self.db.char)
    History.Trim(self.db.char, self.db.global)
    for _, conversation in pairs(self.db.char.conversations) do
        for _, message in ipairs(conversation.messages) do
            if message.pending then
                message.pending = nil
                message.unconfirmed = true
            end
        end
    end

    self:RegisterChatCommand("whispr", function(text)
        self:Command(text)
    end)

    if addon.Extensions then
        addon.Extensions:Initialize()
    end

    addon.Settings:Initialize()
    addon.Media:Initialize()
end

function Whispr:ShowSettings()
    addon.Settings:Show()
end

function Whispr:PlayMessageSound(preview)
    if not preview and self.db.global.notificationSoundEnabled == false then
        return
    end

    PlaySoundFile(addon.Sounds:Path(self.db.global.notificationSound), "Master")
end

function Whispr:OnEnable()
    self.running = true
    if addon.Extensions then
        addon.Extensions:Start()
    end

    if addon.Typing then
        addon.Typing:Enable()
    end

    self:RegisterEvent("PLAYER_LOGOUT", function()
        Window:SaveAllGeometry()
        History.RemoveEmpty(self.db.char)
    end)

    addon.Minimap:Enable()
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        Window:CombatChanged(true)
    end)

    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        Window:CombatChanged(false)
    end)

    self:InstallChatFilters()
    self:RegisterEvent("CHAT_MSG_WHISPER", "Whisper")
    self:RegisterEvent("CHAT_MSG_WHISPER_INFORM", "Whisper")
    self:RegisterEvent("CHAT_MSG_BN_WHISPER", "BattleNetWhisper")
    self:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM", "BattleNetWhisper")
    self:RegisterEvent("CHAT_MSG_AFK", "WhisperStatus")
    self:RegisterEvent("CHAT_MSG_DND", "WhisperStatus")
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, itemID, success)
        local pending = addon.Format.pendingItemColors
        if not pending[itemID] then
            return
        end

        pending[itemID] = nil
        if not success then
            return
        end

        if Window.frame and Window.frame:IsShown() then
            Window:RefreshMessages()
        end

        for _, window in pairs(Window.popouts) do
            if window.frame and window.frame:IsShown() then
                window:RefreshMessages()
            end
        end
    end)

    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD",
        "PLAYER_TARGET_CHANGED",
        "UPDATE_MOUSEOVER_UNIT",
        "GROUP_ROSTER_UPDATE",
        "FRIENDLIST_UPDATE",
        "GUILD_ROSTER_UPDATE",
        "PLAYER_FOCUS_CHANGED",
        "UNIT_LEVEL",
        "UNIT_NAME_UPDATE",
    }) do
        if event == "PLAYER_ENTERING_WORLD" then
            self:RegisterEvent(event, function()
                self:RefreshCharacters()
                Window:RestoreUndocked()
            end)
        else
            self:RegisterEvent(event, "RefreshCharacters")
        end
    end

    self:RefreshCharacters()
    self:HookWhispers()
end

function Whispr:OnDisable()
    if addon.Extensions then
        addon.Extensions:Stop()
    end

    if addon.Typing then
        addon.Typing:Disable()
    end

    self.running = false
    addon.Minimap:Disable()
end

function Whispr:InstallChatFilters()
    if self.filtersInstalled then
        return
    end

    local add = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
    if not add then
        return
    end

    self.filtersInstalled = true

    local function filter(_, event, text, name, ...)
        if self.db.global.suppressWhispers == false then
            return false
        end

        if not self.running or secret(text) or type(text) ~= "string" then
            return false
        end

        if event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
            return addon.BattleNet.Resolve(select(11, ...)) ~= nil
        end

        return not secret(name) and type(name) == "string" and name ~= ""
    end

    for _, event in ipairs({
        "CHAT_MSG_WHISPER",
        "CHAT_MSG_WHISPER_INFORM",
        "CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM",
        "CHAT_MSG_AFK",
        "CHAT_MSG_DND",
    }) do
        add(event, filter)
    end
end

function Whispr:BattleNetWhisper(event, text, name, ...)
    if secret(text) or type(text) ~= "string" then
        return
    end

    local identity = addon.BattleNet.Resolve(select(11, ...))
    if not identity then
        return
    end

    addon.BattleNet.Ensure(identity)
    local outgoing = event == "CHAT_MSG_BN_WHISPER_INFORM"
    if not outgoing and addon.Typing then
        addon.Typing:Clear(identity.key)
    end

    if outgoing then
        self.lastToldWhisper = identity.key
    else
        self.lastWhisper = identity.key
    end

    local confirmed = outgoing and History.Confirm(self.db.char, identity.key, text)
    if not confirmed then
        History.Add(
            self.db.char,
            self.db.global,
            identity.name,
            text,
            outgoing,
            time(),
            Window:IsReading(identity.key),
            identity.key
        )
    end

    if not outgoing and addon.Actions then
        addon.Actions:RememberChat(identity.key, select(9, ...))
    end

    if not outgoing then
        self:PlayMessageSound()
    end

    Window:RefreshCharacters()
    Window:Refresh(identity.key)
    if not outgoing then
        Window:Receive(identity.key)
        if addon.Extensions then
            addon.Extensions:Emit("MESSAGE_RECEIVED", {
                key = identity.key,
                name = identity.name,
                transport = "bnet",
                message = Whispr.db.char.conversations[identity.key].messages[#Whispr.db.char.conversations[identity.key].messages],
            })
        end
    end
end

function Whispr:WhisperStatus(event, text, name)
    if secret(text, name) or type(text) ~= "string" or type(name) ~= "string" then
        return
    end

    local key = History.Key(name)
    local status = event == "CHAT_MSG_AFK" and L["Away"] or L["Do not disturb"]
    local conversation = History.Add(
        self.db.char,
        self.db.global,
        name,
        string.format(L["%s: %s"], status, text),
        false,
        time(),
        Window:IsReading(key)
    )
    if conversation then
        conversation.messages[#conversation.messages].status = status
        addon.Characters.Update(conversation)
        Window:RefreshCharacters()
        Window:Refresh(key)
    end
end

function Whispr:RefreshCharacters()
    if self.charactersPending then
        return
    end

    self.charactersPending = true
    C_Timer.After(0.2, function()
        self.charactersPending = nil
        addon.Characters.RefreshSources(self.db.char)
        Window:RefreshCharacters()
    end)
end

function Whispr:Whisper(event, text, name, ...)
    if secret(text, name) or type(text) ~= "string" or type(name) ~= "string" then
        return
    end

    local key = History.Key(name)
    local outgoing = event == "CHAT_MSG_WHISPER_INFORM"
    if not outgoing and addon.Typing then
        addon.Typing:Clear(key)
    end

    if outgoing then
        self.lastToldWhisper = key
    else
        self.lastWhisper = key
    end

    local conversation = outgoing and History.Confirm(self.db.char, key, text)
    if not conversation then
        conversation = History.Add(self.db.char, self.db.global, name, text, outgoing, time(), Window:IsReading(key))
    end

    if conversation then
        -- Only incoming events identify the remote sender unambiguously.
        local guid = event == "CHAT_MSG_WHISPER" and select(10, ...) or nil
        if not outgoing and addon.Actions then
            addon.Actions:RememberChat(key, select(9, ...))
        end

        if not outgoing then
            self:PlayMessageSound()
        end

        addon.Characters.Update(conversation, guid)
        Window:RefreshCharacters()
        Window:Refresh(key)
        if not outgoing then
            Window:Receive(key)
            if addon.Extensions then
                addon.Extensions:Emit("MESSAGE_RECEIVED", {
                    key = key,
                    name = conversation.name,
                    transport = conversation.transport or "whisper",
                    message = conversation.messages[#conversation.messages],
                })
            end
        end
    end
end

function Whispr:Send(window)
    local targetWindow = window or addon.Window
    local conversation = self.db.char.conversations[targetWindow.active]
    local text = targetWindow.input:GetText()
    if not conversation or not text:find("%S") then
        return
    end

    if conversation.demo then
        self:Print(L["This is a sample conversation. Open a real conversation to send a whisper."])
        return
    end

    text = addon.Format.Outgoing(text)
    if not text then
        self:Print(
            L["This draft contains invalid formatting. Please retype the affected emoji or link. Your draft has been kept."]
        )
        return
    end

    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return
    end

    local dispatch
    if conversation.transport == "bnet" then
        local id = addon.BattleNet.AccountID(conversation)
        local send = C_BattleNet and C_BattleNet.SendWhisper or BNSendWhisper
        if not id or not send then
            self:Print(L["Battle.net is not available for this conversation yet. Your draft has been kept."])
            return
        end

        dispatch = function()
            send(id, text)
        end
    else
        local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
        dispatch = function()
            send(text, "WHISPER", nil, conversation.name)
        end
    end

    History.Add(
        self.db.char,
        self.db.global,
        conversation.name,
        text,
        true,
        time(),
        targetWindow.IsReading and targetWindow:IsReading(conversation.key) or false,
        conversation.key
    )
    local message = conversation.messages[#conversation.messages]
    message.pending = true
    -- Queue the local record before sending: some clients dispatch the echo
    -- synchronously. The echo confirms this record instead of adding a duplicate.
    self.lastToldWhisper = conversation.key
    if addon.Typing then
        addon.Typing:Stop(conversation.key)
    end

    dispatch()
    if addon.Extensions then
        addon.Extensions:Emit("MESSAGE_SENT", {
            key = conversation.key,
            name = conversation.name,
            transport = conversation.transport or "whisper",
            message = message,
        })
    end

    addon.Window:Refresh(conversation.key)
    C_Timer.After(30, function()
        if message.pending then
            message.pending = nil
            message.unconfirmed = true
            if addon.Extensions then
                addon.Extensions:ConversationEvent(
                    "MESSAGE_DELIVERY_CHANGED",
                    conversation,
                    { message = message, status = "unconfirmed" }
                )
            end

            addon.Window:Refresh(conversation.key)
        end
    end)

    targetWindow.input:SetText("")
    targetWindow.drafts[targetWindow.active] = nil
    if addon.Extensions then
        addon.Extensions:ConversationEvent("DRAFT_CHANGED", conversation, { text = "" })
    end

    targetWindow.input:SetFocus()
end

function Whispr:RouteEditBox(editBox)
    if self.routing or not editBox or not editBox.GetAttribute then
        return
    end

    local chatType, target = editBox:GetAttribute("chatType"), editBox:GetAttribute("tellTarget")
    if secret(chatType, target) or (chatType ~= "WHISPER" and chatType ~= "BN_WHISPER") then
        return
    end

    if type(target) ~= "string" and type(target) ~= "number" then
        return
    end

    if target == "" then
        return
    end

    local identity = chatType == "BN_WHISPER" and addon.BattleNet.Resolve(target) or nil
    if chatType == "BN_WHISPER" and not identity then
        return
    end

    if editBox.whisprPending then
        return
    end

    editBox.whisprPending = true
    -- Let the client's parser finish resolving the full character name and
    -- removing /w before transferring the remaining message into our composer.
    C_Timer.After(0, function()
        editBox.whisprPending = nil
        local currentType, currentTarget = editBox:GetAttribute("chatType"), editBox:GetAttribute("tellTarget")
        if secret(currentType, currentTarget) or currentType ~= chatType or currentTarget ~= target then
            return
        end

        local draft = editBox:GetText()
        if secret(draft) then
            return
        end

        self.routing = true
        editBox:SetText("")
        editBox:SetAttribute("chatType", "SAY")
        editBox:SetAttribute("tellTarget", nil)
        if editBox.UpdateHeader then
            editBox:UpdateHeader()
        end

        if ChatFrameUtil and ChatFrameUtil.DeactivateChat then
            ChatFrameUtil.DeactivateChat(editBox)
        elseif ChatEdit_DeactivateChat then
            ChatEdit_DeactivateChat(editBox)
        else
            editBox:ClearFocus()
            editBox:Hide()
        end

        self.routing = false
        if identity then
            addon.BattleNet.Ensure(identity)
            Window:Open(identity.key, draft)
        else
            Window:Open(target, draft)
        end
    end)
end

function Whispr:HookWhispers()
    local function attach(editBox)
        if not editBox then
            return
        end

        if editBox.whisprHooked then
            Whispr:RouteEditBox(editBox)
            return
        end

        editBox.whisprHooked = true
        if editBox.UpdateHeader then
            hooksecurefunc(editBox, "UpdateHeader", function(box)
                Whispr:RouteEditBox(box)
            end)
        end

        Whispr:RouteEditBox(editBox)
    end

    if ChatFrameUtil and ChatFrameUtil.ActivateChat then
        hooksecurefunc(ChatFrameUtil, "ActivateChat", attach)
    end

    if ChatEdit_ActivateChat then
        hooksecurefunc("ChatEdit_ActivateChat", attach)
    end

    if ChatEdit_UpdateHeader then
        hooksecurefunc("ChatEdit_UpdateHeader", function(box)
            self:RouteEditBox(box)
        end)
    end

    for _, name in ipairs(CHAT_FRAMES or {}) do
        attach(_G[name .. "EditBox"])
    end

    -- Context-menu whispers enter the same native edit-box path as /w.
    local function sendTell()
        local box = ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
            or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
        if box then
            attach(box)
            self:RouteEditBox(box)
        end
    end

    if ChatFrameUtil and ChatFrameUtil.SendTell then
        hooksecurefunc(ChatFrameUtil, "SendTell", sendTell)
    end

    if ChatFrame_SendTell then
        hooksecurefunc("ChatFrame_SendTell", sendTell)
    end

    if ChatFrameUtil and ChatFrameUtil.SendBNetTell then
        hooksecurefunc(ChatFrameUtil, "SendBNetTell", sendTell)
    end

    if ChatFrame_SendBNetTell then
        hooksecurefunc("ChatFrame_SendBNetTell", sendTell)
    end

    -- Filtered whispers may never update Blizzard's last-reply target.
    -- Keep session-local targets and use the same handoff when it exists.
    local function openReply(key, message)
        local conversation = self.db.char.conversations[key]
        local draft = not secret(message) and type(message) == "string" and message or nil
        self.replyGeneration = (self.replyGeneration or 0) + 1
        local generation = self.replyGeneration
        -- The binding runs before its key's character event. Focusing an edit
        -- box here would also type that character (e.g. Shift+R becomes "R").
        -- Wait until the next UI tick; never strip letters from a real draft.
        C_Timer.After(0, function()
            if self.running == false or generation ~= self.replyGeneration then
                return
            end

            if conversation and self.db.char.conversations[key] == conversation then
                Window:Open(key, draft)
            end
        end)
    end

    local function reply(sent, message)
        if self.running == false or self.routing then
            return
        end

        local key
        if sent then
            key = self.lastToldWhisper
        else
            key = self.lastWhisper
        end

        local conversation = key and self.db.char.conversations[key]
        local box = ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
            or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
        if box and box.GetAttribute then
            local kind = box:GetAttribute("chatType")
            if not secret(kind) and (kind == "WHISPER" or kind == "BN_WHISPER") then
                if conversation then
                    local bnet = conversation.transport == "bnet"
                    local desired
                    if bnet then
                        desired = addon.BattleNet.AccountID(conversation)
                    else
                        desired = conversation.name
                    end

                    if bnet and not desired then
                        openReply(key, message)
                        return
                    end

                    local desiredType = bnet and "BN_WHISPER" or "WHISPER"
                    local target = box:GetAttribute("tellTarget")
                    if secret(target) or target ~= desired or kind ~= desiredType then
                        box.whisprPending = nil
                        box:SetAttribute("chatType", desiredType)
                        box:SetAttribute("tellTarget", desired)
                    end
                end

                attach(box)
                self:RouteEditBox(box)
                if box.whisprPending then
                    return
                end
            end
        end

        if conversation then
            openReply(key, message)
        end
    end

    if ChatFrameUtil and ChatFrameUtil.ReplyTell then
        hooksecurefunc(ChatFrameUtil, "ReplyTell", function(message)
            reply(false, message)
        end)
    elseif ChatFrame_ReplyTell then
        hooksecurefunc("ChatFrame_ReplyTell", function(message)
            reply(false, message)
        end)
    end

    if ChatFrameUtil and ChatFrameUtil.ReplyTell2 then
        hooksecurefunc(ChatFrameUtil, "ReplyTell2", function(message)
            reply(true, message)
        end)
    elseif ChatFrame_ReplyTell2 then
        hooksecurefunc("ChatFrame_ReplyTell2", function(message)
            reply(true, message)
        end)
    end

    local pendingLink

    local function insertLink(text, source)
        if secret(text) or type(text) ~= "string" or text == "" then
            return
        end

        local input = Window:FocusedInput()
        if not input then
            return
        end

        -- Some clients forward the legacy entry point to the modern one.
        -- Both hooks see that call; insert it only once without replacing
        -- Blizzard functions or affecting their native return values.
        if
            pendingLink
            and pendingLink.input == input
            and pendingLink.text == text
            and pendingLink.source ~= source
            and pendingLink.result == input:GetText()
        then
            return
        end

        input:Insert(text)
        local inserted = { input = input, text = text, source = source, result = input:GetText() }
        pendingLink = inserted
        C_Timer.After(0, function()
            if pendingLink == inserted then
                pendingLink = nil
            end
        end)
    end

    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", function(text)
            insertLink(text, "modern")
        end)
    end

    if ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(text)
            insertLink(text, "legacy")
        end)
    end
end
