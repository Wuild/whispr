local _, addon = ...
local L = addon.L
local UI, History, Format = addon.UI, addon.History, addon.Format
local Window = { rows = {}, bubbles = {}, drafts = {}, following = true, detached = {}, popouts = {} }
local SIDEBAR_WIDTH = 260
addon.Window = Window

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Window:DefaultSeparateSize()
    local profile = Whispr.db.global
    local width = finite(profile.separateWindowWidth) and profile.separateWindowWidth or 550
    local height = finite(profile.separateWindowHeight) and profile.separateWindowHeight or 510
    return math.max(360, math.min(1600, width)), math.max(280, math.min(1200, height))
end

function Window:ApplySeparateSize()
    local width, height = self:DefaultSeparateSize()
    for _, window in pairs(self.popouts or {}) do
        if window.frame and window.frame:IsShown() then
            window:SaveGeometry()
            local record = window:GeometryRecord()
            if record and record.window then
                record.window.width, record.window.height = width, height
                window:RestoreGeometry()
                window:Layout()
                window:RefreshMessages()
                window:SaveGeometry()
            end
        end
    end
end

function Window:UpdateScreenClamping()
    local hub = self.owner or self

    local function update(window)
        if window.frame then
            window:SaveGeometry()
            window.frame:SetClampedToScreen(Whispr.db.global.clampWindowsToScreen ~= false)
            window:RestoreGeometry()
        end
    end

    update(hub)
    for _, window in pairs(hub.popouts or {}) do
        update(window)
    end
end

function Window:GeometryRecord()
    if not self.owner then
        return Whispr.db.char
    end

    return self.geometryKey and Whispr.db.char.conversations[self.geometryKey]
end

function Window:SaveGeometry()
    if not self.geometryReady then
        return
    end

    local record = self:GeometryRecord()
    local x, y = self.frame:GetCenter()
    if not record or not x or not y then
        return
    end

    local ratio = self.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if self.owner and record.undocked then
        record.undockedOpen = self.frame:IsShown() or self.hiddenForCombat == true
    end

    record.window = {
        width = self.frame:GetWidth(),
        height = self.frame:GetHeight(),
        x = (x * ratio - UIParent:GetWidth() / 2) / UIParent:GetWidth(),
        y = (y * ratio - UIParent:GetHeight() / 2) / UIParent:GetHeight(),
    }
end

function Window:RestoreGeometry()
    local record = self:GeometryRecord()
    local saved = record and record.window
    if type(saved) ~= "table" then
        return
    end

    local width = finite(saved.width) and math.max(360, math.min(4000, saved.width)) or self.frame:GetWidth()
    local height = finite(saved.height) and math.max(280, math.min(4000, saved.height)) or self.frame:GetHeight()
    local parentWidth, parentHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local scale = math.min(1, (parentWidth - 40) / width, (parentHeight - 40) / height)
    self.frame:SetSize(width, height)
    self.frame:SetScale(scale)
    local ratio = self.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local maxX = math.max(0, (parentWidth - width * ratio) / 2 - 8)
    local maxY = math.max(0, (parentHeight - height * ratio) / 2 - 8)
    local x = finite(saved.x) and saved.x * parentWidth or 0
    local y = finite(saved.y) and saved.y * parentHeight or 0
    if Whispr.db.global.clampWindowsToScreen ~= false then
        x = math.max(-maxX, math.min(maxX, x))
        y = math.max(-maxY, math.min(maxY, y))
    end

    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", x / ratio, y / ratio)
end

function Window:RestoreUndocked()
    if self.restoredUndocked then
        return
    end

    self.restoredUndocked = true
    local combat = InCombatLockdown and InCombatLockdown()
    local profile = Whispr.db.global
    for _, conversation in ipairs(History.Sorted(Whispr.db.char)) do
        if conversation.undocked and not self.detached[conversation.key] then
            local open = conversation.undockedOpen ~= false
            local combatHidden = open and combat and (profile.hideInCombat or profile.noOpenInCombat)
            self:Detach(conversation.key, nil, true, conversation.undockedStandalone, not open or combatHidden)
            local window = self.detached[conversation.key]
            if combatHidden then
                window.hiddenForCombat = true
                conversation.undockedOpen = true
            end
        end
    end
end

function Window:SaveAllGeometry()
    if self.frame then
        self.frame:StopMovingOrSizing()
        self:SaveGeometry()
    end

    for _, window in pairs(self.popouts or {}) do
        if window.frame then
            window.frame:StopMovingOrSizing()
            window:SaveGeometry()
        end
    end
end

local function setWindowKeyboard(frame, enabled)
    if enabled then
        frame:SetPropagateKeyboardInput(true)
    end

    frame:EnableKeyboard(enabled)
end

-- Only windows hidden by this option are restored when combat ends.
function Window:CombatChanged(inCombat)
    local windows = { self }
    for _, window in pairs(self.popouts or {}) do
        windows[#windows + 1] = window
    end

    for _, window in ipairs(windows) do
        if window.frame then
            setWindowKeyboard(window.frame, not inCombat)
        end

        if not inCombat then
            window.manualCombatOpen = nil
        end

        if inCombat and Whispr.db.global.hideInCombat then
            local typing = Whispr.db.global.dontHideWhenTyping and window.input and window.input:HasFocus()
            if not typing and not window.manualCombatOpen and window.frame and window.frame:IsShown() then
                window.hiddenForCombat = true
                window:HideImmediately()
            end
        elseif window.hiddenForCombat then
            window.hiddenForCombat = nil
            if window.frame then
                window:Show()
            end
        end
    end

    if not inCombat and self.combatMessages then
        local pending = self.combatMessages
        self.combatMessages = nil
        local conversations = History.Sorted(History.DisplayData())
        -- Open oldest first so the newest deferred sender remains selected.
        for index = #conversations, 1, -1 do
            local conversation = conversations[index]
            if pending[conversation.key] and (conversation.unread or 0) > 0 then
                self:Receive(conversation.key)
            end
        end
    end
end

function Window:RefreshUnread()
    local hub = self.owner or self
    local total = 0
    for _, conversation in pairs(History.DisplayData().conversations) do
        total = total + (conversation.unread or 0)
    end

    if addon.Minimap then
        addon.Minimap:UpdateUnread(total)
    end

    if addon.Extensions then
        addon.Extensions:Emit("UNREAD_CHANGED", total)
    end

    if not hub.unreadBadge then
        return
    end

    hub.unreadCount:SetText(total > 99 and "99+" or tostring(total))
    hub.unreadBadge:SetShown(total > 0)
end

function Window:SetDrawer(open)
    local wasShown = self.sidebar:IsShown()
    self.drawerOpen = open and self.compact or false
    self.sidebar:SetShown(not self.owner and (not self.compact or self.drawerOpen))
    self.drawerShade:SetShown(self.drawerOpen)
    if not wasShown and self.sidebar:IsShown() then
        self:QueuePeopleRefresh()
    end
end

function Window:QueuePeopleRefresh()
    if self.peopleRefreshPending then
        return
    end

    self.peopleRefreshPending = true
    C_Timer.After(0, function()
        self.peopleRefreshPending = nil
        if not self.people or not self.sidebar:IsShown() then
            return
        end

        -- Wait for the parent's final resize bounds before refreshing clipping.
        self.people:RefreshContent()
        self:RefreshList()
        self.people:RefreshContent()
    end)
end

-- Window focus persists after leaving the mouse, until another window or the
-- world is clicked. Keyboard focus alone is not a window activation model.
function Window:SetWindowFocus(focused, preserveComposer)
    if focused then
        if not self.frame or not self.frame:IsShown() or self.closing then
            return
        end

        if Window.focusedWindow and Window.focusedWindow ~= self then
            Window.focusedWindow:SetWindowFocus(false)
        end

        local previousInput = Window:FocusedInput()
        if previousInput and previousInput ~= self.input then
            previousInput:ClearFocus()
        end

        Window.focusedWindow = self
        self.focused = true
        self.frame:SetFrameStrata("DIALOG")
        self.frame:Raise()
    else
        self.focused = nil
        if self.frame then
            self.frame:SetFrameStrata("LOW")
        end

        if Window.focusedWindow == self then
            Window.focusedWindow = nil
        end

        if self.input and not preserveComposer then
            self.input:ClearFocus()
        end

        if addon.Selection then
            addon.Selection.Clear(self)
        end
    end

    self:UpdateBorder()
    if self.frame and self.frame:IsShown() then
        self:UpdateOpacity()
    end
end

function Window:Escape()
    if self.url and self.url:IsShown() then
        self.url:Hide()
        return
    end

    if self.info and self.info:IsShown() then
        self.info:Hide()
        return
    end

    if self.emotePicker and self.emotePicker:IsShown() then
        self.emotePicker:Hide()
        return
    end

    if self.messageSelection and addon.Selection then
        addon.Selection.Clear(self)
        return
    end

    if self.drawerOpen then
        self:SetDrawer(false)
        return
    end

    self:Close()
end

function Window:InstallWindowFocus()
    self.frame.whisprController = self
    -- Outside combat, visible windows receive Escape even after clicking back into the world.
    -- Frame stacking determines which window receives it first; consume it so
    -- a single press cannot also close windows underneath this one.
    self.frame:SetScript("OnKeyDown", function(frame, key)
        if InCombatLockdown and InCombatLockdown() then
            return
        end

        local handled = key == "ESCAPE"
        frame:SetPropagateKeyboardInput(not handled)
        if handled then
            if not self.closing then
                self:Escape()
            end

            -- Closing/releasing focus must not let this same key reach the
            -- game's CloseSpecialWindows handler and dismiss unrelated UI.
            frame:SetPropagateKeyboardInput(false)
        end
    end)

    -- Combat locks propagation, which can still be disabled from the last Escape.
    setWindowKeyboard(self.frame, not (InCombatLockdown and InCombatLockdown()))

    if Window.focusEvents then
        return
    end

    local events = CreateFrame("Frame")
    Window.focusEvents = events
    events:RegisterEvent("GLOBAL_MOUSE_DOWN")
    events:SetScript("OnEvent", function()
        local target
        if GetMouseFoci then
            target = GetMouseFoci()[1]
        elseif GetMouseFocus then
            target = GetMouseFocus()
        end

        if not GetMouseFoci and not GetMouseFocus then
            return
        end

        while target do
            if target.whisprController then
                target.whisprController:SetWindowFocus(true)
                return
            end

            target = target.GetParent and target:GetParent()
        end

        -- A shift-click on a spell, talent or item produces its link after
        -- GLOBAL_MOUSE_DOWN. Lower the window but keep the insertion target.
        local preserveComposer = IsModifiedClick and IsModifiedClick("CHATLINK")
        if Window.focusedWindow then
            Window.focusedWindow:SetWindowFocus(false, preserveComposer)
        elseif not preserveComposer then
            local input = Window:FocusedInput()
            if input then
                input:ClearFocus()
            end
        end
    end)
end

function Window:AnimateOpacity(opacity, duration)
    if self.opacityTarget == opacity and not (self.fade and Whispr.db.global.animateWindows == false) then
        return
    end

    self.opacityTarget = opacity
    if Whispr.db.global.animateWindows == false then
        self.fade = nil
        self.visualAlpha = opacity
        self.frame:SetAlpha(opacity)
    else
        self.fade = { from = self.visualAlpha or 1, to = opacity, start = GetTime(), duration = duration }
    end
end

function Window:StepAnimation()
    local fade = self.fade
    if not fade then
        return
    end

    local progress = math.min(1, math.max(0, (GetTime() - fade.start) / fade.duration))
    local eased = 1 - (1 - progress) ^ 3
    self.visualAlpha = progress == 1 and fade.to or (fade.from + (fade.to - fade.from) * eased)
    self.frame:SetAlpha(self.visualAlpha)
    if progress == 1 then
        self.fade = nil
        if self.closing then
            self:HideImmediately()
        end
    end
end

function Window:Show()
    if not self.owner and Whispr.db.global.separateWindows then
        return
    end

    if self.closing then
        self.closing = nil
        self.opacityTarget = nil
        self:UpdateOpacity(true)
    end

    self.frame:Show()
end

function Window:HideImmediately()
    if self.frame then
        self.hideFrame(self.frame)
    end
end

function Window:Close()
    if not self.frame or not self.frame:IsShown() or self.closing then
        return
    end

    self:SetWindowFocus(false)
    if Whispr.db.global.animateWindows == false then
        self:HideImmediately()
        return
    end

    self.closing = true
    self:AnimateOpacity(0, 0.14)
end

function Window:UpdateTheme()
    addon.Theme:StyleWindow(self)
    self:UpdateBorder()
    if self.geometryReady then
        self:Layout()
    end
end

function Window:UpdateBorder()
    if not self.focusBorder then
        return
    end

    self.focusBorder:SetShown(self.frame:IsShown() and not self.themeHidesBorder)
    local key = self.focused and "focusedBorderColor" or "unfocusedBorderColor"
    local color = Whispr.db.global[key] or addon.Theme.defaults[key]
    for _, edge in ipairs(self.focusBorder.edges) do
        edge:SetColorTexture(color[1], color[2], color[3], 1)
    end
end

function Window:UpdateOpacity(justOpened)
    if not self.frame then
        return
    end

    if self.closing then
        return
    end

    local profile = Whispr.db.global
    self:UpdateBorder()
    -- Keep appearance previews readable in either settings window.
    local settingsOpen = (addon.Settings and addon.Settings:IsShown())
        or (SettingsPanel and SettingsPanel:IsShown())
        or (InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown())
    local active = settingsOpen
        or self.focused
        or self.frame:IsMouseOver()
        or (self.input and self.input:HasFocus())
        or (self.copyBridge and self.copyBridge:HasFocus())
        or (self.url and self.url:IsShown() and self.url.input:HasFocus())
        or (self.emotePicker and self.emotePicker:IsShown() and self.emotePicker:IsMouseOver())
    local opacity = profile.windowOpacity or 1
    local now = GetTime()
    if justOpened then
        self.idleSince = now
    end

    if active or not profile.fadeWhenIdle then
        self.idleSince = nil
    else
        self.idleSince = self.idleSince or now
        if not justOpened and now - self.idleSince >= (profile.idleFadeDelay or 4) then
            opacity = math.min(opacity, profile.idleOpacity or 0.35)
        end
    end

    self:AnimateOpacity(opacity, justOpened and 0.18 or (active and 0.12 or 0.3))
end

function Window:Layout()
    if addon.Info then
        addon.Info.Layout(self)
    end

    local width = self.frame:GetWidth()
    self.compact = not self.owner and width < 680
    local innerLeft = self.themeContentLeft or 0
    local innerRight = self.themeContentRight or 0
    local innerBottom = self.themeContentBottom or 0
    local sidebarWidth = not self.owner and not self.compact and SIDEBAR_WIDTH or 0
    local left = innerLeft + sidebarWidth
    local contentWidth = width - left - innerRight
    local top = self.themeContentTop or 39
    local portraitInset = sidebarWidth == 0 and (self.themePortraitInset or 0) or 0
    self.sidebar:ClearAllPoints()
    self.sidebar:SetPoint("TOPLEFT", innerLeft, -top)
    self.sidebar:SetPoint("BOTTOMLEFT", innerLeft, innerBottom)
    self.drawerShade:ClearAllPoints()
    self.drawerShade:SetPoint("TOPLEFT", math.max(1, innerLeft), -top)
    self.drawerShade:SetPoint("BOTTOMRIGHT", -math.max(1, innerRight), math.max(1, innerBottom))
    local searchInset = self.themeSearchInset or 0
    self.search:SetTextInsets(32 + searchInset, 30, 0, 0)
    self.searchIcon:ClearAllPoints()
    self.searchIcon:SetPoint("LEFT", 10 + searchInset, 0)
    self.searchPlaceholder:ClearAllPoints()
    self.searchPlaceholder:SetPoint("LEFT", 32 + searchInset, 0)
    local composerHeight = math.max(48, (Whispr.db.global.chatFontSize or 14) + 24)
    self.input:SetHeight(composerHeight)
    if self.input.RefreshFormatting then
        self.input:RefreshFormatting()
    end

    self.footer:ClearAllPoints()
    self.footer:SetPoint("BOTTOMLEFT", math.max(1, left), math.max(1, innerBottom))
    self.footer:SetPoint("BOTTOMRIGHT", -math.max(1, innerRight), math.max(1, innerBottom))
    self.footer:SetHeight(composerHeight + 1)
    self.drawerToggle:SetShown(self.compact)
    self.brandIcon:ClearAllPoints()
    self.brandIcon:SetPoint("LEFT", self.compact and 46 or 12, 0)
    self.brand:ClearAllPoints()
    self.brand:SetPoint("LEFT", self.brandIcon, "RIGHT", 7, 0)
    self:SetDrawer(self.drawerOpen)
    self.conversationBand:ClearAllPoints()
    self.conversationBand:SetPoint("TOPLEFT", math.max(1, left), -top)
    self.conversationBand:SetPoint("TOPRIGHT", -math.max(1, innerRight), -top)
    self.pop:ClearAllPoints()
    self.pop:SetPoint("TOPRIGHT", -10 - innerRight, -top - 10)
    self.headerAvatar:ClearAllPoints()
    self.headerAvatar:SetPoint("TOPLEFT", left + 10 + portraitInset, -top - 9)
    self.header:ClearAllPoints()
    self.header:SetPoint("TOPLEFT", left + 46 + portraitInset, -top - 7)
    self.header:SetWidth(contentWidth - portraitInset - 184)
    self.subtitle:ClearAllPoints()
    self.subtitle:SetPoint("TOPLEFT", left + 46 + portraitInset, -top - 25)
    self.subtitle:SetWidth(contentWidth - portraitInset - 184)
    self.divider:ClearAllPoints()
    self.divider:SetPoint("TOPLEFT", left, -top - 44)
    self.divider:SetPoint("TOPRIGHT", -math.max(1, innerRight), -top - 44)
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", left + 4, -top - 49)
    self.scroll:SetPoint("BOTTOMRIGHT", -12 - innerRight, composerHeight + 8 + innerBottom)
    self.input:ClearAllPoints()
    self.input:SetPoint("BOTTOMLEFT", math.max(1, left), math.max(1, innerBottom))
    self.input:SetWidth(width - math.max(1, left) - math.max(1, innerRight))
    self.placeholder:SetWidth(contentWidth - 80)
    if self.url then
        self.url:SetWidth(math.min(420, width - 24))
        self.url.input:SetWidth(self.url:GetWidth() - 32)
        self.url.title:SetWidth(self.url:GetWidth() - 106)
        self.url.subtitle:SetWidth(self.url:GetWidth() - 94)
    end

    if self.themeSkin and self.themeSkin.LayoutWindow then
        self.themeSkin:LayoutWindow(self)
    end

    self.emptyTitle:SetWidth(contentWidth - 28)
    self.emptyTitle:SetJustifyH("CENTER")
    self.empty:SetWidth(math.min(340, contentWidth - 28))
end

function Window:ConfirmAction(action, key)
    local conversation = History.Get(key)
    if not conversation then
        return
    end

    if action ~= "delete" then
        return
    end

    StaticPopupDialogs.WHISPR_CONVERSATION_ACTION = StaticPopupDialogs.WHISPR_CONVERSATION_ACTION
        or {
            text = "%s",
            button1 = ACCEPT,
            button2 = CANCEL,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(_, data)
                if
                    History.Identity(data.key) ~= data.conversation
                    or (Whispr.db.global.showAllCharacters == true) ~= data.allCharacters
                then
                    return
                end

                data.window:Delete(data.key)
            end,
        }

    local question = string.format(
        Whispr.db.global.showAllCharacters
                and L["Delete the conversation with %s from all characters? This removes all of its saved messages."]
            or L["Delete the conversation with %s? This removes its saved messages."],
        conversation.name
    )
    StaticPopup_Show("WHISPR_CONVERSATION_ACTION", question, nil, {
        window = self,
        key = key,
        conversation = History.Identity(key),
        action = action,
        allCharacters = Whispr.db.global.showAllCharacters == true,
    })
end

function Window:IsReading(key)
    if self.detached and self.detached[key] then
        return self.detached[key]:IsReading(key)
    end

    return self.frame and self.frame:IsShown() and not self.closing and self.active == key and self.following
end

function Window:MarkRead()
    if not self.frame or not self.frame:IsShown() or self.closing or not self.following then
        return
    end

    local conversation = History.Get(self.active)
    if not conversation or (conversation.unread or 0) == 0 then
        return
    end

    History.MarkRead(self.active)
    self:RefreshList()
    if self.owner then
        self.owner:RefreshList()
    end
end

function Window:Latest()
    self.following = true
    self.scroll:SetVerticalScroll(self.scroll:GetVerticalScrollRange())
    self:MarkRead()
    self.latest:Hide()
    self:RefreshList()
end

function Window:Open(name, draft, noFocus)
    local inCombat = InCombatLockdown and InCombatLockdown()
    if noFocus and Whispr.db.global.hideInCombat and inCombat then
        return
    end

    if not self.owner and Whispr.db.global.separateWindows then
        if self.frame then
            self:HideImmediately()
        end

        if not name then
            addon.Minimap:Menu(addon.Minimap.button or UIParent, true)
            return
        end
    end

    if name and self.detached then
        local key = History.Key(name)
        if self.detached[key] then
            self.detached[key]:Open(name, draft, noFocus)
            return
        end

        if Whispr.db.global.separateWindows then
            self:Detach(name, draft, noFocus, true)
            return
        end
    end

    self:Create()
    if not noFocus then
        self.manualCombatOpen = inCombat or nil
        self.hiddenForCombat = nil
    end

    self:Show()
    if not noFocus then
        self:SetWindowFocus(true)
    end

    if name then
        local key = History.Key(name)
        if key == "" then
            return
        end

        History.EnsureCurrent(key)
        if not Whispr.db.char.conversations[key] then
            local data = Whispr.db.char
            data.sequence = data.sequence + 1
            data.conversations[key] = { key = key, name = name, updated = data.sequence, unread = 0, messages = {} }
            History.Trim(data, Whispr.db.global)
            if addon.Extensions then
                addon.Extensions:ConversationEvent("CONVERSATION_CREATED", data.conversations[key])
            end
        end

        self:Select(key)
        if draft and draft ~= "" then
            self.input:Insert(draft)
        end

        if not noFocus then
            self.input:SetFocus()
        end
    else
        local first
        for _, conversation in ipairs(History.Sorted(History.DisplayData())) do
            if not self.detached or not self.detached[conversation.key] then
                first = conversation
                break
            end
        end

        self:Select(self.active or (first and first.key))
    end
end

function Window:Receive(key)
    if (Whispr.db.global.hideInCombat or Whispr.db.global.noOpenInCombat) and InCombatLockdown() then
        self.combatMessages = self.combatMessages or {}
        self.combatMessages[key] = true
        return
    end

    local detached = self.detached[key]
    local profile = Whispr.db.global
    if profile.autoOpenConversations == false then
        local target = detached or (not profile.separateWindows and self)
        if not target or not target.frame or not target.frame:IsShown() or target.closing then
            return
        end
    end

    if detached then
        detached:Show()
        detached.frame:Raise()
        detached:UpdateOpacity(true)
    elseif Whispr.db.global.separateWindows then
        self:Open(key, nil, true)
    else
        self:Create()
        self:Show()
        if self.active and self.active ~= key then
            local typing = self.input:HasFocus()
            if profile.autoSelectIncoming == false or typing then
                return
            end
        end

        if self.active ~= key then
            -- Save the old draft through Select, but do not leave the keyboard
            -- aimed at a different recipient mid-sentence.
            self.input:ClearFocus()
            self:Select(key)
        end

        self:SetDrawer(false)
        self.frame:Raise()
        self:UpdateOpacity(true)
    end
end

function Window:SetSeparateMode(enabled)
    Whispr.db.global.separateWindows = enabled
    if enabled then
        local key = self.active
        local shown = self.frame and self.frame:IsShown()
        if self.frame then
            self:HideImmediately()
        end

        self.hiddenForCombat = nil
        if shown and key then
            self:Detach(key, nil, true, true)
        end
    else
        local selected
        for key, window in pairs(self.detached) do
            if window.standalone then
                if window.frame and window.frame:IsShown() then
                    selected = selected or key
                end

                self.drafts[key] = window.input:GetText()
                window:HideImmediately()
                window.hiddenForCombat = nil
                window.standalone = nil
                self.detached[key] = nil
                local record = Whispr.db.char.conversations[key]
                if record then
                    record.undocked, record.undockedOpen, record.undockedStandalone = nil, nil, nil
                end
            end
        end

        self:Open(selected)
    end
end

function Window:Detach(name, draft, noFocus, standalone, restoreHidden)
    local key = History.Key(name)
    if key == "" then
        return
    end

    local window = self.detached[key] or self.popouts[key]
    if not window then
        window = setmetatable({ rows = {}, bubbles = {}, drafts = {}, following = true, owner = self }, {
            -- Controllers share methods, never the hub's frames or selection.
            __index = function(_, method)
                if type(Window[method]) == "function" then
                    return Window[method]
                end
            end,
        })

        self.popouts[key] = window
    end

    window.standalone = standalone or nil
    self.detached[key] = window
    window.geometryKey = key
    local record = History.EnsureCurrent(key)
    if record then
        record.undocked, record.undockedStandalone = true, standalone == true
    end

    if self.active == key then
        window.drafts[key] = self.input:GetText()
        local sorted, nextKey, removedIndex = History.Sorted(History.DisplayData()), nil, 0
        for index, conversation in ipairs(sorted) do
            if conversation.key == key then
                removedIndex = index
                break
            end
        end

        for index = removedIndex + 1, #sorted do
            if not self.detached[sorted[index].key] then
                nextKey = sorted[index].key
                break
            end
        end

        if not nextKey then
            for index = removedIndex - 1, 1, -1 do
                if not self.detached[sorted[index].key] then
                    nextKey = sorted[index].key
                    break
                end
            end
        end

        self.input:ClearFocus()
        self:Select(nextKey)
        self.drafts[key] = nil
    elseif self.drafts[key] then
        window.drafts[key] = self.drafts[key]
        self.drafts[key] = nil
    end

    -- A reused popout must not overwrite the newly transferred draft with the
    -- text it held before it was docked.
    window.active = nil
    if restoreHidden then
        window:Create()
        window:Select(key)
        window:HideImmediately()
    else
        window:Open(name, draft, noFocus)
    end

    record = Whispr.db.char.conversations[key]
    if record then
        record.undocked, record.undockedStandalone = true, standalone == true
    end

    if window.frame then
        window:SaveGeometry()
    end

    self:RefreshList()
end

function Window:Dock()
    if Whispr.db.global.separateWindows then
        return
    end

    local owner, key = self.owner, self.active
    local conversation = History.Get(key)
    if not owner or not conversation then
        return
    end

    owner.drafts[key] = self.input:GetText()
    self:HideImmediately()
    owner.detached[key] = nil
    local record = Whispr.db.char.conversations[key]
    if record then
        record.undocked, record.undockedOpen, record.undockedStandalone = nil, nil, nil
    end

    owner:Create()
    owner:Show()
    owner:Select(key)
    owner.input:SetFocus()
end

function Window:FocusedInput()
    if self.input and self.input:HasFocus() then
        return self.input
    end

    for _, window in pairs(self.detached or {}) do
        if window.input and window.input:HasFocus() then
            return window.input
        end
    end
end

function Window:Select(key)
    self.demoTypingKey, self.demoTypingUntil = nil, nil
    if addon.Typing then
        addon.Typing:Stop(self.active)
    end

    if addon.Selection then
        addon.Selection.Clear(self)
    end

    if self.emotePicker then
        self.emotePicker:Hide()
    end

    if key and self.detached and self.detached[key] then
        local conversation = History.Get(key)
        if conversation then
            self.detached[key]:Open(conversation.key)
        end

        return
    end

    if self.active then
        self.drafts[self.active] = self.input:GetText()
    end

    self:ReleaseMessageFrames()
    self.messageRows = nil
    if key then
        History.EnsureCurrent(key)
    end

    self.active = key
    self.firstMessageID = nil
    self.following = true
    self.input:SetText(self.drafts[key] or "")
    local conversation = History.Get(key)
    self:MarkRead()
    addon.Characters.Update(key and Whispr.db.char.conversations[key])
    self.header:SetText(conversation and conversation.name or L["Your whispers"])
    self.subtitle:SetText(conversation and L["Private conversation"] or L["A little closer, even in Azeroth."])
    self.placeholder:SetText(
        conversation and string.format(L["Message %s..."], conversation.name) or L["Choose a conversation"]
    )
    self.input:SetEnabled(conversation ~= nil)
    self.emoteButton:SetEnabled(conversation ~= nil)
    self:RefreshIdentity()
    self:RefreshList()
    self:RefreshMessages(true)
    if conversation and addon.Extensions then
        addon.Extensions:Emit("CONVERSATION_OPENED", {
            key = key,
            name = conversation.name,
            transport = conversation.transport or "whisper",
        })
    end
end

function Window:RefreshIdentity()
    if not self.frame then
        return
    end

    local conversation = History.Get(self.active)
    local details = addon.Characters.Label(conversation)
    local color = addon.Characters.Color(conversation)
    if color and details ~= "" then
        details = string.format(
            "|cff%02x%02x%02x%s|r",
            math.floor(color.r * 255 + 0.5),
            math.floor(color.g * 255 + 0.5),
            math.floor(color.b * 255 + 0.5),
            details
        )
    end

    local guild = conversation and conversation.character and conversation.character.guild
    if guild then
        details = details .. (details ~= "" and "  ·  " or "") .. "|cff40ff40<" .. guild .. ">|r"
    end

    self.subtitle:SetText(
        details ~= "" and details or (conversation and L["Private conversation"] or L["Your conversations, together."])
    )
    self.headerAvatar:SetCharacter(conversation)
    self:RefreshHeaderActions()
end

function Window:RefreshHeaderActions()
    if not self.headerActions then
        return
    end

    local conversation = History.Get(self.active)
    local entries = {}
    for _, entry in ipairs(addon.Actions:Entries(conversation)) do
        entries[entry.key] = entry
    end

    for key, button in pairs(self.headerActions) do
        local entry = entries[key]
        button:SetShown(conversation ~= nil)
        button:SetEnabled(entry ~= nil and entry.enabled)
        if entry then
            button:SetIcon(key, entry.label)
        end
    end
end

function Window:Delete(key)
    local removed = History.Get(key)
    local hub = self.owner or self
    hub:Dismiss(key)
    History.Delete(key)
    hub.drafts[key] = nil
    local popout = hub.popouts[key]
    if popout then
        popout.drafts[key] = nil
    end

    hub:RefreshCharacters()
    if addon.Extensions then
        addon.Extensions:ConversationEvent("CONVERSATION_DELETED", removed)
    end
end

function Window:Dismiss(key)
    local popout = self.detached[key]
    if self.frame and (self.active == key or (not self.active and popout)) then
        local sorted = History.Sorted(History.DisplayData())
        local removedIndex = 0
        for index, conversation in ipairs(sorted) do
            if conversation.key == key then
                removedIndex = index
                break
            end
        end

        local nextKey

        local function available(index)
            local candidate = sorted[index]
            return candidate and candidate.key ~= key and not self.detached[candidate.key] and candidate.key
        end

        for index = removedIndex + 1, #sorted do
            nextKey = available(index)
            if nextKey then
                break
            end
        end

        if not nextKey then
            for index = removedIndex - 1, 1, -1 do
                nextKey = available(index)
                if nextKey then
                    break
                end
            end
        end

        self.input:ClearFocus()
        self:Select(nextKey)
    end

    if popout then
        popout:Select(nil)
        popout:HideImmediately()
        self.detached[key] = nil
    end
end

function Window:RefreshCharacters()
    self:RefreshList()
    self:RefreshIdentity()
    for _, window in pairs(self.detached or {}) do
        window:RefreshCharacters()
    end
end

function Window:LayoutPeople()
    if not self.people or self.peopleLayout then
        return
    end

    self.peopleLayout = true
    local range = math.max(0, self.people.content:GetHeight() - self.people:GetHeight())
    local gutter = range > 1 and 7 or 0
    local width = self.sidebar:GetWidth() - gutter
    -- Keep the viewport fixed. Reanchoring it from its own size/range callbacks
    -- invalidates the scroll-child rectangle while the client is laying it out.
    -- Only rows reserve room for the thumb when the list actually overflows.
    if self.people:GetVerticalScroll() > range then
        self.people:SetVerticalScroll(range)
    end

    for _, row in ipairs(self.rows) do
        row:SetWidth(width)
        local conversation = History.Get(row.key)
        row.title:SetWidth(
            width
                - 56
                - (conversation and conversation.unread > 0 and 26 or 0)
                - (conversation and conversation.pinned and 18 or 0)
        )
        row.details:SetWidth(width - 56)
        row.preview:SetWidth(width - 56)
    end

    self.peopleLayout = nil
end

function Window:ConversationMenu(button, key)
    if addon.Actions:OpenPlayerMenu(key, function(menu)
        self:AddConversationMenuEntries(menu, key)
    end) then
        return
    end

    MenuUtil.CreateContextMenu(button, function(_, menu)
        self:AddConversationMenuEntries(menu, key, true)
    end)
end

function Window:AddConversationMenuEntries(menu, key, includePlayerActions)
    local conversation = History.Get(key)
    if not Whispr.db.global.separateWindows then
        local label = self.owner and L["Dock in main window"] or L["Open in separate window"]

        local function moveConversation()
            if self.owner then
                self:Dock()
            elseif History.Get(key) then
                self:Detach(key)
            end
        end

        local move
        if not includePlayerActions and menu.Insert and MenuUtil.CreateButton then
            -- Native player menus start with the character title. Put our
            -- window action directly beneath it, ahead of player interactions.
            move = MenuUtil.CreateButton(label, moveConversation)
            menu:Insert(move, 2)
        else
            move = menu:CreateButton(label, moveConversation)
        end

        move:SetEnabled(conversation ~= nil)
    end

    if conversation then
        menu:CreateButton(conversation.pinned and L["Unpin conversation"] or L["Pin conversation"], function()
            local current = History.EnsureCurrent(key)
            current.pinned = not conversation.pinned or nil
            History.Invalidate()
            local hub = self.owner or self
            hub:RefreshList()
        end)

        if includePlayerActions then
            menu:CreateDivider()
            addon.Actions:AddMenu(menu, History.EnsureCurrent(key))
        end

        menu:CreateDivider()
        menu:CreateButton(L["Delete conversation"], function()
            self:ConfirmAction("delete", conversation.key)
        end)
    end

    menu:CreateDivider()
    menu:CreateButton(L["Close window"], function()
        self:Close()
    end)
end

function Window:UpdateCardTyping(row, conversation)
    if Whispr.db.global.showMessagePreviews == false then
        return
    end

    local text = row.lastMessagePreview or L["New conversation"]
    if self:HasTypingIndicator(conversation.key) then
        local animated = conversation.demo or Whispr.db.global.animateWindows ~= false
        local dots = animated and (math.floor(GetTime() / 0.4) % 3 + 1) or 3
        text = string.format(L["Typing%s"], string.rep(".", dots))
    end

    if row.preview:GetText() ~= text then
        row.preview:SetText(text)
    end
end

function Window:RefreshList()
    self:RefreshUnread()
    if not self.frame then
        return
    end

    local sorted = {}
    local detached = (self.owner or self).detached or {}
    for _, conversation in ipairs(History.Sorted(History.DisplayData(), self.conversationQuery)) do
        if not detached[conversation.key] then
            sorted[#sorted + 1] = conversation
        end
    end

    local showPreviews = Whispr.db.global.showMessagePreviews ~= false
    local rowHeight = showPreviews and 60 or 44
    for index, conversation in ipairs(sorted) do
        local row = self.rows[index]
        if not row then
            row = CreateFrame("Button", nil, self.people.content)
            row:SetSize(SIDEBAR_WIDTH, 60)
            row.background = row:CreateTexture(nil, "BACKGROUND", nil, -1)
            row.background:SetPoint("TOPLEFT")
            row.background:SetPoint("BOTTOMRIGHT", 0, 1)
            row.background:SetColorTexture(0.12, 0.14, 0.16, 1)
            if addon.Theme then
                addon.Theme:Paint(row.background, "conversationColor")
            end

            row.selected = UI.Background(row, 0.15, 0.21, 0.25)
            if addon.Theme then
                addon.Theme:Paint(row.selected, "selectedColor")
            end

            row.avatar = UI.Avatar(row, 34)
            row.avatar:SetPoint("TOPLEFT", 6, -6)
            row.unreadIndicator = CreateFrame("Frame", nil, row.avatar)
            row.unreadIndicator:SetSize(12, 16)
            row.unreadIndicator:SetPoint("TOPRIGHT", 4, 4)
            UI.Round(row.unreadIndicator, 4, 0.95, 0.66, 0.20)
            row.unreadIndicator.label = UI.Text(row.unreadIndicator, "!", "GameFontNormal")
            row.unreadIndicator.label:SetPoint("CENTER")
            row.unreadIndicator.label:SetTextColor(0.12, 0.10, 0.06)
            row:SetScript("OnEnter", function(button)
                if button.key ~= self.active then
                    if addon.Theme then
                        addon.Theme:Paint(button.selected, "selectedColor", true)
                    else
                        button.selected:SetColorTexture(0.13, 0.16, 0.18)
                    end

                    button.selected:SetShown(true)
                end
            end)

            row:SetScript("OnLeave", function(button)
                if addon.Theme then
                    addon.Theme:Paint(button.selected, "selectedColor")
                else
                    button.selected:SetColorTexture(0.15, 0.21, 0.25)
                end

                button.selected:SetShown(button.key == self.active)
            end)

            row.title = UI.Text(row, "", "GameFontNormal")
            row.title:SetPoint("TOPLEFT", 48, -7)
            row.title:SetWidth(134)
            row.title:SetWordWrap(false)
            row.pin = row:CreateTexture(nil, "OVERLAY")
            row.pin:SetTexture("Interface\\AddOns\\Whispr\\assets\\icons\\pin.tga")
            row.pin:SetSize(14, 14)
            row.pin:SetVertexColor(unpack(UI.colors.muted))
            row.preview = UI.Text(row, "", "GameFontHighlightSmall")
            row.preview:SetPoint("TOPLEFT", 48, -39)
            row.preview:SetWidth(160)
            row.preview:SetTextColor(unpack(UI.colors.muted))
            row.preview:SetWordWrap(false)
            row.details = UI.Text(row, "", "GameFontHighlightSmall")
            row.details:SetPoint("TOPLEFT", 48, -23)
            row.details:SetWidth(160)
            row.details:SetWordWrap(false)
            row.badge = CreateFrame("Frame", nil, row)
            row.badge:SetSize(22, 20)
            row.badge:SetPoint("TOPRIGHT", -8, -12)
            local badgeSurface = UI.Round(row.badge, 10, unpack(UI.colors.accent))
            if addon.Theme then
                addon.Theme:Paint(badgeSurface, "accentColor")
            end

            row.count = UI.Text(row.badge, "", "GameFontHighlightSmall")
            row.count:SetPoint("CENTER")
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(button, mouseButton)
                if mouseButton == "RightButton" then
                    self:ConversationMenu(button, button.key)
                    return
                end

                self:SetDrawer(false)
                if self.detached and (self.detached[button.key] or Whispr.db.global.separateWindows) then
                    self:Open(button.key)
                else
                    self:Select(button.key)
                    self.input:SetFocus()
                end
            end)

            self.rows[index] = row
        end

        row.key = conversation.key
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
        row.title:SetText(conversation.name)
        row.pin:ClearAllPoints()
        row.pin:SetPoint("TOPRIGHT", conversation.unread > 0 and -36 or -10, -8)
        row.pin:SetShown(conversation.pinned == true)
        row.avatar:SetCharacter(conversation)
        local details = addon.Characters.Label(conversation)
        row.details:SetText(details)
        local color = addon.Characters.Color(conversation)
        if color then
            row.details:SetTextColor(color.r, color.g, color.b)
        else
            row.details:SetTextColor(unpack(UI.colors.muted))
        end

        row.preview:ClearAllPoints()
        row.preview:SetPoint("TOPLEFT", 48, details ~= "" and -39 or -26)
        row.title:SetWidth(conversation.unread > 0 and 134 or 160)
        row.badge:SetShown(conversation.unread > 0)
        row.unreadIndicator:SetShown(conversation.unread > 0)
        local last = conversation.messages[#conversation.messages]
        row.preview:SetShown(showPreviews)
        row.lastMessagePreview = last
                and (last.outgoing and string.format(L["You: %s"], Format.Preview(last.text)) or Format.Preview(
                    last.text
                ))
            or L["New conversation"]
        if showPreviews then
            self:UpdateCardTyping(row, conversation)
        else
            row.preview:SetText("")
        end

        row.count:SetText(
            conversation.unread > 0 and (conversation.unread > 99 and "99+" or tostring(conversation.unread)) or ""
        )
        row.selected:SetShown(self.active == conversation.key)
        row:Show()
    end

    for index = #sorted + 1, #self.rows do
        self.rows[index]:Hide()
    end

    self.people.content:SetHeight(math.max(1, #sorted * rowHeight))
    if self.searchEmpty then
        self.searchEmpty:SetShown(self.conversationQuery ~= nil and self.conversationQuery ~= "" and #sorted == 0)
    end

    self:LayoutPeople()
end

function Window:ShowCopyText(value, caption)
    if not self.url then
        local shade = CreateFrame("Button", nil, self.frame)
        shade:SetAllPoints()
        shade:SetFrameLevel(self.frame:GetFrameLevel() + 60)
        UI.Background(shade, 0, 0, 0, 0.78)
        if shade.SetIgnoreParentAlpha then
            shade:SetIgnoreParentAlpha(true)
        end

        Window.urlSequence = (Window.urlSequence or 0) + 1
        local box = CreateFrame("Frame", "WhisprLinkDialog" .. Window.urlSequence, shade)
        box.shade = shade
        box:SetSize(420, 190)
        box:SetPoint("CENTER")
        box:SetFrameLevel(shade:GetFrameLevel() + 1)
        box:SetClampedToScreen(true)
        box:EnableMouse(true)
        box.surface = UI.ModalSurface(box)
        box.logo = box:CreateTexture(nil, "ARTWORK")
        box.logo:SetSize(38, 38)
        box.logo:SetPoint("TOPLEFT", 18, -20)
        box.logo:SetTexture("Interface\\AddOns\\Whispr\\assets\\icons\\link.tga")
        box.logo:SetVertexColor(0.40, 0.76, 0.90, 1)
        box.title = UI.Text(box, L["Copy link"], "GameFontHighlight")
        box.title:SetPoint("TOPLEFT", 70, -20)
        box.title:SetWordWrap(true)
        box.subtitle = UI.Text(box, L["Open this link in your browser."], "GameFontHighlightSmall")
        box.subtitle:SetPoint("TOPLEFT", 70, -54)
        box.subtitle:SetTextColor(unpack(UI.colors.muted))
        box.close = UI.IconButton(box, "close", L["Close"], 24, function()
            box:Hide()
        end)

        box.close:SetPoint("TOPRIGHT", -6, -6)
        box.input = UI.Input(box, 388)
        box.input:SetHeight(36)
        box.input:SetPoint("TOPLEFT", 16, -86)
        local hint = UI.Text(box, L["Ctrl+C to copy the selected link"], "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", box.input, "BOTTOMLEFT", 0, -10)
        hint:SetTextColor(unpack(UI.colors.muted))
        box.done = UI.Button(box, L["Done"], 72, function()
            box:Hide()
        end)

        box.done:SetHeight(26)
        box.done:SetPoint("BOTTOMRIGHT", -16, 12)
        shade:SetScript("OnClick", function()
            box:Hide()
        end)

        box:SetScript("OnShow", function()
            shade:Show()
        end)

        box:SetScript("OnHide", function()
            box.input:ClearFocus()
            shade:Hide()
        end)

        box.input:SetScript("OnEscapePressed", function()
            box:Hide()
        end)

        box.input:SetScript("OnEnterPressed", function()
            box:Hide()
        end)

        self.url = box
    end

    self.url:SetWidth(math.min(420, self.frame:GetWidth() - 24))
    self.url.input:SetWidth(self.url:GetWidth() - 32)
    self.url.title:SetWidth(self.url:GetWidth() - 106)
    self.url.subtitle:SetWidth(self.url:GetWidth() - 94)
    self.url.title:SetText(caption)
    local patreon = addon.Info and value == addon.Info.patreonURL
    self.url.logo:SetTexture(
        patreon and "Interface\\AddOns\\Whispr\\assets\\icons\\patreon.tga"
            or "Interface\\AddOns\\Whispr\\assets\\icons\\link.tga"
    )
    self.url.logo:SetVertexColor(patreon and 1 or 0.40, patreon and 0.45 or 0.76, patreon and 0.36 or 0.90, 1)
    self.url.shade:Show()
    self.url:Show()
    self.url.input:SetText(value)
    self.url.input:SetFocus()
    self.url.input:HighlightText()
end

function Window:Link(link, text, button, inviteKey)
    if link:match("^whisprkeyword:") or link:match("^whisprinvite:") then
        if addon.KeywordActions then
            addon.KeywordActions:Click(self, link, button, inviteKey)
        end

        return
    end

    local encoded = link:match("^whisprurl:(.*)$")
    if encoded then
        local url = Format.Decode(encoded)
        if not url then
            return
        end

        self:ShowCopyText(url, L["Copy link"])
    else
        SetItemRef(link, text, button, self.frame)
    end
end

local function setMessageOpacity(bubble, message)
    local target = message.outgoing and (message.pending and 0.65 or message.unconfirmed and 0.4) or 1
    if bubble.messageID ~= message.id or Whispr.db.global.animateWindows == false then
        bubble.deliveryFade = nil
        bubble.deliveryAlpha, bubble.deliveryTarget = target, target
        bubble:SetAlpha(target)
    elseif bubble.deliveryTarget ~= target then
        bubble.deliveryTarget = target
        bubble.deliveryFade = { from = bubble.deliveryAlpha or target, elapsed = 0, target = target }
    end
end

local function updateMessageOpacity(bubble, delta)
    local fade = bubble.deliveryFade
    if not fade then
        return
    end

    fade.elapsed = fade.elapsed + delta
    local progress = math.min(1, fade.elapsed / 0.25)
    local eased = 1 - (1 - progress) ^ 3
    bubble.deliveryAlpha = fade.from + (fade.target - fade.from) * eased
    bubble:SetAlpha(bubble.deliveryAlpha)
    if progress == 1 then
        bubble.deliveryFade = nil
    end
end

local MESSAGE_PAGE_SIZE = 20

function Window:LoadOlderMessages()
    if self.layout or not self.firstMessageID then
        return
    end

    local conversation = History.Get(self.active)
    if not conversation then
        return
    end

    for index, message in ipairs(conversation.messages) do
        if message.id == self.firstMessageID then
            if index == 1 then
                return
            end

            self.firstMessageID = conversation.messages[math.max(1, index - MESSAGE_PAGE_SIZE)].id
            self.following = false
            self:RefreshMessages()
            return
        end
    end
end

-- WoW frames cannot be destroyed. Keep only viewport frames active and recycle
-- them before allocating replacements, just like GatherLite's node frame pool.
local MESSAGE_OVERSCAN = 80

local function createMessageText(parent)
    local text = UI.Text(parent, "", "GameFontHighlight")
    text:SetSpacing(2)
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    text:SetNonSpaceWrap(true)
    return text
end

local function createMessageFrame(self)
    local scroll = self.scroll
    local bubble = CreateFrame("Frame", nil, scroll.content)
    bubble.background = UI.Round(bubble, 5, 0.15, 0.17, 0.19)
    bubble.background.role = "message"
    bubble.meta = UI.Text(bubble, "", "GameFontDisableSmall")
    bubble.meta:SetPoint("TOPLEFT", 10, -7)
    bubble.meta:SetTextColor(0.64, 0.73, 0.78)
    bubble.classIcon = bubble:CreateTexture(nil, "ARTWORK")
    bubble.classIcon:SetSize(28, 28)
    bubble.classIcon:SetPoint("TOPLEFT", 10, -6)
    bubble.classIcon:Hide()
    -- Use one native FontString per bubble. A ScrollingMessageFrame
    -- crops its internal line boxes, even when its outer frame is tall.
    bubble.text = createMessageText(bubble)
    bubble.text:SetPoint("TOPLEFT", 10, -22)
    bubble.text:SetTextColor(0.94, 0.95, 1)
    bubble:SetHyperlinksEnabled(true)
    bubble:SetScript("OnHyperlinkClick", function(owner, link, text, button)
        local selection = self.messageSelection
        local dragging = owner.selectionDragging and selection and selection.start ~= selection.finish
        if button ~= "RightButton" and not owner.selectionClickSuppressed and not dragging then
            self:Link(link, text, button, owner.inviteKey)
        end
    end)

    bubble:SetScript("OnHyperlinkEnter", function(owner, link)
        local caption = addon.KeywordActions and addon.KeywordActions:Tooltip(link, owner.inviteKey)
        if caption then
            GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
            GameTooltip:SetText(caption)
            GameTooltip:Show()
        end
    end)

    bubble:SetScript("OnHyperlinkLeave", function()
        GameTooltip:Hide()
    end)

    bubble:EnableMouseWheel(true)
    bubble:SetScript("OnMouseWheel", function(_, delta)
        scroll:SetVerticalScroll(
            math.max(0, math.min(scroll:GetVerticalScrollRange(), scroll:GetVerticalScroll() - delta * 36))
        )
        if delta > 0 and scroll:GetVerticalScroll() <= 36 then
            self:LoadOlderMessages()
        end
    end)

    -- Keep this update script installed: selection hooks share it with delivery fades.
    bubble:SetScript("OnUpdate", updateMessageOpacity)
    if addon.Selection then
        addon.Selection.Attach(self, bubble)
    end

    bubble:Hide()
    return bubble
end

local function createDateFrame(self)
    local scroll = self.scroll
    local header = CreateFrame("Frame", nil, scroll.content)
    header.label = UI.Text(header, "", "GameFontDisableSmall")
    header.label:SetPoint("CENTER")
    header.label:SetTextColor(unpack(UI.colors.muted))
    header.left = header:CreateTexture(nil, "ARTWORK")
    header.right = header:CreateTexture(nil, "ARTWORK")
    for _, line in ipairs({ header.left, header.right }) do
        line:SetColorTexture(0.24, 0.29, 0.32, 0.8)
        line:SetHeight(1)
    end

    header.left:SetPoint("LEFT", header, "LEFT")
    header.left:SetPoint("RIGHT", header.label, "LEFT", -8, 0)
    header.right:SetPoint("LEFT", header.label, "RIGHT", 8, 0)
    header.right:SetPoint("RIGHT", header, "RIGHT")
    header:Hide()
    return header
end

local function measureMessage(bubble, message, conversation, maxWidth, grouped)
    local _, fontSize = bubble.text:GetFont()
    if addon.Media then
        fontSize = addon.Media:Apply(bubble.text)
        addon.Media:Apply(bubble.meta, true)
    end

    bubble.inviteKey = not message.outgoing
            and not message.status
            and conversation.transport ~= "bnet"
            and conversation.key
        or nil
    local rendered = Format.Message(message.text, true, fontSize, bubble.inviteKey)
    local classFile = conversation.character and conversation.character.classFile
    if message.outgoing then
        classFile = nil
        local currentCharacter = Whispr.db.keys and Whispr.db.keys.char or "current"
        if not message.sourceCharacter or message.sourceCharacter == currentCharacter then
            if UnitClass then
                local _, playerClass = UnitClass("player")
                classFile = playerClass
            end
        end
    end

    local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    local iconsEnabled = Whispr.db.global.showMessageClassIcons ~= false
    local showClass = iconsEnabled and not message.status and coords ~= nil
    local showBattleNet = iconsEnabled
        and not message.status
        and not message.outgoing
        and conversation.transport == "bnet"
    local right = message.outgoing and Whispr.db.global.outgoingOnRight ~= false
    if bubble.classIcon then
        bubble.classIcon:SetShown(not grouped and (showClass or showBattleNet))
        bubble.classIcon:ClearAllPoints()
        bubble.classIcon:SetPoint(
            right and "TOPLEFT" or "TOPRIGHT",
            bubble,
            right and "TOPRIGHT" or "TOPLEFT",
            right and 6 or -6,
            -24
        )
        if showBattleNet then
            bubble.classIcon:SetTexture("Interface\\FriendsFrame\\Battlenet-Battleneticon")
            bubble.classIcon:SetTexCoord(0.125, 0.875, 0.125, 0.875)
        elseif showClass then
            UI.SetClassIcon(bubble.classIcon, classFile)
        end
    end

    bubble.meta:ClearAllPoints()
    bubble.meta:SetPoint(right and "TOPRIGHT" or "TOPLEFT", right and -10 or 10, -7)
    bubble.meta:SetShown(not grouped)
    bubble.meta:SetText(
        (
            message.status and L["Auto-reply"]
            or (message.outgoing and (message.sourceCharacter or L["You"]) or conversation.name)
        ) .. (Whispr.db.global.timestamps and ("  ·  " .. date(L["%H:%M"], message.time)) or "")
    )
    local textTop = grouped and 8 or math.max(30, math.ceil(bubble.meta:GetStringHeight()) + 20)
    bubble.bodyTop = textTop - 7

    bubble.text:ClearAllPoints()
    bubble.text:SetPoint("TOPLEFT", 10, -textTop)
    -- WoW also needs word wrap enabled to draw the explicit breaks in texture text.
    bubble.text:SetWordWrap(true)
    bubble.text:SetHeight(0)
    -- Width APIs can report only the part visible within the current bounds.
    bubble.text:SetWidth(0)
    bubble.text:SetText(rendered)
    local naturalWidth = bubble.text.GetUnboundedStringWidth and bubble.text:GetUnboundedStringWidth()
        or bubble.text:GetStringWidth()
    local bodyWidth = math.min(maxWidth, math.max(32, math.ceil(naturalWidth) + 22))
    local width = math.min(maxWidth, math.max(bodyWidth, grouped and 0 or bubble.meta:GetStringWidth() + 20))
    bubble.bodyWidth = bodyWidth
    bubble.bodyLeft = right and (width - bodyWidth) or 0
    if bubble.background then
        bubble.background:SetInsets(bubble.bodyTop, bubble.bodyLeft, right and 0 or (width - bodyWidth))
    end

    bubble.text:SetWidth(bodyWidth - 20)
    if addon.Selection then
        addon.Selection.Prepare(bubble, rendered, bodyWidth - 20, naturalWidth)
    end

    local layout = bubble.selectionLayout
    local height = math.ceil(math.max(fontSize or 12, layout and layout.height or bubble.text:GetHeight()))
    bubble.textHeight = height
    local singleLine = layout and #layout.lines == 1
        or (
            not layout
            and height < 2 * (fontSize or 12)
            and not rendered:find("\n", 1, true)
            and naturalWidth <= bodyWidth - 20
        )
    -- A single native line includes descent/leading below the nominal font
    -- height. Center that visible line rather than the extra space beneath it.
    -- Keep the full text region for textures, descenders and selection bounds.
    local baselineOffset = math.min((fontSize or 12) / 6, math.max(0, (height - (fontSize or 12)) / 2))
    bubble.textBaselineOffset = singleLine and baselineOffset or 0
    return width, height + textTop + 8, rendered
end

local function releaseMessage(self, bubble)
    if GameTooltip:IsOwned(bubble) then
        GameTooltip:Hide()
    end

    if addon.Selection and self.messageSelection and self.messageSelection.bubble == bubble then
        addon.Selection.Clear(self)
    end

    bubble:Hide()
    bubble.deliveryFade = nil
    bubble:ClearAllPoints()
    bubble.text:SetText("")
    bubble.meta:SetText("")
    bubble.classIcon:Hide()
    bubble.classIcon:SetTexture(nil)
    bubble.classIcon:SetTexCoord(0, 1, 0, 1)
    bubble.messageID, bubble.inviteKey, bubble.y, bubble.row = nil, nil, nil, nil
    bubble.deliveryAlpha, bubble.deliveryTarget = nil, nil
    bubble.selectionRendered, bubble.selectionWidth = nil, nil
    bubble.selectionLayout = nil
    if bubble.selectionMeasure then
        bubble.selectionMeasure:SetText("")
    end

    bubble.selectionDragging, bubble.selectionClickSuppressed = nil, nil
    bubble:SetAlpha(1)
    self.messagePool[#self.messagePool + 1] = bubble
end

function Window:ReleaseMessageFrames()
    self.messagePool = self.messagePool or {}
    self.datePool = self.datePool or {}
    for _, bubble in ipairs(self.bubbles) do
        releaseMessage(self, bubble)
    end

    for _, header in ipairs(self.dateHeaders or {}) do
        header:Hide()
        header:ClearAllPoints()
        header.label:SetText("")
        header.row = nil
        self.datePool[#self.datePool + 1] = header
    end

    self.bubbles, self.dateHeaders = {}, {}
end

function Window:UpdateVisibleMessages()
    if not self.messageRows or not self.frame:IsShown() or not History.Get(self.active) then
        return
    end

    self.messagePool, self.datePool = self.messagePool or {}, self.datePool or {}
    local scroll, rows = self.scroll, self.messageRows
    local top = scroll:GetVerticalScroll() - MESSAGE_OVERSCAN
    local bottom = top + scroll:GetHeight() + MESSAGE_OVERSCAN * 2
    -- Find the first intersecting row without walking the entire loaded history.
    local low, high = 1, #rows
    while low <= high do
        local middle = math.floor((low + high) / 2)
        if rows[middle].y + rows[middle].height < top then
            low = middle + 1
        else
            high = middle - 1
        end
    end

    local wanted, visible = {}, {}
    for index = low, #rows do
        local row = rows[index]
        if row.y > bottom then
            break
        end

        wanted[row.key] = row
        visible[#visible + 1] = row
    end

    local kept = {}
    for _, bubble in ipairs(self.bubbles) do
        if bubble.row and wanted[bubble.row.key] then
            kept[bubble.row.key] = bubble
        else
            releaseMessage(self, bubble)
        end
    end

    for _, header in ipairs(self.dateHeaders or {}) do
        if header.row and wanted[header.row.key] then
            kept[header.row.key] = header
        else
            header:Hide()
            header:ClearAllPoints()
            header.label:SetText("")
            header.row = nil
            self.datePool[#self.datePool + 1] = header
        end
    end

    self.bubbles, self.dateHeaders = {}, {}
    local conversation = History.Get(self.active)
    for _, row in ipairs(visible) do
        local widget = kept[row.key]
        if row.message then
            local bubble = widget or table.remove(self.messagePool) or createMessageFrame(self)
            if bubble.row ~= row then
                local message = row.message
                local width, _, rendered =
                    measureMessage(bubble, message, conversation, self.messageMaxWidth, row.grouped)
                bubble:SetSize(width, row.height)
                bubble.text:ClearAllPoints()
                local textOffset = bubble.bodyTop
                    + (row.height - bubble.bodyTop - bubble.textHeight) / 2
                    + bubble.textBaselineOffset
                bubble.text:SetPoint("TOPLEFT", bubble.bodyLeft + 10, -textOffset)
                if addon.Selection then
                    local geometry = table.concat({ row.y, bubble.bodyLeft, textOffset, bubble.textHeight }, ":")
                    addon.Selection.Update(self, bubble, rendered, bubble.bodyWidth, message.id, geometry)
                end

                setMessageOpacity(bubble, message)
                bubble.background:SetColorTexture(
                    message.outgoing and 0.10 or 0.14,
                    message.outgoing and 0.24 or 0.16,
                    message.outgoing and 0.31 or 0.18,
                    1
                )
                if addon.Theme then
                    addon.Theme:Paint(bubble.background, message.outgoing and "outgoingColor" or "incomingColor")
                end

                bubble:ClearAllPoints()
                local right = message.outgoing and Whispr.db.global.outgoingOnRight ~= false
                bubble:SetPoint(
                    right and "TOPRIGHT" or "TOPLEFT",
                    scroll.content,
                    right and "TOPRIGHT" or "TOPLEFT",
                    right and -(8 + (self.messageIconGutter or 0)) or (8 + (self.messageIconGutter or 0)),
                    -row.y
                )
                bubble.messageID, bubble.y, bubble.row = message.id, row.y, row
            end

            bubble:Show()
            self.bubbles[#self.bubbles + 1] = bubble
        else
            local header = widget or table.remove(self.datePool) or createDateFrame(self)
            if header.row ~= row then
                if addon.Media then
                    addon.Media:Apply(header.label, true)
                end

                header.label:SetText(row.label)
                header:SetSize(self.messageMaxWidth, row.height)
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 8, -row.y)
                header.row = row
            end

            header:Show()
            self.dateHeaders[#self.dateHeaders + 1] = header
        end
    end
end

function Window:RefreshMessages(forceBottom)
    if not self.frame then
        return
    end

    local scroll = self.scroll
    local offset, anchor, anchorOffset = scroll:GetVerticalScroll()
    for _, row in ipairs(self.messageRows or {}) do
        if row.message and row.y + row.height > offset then
            anchor, anchorOffset = row.message.id, offset - row.y
            break
        end
    end

    local follow = forceBottom or self.following
    self.layout = true
    if self.typingBadge then
        self.typingBadge:SetShown(self:HasTypingIndicator())
    end

    local conversation = History.Get(self.active)
    local messages = conversation and conversation.messages or {}
    local first = math.max(1, #messages - MESSAGE_PAGE_SIZE + 1)
    if self.firstMessageID then
        -- IDs survive retention trimming and newly appended messages.
        first = 1
        while first <= #messages and messages[first].id < self.firstMessageID do
            first = first + 1
        end
    end

    self.firstMessageID = messages[first] and messages[first].id or nil
    if not self.messageMeasure then
        local measure = CreateFrame("Frame", nil, scroll.content)
        measure.text = createMessageText(measure)
        measure.meta = UI.Text(measure, "", "GameFontDisableSmall")
        measure.meta:SetPoint("TOPLEFT", 10, -7)
        measure:Hide()
        self.messageMeasure = measure
    end

    local measure = self.messageMeasure
    local rows, previousDay = {}, nil
    local y, anchorY = 10, nil
    self.messageIconGutter = Whispr.db.global.showMessageClassIcons ~= false and 34 or 0
    local maxWidth = math.max(146, scroll:GetWidth() - 16 - self.messageIconGutter)
    self.messageMaxWidth = maxWidth
    for messageIndex = first, #messages do
        local message = messages[messageIndex]
        local day = date("%Y-%m-%d", message.time)
        if day ~= previousDay then
            local label = date(L["%B %d, %Y"], message.time):gsub(" 0", " ")
            if addon.Media then
                addon.Media:Apply(measure.meta, true)
            end

            measure.meta:SetText(label)
            local height = math.max(28, measure.meta:GetStringHeight() + 12)
            rows[#rows + 1] = { key = "day:" .. message.id, label = label, y = y, height = height }
            y, previousDay = y + height, day
        end

        local previous = messageIndex > first and messages[messageIndex - 1]
        local grouped = previous
            and not message.status
            and not previous.status
            and message.outgoing == previous.outgoing
            and message.sourceCharacter == previous.sourceCharacter
            and day == date("%Y-%m-%d", previous.time)
            and message.time >= previous.time
            and message.time - previous.time <= 300
        local _, height = measureMessage(measure, message, conversation, maxWidth, grouped)
        rows[#rows + 1] = { key = message.id, message = message, y = y, height = height, grouped = grouped }
        if message.id == anchor then
            anchorY = y
        end

        y = y + height + 6
    end

    measure.text:SetText("")
    measure.meta:SetText("")
    measure.inviteKey = nil
    self.messageRows = rows
    self.empty:SetShown(#messages == 0)
    self.emptyTitle:SetShown(#messages == 0)
    self.emptyIcon:SetShown(#messages == 0)
    self.empty:SetText(
        conversation and L["Say hello to start the conversation."]
            or L["Start a whisper with /w or a character's Whisper menu."]
    )
    local typingSpace = self.typingBadge and self.typingBadge:IsShown() and 38 or 0
    scroll.content:SetHeight(math.max(1, y + typingSpace))
    -- Scroll ranges settle on the next UI tick. Keep the visible message anchored
    -- when retention removes old messages while the reader is scrolled up.
    self.generation = (self.generation or 0) + 1
    local generation = self.generation
    C_Timer.After(0, function()
        if generation ~= self.generation then
            return
        end

        scroll:UpdateScrollChildRect()
        local target = follow and scroll:GetVerticalScrollRange() or (anchorY and anchorY + anchorOffset or 0)
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(), target)))
        self:UpdateVisibleMessages()
        self.layout = false
        self.following = follow
        self.latest:SetShown(not follow)
        self:MarkRead()
    end)
end

function Window:Refresh(key)
    History.Invalidate()
    for id, window in pairs(self.detached or {}) do
        if not History.Get(id) then
            window:HideImmediately()
            self.detached[id] = nil
        else
            window:Refresh(key)
        end
    end

    if not self.frame then
        return
    end

    if self.active and not History.Get(self.active) then
        self:Select(nil)
    end

    if self.input.RefreshFormatting then
        self.input:RefreshFormatting()
    end

    self:RefreshList()
    if key == self.active then
        self:RefreshMessages()
    end
end

function Window:DraftEdited()
    local conversation = History.Get(self.active)
    if addon.Extensions then
        addon.Extensions:ConversationEvent("DRAFT_CHANGED", conversation, { text = self.input:GetText() })
    end

    if conversation and conversation.demo then
        self.demoTypingKey = self.active
        self.demoTypingUntil = self.input:GetText():find("%S") and (GetTime() + 4) or nil
        self:UpdateTyping()
    elseif addon.Typing then
        addon.Typing:Changed(self)
    end
end

function Window:HasTypingIndicator(key)
    key = key or self.active
    local conversation = History.Get(key)
    if conversation and conversation.demo then
        return self.demoTypingKey == key and self.demoTypingUntil ~= nil and self.demoTypingUntil > GetTime()
    end

    return (addon.Typing and addon.Typing:IsTyping(key)) or false
end

function Window:UpdateTyping()
    for _, row in ipairs(self.rows) do
        local conversation = History.Get(row.key)
        if row:IsShown() and conversation then
            self:UpdateCardTyping(row, conversation)
        end
    end

    if not self.typingBadge then
        return
    end

    local conversation = History.Get(self.active)
    local demo = conversation and conversation.demo
    local shown = self:HasTypingIndicator()
    if self.typingBadge:IsShown() ~= shown then
        self.typingBadge:SetShown(shown)
        self:RefreshMessages()
    end

    if shown then
        for index, dot in ipairs(self.typingBadge.dots) do
            local alpha = not demo and Whispr.db.global.animateWindows == false and 1
                or (0.3 + 0.7 * (math.sin(GetTime() * 6 - index * 0.8) + 1) / 2)
            dot:SetAlpha(alpha)
        end
    end
end

function Window:ToggleEmotes()
    addon.Emoji.Toggle(self)
end

function Window:Create()
    if self.frame then
        return
    end

    Window.frameSequence = (Window.frameSequence or 0) + 1
    local frameName = self.owner and ("WhisprConversation" .. Window.frameSequence) or "WhisprWindow"
    local frame = CreateFrame("Frame", frameName, UIParent)
    local left = self.owner and 0 or SIDEBAR_WIDTH
    local width, height = 800, 510
    if self.owner then
        width, height = self:DefaultSeparateSize()
    end

    self.frame = frame
    self.hideFrame = frame.Hide
    frame:Hide()
    frame:SetSize(width, height)
    frame:SetPoint(
        "CENTER",
        UIParent,
        "CENTER",
        self.owner and (Window.frameSequence % 5) * 24 or 0,
        self.owner and -(Window.frameSequence % 5) * 24 or 0
    )
    frame:SetScale(math.min(1, (UIParent:GetWidth() - 40) / width, (UIParent:GetHeight() - 40) / height))
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(Whispr.db.global.clampWindowsToScreen ~= false)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetToplevel(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(360, 280)
    self:RestoreGeometry()
    self.background = UI.Round(frame, 6, 0.075, 0.085, 0.095)
    self.background.windowChrome = true
    self.background.role = "window"
    if addon.Theme then
        addon.Theme:Paint(self.background, "windowColor")
    end

    frame:SetScript("OnHide", function()
        if addon.Extensions then
            addon.Extensions:Emit(
                "WINDOW_CLOSED",
                { window = frameName, key = self.active, separate = self.owner ~= nil }
            )
        end

        self.demoTypingKey, self.demoTypingUntil = nil, nil
        if addon.Typing then
            addon.Typing:Stop(self.active)
        end

        self:SetWindowFocus(false)
        self.closing = nil
        self.fade = nil
        self.opacityTarget = nil
        self:ReleaseMessageFrames()
        frame:StopMovingOrSizing()
        self:SaveGeometry()
        self.input:ClearFocus()
        if self.url then
            self.url:Hide()
        end

        if self.info then
            self.info:Hide()
        end

        if self.emotePicker then
            self.emotePicker:Hide()
        end
    end)

    frame:SetScript("OnShow", function()
        if addon.Extensions then
            addon.Extensions:Emit(
                "WINDOW_OPENED",
                { window = frameName, key = self.active, separate = self.owner ~= nil }
            )
        end

        self.closing = nil
        self.opacityTarget = nil
        self.visualAlpha = Whispr.db.global.animateWindows == false and (Whispr.db.global.windowOpacity or 1) or 0
        frame:SetAlpha(self.visualAlpha)
        self:UpdateVisibleMessages()
        self:MarkRead()
        self:UpdateOpacity(true)
    end)

    frame:SetScript("OnUpdate", function(_, elapsed)
        self:StepAnimation()
        if not frame:IsShown() then
            return
        end

        self.opacityElapsed = (self.opacityElapsed or 0) + elapsed
        if self.opacityElapsed < 0.05 then
            return
        end

        self.opacityElapsed = 0
        self:UpdateOpacity()
        self:UpdateTyping()
    end)

    local titlebar = CreateFrame("Frame", nil, frame)
    self.titlebar = titlebar
    titlebar:SetPoint("TOPLEFT", 1, -1)
    titlebar:SetPoint("TOPRIGHT", -1, -1)
    titlebar:SetHeight(38)
    local titleBackground = UI.Background(titlebar, 0.14, 0.16, 0.18)
    if addon.Theme then
        addon.Theme:Paint(titleBackground, "headerColor")
    end

    local titleEdge = titlebar:CreateTexture(nil, "BORDER")
    titleEdge:SetPoint("BOTTOMLEFT")
    titleEdge:SetPoint("BOTTOMRIGHT")
    titleEdge:SetHeight(1)
    titleEdge:SetColorTexture(0.25, 0.30, 0.33, 1)
    titlebar:EnableMouse(true)
    titlebar:RegisterForDrag("LeftButton")
    titlebar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)

    titlebar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        self:SaveGeometry()
    end)

    self.brandIcon = titlebar:CreateTexture(nil, "ARTWORK")
    self.brandIcon:SetSize(20, 20)
    self.brandIcon:SetTexture("Interface\\AddOns\\Whispr\\assets\\whispr-icon.tga")
    self.brandIcon:SetPoint("LEFT", 12, 0)
    local brand = UI.Text(titlebar, "Whispr", "GameFontHighlightLarge")
    self.brand = brand
    brand:SetPoint("LEFT", self.brandIcon, "RIGHT", 7, 0)
    local dot = CreateFrame("Frame", nil, titlebar)
    dot:SetSize(5, 5)
    dot:SetPoint("LEFT", brand, "RIGHT", 7, -3)
    local dotSurface = UI.Background(dot, unpack(UI.colors.accent))
    if addon.Theme then
        addon.Theme:Paint(dotSurface, "accentColor")
    end

    local close = UI.IconButton(titlebar, "close", L["Close window"], 24, function()
        self:Close()
    end)

    close:SetPoint("RIGHT", -8, 0)
    self.themeTitleParts = { titleBackground, titleEdge, self.brandIcon, brand, dot, close }
    self.settingsButton = UI.IconButton(titlebar, "settings", L["Settings"], 24, function()
        Whispr:ShowSettings()
    end)

    self.settingsButton:SetPoint("RIGHT", close, "LEFT", -6, 0)
    self.infoButton = UI.Button(titlebar, "?", 24, function()
        addon.Info.Show(self)
    end)

    self.infoButton:SetHeight(24)
    self.infoButton:SetPoint("RIGHT", self.settingsButton, "LEFT", -6, 0)
    self.infoButton:HookScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["About Whispr"])
        GameTooltip:Show()
    end)

    self.infoButton:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local sidebar = CreateFrame("Frame", nil, frame)
    self.sidebar = sidebar
    sidebar:SetPoint("TOPLEFT", 0, -39)
    sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    local sidebarSurface = UI.Background(sidebar, 0.10, 0.115, 0.13)
    if addon.Theme then
        addon.Theme:Paint(sidebarSurface, "sidebarColor")
    end

    self.sidebarGrain = UI.Grain(sidebar)
    local sidebarDivider = sidebar:CreateTexture(nil, "OVERLAY")
    sidebarDivider:SetColorTexture(0.24, 0.29, 0.32, 0.8)
    sidebarDivider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
    sidebarDivider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 1)
    sidebarDivider:SetWidth(1)
    self.search = UI.Input(sidebar, SIDEBAR_WIDTH, true, "sidebarColor")
    self.search:SetHeight(38)
    self.search:SetPoint("TOPLEFT", 0, 0)
    self.search:SetPoint("TOPRIGHT", 0, 0)
    self.search:SetTextInsets(32, 30, 0, 0)
    self.search:SetMaxBytes(100)
    local searchIcon = self.search:CreateTexture(nil, "ARTWORK")
    self.searchIcon = searchIcon
    searchIcon:SetTexture("Interface\\AddOns\\Whispr\\assets\\icons\\search.tga")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", 10, 0)
    searchIcon:SetVertexColor(unpack(UI.colors.muted))
    local searchDivider = self.search:CreateTexture(nil, "OVERLAY")
    searchDivider:SetPoint("BOTTOMLEFT")
    searchDivider:SetPoint("BOTTOMRIGHT")
    searchDivider:SetHeight(1)
    searchDivider:SetColorTexture(0.20, 0.24, 0.27, 1)
    if addon.Theme then
        addon.Theme:Paint(searchDivider, "buttonColor")
    end

    self.searchPlaceholder = UI.Text(self.search, L["Search characters..."], "GameFontHighlightSmall")
    self.searchPlaceholder:SetPoint("LEFT", 32, 0)
    self.searchPlaceholder:SetTextColor(unpack(UI.colors.muted))
    self.searchClear = CreateFrame("Button", nil, self.search)
    self.searchClear:SetSize(28, 28)
    self.searchClear:SetScript("OnClick", function()
        self.search:SetText("")
        self.search:SetFocus()
    end)

    local clearIcon = self.searchClear:CreateTexture(nil, "OVERLAY")
    clearIcon:SetTexture("Interface\\AddOns\\Whispr\\assets\\icons\\close.tga")
    clearIcon:SetSize(14, 14)
    clearIcon:SetPoint("CENTER")
    clearIcon:SetVertexColor(unpack(UI.colors.muted))
    local clearHover = UI.Background(self.searchClear, 0.15, 0.21, 0.25)
    if addon.Theme then
        addon.Theme:Paint(clearHover, "buttonColor", true)
    end

    clearHover:Hide()
    self.searchClear:SetScript("OnEnter", function()
        clearHover:Show()
        clearIcon:SetVertexColor(0.90, 0.94, 0.96, 1)
    end)

    self.searchClear:SetScript("OnLeave", function()
        clearHover:Hide()
        clearIcon:SetVertexColor(unpack(UI.colors.muted))
    end)

    self.searchClear:SetScript("OnHide", function()
        clearHover:Hide()
        clearIcon:SetVertexColor(unpack(UI.colors.muted))
    end)

    self.searchClear:SetPoint("RIGHT", -3, 0)
    self.searchClear:Hide()
    self.searchEmpty = UI.Text(sidebar, L["No matching conversations"], "GameFontHighlightSmall")
    self.searchEmpty:SetPoint("TOP", 0, -50)
    self.searchEmpty:SetTextColor(unpack(UI.colors.muted))
    self.searchEmpty:Hide()
    self.people = UI.Scroll(sidebar)
    self.people:SetPoint("TOPLEFT", 0, -38)
    self.people:SetPoint("BOTTOMRIGHT", 0, 0)
    self.people.ScrollBar:ClearAllPoints()
    self.people.ScrollBar:SetPoint("TOPRIGHT", self.people, "TOPRIGHT", 0, 0)
    self.people.ScrollBar:SetPoint("BOTTOMRIGHT", self.people, "BOTTOMRIGHT", 0, 0)
    self.people:HookScript("OnSizeChanged", function()
        self:LayoutPeople()
    end)

    self.people:HookScript("OnScrollRangeChanged", function()
        self:LayoutPeople()
    end)

    self.people:HookScript("OnShow", function()
        self:QueuePeopleRefresh()
    end)

    self.people.ScrollBar:SetAlpha(0.4)
    self.search:SetScript("OnTextChanged", function(input)
        local text = input:GetText()
        self.conversationQuery = text:match("^%s*(.-)%s*$")
        self.searchPlaceholder:SetShown(text == "")
        self.searchClear:SetShown(text ~= "")
        self.people:SetVerticalScroll(0)
        self:RefreshList()
    end)

    self.search:HookScript("OnEditFocusGained", function()
        self:SetWindowFocus(true)
    end)

    self.search:SetScript("OnEnterPressed", function(input)
        input:ClearFocus()
    end)

    self.search:SetScript("OnEscapePressed", function(input)
        input:SetText("")
        input:ClearFocus()
    end)

    if self.owner then
        sidebar:Hide()
    end

    local conversationBand = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    self.conversationBand = conversationBand
    conversationBand:SetPoint("TOPLEFT", left > 0 and left or 1, -39)
    conversationBand:SetPoint("TOPRIGHT", -1, -39)
    conversationBand:SetHeight(44)
    conversationBand:SetColorTexture(0.115, 0.14, 0.16, 1)
    if addon.Theme then
        addon.Theme:Paint(conversationBand, "headerColor")
    end

    self.headerAvatar = UI.Avatar(frame, 26)
    self.headerAvatar:SetPoint("TOPLEFT", left + 10, -48)
    self.header = UI.Text(frame, L["Your whispers"], "GameFontHighlight")
    self.header:SetPoint("TOPLEFT", left + 46, -46)
    self.header:SetWidth(width - left - 230)
    self.header:SetWordWrap(false)

    local function openPlayerMenu()
        self:ConversationMenu(self.headerAvatar, self.active)
    end

    self.headerAvatar:EnableMouse(true)
    self.headerAvatar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" or button == "LeftButton" then
            openPlayerMenu()
        end
    end)

    self.headerMenu = CreateFrame("Button", nil, frame)
    self.headerMenu:SetAllPoints(self.header)
    self.headerMenu:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    self.headerMenu:SetScript("OnClick", openPlayerMenu)
    self.subtitle = UI.Text(frame, "", "GameFontHighlightSmall")
    self.subtitle:SetPoint("TOPLEFT", left + 46, -64)
    self.subtitle:SetTextColor(unpack(UI.colors.muted))
    self.subtitle:SetWidth(width - left - 94)
    self.subtitle:SetWordWrap(false)
    self.pop = UI.IconButton(frame, "menu", L["Conversation options"], 26, function(button)
        self:ConversationMenu(button, self.active)
    end)

    self.pop:SetPoint("TOPRIGHT", -10, -49)
    self.pop:SetHeight(24)
    self.headerActions = {}
    local previous = self.pop
    for _, key in ipairs({ "report", "block", "invite" }) do
        local actionKey = key
        local button = UI.IconButton(frame, key, "", 24, function()
            addon.Actions:Run(actionKey, Whispr.db.char.conversations[self.active])
            self:RefreshHeaderActions()
        end)

        button:SetPoint("RIGHT", previous, "LEFT", -4, 0)
        self.headerActions[key] = button
        previous = button
    end

    self:RefreshHeaderActions()
    local divider = frame:CreateTexture(nil, "BORDER")
    self.divider = divider
    divider:SetColorTexture(0.24, 0.29, 0.32, 0.8)
    divider:SetPoint("TOPLEFT", left, -83)
    divider:SetPoint("TOPRIGHT", -1, -83)
    divider:SetHeight(1)
    self.scroll = UI.Scroll(frame)
    self.scroll:SetPoint("TOPLEFT", left + 4, -88)
    self.scroll:SetPoint("BOTTOMRIGHT", -12, 56)
    self.scroll.ScrollBar:SetAlpha(0.5)
    self.messageGrain = UI.Grain(self.scroll)
    self.scroll:HookScript("OnVerticalScroll", function(scroll)
        if self.layout then
            return
        end

        self:UpdateVisibleMessages()
        self.following = scroll:GetVerticalScrollRange() - scroll:GetVerticalScroll() <= 8
        self.latest:SetShown(not self.following)
        self:MarkRead()
        if scroll:GetVerticalScroll() <= 36 then
            self:LoadOlderMessages()
        end
    end)

    self.scroll:HookScript("OnMouseWheel", function(scroll, delta)
        if delta > 0 and scroll:GetVerticalScroll() <= 36 then
            self:LoadOlderMessages()
        end
    end)

    self.emptyIcon = UI.Avatar(frame, 58)
    self.emptyIcon.surface:SetColorTexture(0.15, 0.21, 0.24)
    self.emptyIcon.label:SetText(":)")
    self.emptyIcon:SetPoint("CENTER", self.scroll, "CENTER", 0, 56)
    self.emptyTitle = UI.Text(frame, L["A conversation starts with hello."], "GameFontHighlightLarge")
    self.emptyTitle:SetPoint("CENTER", self.scroll, "CENTER", 0, 0)
    self.empty = UI.Text(frame, "", "GameFontHighlightSmall")
    self.empty:SetPoint("TOP", self.emptyTitle, "BOTTOM", 0, -12)
    self.empty:SetWidth(340)
    self.empty:SetJustifyH("CENTER")
    self.empty:SetTextColor(unpack(UI.colors.muted))
    self.footer = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    self.footer:SetColorTexture(0.105, 0.13, 0.15, 1)
    self.footerDivider = frame:CreateTexture(nil, "ARTWORK")
    self.footerDivider:SetHeight(1)
    self.footerDivider:SetPoint("TOPLEFT", self.footer, "TOPLEFT")
    self.footerDivider:SetPoint("TOPRIGHT", self.footer, "TOPRIGHT")
    self.footerDivider:SetColorTexture(0.20, 0.24, 0.27, 1)
    if addon.Theme then
        addon.Theme:Paint(self.footer, "footerColor")
        addon.Theme:Paint(self.footerDivider, "buttonColor")
    end

    self.input = UI.Input(frame, width - left - 1, true)
    if addon.Media then
        addon.Media:Apply(self.input)
    end

    self.input:SetHeight(48)
    local inputDivider = self.input:CreateTexture(nil, "OVERLAY")
    inputDivider:SetPoint("TOPLEFT")
    inputDivider:SetPoint("TOPRIGHT")
    inputDivider:SetHeight(1)
    inputDivider:SetColorTexture(0.20, 0.24, 0.27, 1)
    if addon.Theme then
        addon.Theme:Paint(inputDivider, "buttonColor")
    end

    self.input:SetPoint("BOTTOMLEFT", math.max(1, left), 1)
    self.input:SetMaxBytes(255)
    self.input:SetTextInsets(14, 48, 0, 0)
    self.emoteButton = UI.EmoteButton(self.input, "happy", L["Smileys"], 26, function()
        self:ToggleEmotes()
    end)

    self.emoteButton:SetPoint("RIGHT", -14, 0)
    self.emoteButton:SetShown(Whispr.db.global.smileys == true)
    self.input:SetTextInsets(14, Whispr.db.global.smileys and 48 or 14, 0, 0)
    self.placeholder = UI.Text(self.input, L["Message..."], "GameFontHighlightSmall")
    self.placeholder:SetPoint("LEFT", 14, 0)
    self.placeholder:SetWidth(width - left - 120)
    self.placeholder:SetWordWrap(false)
    self.placeholder:SetTextColor(unpack(UI.colors.muted))
    self.input:SetScript("OnTextChanged", function(input)
        self.placeholder:SetShown(input:GetText() == "")
    end)

    self.input:SetScript("OnEnterPressed", function()
        self.demoTypingKey, self.demoTypingUntil = nil, nil
        if self.emotePicker then
            self.emotePicker:Hide()
        end

        Whispr:Send(self)
    end)

    self.input:SetScript("OnEscapePressed", function()
        self:Escape()
    end)

    self.input:HookScript("OnEditFocusGained", function()
        self:SetWindowFocus(true)
    end)

    addon.Composer.Attach(self.input)
    self.input.onDraftEdited = function()
        self:DraftEdited()
    end

    self.typingBadge = CreateFrame("Frame", nil, self.scroll.content)
    self.typingBadge:SetSize(94, 20)
    self.typingBadge:SetPoint("BOTTOMLEFT", self.scroll.content, "BOTTOMLEFT", 10, 10)
    self.typingBadge:SetFrameLevel(self.scroll:GetFrameLevel() + 20)
    self.typingBadge:EnableMouse(false)
    local typingSurface = UI.Round(self.typingBadge, 5, 0.15, 0.21, 0.25)
    if addon.Theme then
        addon.Theme:Paint(typingSurface, "selectedColor")
    end

    local typingLabel = UI.Text(self.typingBadge, L["Typing"], "GameFontHighlightSmall")
    typingLabel:SetPoint("LEFT", 8, 0)
    self.typingBadge.dots = {}
    for index = 1, 3 do
        local typingDot = CreateFrame("Frame", nil, self.typingBadge)
        typingDot:SetSize(4, 4)
        typingDot:SetPoint("RIGHT", -8 - (3 - index) * 7, 0)
        UI.Round(typingDot, 2, unpack(UI.colors.muted))
        self.typingBadge.dots[index] = typingDot
    end

    self.typingBadge:Hide()
    self.latest = UI.IconButton(frame, "latest", L["Jump to latest message"], 30, function()
        self:Latest()
    end, true)
    self.latest:SetFrameLevel(self.scroll:GetFrameLevel() + 20)
    self.latest:SetPoint("BOTTOMRIGHT", self.scroll, "BOTTOMRIGHT", -10, 10)
    self.latest:Hide()

    self.drawerShade = CreateFrame("Button", nil, frame)
    self.drawerShade:SetPoint("TOPLEFT", 1, -39)
    self.drawerShade:SetPoint("BOTTOMRIGHT", -1, 1)
    self.drawerShade:SetFrameLevel(self.latest:GetFrameLevel() + 2)
    UI.Background(self.drawerShade, 0, 0, 0, 0.55)
    self.drawerShade:SetScript("OnClick", function()
        self:SetDrawer(false)
    end)

    sidebar:SetFrameLevel(self.drawerShade:GetFrameLevel() + 2)
    self.drawerToggle = UI.IconButton(titlebar, "menu", L["Conversations"], 26, function()
        self:SetDrawer(not self.drawerOpen)
    end)

    self.drawerToggle:SetPoint("LEFT", 8, 0)
    self.unreadBadge = CreateFrame("Frame", nil, self.drawerToggle)
    self.unreadBadge:SetSize(22, 16)
    self.unreadBadge:SetPoint("TOPRIGHT", 8, 4)
    local unreadSurface = UI.Round(self.unreadBadge, 5, unpack(UI.colors.accent))
    if addon.Theme then
        addon.Theme:Paint(unreadSurface, "accentColor")
    end

    self.unreadCount = UI.Text(self.unreadBadge, "", "GameFontHighlightSmall")
    self.unreadCount:SetPoint("CENTER")
    self.resize = UI.IconButton(frame, "resize", L["Resize window"], 12, function() end)
    self.resize.surface:Hide()
    self.resize:SetPoint("BOTTOMRIGHT", -1, 1)
    self.resize:SetFrameLevel(sidebar:GetFrameLevel() + 5)
    self.resize:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)

    self.resize:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        self:SaveGeometry()
    end)

    self.resize:SetScript("OnHide", function()
        frame:StopMovingOrSizing()
        self:SaveGeometry()
    end)

    frame:SetScript("OnSizeChanged", function()
        -- Keep scroll callbacks from marking history read while bounds change.
        self.layout = true
        if self.resizePending then
            return
        end

        self.resizePending = true
        C_Timer.After(0, function()
            self.resizePending = nil
            self:Layout()
            self:RefreshMessages()
        end)
    end)

    self.focusBorder = CreateFrame("Frame", nil, frame)
    self.focusBorder:SetAllPoints()
    self.focusBorder:SetFrameLevel(self.resize:GetFrameLevel() + 10)
    self.focusBorder:EnableMouse(false)
    self.focusBorder.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = self.focusBorder:CreateTexture(nil, "OVERLAY")
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT")
            edge:SetPoint(side .. "RIGHT")
            edge:SetHeight(1)
        else
            edge:SetPoint("TOP" .. side)
            edge:SetPoint("BOTTOM" .. side)
            edge:SetWidth(1)
        end

        self.focusBorder.edges[#self.focusBorder.edges + 1] = edge
    end

    self.focusBorder:Hide()
    self:UpdateTheme()
    self:InstallWindowFocus()
    self.geometryReady = true
    self:Layout()
    self:RefreshUnread()
    -- Animate ordinary closes; combat, docking and cleanup use the original Hide.
    frame.Hide = function()
        self:Close()
    end
end
