-- A layout/controller harness, not a replacement for testing Blizzard widgets.
local addon, queue = {}, {}
assert(loadfile("tests/support/locale.lua"))(addon)
local clockTime = 0
GetTime = function()
    return clockTime
end

local function load(name)
    assert(loadfile("scripts/" .. name .. ".lua"))("Whispr", addon)
end

local function flush()
    while #queue > 0 do
        local pending = queue
        queue = {}
        for _, callback in ipairs(pending) do
            callback()
        end
    end
end

local function equal(a, b, label)
    assert(a == b, (label or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local methods = {}

local function noop() end

local function frame(name, parent)
    return setmetatable(
        { name = name, parent = parent, scripts = {}, shown = true, width = 540, height = 300, text = "", offset = 0 },
        { __index = methods }
    )
end

for method in
    ("EnableKeyboard SetPropagateKeyboardInput UpdateScrollChildRect SetMultiLine SetNonSpaceWrap SetFont HighlightText RegisterEvent Raise RegisterForClicks SetResizable SetResizeBounds StartSizing SetFrameLevel SetClipsChildren SetThickness SetStartPoint SetEndPoint SetSpacing SetIndentedWordWrap SetOrientation SetMinMaxValues SetValueStep SetThumbTexture SetTexture SetVertexColor SetTexCoord SetTextColor SetShadowOffset SetFontString SetTextInsets SetAlpha SetToplevel SetPoint ClearAllPoints SetColorTexture SetAllPoints SetJustifyH SetJustifyV SetFontObject SetWordWrap SetHighlightTexture SetSizeDummy SetAutoFocus SetMaxBytes SetEnabled SetTitle SetPortraitToAsset SetScale SetFrameStrata SetClampedToScreen SetMovable EnableMouse RegisterForDrag StartMoving StopMovingOrSizing SetFading SetMaxLines SetHyperlinksEnabled EnableMouseWheel SetPanExtent"):gmatch(
        "%S+"
    )
do
    methods[method] = noop
end

function methods:SetClampedToScreen(value)
    self.clampedToScreen = value
end

function methods:SetParent(parent)
    self.parent = parent
end

function methods:SetFrameStrata(strata)
    self.strata = strata
end

function methods:GetFrameStrata()
    return self.strata or (self.parent and self.parent:GetFrameStrata()) or "MEDIUM"
end

function methods:SetAlpha(alpha)
    self.alpha = alpha
end

function methods:EnableKeyboard(enabled)
    self.keyboardEnabled = enabled
end

function methods:SetScale(scale)
    self.scale = scale
end

function methods:GetEffectiveScale()
    return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1)
end

function methods:GetCenter()
    if self.centerX then
        return self.centerX, self.centerY
    end

    local ratio = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return UIParent:GetWidth() / (2 * ratio), UIParent:GetHeight() / (2 * ratio)
end

function methods:SetPoint(...)
    self.lastPoint = { ... }
end

function methods:CreateFontString()
    local label = frame(nil, self)
    label.isFontString = true
    label.height = 0
    return label
end

function methods:CreateLine()
    return frame(nil, self)
end

function methods:IsMouseOver()
    return self.mouseOver or false
end

function methods:CreateTexture()
    return frame(nil, self)
end

function methods:SetTexture(texture)
    self.texture = texture
end

function methods:SetText(text)
    self.text = text
    self.cursor = #text
end

function methods:GetText()
    return self.text
end

function methods:GetCursorPosition()
    return self.cursor or #self.text
end

function methods:SetCursorPosition(cursor)
    self.cursor = cursor
end

function methods:Insert(text)
    local cursor = self.cursor or #self.text
    self.text = self.text:sub(1, cursor) .. text .. self.text:sub(cursor + 1)
    self.cursor = cursor + #text
end

function methods:SetSize(w, h)
    self.width, self.height = w, h
end

function methods:SetWidth(w)
    self.width = w
end

function methods:SetHeight(h)
    self.height = h
end

function methods:GetWidth()
    return self.width
end

function methods:GetHeight()
    if self.isFontString and self.height == 0 then
        return self:GetStringHeight()
    end

    return self.height
end

function methods:SetNonSpaceWrap(enabled)
    self.nonSpaceWrap = enabled
end

function methods:GetStringWidth()
    local width = #self.text * 7
    return self.width == 0 and width or math.min(self.width, width)
end

function methods:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then
        self.scripts.OnValueChanged(self, value)
    end
end

function methods:GetFrameLevel()
    return 1
end

function methods:GetFont()
    return "font", 12
end

function methods:GetSpacing()
    return 2
end

function methods:GetStringHeight()
    return math.ceil(math.max(1, #self.text) / 55) * 16
end

function methods:GetScript(event)
    return self.scripts[event]
end

function methods:SetScript(event, callback)
    self.scripts[event] = callback
end

function methods:HookScript(event, callback)
    local previous = self.scripts[event]
    self.scripts[event] = function(...)
        if previous then
            previous(...)
        end

        callback(...)
    end
end

function methods:Show()
    local wasShown = self.shown
    self.shown = true
    if not wasShown and self.scripts.OnShow then
        self.scripts.OnShow(self)
    end
end

function methods:Hide()
    self.shown = false
    if self.scripts.OnHide then
        self.scripts.OnHide(self)
    end
end

function methods:IsShown()
    return self.shown
end

function methods:SetShown(shown)
    self.shown = shown
end

function methods:SetFocus()
    self.focused = true
end

function methods:ClearFocus()
    self.focused = false
end

function methods:HasFocus()
    return self.focused
end

function methods:SetScrollChild(child)
    self.content = child
end

function methods:GetVerticalScrollRange()
    return math.max(0, self.content.height - self.height)
end

function methods:GetVerticalScroll()
    return self.offset
end

function methods:SetVerticalScroll(offset)
    self.offset = offset
    if self.scripts.OnVerticalScroll then
        self.scripts.OnVerticalScroll(self)
    end
end

function methods:Clear()
    self.text = ""
end

function methods:AddMessage(text)
    self.text = text
end

CreateFrame = function(_, name, parent, template)
    local f = frame(name, parent)
    if template == "InsetFrameTemplate" then
        f.Bg = frame(nil, f)
        f.NineSlice = frame(nil, f)
    end

    if template == "PortraitFrameFlatTemplate" then
        f.Bg = frame(nil, f)
        f.TitleContainer = frame(nil, f)
        f.TitleContainer.frameLevel = 510
        f.TitleContainer.TitleText = frame(nil, f.TitleContainer)
        f.TitleContainer.TitleBg = frame(nil, f.TitleContainer)
        f.NineSlice = frame(nil, f)
        f.NineSlice.frameLevel = 500
        f.NineSlice.TopEdge = frame(nil, f.NineSlice)
        f.NineSlice.TopEdge.height = 28
        f.PortraitContainer = frame(nil, f)
        f.PortraitContainer.portrait = frame(nil, f.PortraitContainer)
        f.CloseButton = frame(nil, f)
        f.GetPortrait = function(self)
            return self.PortraitContainer.portrait
        end

        f.SetBorder = function(self, layout)
            self.layout = layout
        end

        f.SetPortraitTextureSizeAndOffset = function(self, size, x, y)
            self:GetPortrait():SetSize(size, size)
            self:GetPortrait():SetPoint("TOPLEFT", self, "TOPLEFT", x, y)
        end

        f.SetTitleOffsets = function(self, left, right)
            self.titleOffsets = { left, right }
        end

        f.SetBackgroundColor = function(self, color)
            self.nativeBackground = true
            self.nativeBackgroundColor = color
        end
    end

    if template == "ButtonFrameTemplate" then
        f.Inset = frame(nil, f)
    end

    return f
end

GameTooltip = {
    IsOwned = function()
        return false
    end,

    Hide = noop,
    SetOwner = noop,
    SetText = noop,
    Show = noop,
}

UIParent = frame()
UIParent:SetSize(1920, 1080)
UISpecialFrames = {}
ButtonFrameTemplate_HideButtonBar = noop
ScrollUtil = { InitScrollFrameWithScrollBar = noop }
C_Timer = {
    After = function(_, callback)
        queue[#queue + 1] = callback
    end,
}

date = os.date
Whispr = {
    db = {
        char = { conversations = {}, sequence = 0 },
        global = { animateWindows = false, maxPeople = 50, maxMessages = 20, smileys = true, timestamps = true },
    },
}

load("history")
load("characters")
assert(loadfile("extensions/emoji/emotes.lua"))("Whispr", addon)
assert(loadfile("extensions/emoji/renderer.lua"))("Whispr", addon)
load("format")
load("composer")
load("theme")
assert(loadfile("tests/support/themes.lua"))(addon)
load("ui")
load("info")
load("actions")
load("window")
load("extensions")
assert(loadfile("extensions/emoji/module.lua"))("Whispr", addon)
assert(loadfile("extensions/keywords/module.lua"))("Whispr", addon)
addon.Extensions:Start()
local Window, History = addon.Window, addon.History

local function add(name, text)
    local c = History.Add(Whispr.db.char, Whispr.db.global, name, text, false, 1, Window:IsReading(History.Key(name)))
    Window:Refresh(c.key)
    flush()
end

Window:Open("First Last")
flush()
for i = 1, 10 do
    add("First Last", "Message " .. i)
end

equal(Window.scroll:GetVerticalScroll(), Window.scroll:GetVerticalScrollRange(), "follow new messages at bottom")
Window.scroll:SetVerticalScroll(120)
equal(Window.following, false, "scrolling away disables follow")
equal(Window.latest:IsShown(), true, "floating down arrow appears away from bottom")
add("First Last", "while reading")
equal(Window.scroll:GetVerticalScroll(), 120, "new messages preserve viewport")
equal(Whispr.db.char.conversations["first last"].unread, 1, "scrolled-away unread")
Window:Latest()
equal(Window.following, true, "latest resumes follow")
equal(Window.latest:IsShown(), false, "floating down arrow hides at bottom")
equal(Whispr.db.char.conversations["first last"].unread, 0, "latest marks read")
Whispr.db.global.maxMessages = 11
Window.scroll:SetVerticalScroll(120)
local oldSecondY = Window.bubbles[2].y
add("First Last", "prunes oldest")
equal(Window.scroll:GetVerticalScroll(), 120 - (oldSecondY - Window.bubbles[1].y), "pruning preserves visible anchor")
Window.input:SetText("saved draft")
Window:Detach("First Last")
flush()
local separate = Window.detached["first last"]
assert(separate.frame ~= Window.frame, "separate controllers must own distinct frames")
equal(separate.input:GetText(), "saved draft", "draft moves into popout")
equal(Window.active, nil, "hub releases popped-out conversation")
separate.input:SetText("edited draft")
separate:Dock()
flush()
equal(Window.detached["first last"], nil, "docking removes detached routing")
equal(Window.input:GetText(), "edited draft", "dock transfers draft")
Window.input:SetText("changed after docking")
Window:Detach("First Last")
flush()
equal(Window.detached["first last"], separate, "popout frames are reused")
equal(separate.input:GetText(), "changed after docking", "reused popout keeps the current draft")
Window:Open("Other Person")
flush()
equal(Window.active, "other person", "hub selection independent of popout")
equal(separate.active, "first last", "popout selection retained")
separate.scroll:SetVerticalScroll(120)
add("First Last", "background update")
equal(separate.following, false, "popout follows its own scroll state")
Whispr.db.global.separateWindows = true
Window:Open("Third Person")
flush()
assert(Window.detached["third person"], "separate-window preference routes new chats")
Whispr.db.global.separateWindows = false
load("battlenet")
local bn = addon.BattleNet.Ensure({ key = "bnet:friend#1234", name = "Friend", battleTag = "Friend#1234" })
Window:Open(bn.key)
flush()
equal(Window.active, bn.key, "Battle.net window retains its account key")
equal(Window.header:GetText(), "Friend", "Battle.net displays a friendly name")
Window:Detach(bn.key)
flush()
Window.detached[bn.key]:Dock()
flush()
equal(Window.active, bn.key, "Battle.net docking retains identity")
local scroll = Window.scroll
scroll.content:SetHeight(1)
scroll.scripts.OnScrollRangeChanged()
equal(scroll.ScrollBar:IsShown(), false, "scroll thumb hidden without overflow")
scroll.content:SetHeight(900)
scroll.scripts.OnScrollRangeChanged()
equal(scroll.ScrollBar:IsShown(), true, "scroll thumb visible with overflow")
scroll.ScrollBar:SetValue(75)
equal(scroll:GetVerticalScroll(), 75, "dragging thumb changes scroll position")
local avatar = addon.UI.Avatar(Window.frame, 28)
local previousCoords = CLASS_ICON_TCOORDS
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
SetPortraitTexture = function()
    error("character portraits are disabled")
end

avatar:SetCharacter({ key = "class person", name = "Class Person", character = { classFile = "WARRIOR" } })
assert(avatar.icon.texture:find("assets\\classes\\warrior.tga", 1, true), "characters always use class icons")
avatar:SetCharacter({ key = "unknown", name = "Unknown" })
assert(avatar.icon.texture:find("INV_Misc_QuestionMark", 1, true), "unknown class uses fallback icon")
avatar:SetCharacter({ key = "bnet:test", name = "Test", transport = "bnet" })
assert(avatar.icon.texture:find("Battlenet", 1, true), "Battle.net retains its account icon")
CLASS_ICON_TCOORDS = previousCoords

bn.archived = true
History.Trim(Whispr.db.char, Whispr.db.global)
equal(bn.archived, nil, "legacy archived conversation is restored")
assert(Whispr.db.char.conversations[bn.key], "legacy archived history retained")
Window:Open(bn.key)
flush()
Window.input:SetText("delete this draft")
Window:Delete(bn.key)
flush()
equal(Whispr.db.char.conversations[bn.key], nil, "delete removes history")
equal(Window.drafts[bn.key], nil, "delete removes draft")
local row = Window.rows[1]
row.scripts.OnClick(row)
flush()
print("Window following, retention anchoring, unread state, popouts, docking and drafts passed.")

Window.frame:SetWidth(500)
Window.frame.scripts.OnSizeChanged()
flush()
equal(Window.compact, true, "narrow main window collapses sidebar")
equal(Window.sidebar:IsShown(), false, "collapsed sidebar starts hidden")
equal(Window.drawerToggle:IsShown(), true, "narrow window exposes conversation button")
Window:SetDrawer(true)
equal(Window.sidebar:IsShown(), true, "drawer opens")
equal(Window.drawerShade:IsShown(), true, "drawer has outside click target")
Window.drawerShade.scripts.OnClick()
equal(Window.sidebar:IsShown(), false, "outside click closes drawer")
Window.frame:SetWidth(800)
Window.frame.scripts.OnSizeChanged()
flush()
equal(Window.sidebar:IsShown(), true, "wide window restores sidebar")
equal(Window.drawerToggle:IsShown(), false, "wide window hides drawer button")
local conversation = Whispr.db.char.conversations[row.key]
conversation.unread = 7
Window:RefreshUnread()
local total = 0
for _, c in pairs(Whispr.db.char.conversations) do
    total = total + c.unread
end

equal(Window.unreadCount:GetText(), tostring(total), "badge totals unread messages")
local combat = true
InCombatLockdown = function()
    return combat
end

Whispr.db.global.noOpenInCombat = true
Window.frame:Hide()
Window:Receive(conversation.key)
equal(Window.frame:IsShown(), false, "combat incoming whispers do not open window")
Window.frame:Show()
Window:Receive(conversation.key)
equal(Window.frame:IsShown(), true, "no-open setting leaves existing window visible")
Whispr.db.global.hideInCombat = true
Window:CombatChanged(true)
equal(Window.frame:IsShown(), false, "hide setting hides existing window")
Window:Open(conversation.key)
equal((Window.detached[conversation.key] or Window).frame:IsShown(), true, "manual open bypasses combat hiding")
combat = false
Window:CombatChanged(false)
equal(Window.frame:IsShown(), true, "combat exit restores previously open window")
StaticPopupDialogs = {}
ACCEPT = "Accept"
CANCEL = "Cancel"
local popupData
StaticPopup_Show = function(_, _, _, data)
    popupData = data
end

Window:ConfirmAction("delete", conversation.key)
equal(Whispr.db.char.conversations[conversation.key], conversation, "delete waits for confirmation")
StaticPopupDialogs.WHISPR_CONVERSATION_ACTION.OnAccept(nil, popupData)
flush()
equal(Whispr.db.char.conversations[conversation.key], nil, "confirmed delete applies")
print("Responsive sidebar, unread badge, combat settings and confirmations passed.")
Whispr.db.global.hideInCombat = false
Whispr.db.global.noOpenInCombat = true
combat = true
Window.frame:Hide()
local deferred = History.Add(Whispr.db.char, Whispr.db.global, "Combat Friend", "during combat", false, 1, false)
Window:Receive(deferred.key)
equal(Window.frame:IsShown(), false, "held whisper stays hidden during combat")
combat = false
Window:CombatChanged(false)
flush()
equal(Window.frame:IsShown(), true, "held whisper opens on combat end")
equal(Window.combatMessages, nil, "deferred queue clears after combat")

-- Showing a hidden conversation at the bottom clears the read state.
Window:Open(deferred.key)
flush()
Window.frame:Hide()
deferred.unread = 3
Window.frame:Show()
equal(deferred.unread, 0, "reopened visible conversation marks messages read")
Window.following = false
Window.frame:Hide()
deferred.unread = 2
Window.frame:Show()
equal(deferred.unread, 2, "reopened scrolled-away conversation stays unread")
Window:Latest()
flush()
equal(deferred.unread, 0, "latest clears unread after reopening")
Window:Detach(deferred.key)
flush()
local separate = Window.detached[deferred.key]
separate.frame:Hide()
deferred.unread = 4
Window:RefreshList()
separate.frame:Show()
equal(deferred.unread, 0, "separate window reopening marks read")
for _, item in ipairs(Window.rows) do
    if item.key == deferred.key then
        equal(item.badge:IsShown(), false, "main list badge updates from separate window")
    end
end

Minimap = frame()
Minimap:SetSize(140, 140)
local broker, dbIcon = {}, {}

function broker:NewDataObject(_, object)
    return object
end

function dbIcon:IsRegistered()
    return self.button ~= nil
end

function dbIcon:Register(_, object, db)
    self.button = frame()
    self.button.background = frame()
    self.db = db
    self.object = object
end

function dbIcon:GetMinimapButton()
    return self.button
end

function dbIcon:Show()
    self.button:Show()
end

function dbIcon:Hide()
    self.button:Hide()
end

function dbIcon:Refresh(_, db)
    self.db = db
end

LibStub = function(name)
    return name == "LibDBIcon-1.0" and dbIcon or broker
end

Whispr.db.global.minimapAngle = 123
load("minimap")
addon.Minimap:Enable()
equal(addon.Minimap.button:IsShown(), true, "minimap icon enabled")
equal(dbIcon.db, Whispr.db.global.minimap, "LibDBIcon receives AceDB profile table")
equal(dbIcon.db.minimapPos, 123, "old minimap position migrated")
equal(Whispr.db.global.minimapAngle, nil, "migration only runs once")
local entries
MenuUtil = {
    CreateContextMenu = function(_, generate)
        entries = {}
        generate(nil, {
            CreateButton = function(_, label, action)
                local entry = { label = label, action = action, SetEnabled = noop }
                entries[#entries + 1] = entry
                return entry
            end,

            CreateDivider = function()
                entries[#entries + 1] = { divider = true }
            end,
        })
    end,
}

Whispr.db.global.maxPeople = 50
for i = 1, 12 do
    History.Add(Whispr.db.char, Whispr.db.global, "Recent " .. i, "hi", false, 1, false)
end

addon.Minimap:Menu(addon.Minimap.button)
equal(#entries, 13, "menu has two actions, divider and ten conversations")
equal(entries[1].label, "Open Whispr", "open window first")
equal(entries[2].label, "Settings", "settings second")
equal(entries[3].divider, true, "divider before recents")
equal(entries[4].label, "Recent 12 (1)", "newest conversation first with unread")
equal(entries[13].label, "Recent 3 (1)", "only ten newest conversations")
entries[4].action()
flush()
equal(Window.active, "recent 12", "menu opens matching identity")
equal(Whispr.db.char.conversations["recent 12"].unread, 0, "menu opening marks read")
addon.Minimap:Menu(addon.Minimap.button)
equal(entries[4].label, "Recent 12", "menu reflects cleared unread count")
addon.Minimap:Disable()
equal(addon.Minimap.button:IsShown(), false, "minimap icon disabled")
print("Minimap recent menu and read-state synchronization passed.")
Window:SetWindowFocus(false)
Window.frame.mouseOver = false
Whispr.db.global.fadeWhenIdle = true
Whispr.db.global.idleOpacity = 0.3
Whispr.db.global.idleFadeDelay = 0
Whispr.db.global.windowOpacity = 0.9
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.3, "idle window becomes see-through")
Window.frame.mouseOver = true
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.9, "hover restores active opacity")
Window.frame.mouseOver = false
Window.input:SetFocus()
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.9, "typing retains active opacity outside window")
Window.input:ClearFocus()
Whispr.db.global.fadeWhenIdle = false
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.9, "idle fade can be disabled")
local surface = {
    SetColorTexture = function(self, ...)
        self.color = { ... }
    end,
}

addon.Theme:Paint(surface, "windowColor")
Whispr.db.global.windowColor = { 0.2, 0.3, 0.4 }
Whispr.db.global.backgroundOpacity = 0.5
addon.Theme:Refresh()
equal(surface.color[1], 0.2, "theme updates already-created surfaces")
equal(surface.color[4], 0.5, "background opacity applies separately from text")
print("Live window colors, background transparency and idle focus opacity passed.")
local person = Whispr.db.char.conversations["recent 12"]
local invited
C_PartyInfo = {
    InviteUnit = function(name)
        invited = name
    end,
}

Window:Open(person.key)
flush()
local bubble = Window.bubbles[1]
local payload = addon.Format.Message("inv", false, 14, person.key):match("|H(.-)|h")
Window:Link(payload, "inv", "LeftButton", person.key)
equal(invited, person.name, "invite links invite matching full character name")
invited = nil
Window:Link(payload, "inv", "LeftButton", "someone else")
equal(invited, nil, "mismatched invite payload rejected")
Window:Link(payload, "inv", "RightButton", person.key)
equal(invited, nil, "right click cannot send invite")
GameTooltip.SetHyperlink = function()
    error("hover must not open item tooltip")
end

bubble.scripts.OnHyperlinkEnter(bubble, "item:123")
local clicked
SetItemRef = function(link)
    clicked = link
end

Window:Link("item:123", "item", "LeftButton")
equal(clicked, "item:123", "item clicks still use native behavior")
local other = Whispr.db.char.conversations["recent 11"]
Window:Open(person.key)
flush()
assert(Window.headerActions.invite:IsShown(), "active conversation shows quick actions")
invited = nil
Window.headerActions.invite.scripts.OnClick()
equal(invited, person.name, "header invite targets active person")
Window:Open(other.key)
flush()
Window.headerActions.invite.scripts.OnClick()
equal(invited, other.name, "header action follows conversation switch")
Window:Detach(other.key)
flush()
local popped = Window.detached[other.key]
popped.headerActions.invite.scripts.OnClick()
equal(invited, other.name, "separate window has same quick actions")
Window:Select(nil)
flush()
equal(Window.headerActions.invite:IsShown(), false, "empty header hides quick actions")
local ignoredName, isIgnored
C_FriendList = {
    IsOnIgnoredList = function()
        return isIgnored
    end,

    AddIgnore = function(name)
        ignoredName = name
        isIgnored = true
    end,

    DelIgnore = function(name)
        ignoredName = name
        isIgnored = false
    end,
}

popped:RefreshHeaderActions()
popped.headerActions.block.scripts.OnClick()
equal(ignoredName, other.name, "quick ignore uses correct target")
equal(popped.headerActions.block.tooltip, "Unignore character", "quick ignore becomes unignore")
popped.headerActions.block.scripts.OnClick()
equal(isIgnored, false, "quick unignore removes ignore")
print("Quick header actions, target switching, separate windows and ignore state passed.")
Window.frame:SetSize(720, 440)
Window.frame:SetScale(1)
Window.frame.centerX, Window.frame.centerY = 1000, 600
Window:SaveGeometry()
equal(Whispr.db.char.window.width, 720, "main width saved in character AceDB")
equal(Whispr.db.char.window.height, 440, "main height saved")
popped.frame:SetSize(490, 370)
popped.frame:SetScale(1)
popped.frame.centerX, popped.frame.centerY = 1100, 650
popped:SaveGeometry()
equal(other.window.width, 490, "popout geometry stored on its conversation")
equal(Whispr.db.char.window.width, 720, "popout does not overwrite main geometry")

local function recreated(owner, key)
    return setmetatable({ rows = {}, bubbles = {}, drafts = {}, following = true, owner = owner, geometryKey = key }, {
        __index = function(_, method)
            if type(Window[method]) == "function" then
                return Window[method]
            end
        end,
    })
end

local restored = recreated()
restored:Create()
equal(restored.frame:GetWidth(), 720, "fresh main controller restores width")
equal(restored.frame:GetHeight(), 440, "fresh main controller restores height")
equal(math.floor(restored.frame.lastPoint[4] + 0.5), 40, "main position restored")
local restoredPop = recreated(Window, other.key)
restoredPop:Create()
equal(restoredPop.frame:GetWidth(), 490, "fresh popout restores its own width")
equal(restoredPop.frame:GetHeight(), 370, "fresh popout restores its own height")
equal(math.floor(restoredPop.frame.lastPoint[4] + 0.5), 140, "popout position restored")
other.window.x, other.window.y = 10, 10
UIParent:SetSize(800, 600)
restoredPop:RestoreGeometry()
assert(
    restoredPop.frame.lastPoint[4] <= 155 and restoredPop.frame.lastPoint[5] <= 115,
    "offscreen saved position clamped after screen change"
)
Whispr.db.global.clampWindowsToScreen = false
restoredPop:RestoreGeometry()
equal(restoredPop.frame.lastPoint[4], 8000, "disabled clamping restores offscreen horizontal position")
equal(restoredPop.frame.lastPoint[5], 6000, "disabled clamping restores offscreen vertical position")
local offscreenPop = recreated(Window, other.key)
offscreenPop:Create()
equal(offscreenPop.frame.clampedToScreen, false, "new popouts inherit disabled clamping")
equal(offscreenPop.frame.lastPoint[4], 8000, "recreated popouts retain offscreen position")
Window:UpdateScreenClamping()
equal(Window.frame.clampedToScreen, false, "main window updates clamping live")
for _, popup in pairs(Window.popouts) do
    equal(popup.frame.clampedToScreen, false, "existing popouts update clamping live")
end

Whispr.db.global.clampWindowsToScreen = true
Window:UpdateScreenClamping()
equal(Window.frame.clampedToScreen, true, "clamping can be enabled again")
restoredPop:RestoreGeometry()
assert(restoredPop.frame.lastPoint[4] <= 155, "reenabled clamping restores screen bounds")
assert(restored.location == nil, "chat header no longer creates location label")
UIParent:SetSize(1920, 1080)
Window.frame:SetWidth(740)
Window:SaveAllGeometry()
equal(Whispr.db.char.window.width, 740, "logout flush saves current geometry")
print("Main/popout geometry persistence, fresh restoration and screen bounds passed.")
Window.frame:Show()
addon.Minimap.dataObject.OnClick(addon.Minimap.button, "LeftButton")
equal(Window.frame:IsShown(), false, "minimap left click closes main window")
addon.Minimap.dataObject.OnClick(addon.Minimap.button, "LeftButton")
flush()
equal(Window.frame:IsShown(), true, "minimap left click opens main window")
entries = nil
addon.Minimap.dataObject.OnClick(addon.Minimap.button, "RightButton")
assert(entries and entries[1].label == "Open Whispr", "minimap right click opens menu")
equal(Window.frame:IsShown(), true, "right click does not toggle window")
equal(
    addon.Minimap.dataObject.icon,
    "Interface\\AddOns\\Whispr\\assets\\whispr-icon.tga",
    "broker uses custom whispr logo"
)
local recent = History.Sorted(Whispr.db.char)[1]
Window:Detach(recent.key)
flush()
local recentPopout = Window.detached[recent.key]
recentPopout.frame:Hide()
Window.frame:Hide()
addon.Minimap.dataObject.OnClick(addon.Minimap.button, "LeftButton")
flush()
equal(Window.frame:IsShown(), true, "main toggle works when newest conversation is detached")
equal(recentPopout.frame:IsShown(), false, "main toggle does not reopen detached windows")
print("Minimap left/right clicks, custom logo and main-only toggle passed.")

equal(
    addon.Minimap.button.background.texture,
    "Interface\\AddOns\\Whispr\\assets\\minimap-background.tga",
    "minimap backing uses bundled texture"
)
equal(addon.Minimap.button.background:IsShown(), true, "minimap backing is visible")
Whispr.db.global.fadeWhenIdle = true
Whispr.db.global.idleFadeDelay = 2
Window.input:ClearFocus()
Window.frame.mouseOver = false
Window.frame:Hide()
clockTime = 100
Window.frame:Show()
equal(Window.frame.alpha, 0.9, "opening starts at active opacity without focus")
clockTime = 101.9
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.9, "new window remains active during grace period")
clockTime = 102
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.3, "idle opacity begins after configured delay")
Window.frame.mouseOver = true
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.9, "hover immediately restores active opacity")
Window.frame.mouseOver = false
clockTime = 110
Window:UpdateOpacity()
clockTime = 111.9
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.9, "leaving hover starts a fresh delay")
Window.input:SetFocus()
Window:UpdateOpacity()
clockTime = 120
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.9, "typing cancels idle countdown")
Window.input:ClearFocus()
Window:UpdateOpacity()
clockTime = 122
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.3, "losing keyboard focus starts a fresh delay")
Window.frame:Hide()
clockTime = 140
Window.frame:Show()
equal(Window.frame.alpha, 0.9, "reopening faded window resets old countdown")
local isolated = recreated(Window, other.key)
isolated:Create()
isolated.frame:Show()
clockTime = 141
isolated:UpdateOpacity()
equal(isolated.frame.alpha, 0.9, "separate windows have opening grace period")
clockTime = 143
isolated:UpdateOpacity()
equal(isolated.frame.alpha, 0.3, "separate window fades after its own delay")
print("Idle fade delay, opening grace period, hover/focus cancellation and popouts passed.")
SettingsPanel = frame()
SettingsPanel:Show()
Window:UpdateOpacity()
isolated:UpdateOpacity()
equal(Window.frame.alpha, 0.9, "settings restores main window active opacity")
equal(isolated.frame.alpha, 0.9, "settings restores popout active opacity")
clockTime = 200
Window:UpdateOpacity()
isolated:UpdateOpacity()
equal(Window.frame.alpha, 0.9, "settings keeps windows visible beyond idle delay")
SettingsPanel:Hide()
Window:UpdateOpacity()
isolated:UpdateOpacity()
clockTime = 201.9
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.9, "closing settings starts a fresh idle delay")
clockTime = 202
Window:UpdateOpacity()
isolated:UpdateOpacity()
equal(Window.frame.alpha, 0.3, "main window fades again after settings closes")
equal(isolated.frame.alpha, 0.3, "popout fades again after settings closes")
SettingsPanel = nil
InterfaceOptionsFrame = frame()
InterfaceOptionsFrame:Show()
isolated:UpdateOpacity()
equal(isolated.frame.alpha, 0.9, "legacy settings also suppress idle fade")
InterfaceOptionsFrame = nil
print("Settings suspends idle fading for main and separate windows, then restores the delay.")

function methods:CreateAnimationGroup()
    local group = {
        Play = function(self)
            self.playing = true
        end,

        Stop = function(self)
            self.playing = false
        end,
    }

    function group:CreateAnimation()
        local anim = { SetOrigin = noop, SetSmoothing = noop, SetDuration = noop }

        function anim:SetScaleFrom(x, y)
            self.from = x
        end

        function anim:SetScaleTo(x, y)
            self.to = x
        end

        return anim
    end

    return group
end

Whispr.db.global.animateWindows = true
Whispr.db.global.idleFadeDelay = 4
Window:HideImmediately()
Window.input:ClearFocus()
Window.frame.mouseOver = false
clockTime = 200
Window:Show()
equal(Window.frame.alpha, 0, "open animation starts transparent")
clockTime = 200.09
Window:StepAnimation()
assert(Window.frame.alpha > 0 and Window.frame.alpha < 0.9, "opening smoothly interpolates alpha")
clockTime = 200.2
Window:StepAnimation()
equal(Window.frame.alpha, 0.9, "open animation ends at active opacity")
clockTime = 204
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.9, "idle fade starts without snapping")
clockTime = 204.15
Window:StepAnimation()
assert(Window.frame.alpha > 0.3 and Window.frame.alpha < 0.9, "idle fade smoothly interpolates alpha")
clockTime = 204.31
Window:StepAnimation()
equal(Window.frame.alpha, 0.3, "idle fade ends at configured opacity")
Window.frame.mouseOver = true
Window:UpdateOpacity()
clockTime = 204.5
Window:StepAnimation()
equal(Window.frame.alpha, 0.9, "hover fades back to active opacity")
Window.frame:Hide()
assert(Window.closing and Window.frame:IsShown(), "native close request waits for close animation")
clockTime = 204.56
Window:StepAnimation()
assert(Window.frame.alpha > 0 and Window.frame.alpha < 0.9, "close animation interpolates")
Window:Show()
assert(not Window.closing, "reopen cancels pending close")
clockTime = 205
Window:StepAnimation()
equal(Window.frame:IsShown(), true, "cancelled close never hides reopened window")
Window:Close()
clockTime = 205.2
Window:StepAnimation()
equal(Window.frame:IsShown(), false, "close hides frame after animation")
equal(Window.motion, nil, "window transitions never scale message content")
Window:Show()
Whispr.db.global.hideInCombat = true
Window:CombatChanged(true)
equal(Window.frame:IsShown(), false, "combat hiding stays immediate")
print("Opening, closing, idle fades, interrupted close and immediate combat hiding passed.")
Whispr.db.global.animateWindows = false
Whispr.db.global.hideInCombat = true
Whispr.db.global.separateWindows = false
if Window.detached[person.key] then
    Window.detached[person.key]:Dock()
end

combat = true
Window:Open(person.key)
flush()
equal(Window.frame:IsShown(), true, "manual combat opening allowed")
Window:CombatChanged(true)
equal(Window.frame:IsShown(), true, "settings refresh preserves manual combat override")
Window:Close()
Window:Receive(person.key)
equal(Window.frame:IsShown(), false, "incoming whisper cannot bypass combat hide")
combat = false
Window:CombatChanged(false)
equal(Window.manualCombatOpen, nil, "manual override expires after combat")
equal(Window.frame:IsShown(), false, "read conversation manually closed stays closed after combat")
Window:Open(person.key)
combat = true
Window:CombatChanged(true)
equal(Window.frame:IsShown(), false, "next combat hides normally again")
Window:Detach(person.key)
flush()
local manualPopout = Window.detached[person.key]
equal(manualPopout.frame:IsShown(), true, "manual separate window opens during combat")
Window:CombatChanged(true)
equal(manualPopout.frame:IsShown(), true, "manual popout retains combat override")
print("Manual combat override, incoming suppression and next-combat reset passed.")
combat = false
Window:CombatChanged(false)
Whispr.db.global.separateWindows = false
local senderA = History.Add(Whispr.db.char, Whispr.db.global, "Sender A", "hello", false, 1, false)
local senderB = History.Add(Whispr.db.char, Whispr.db.global, "Sender B", "hello", false, 1, false)
Window:Open(senderA.key)
flush()
Window.input:SetText("draft for A")
Window.input:SetFocus()
Window:Receive(senderB.key)
flush()
equal(Window.active, senderA.key, "incoming sender cannot interrupt typing")
equal(Window.input:GetText(), "draft for A", "typing draft stays intact")
assert(Window.input:HasFocus(), "typing retains keyboard focus")
equal(senderB.unread, 1, "other sender remains unread while typing")
Window.input:ClearFocus()
Window:Receive(senderB.key)
flush()
equal(Window.active, senderB.key, "incoming message selects sender conversation")
equal(Window.drafts[senderA.key], "draft for A", "automatic switch preserves previous draft")
equal(Window.input:HasFocus(), false, "automatic switch does not redirect keyboard input")
Window.following = false
Window:Receive(senderB.key)
equal(Window.following, false, "same-sender message preserves reading position")
local bnSender = History.Add(Whispr.db.char, Whispr.db.global, "Bnet Friend", "hi", false, 1, false, "bnet:friend#9876")
bnSender.transport = "bnet"
Window:Receive(bnSender.key)
flush()
equal(Window.active, bnSender.key, "incoming Battle.net conversation selected")
Window.input:SetFocus()
Window.input:SetText("   ")
Window:Receive(senderA.key)
flush()
equal(Window.active, bnSender.key, "focused whitespace-only composer blocks switching")
Window.input:ClearFocus()
Window:Receive(senderA.key)
flush()
Window.input:SetFocus()
Window.input:SetText("typing to A")
Window:Receive(bnSender.key)
flush()
equal(Window.active, senderA.key, "Battle.net arrival also preserves active typing")
Window.input:SetText("")
Window:Receive(bnSender.key)
flush()
equal(Window.active, senderA.key, "clearing draft does not switch a focused conversation")
Window.input:ClearFocus()
Window:Receive(bnSender.key)
flush()
equal(Window.active, bnSender.key, "automatic switching waits for input to lose focus")
combat = true
Window:CombatChanged(true)
senderA.unread = 1
senderB.unread = 1
Window:Receive(senderB.key)
Window:Receive(senderA.key)
equal(Window.active, bnSender.key, "combat defers conversation switches")
combat = false
Window:CombatChanged(false)
flush()
equal(Window.active, senderB.key, "newest queued conversation remains selected after combat")
print("Incoming conversation selection, preserved drafts/scroll and deferred order passed.")
-- Isolate sidebar ordering from the earlier controller scenarios.
Whispr.db.char = { conversations = {}, sequence = 0 }
Whispr.db.global.separateWindows = false
Whispr.db.global.animateWindows = false
Whispr.db.global.hideInCombat = false
combat = false
local inbox = recreated()
inbox.detached = {}
inbox.popouts = {}
inbox:Create()

local function seed(name)
    return History.Add(Whispr.db.char, Whispr.db.global, name, "message", false, 1, false)
end

local oldest, middle, newest = seed("Oldest"), seed("Middle"), seed("Newest")
inbox:Open(middle.key)
flush()
inbox:Delete(middle.key)
flush()
equal(inbox.active, oldest.key, "deleting middle row selects row below it")
inbox:Delete(oldest.key)
flush()
equal(inbox.active, newest.key, "deleting last row selects previous row")
local inactive = seed("Inactive")
inbox:Delete(inactive.key)
flush()
equal(inbox.active, newest.key, "deleting inactive row keeps active conversation")
inbox:Delete(newest.key)
flush()
equal(inbox.active, nil, "empty inbox clears selection")
newest = seed("Newest")
inbox:Open(newest.key)
flush()
local detached = seed("Detached")
local above = seed("Above")
inbox:Detach(detached.key)
flush()
inbox:Open(above.key)
flush()
inbox:Delete(above.key)
flush()
equal(inbox.active, newest.key, "selection skips conversations already in separate windows")
print("Delete neighbor selection, previous fallback and inactive rows passed.")
for _, conversation in pairs(Whispr.db.char.conversations) do
    conversation.unread = 0
end

assert(loadfile("extensions/floating-button/module.lua"))("Whispr", addon)
flush()
local floating = Whispr:GetExtension("floating_button")
equal(floating:IsEnabled(), false, "floating button disabled by default")
equal(floating.frame, nil, "disabled floating button creates no frame")
floating:Enable()
assert(floating:IsEnabled(), addon.Extensions.entries.floating_button.error)
equal(floating.frame:GetWidth(), 40, "default floating button size")
floating.options.args.size.set(nil, 64)
equal(floating.frame:GetWidth(), 64, "floating button size updates immediately")
local originalClick = addon.Minimap.Click
local clicks = 0
addon.Minimap.Click = function(_, owner, mouseButton)
    equal(owner, floating.frame, "floating menu anchor")
    equal(mouseButton, "RightButton", "floating forwards mouse button")
    clicks = clicks + 1
end

floating.frame.scripts.OnMouseDown()
floating.frame.scripts.OnClick(floating.frame, "RightButton")
equal(clicks, 1, "floating uses minimap actions")
floating.frame.scripts.OnDragStart()
floating.frame.centerX, floating.frame.centerY = 1100, 650
floating.frame.scripts.OnDragStop()
floating.frame.scripts.OnClick(floating.frame, "LeftButton")
equal(clicks, 1, "drag does not trigger click")
equal(floating:GetSettings().x, 140, "floating saves horizontal position")
equal(floating:GetSettings().y, 110, "floating saves vertical position")
addon.Minimap.Click = originalClick
floating:Disable()
equal(floating.frame:IsShown(), false, "disable hides floating button")
floating:Enable()
equal(floating.frame.lastPoint[4], 140, "reenable restores saved position")
equal(floating.frame:GetWidth(), 64, "reenable preserves size")
floating.options.args.reset.func()
equal(floating.frame.lastPoint[2], Minimap, "reset restores minimap anchor")
equal(floating.frame.lastPoint[1], "RIGHT", "button right edge faces minimap")
equal(floating.frame.lastPoint[3], "LEFT", "button sits left of minimap")
equal(floating.frame.lastPoint[4], -12, "button has a gap from minimap")
addon.Minimap:UpdateUnread()
equal(addon.Minimap.badge:IsShown(), false, "minimap badge hidden with no unread messages")
newest.unread = 2
detached.unread = 3
inbox:RefreshUnread()
equal(floating.badgeCount:GetText(), "5", "floating totals unread messages")
equal(floating.badge:IsShown(), true, "floating badge visible")
equal(addon.Minimap.badgeCount:GetText(), "5", "minimap totals unread messages across conversations")
equal(addon.Minimap.badge:IsShown(), true, "minimap badge shown for unread messages")
newest.unread = 120
inbox:RefreshUnread()
equal(addon.Minimap.badgeCount:GetText(), "99+", "minimap count caps at 99+")
equal(floating.badgeCount:GetText(), "99+", "floating overflow count")
equal(addon.Minimap.unread, 123, "tooltip retains exact unread total")
newest.unread = 1
detached.unread = 0
inbox:Open(newest.key)
flush()
equal(floating.badge:IsShown(), false, "reading clears floating badge")
equal(addon.Minimap.badge:IsShown(), false, "reading active conversation clears minimap badge")
local unopened = recreated()
unopened.detached = {}
unopened.popouts = {}
newest.unread = 4
unopened:RefreshUnread()
equal(addon.Minimap.badgeCount:GetText(), "4", "minimap refresh works before any chat frame is created")
inbox:Delete(newest.key)
flush()
equal(floating.badge:IsShown(), false, "deleting clears floating badge")
floating:Disable()
equal(addon.Extensions.listeners.UNREAD_CHANGED.floating_button, nil, "disable removes unread subscription")
equal(addon.Minimap.badge:IsShown(), false, "deleting unread conversation clears minimap badge")
addon.Minimap:Enable()
equal(addon.Minimap.badge:IsShown(), false, "enable restores correct badge state")
print("Minimap unread totals, read/delete clearing, overflow and unopened inbox passed.")

local smileChat = seed("Smile picker")
inbox:Open(smileChat.key)
flush()
inbox.input:SetText("before  after")
inbox.input:SetCursorPosition(7)
inbox.emoteButton.scripts.OnClick()
local picker = inbox.emotePicker
equal(#picker.buttons, 22, "picker contains each smiley exactly once")
picker.buttons[1].scripts.OnClick()
equal(inbox.input:GetText(), "before :)  after", "smiley text inserted at middle caret")
equal(inbox.input:GetCursorPosition(), 10, "caret follows inserted text")
equal(inbox.input:HasFocus(), true, "selection returns focus to composer")
equal(picker:IsShown(), true, "selection keeps picker open")
local originalInsert = inbox.input.Insert
inbox.input.Insert = function(input, text)
    originalInsert(input, text)
    input.scripts.OnTextChanged(input)
end

picker.buttons[4].scripts.OnClick()
equal(inbox.input:GetText(), "before :) :P  after", "second smiley follows first at updated caret")
equal(picker:IsShown(), true, "insertion text events keep picker open")
inbox.input.Insert = originalInsert
-- Native text/formatting notifications can arrive after OnClick returns.
inbox.input.scripts.OnTextChanged(inbox.input)
equal(picker:IsShown(), true, "delayed text event cannot dismiss picker")
picker.buttons[1].mouseOver = true
picker.scripts.OnEvent()
equal(picker:IsShown(), true, "emoji child click counts as inside popup")
picker.buttons[1].mouseOver = false
inbox.input:SetCursorPosition(0)
picker.buttons[1].scripts.OnClick()
equal(inbox.input:GetText(), ":) before :) :P  after", "picker uses current caret after moving it")
equal(picker:IsShown(), true, "multiple selections keep popup open")
picker.scripts.OnEvent()
equal(picker:IsShown(), false, "outside click dismisses picker")
inbox:ToggleEmotes()
picker.mouseOver = true
picker.scripts.OnEvent()
equal(picker:IsShown(), true, "inside click leaves picker available")
picker.mouseOver = false
inbox:Select(nil)
equal(picker:IsShown(), false, "conversation switch dismisses picker")
inbox:ToggleEmotes()
equal(picker:IsShown(), false, "cannot insert without active conversation")
inbox:Open(smileChat.key)
inbox:Detach(smileChat.key)
flush()
local smilePop = inbox.detached[smileChat.key]
smilePop.input:SetText("hello ")
smilePop.input:SetCursorPosition(6)
smilePop:ToggleEmotes()
smilePop.emotePicker.buttons[4].scripts.OnClick()
equal(smilePop.input:GetText(), "hello :P ", "popout picker inserts plain text")
smilePop.input.scripts.OnEscapePressed(smilePop.input)
equal(smilePop.emotePicker:IsShown(), false, "escape dismisses picker")
print("Smiley picker, caret insertion, popouts and dismissal checks passed.")

Whispr.db.global.separateWindows = false
local modeChat = seed("Mode conversation")
local manualChat = seed("Manual popout")
Window:Open(manualChat.key)
Window:Detach(manualChat.key)
flush()
local manualWindow = Window.detached[manualChat.key]
Window:Open(modeChat.key)
flush()
Window.input:SetText("draft before mode switch")
Window:SetSeparateMode(true)
flush()
equal(Window.frame:IsShown(), false, "separate mode immediately hides inbox")
local standalone = Window.detached[modeChat.key]
equal(standalone.standalone, true, "mode window is distinct from manual popout")
equal(standalone.input:GetText(), "draft before mode switch", "mode switch preserves draft")
standalone:Dock()
equal(Window.frame:IsShown(), false, "docking cannot reopen inbox in separate mode")
standalone.pop.scripts.OnClick(standalone.pop)
for _, entry in ipairs(entries) do
    assert(entry.label ~= "Dock in main window", "no dock action in separate mode")
end

for i = 1, 12 do
    seed("Mode recent " .. i)
end

addon.Minimap:Click(addon.Minimap.button, "LeftButton")
equal(#entries, 10, "separate mode left click contains only ten recent conversations")
equal(entries[1].label, "Mode recent 12 (1)", "recents are newest first with unread count")
entries[1].action()
flush()
equal(Window.frame:IsShown(), false, "recent selection leaves inbox hidden")
assert(Window.detached["mode recent 12"].frame:IsShown(), "recent opens its own window")
Window:Open()
equal(#entries, 10, "unnamed open uses recent menu in separate mode")
Window:Show()
equal(Window.frame:IsShown(), false, "inbox show remains suppressed")
standalone.input:SetText("draft after mode switch")
Window:SetSeparateMode(false)
flush()
equal(Window.frame:IsShown(), true, "disabling mode restores inbox")
equal(Window.detached[modeChat.key], nil, "mode windows return to inbox")
equal(Window.detached[manualChat.key], manualWindow, "manual popout is preserved independently")
Window:Open(modeChat.key)
flush()
equal(Window.input:GetText(), "draft after mode switch", "return to inbox preserves updated draft")
print("Separate mode routing, recent menu, independent popouts and draft transfer passed.")

Window:Open(modeChat.key)
flush()
Window.frame:SetWidth(360)
Window:Layout()
local encoded = ("https://example.com"):gsub(".", function(char)
    return string.format("%02x", char:byte())
end)

Window:Link("whisprurl:" .. encoded, nil, "LeftButton")
equal(Window.url:GetWidth(), 336, "link dialog fits narrow window")
equal(Window.url.input:GetText(), "https://example.com", "copy field uses original URL")
Window.url.close.scripts.OnClick()
equal(Window.url:IsShown(), false, "visible close icon dismisses link dialog")
equal(Window.url.input:HasFocus(), false, "dismissal releases copy field focus")
Window:Link("whisprurl:" .. encoded, nil, "LeftButton")
Window.url.input.scripts.OnEscapePressed()
equal(Window.url:IsShown(), false, "Escape dismisses link dialog")
Window:Link("whisprurl:" .. encoded, nil, "LeftButton")
Window.url.parent.scripts.OnClick()
equal(Window.url:IsShown(), false, "click outside dismisses link dialog")
print("Compact link modal, close icon, Escape and outside dismissal passed.")

Window:Open(modeChat.key)
flush()
local people = Window.people
local originalClear, originalPoint = people.ClearAllPoints, people.SetPoint
people.ClearAllPoints = function()
    error("list callback must not clear viewport anchors")
end

people.SetPoint = function()
    error("list callback must not reanchor viewport")
end

people:SetHeight(500)
people.content:SetHeight(120)
people.offset = 400
Window:LayoutPeople()
equal(people:GetVerticalScroll(), 0, "shortened list clears stale scroll offset")
equal(Window.rows[1]:GetWidth(), 260, "non-scrolling cards fill sidebar")
people.content:SetHeight(600)
Window:LayoutPeople()
equal(Window.rows[1]:GetWidth(), 253, "overflow reserves only thumb gutter")
people.content:SetHeight(120)
Window:LayoutPeople()
equal(Window.rows[1]:GetWidth(), 260, "cards reclaim gutter after list shrinks")
people.ClearAllPoints, people.SetPoint = originalClear, originalPoint
print("Stable sidebar viewport, full-width rows and stale scroll recovery passed.")

Window.frame:SetWidth(800)
Window:Layout()
flush()
Window.people:SetWidth(260)
Window.people:RefreshContent()
Window.frame:SetWidth(600)
Window:Layout()
flush()
equal(Window.sidebar:IsShown(), false, "resize collapses sidebar")
Window.people.scripts.OnSizeChanged(Window.people, 0, 0)
equal(Window.people.content:GetWidth(), 260, "hidden zero-size event cannot collapse scroll child")
-- Simulate an already collapsed/stale child from the previous implementation.
Window.people.content:SetWidth(0)
Window.rows[1]:Hide()
Window.frame:SetWidth(800)
Window:Layout()
flush()
equal(Window.people.content:GetWidth(), 260, "expanding sidebar restores scroll child width")
equal(Window.rows[1]:IsShown(), true, "expanding sidebar rebuilds visible rows")
Window.frame:SetWidth(600)
Window:Layout()
flush()
Window.people.content:SetWidth(0)
Window.rows[1]:Hide()
Window:SetDrawer(true)
flush()
equal(Window.people.content:GetWidth(), 260, "opening compact drawer restores scroll child width")
equal(Window.rows[1]:IsShown(), true, "opening compact drawer refreshes rows")
print("Sidebar collapse/expand and compact drawer scroll-child restoration passed.")

Window:Open(modeChat.key)
flush()
assert(Window.bubbles[1].text, "message uses display text")
assert(not Window.bubbles[1].selectable, "message has no editable control or caret")
local active = Window.active
local clicked
for _, row in ipairs(Window.rows) do
    if row.key and row.key ~= active and Whispr.db.char.conversations[row.key] then
        clicked = row
        break
    end
end

assert(clicked, "test needs an inactive conversation")
clicked.scripts.OnClick(clicked, "RightButton")
equal(Window.active, active, "context menu does not switch active conversation")
local deleteAction
for _, entry in ipairs(entries) do
    if entry.label == "Delete conversation" then
        deleteAction = entry.action
    end
end

assert(deleteAction, "row menu includes conversation actions")
local previousConfirm = Window.ConfirmAction
Window.ConfirmAction = function(_, action, key)
    equal(action, "delete", "context action")
    equal(key, clicked.key, "context targets clicked conversation")
end

deleteAction()
Window.ConfirmAction = previousConfirm
print("Read-only message display and clicked-conversation context menu passed.")

Whispr.db.global.animateWindows = false
Whispr.db.global.fadeWhenIdle = true
Whispr.db.global.idleFadeDelay = 4
Whispr.db.global.windowOpacity = 0.9
Whispr.db.global.idleOpacity = 0.3
Window:Open(modeChat.key)
flush()
Window.input:ClearFocus()
Window.frame.mouseOver = false
clockTime = 1000
Window:UpdateOpacity()
clockTime = 1010
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.9, "window focus prevents idle fade without typing or hover")
equal(Window.focusBorder:IsShown(), true, "focused window has border")
local registered = false
for _, name in ipairs(UISpecialFrames) do
    if name == Window.frame.name then
        registered = true
    end
end

assert(not registered, "main window excluded from global close-all Escape list")

function methods:GetParent()
    return self.parent
end

local hovered = Window.settingsButton
GetMouseFoci = function()
    return { hovered }
end

Window.focusEvents.scripts.OnEvent()
equal(Window.focused, true, "child click activates owning window")
equal(Window.frame:GetFrameStrata(), "DIALOG", "focused hub rises above ordinary UI")
local focusPop = recreated(Window, manualChat.key)
focusPop:Open(manualChat.key, nil, true)
flush()
equal(Window.focused, true, "background opening does not steal window focus")
equal(focusPop.frame:GetFrameStrata(), "LOW", "background popout stays behind dialogs")
hovered = focusPop.input
Window.focusEvents.scripts.OnEvent()
equal(focusPop.focused, true, "click activates separate window")
equal(Window.focused, nil, "only one Whispr window focused")
equal(Window.frame:GetFrameStrata(), "LOW", "previously focused hub drops into background")
equal(focusPop.frame:GetFrameStrata(), "DIALOG", "clicked popout moves to foreground")
equal(Window.focusBorder:IsShown(), true, "unfocused window keeps its border")
registered = false
for _, name in ipairs(UISpecialFrames) do
    if name == focusPop.frame.name then
        registered = true
    end
end

assert(not registered, "separate window excluded from global close-all Escape list")
focusPop.input:SetFocus()
focusPop.input.scripts.OnEscapePressed(focusPop.input)
equal(focusPop.frame:IsShown(), false, "Escape from composer closes separate window")
Window:Open(modeChat.key)
flush()
hovered = UIParent
clockTime = 1020
Window.focusEvents.scripts.OnEvent()
Window:UpdateOpacity()
equal(Window.focused, nil, "world click releases window focus")
equal(Window.frame:GetFrameStrata(), "LOW", "world click lowers window immediately")
equal(Window.frame.alpha, 0.9, "blur starts normal fade delay")
clockTime = 1024
Window:UpdateOpacity()
equal(Window.frame.alpha, 0.3, "unfocused window fades after delay")
Window:Open(modeChat.key)
Window:SetDrawer(false)
flush()
Window.input.scripts.OnEscapePressed(Window.input)
equal(Window.frame:IsShown(), false, "Escape from composer closes main window")
equal(Window.focusBorder:IsShown(), false, "hidden window cannot retain focus border")
print("Focused Escape handling, composer Escape, persistent focus border and idle fade passed.")

function methods:SetPropagateKeyboardInput(propagate)
    assert(not InCombatLockdown(), "keyboard propagation cannot change during combat")
    self.propagate = propagate
end

local unrelated = frame("OtherAddonWindow", UIParent)
UISpecialFrames[#UISpecialFrames + 1] = "OtherAddonWindow"

local function pressKey(window, key)
    window.frame.scripts.OnKeyDown(window.frame, key)
    if window.frame.propagate and key == "ESCAPE" then
        unrelated:Hide()
    end
end

Window:Open(modeChat.key)
flush()
Window:SetDrawer(false)
pressKey(Window, "W")
equal(Window.frame.propagate, true, "normal game keys pass through focused window")
pressKey(Window, "ESCAPE")
equal(Window.frame:IsShown(), false, "focused Escape closes Whispr")
equal(unrelated:IsShown(), true, "same Escape cannot close unrelated windows")
focusPop:Open(manualChat.key)
flush()
pressKey(focusPop, "ESCAPE")
equal(focusPop.frame:IsShown(), false, "focused Escape closes separate window")
equal(unrelated:IsShown(), true, "popout Escape preserves unrelated windows")
Window:Open(modeChat.key)
flush()
Window:ToggleEmotes()
pressKey(Window, "ESCAPE")
equal(Window.frame:IsShown(), true, "first Escape closes picker only")
equal(Window.emotePicker:IsShown(), false, "picker dismissed")
equal(unrelated:IsShown(), true, "picker Escape is consumed")
pressKey(Window, "ESCAPE")
equal(Window.frame:IsShown(), false, "next Escape closes owner")
print("Escape consumption preserves other windows and passes ordinary keys through.")

Window:Open(modeChat.key)
flush()
Window:SetDrawer(false)
Window:SetWindowFocus(false)
equal(Window.frame.keyboardEnabled, true, "unfocused visible window keeps Escape enabled")
pressKey(Window, "W")
equal(Window.frame.propagate, true, "unfocused window passes gameplay keys through")
pressKey(Window, "ESCAPE")
equal(Window.frame:IsShown(), false, "Escape closes main window after clicking the world")
equal(unrelated:IsShown(), true, "unfocused Escape preserves unrelated windows")
focusPop:Open(manualChat.key, nil, true)
flush()
equal(focusPop.focused, nil, "background popout starts unfocused")
equal(focusPop.frame.keyboardEnabled, true, "background popout listens for Escape")
pressKey(focusPop, "ESCAPE")
equal(focusPop.frame:IsShown(), false, "Escape closes unfocused popout")
print("Unfocused windows handle Escape without blocking gameplay keys.")

do
    local combatWindow = recreated()
    combatWindow.popouts = {}
    combatWindow:Open(modeChat.key, nil, true)
    flush()
    combatWindow:ToggleEmotes()
    pressKey(combatWindow, "ESCAPE")
    equal(combatWindow.frame.propagate, false, "Escape leaves the window in consuming mode")

    combat = true
    combatWindow:CombatChanged(true)
    equal(combatWindow.frame:IsShown(), true, "combat leaves the chat visible when hiding is disabled")
    equal(combatWindow.frame.keyboardEnabled, false, "combat disables a window that was consuming keys")
    combatWindow.frame.scripts.OnKeyDown(combatWindow.frame, "W")

    local combatPopout = recreated(combatWindow, manualChat.key)
    combatWindow.popouts[manualChat.key] = combatPopout
    combatPopout:Open(manualChat.key, nil, true)
    flush()
    equal(combatPopout.frame.keyboardEnabled, false, "popout opened in combat starts without keyboard capture")
    combatPopout.input:SetFocus()
    combatPopout.input.scripts.OnEscapePressed(combatPopout.input)
    equal(combatPopout.frame:IsShown(), false, "composer Escape still works in combat")

    combat = false
    combatWindow:CombatChanged(false)
    equal(combatWindow.frame.keyboardEnabled, true, "keyboard capture resumes after combat")
    equal(combatWindow.frame.propagate, true, "gameplay key propagation is restored after combat")
    equal(combatPopout.frame.keyboardEnabled, true, "combat-created popout gains keyboard capture")
    equal(combatPopout.frame.propagate, true, "combat-created popout passes gameplay keys through")
    pressKey(combatWindow, "ESCAPE")
    equal(combatWindow.frame:IsShown(), false, "window Escape works again after combat")
end

-- Paging uses saved IDs so appends and retention do not shift its boundary.
Whispr.db.global.maxMessages = 100
local paged
local dayOne = os.time({ year = 2026, month = 9, day = 30, hour = 12 })
local dayTwo = os.time({ year = 2026, month = 10, day = 1, hour = 12 })
for i = 1, 45 do
    paged = History.Add(
        Whispr.db.char,
        Whispr.db.global,
        "Paged history",
        "Page message " .. i,
        false,
        i <= 30 and dayOne or dayTwo,
        false
    )
end

local reader = recreated()
reader.detached = {}
reader.popouts = {}
reader:Open(paged.key)
flush()

local function visibleBubbles(window)
    local count = 0
    for _, bubble in ipairs(window.bubbles) do
        if bubble:IsShown() then
            count = count + 1
        end
    end

    return count
end

local function loadedMessages(window)
    local messages = {}
    for _, row in ipairs(window.messageRows or {}) do
        if row.message then
            messages[#messages + 1] = row
        end
    end

    return messages
end

local function loadedDates(window)
    local dates = {}
    for _, row in ipairs(window.messageRows or {}) do
        if row.label then
            dates[#dates + 1] = row
        end
    end

    return dates
end

equal(#loadedMessages(reader), 20, "initial layout limited to newest twenty")
assert(visibleBubbles(reader) < 20, "only viewport messages get frames")
equal(loadedMessages(reader)[1].message.id, paged.messages[26].id, "initial page starts with correct message")
equal(loadedDates(reader)[1].label, "September 30, 2026", "first day has heading")
equal(loadedDates(reader)[2].label, "October 1, 2026", "day change has heading")
local anchorID, anchorY = loadedMessages(reader)[1].message.id, loadedMessages(reader)[1].y
reader.scroll:SetVerticalScroll(0)
reader:LoadOlderMessages() -- repeated scroll notifications cannot fetch another page mid-layout
flush()
equal(#loadedMessages(reader), 40, "scrolling to top loads exactly twenty older messages")
equal(loadedMessages(reader)[1].message.id, paged.messages[6].id, "older page boundary")
equal(loadedMessages(reader)[21].message.id, anchorID, "anchor message retained")
equal(
    reader.scroll:GetVerticalScroll(),
    loadedMessages(reader)[21].y - anchorY,
    "prepending preserves viewport including date heading"
)
equal(reader.following, false, "paging never jumps to latest")
local before = reader.scroll:GetVerticalScroll()
History.Add(Whispr.db.char, Whispr.db.global, "Paged history", "New arrival", false, dayTwo, false)
reader:RefreshMessages()
flush()
equal(#loadedMessages(reader), 41, "new arrival retains loaded history")
equal(reader.scroll:GetVerticalScroll(), before, "new arrival preserves older viewport")
reader.scroll:SetVerticalScroll(0)
flush()
equal(#loadedMessages(reader), 46, "last page loads only remaining messages")
reader.scroll:SetVerticalScroll(0)
flush()
equal(#loadedMessages(reader), 46, "history exhaustion does not duplicate messages")
Whispr.db.global.timestamps = false
reader:RefreshMessages()
flush()
equal(reader.dateHeaders[1]:IsShown(), true, "dates remain when timestamps disabled")
reader:Select(modeChat.key)
flush()
assert(#reader.dateHeaders <= 1, "unused date headings released after switching")
reader:Select(paged.key)
flush()
equal(#loadedMessages(reader), 20, "returning to conversation starts with latest page")
Whispr.db.global.maxMessages = 20
History.Trim(Whispr.db.char, Whispr.db.global)
reader:RefreshMessages()
flush()
equal(#loadedMessages(reader), 20, "retention keeps remaining page visible")
equal(loadedMessages(reader)[1].message.id, paged.messages[1].id, "retention reconciles page boundary")
reader:Select(nil)
flush()
equal(visibleBubbles(reader), 0, "empty conversation releases pooled messages")
equal(#reader.dateHeaders, 0, "empty conversation releases date headings")
print("Date grouping, twenty-message paging, scroll anchors, arrivals, switching and retention passed.")

reader:Select(paged.key)
flush()
local delivery = paged.messages[#paged.messages]
delivery.outgoing = true
delivery.pending = true
reader:RefreshMessages()
flush()
local deliveryBubble = reader.bubbles[visibleBubbles(reader)]
equal(deliveryBubble.alpha, 0.65, "sending bubble is dimmed")
assert(deliveryBubble.meta:GetText():match("^You"), "sending keeps normal sender label")
delivery.pending = nil
delivery.unconfirmed = true
reader:RefreshMessages()
flush()
equal(deliveryBubble.alpha, 0.4, "unconfirmed bubble is more visibly dimmed")
assert(not deliveryBubble.meta:GetText():find("Not confirmed", 1, true), "delivery status omitted from message header")
delivery.unconfirmed = nil
reader:RefreshMessages()
flush()
equal(deliveryBubble.alpha, 1, "confirmation restores full bubble opacity")
print("Sending and unconfirmed bubble opacity, sender labels and confirmation restoration passed.")

Whispr.db.global.animateWindows = true
delivery.pending = true
reader:RefreshMessages()
flush()
equal(deliveryBubble.alpha, 1, "delivery fade starts at current opacity")
deliveryBubble.scripts.OnUpdate(deliveryBubble, 0.1)
assert(deliveryBubble.alpha < 1 and deliveryBubble.alpha > 0.65, "sending transition interpolates opacity")
local intermediate = deliveryBubble.alpha
reader:RefreshMessages()
flush()
equal(deliveryBubble.alpha, intermediate, "refresh does not restart delivery fade")
delivery.pending = nil
delivery.unconfirmed = true
reader:RefreshMessages()
flush()
equal(deliveryBubble.alpha, intermediate, "interrupted fade starts at visible opacity")
deliveryBubble.scripts.OnUpdate(deliveryBubble, 0.25)
equal(deliveryBubble.alpha, 0.4, "unconfirmed fade reaches target")
equal(deliveryBubble.deliveryFade, nil, "completed delivery fade stops animating")
assert(deliveryBubble.scripts.OnUpdate, "selection update handler remains installed")
delivery.unconfirmed = nil
reader:RefreshMessages()
flush()
deliveryBubble.scripts.OnUpdate(deliveryBubble, 0.25)
equal(deliveryBubble.alpha, 1, "confirmation fades to full opacity")
delivery.pending = true
reader:RefreshMessages()
flush()
Whispr.db.global.animateWindows = false
reader:RefreshMessages()
flush()
equal(deliveryBubble.alpha, 0.65, "disabling animations applies delivery opacity immediately")
equal(deliveryBubble.deliveryFade, nil, "disabling animations cancels in-flight delivery fade")
print("Delivery opacity fades, interruption, refresh stability and animation preference passed.")

local typingKey = reader.active
addon.Typing = {
    IsTyping = function(_, key)
        return key == typingKey
    end,
}

local heightWithoutTyping = reader.scroll.content:GetHeight()
reader:UpdateTyping()
flush()
equal(reader.typingBadge:IsShown(), true, "remote typing displays badge")
equal(reader.scroll.content:GetHeight(), heightWithoutTyping + 38, "typing badge gets space after messages")
equal(reader.typingBadge.parent, reader.scroll.content, "typing badge scrolls and clips with conversation")
local lastBubble = reader.bubbles[visibleBubbles(reader)]
assert(
    lastBubble.y + lastBubble:GetHeight() < reader.scroll.content:GetHeight() - 30,
    "badge cannot overlap last message"
)
local tallFooter = reader.footer:GetHeight()
Whispr.db.global.animateWindows = true
clockTime = 2000
reader:UpdateTyping()
local dotAlpha = reader.typingBadge.dots[1].alpha
clockTime = 2000.1
reader:UpdateTyping()
assert(reader.typingBadge.dots[1].alpha ~= dotAlpha, "typing dots animate")
typingKey = nil
reader:UpdateTyping()
flush()
equal(reader.typingBadge:IsShown(), false, "stop or expiry hides typing badge")
equal(reader.footer:GetHeight(), tallFooter, "floating indicator leaves footer size unchanged")
addon.Typing = nil
print("Floating typing badge, animated dots and stable footer size passed.")

local demoConversation = Whispr.db.char.conversations[reader.active]
demoConversation.demo = true
Whispr.db.global.animateWindows = false
reader:UpdateTyping()
flush()
equal(reader.typingBadge:IsShown(), false, "idle demo hides typing badge")
reader.input:SetText("demo draft")
reader.input.onDraftEdited()
flush()
equal(reader.typingBadge:IsShown(), true, "typing in demo previews indicator without a peer")
local demoAlpha = reader.typingBadge.dots[1].alpha
clockTime = clockTime + 0.1
reader:UpdateTyping()
assert(reader.typingBadge.dots[1].alpha ~= demoAlpha, "demo preview animates even when normal animations disabled")
clockTime = clockTime + 4
reader:UpdateTyping()
flush()
equal(reader.typingBadge:IsShown(), false, "demo indicator expires after pause")
reader.input:Insert(" :) ")
flush()
equal(reader.typingBadge:IsShown(), true, "emoji insertion activates demo typing")
reader.input:SetText("")
reader.input.onDraftEdited()
flush()
equal(reader.typingBadge:IsShown(), false, "clearing draft hides demo typing")
demoConversation.demo = nil
reader:UpdateTyping()
flush()
equal(reader.typingBadge:IsShown(), false, "demo preview does not leak into real conversations")
print("Local demo typing preview and animated dots passed.")

-- The real ScrollFrame may retain its previous range until its child rect updates.
local messageScroll = reader.scroll
messageScroll.cachedRange = 0
messageScroll.GetVerticalScrollRange = function(self)
    return self.cachedRange
end

messageScroll.UpdateScrollChildRect = function(self)
    self.cachedRange = math.max(0, self.content:GetHeight() - self:GetHeight())
end

demoConversation.demo = true
reader:Select(demoConversation.key)
equal(reader.typingBadge:IsShown(), false, "opening demo starts with typing hidden")
reader.input:Insert("typing now")
equal(reader.typingBadge:IsShown(), true, "demo edit includes indicator in layout")
flush()
equal(
    messageScroll:GetVerticalScroll(),
    messageScroll:GetVerticalScrollRange(),
    "opening scrolls to updated range including badge"
)
local badgeBottom = messageScroll.content:GetHeight() - 10 - messageScroll:GetVerticalScroll()
assert(
    badgeBottom <= messageScroll:GetHeight() and badgeBottom - 20 >= 0,
    "badge fully visible immediately after opening"
)
reader:Select(nil)
flush()
equal(reader.typingBadge:IsShown(), false, "switching clears old typing indicator synchronously")
reader:Select(demoConversation.key)
flush()
equal(reader.typingBadge:IsShown(), false, "restored demo draft does not simulate typing")
reader.input:Insert(" more")
flush()
equal(
    messageScroll:GetVerticalScroll(),
    messageScroll:GetVerticalScrollRange(),
    "demo typing includes badge without manual scroll"
)
messageScroll:SetVerticalScroll(120)
local savedOffset = messageScroll:GetVerticalScroll()
demoConversation.demo = nil
reader:UpdateTyping()
flush()
equal(messageScroll:GetVerticalScroll(), savedOffset, "typing changes preserve position while reading older messages")
print("Typing indicator initial layout, cached scroll range, reentry and reading anchors passed.")

reader:RefreshList()
local typingRow
for _, row in ipairs(reader.rows) do
    if row:IsShown() and row.key ~= reader.active then
        typingRow = row
        break
    end
end

assert(typingRow, "test needs an inactive conversation card")
local preview = typingRow.preview:GetText()
local remoteTyping = typingRow.key
addon.Typing = {
    IsTyping = function(_, key)
        return key == remoteTyping
    end,
}

Whispr.db.global.animateWindows = true
clockTime = 2100
reader:UpdateTyping()
flush()
equal(typingRow.preview:GetText(), "Typing.", "inactive card shows typing instead of last message")
clockTime = 2100.5
reader:UpdateTyping()
flush()
equal(typingRow.preview:GetText(), "Typing..", "card typing dots animate")
remoteTyping = nil
reader:UpdateTyping()
flush()
equal(typingRow.preview:GetText(), preview, "stopping restores original last message")
Whispr.db.global.showMessagePreviews = false
remoteTyping = typingRow.key
reader:RefreshList()
reader:UpdateTyping()
flush()
equal(typingRow.preview:IsShown(), false, "hidden previews remain hidden while typing")
Whispr.db.global.showMessagePreviews = true
reader:RefreshList()
assert(typingRow.preview:GetText():match("^Typing%."), "refresh retains current typing state")
addon.Typing = nil
reader:UpdateTyping()
flush()
print("Conversation card typing animation, inactive chats, preview restoration and visibility setting passed.")

Whispr.db.global.animateWindows = true
reader:Open(demoConversation.key)
flush()
local reopenMessage = demoConversation.messages[#demoConversation.messages]
reopenMessage.outgoing = true
reopenMessage.pending = nil
reopenMessage.unconfirmed = nil
reader:RefreshMessages()
flush()
local reopenBubble = reader.bubbles[visibleBubbles(reader)]
reopenMessage.pending = true
reader:RefreshMessages()
flush()
assert(reopenBubble.scripts.OnUpdate, "delivery animation running before hide")
reopenBubble.scripts.OnUpdate(reopenBubble, 0.05)
reader:HideImmediately()
equal(reopenBubble.deliveryFade, nil, "hiding stops message animation")
equal(reopenBubble.alpha, 1, "released messages reset opacity")
equal(reopenBubble.messageID, nil, "released messages clear identity")
reader:Open(demoConversation.key)
flush()
equal(reopenBubble.deliveryFade, nil, "reopening does not replay stale message animation")
print("Opening keeps stable message scale and cancels stale delivery animations.")

Whispr.db.global.animateWindows = false
reader:Open(demoConversation.key)
flush()
C_AddOns = {
    GetAddOnMetadata = function(name, key)
        equal(name, "Whispr", "metadata addon name")
        equal(key, "Version", "metadata key")
        return "0.1.0"
    end,
}

reader.infoButton.scripts.OnClick()
flush()
assert(reader.info:IsShown(), "question button opens info page")
equal(reader.info.version:GetText(), "Version 0.1.0  |  By Wuild", "info reads installed addon version")
assert(reader.info.text:GetText():find("Created by Wuild", 1, true), "info contains addon description and author")
reader.frame:SetSize(360, 280)
reader:Layout()
flush()
equal(reader.info:GetWidth(), 336, "info fits narrow window")
equal(reader.info:GetHeight(), 256, "info fits short window")
reader.info.support.scripts.OnClick()
equal(reader.url.input:GetText(), "https://www.patreon.com/Wuild", "Patreon opens correct copy link")
reader:Escape()
equal(reader.url:IsShown(), false, "Escape closes copy link first")
equal(reader.info:IsShown(), true, "info remains behind copy link")
reader:Escape()
equal(reader.info:IsShown(), false, "next Escape closes info")
equal(reader.frame:IsShown(), true, "closing info keeps conversation open")
reader.infoButton.scripts.OnClick()
reader.info.close.scripts.OnClick()
equal(reader.info.shade:IsShown(), false, "close button also dismisses modal shade")
reader.infoButton.scripts.OnClick()
reader.info.shade.scripts.OnClick()
equal(reader.info:IsShown(), false, "outside click dismisses info")
reader.infoButton.scripts.OnClick()
reader:HideImmediately()
equal(reader.info:IsShown(), false, "closing owner hides info")
C_AddOns = nil
GetAddOnMetadata = function()
    return "legacy-version"
end

equal(addon.Info.Version(), "legacy-version", "legacy client metadata fallback")
GetAddOnMetadata = nil
print("Addon info page, metadata, Patreon copy link, responsive layout and dismissal passed.")

reader:Open(demoConversation.key)
flush()
Whispr.db.global.backgroundOpacity = 0.1
reader.infoButton.scripts.OnClick()
flush()
assert(reader.info.logo.texture:find("whispr-icon.tga", 1, true), "info displays addon logo")
assert(reader.info.support.logo.texture:find("patreon.tga", 1, true), "support button displays Patreon mark")
equal(addon.Theme.surfaces[reader.info.surface][3], true, "info surface ignores background transparency")
reader.info.support.scripts.OnClick()
assert(reader.url.logo.texture:find("patreon.tga", 1, true), "Patreon copy dialog uses matching branding")
equal(addon.Theme.surfaces[reader.url.surface][3], true, "copy dialog surface stays opaque")
reader.url.done.scripts.OnClick()
equal(reader.url:IsShown(), false, "Done dismisses copy dialog")
reader:ShowCopyText("https://example.com", "Copy link")
assert(reader.url.logo.texture:find("link.tga", 1, true), "ordinary links use link icon")
print("Branded info and copy modals, opaque surfaces and Done action passed.")

reader:RefreshMessages()
flush()
local alignedBubble = reader.bubbles[visibleBubbles(reader)]
equal(alignedBubble.lastPoint[1], "TOPRIGHT", "outgoing messages default to right")
Whispr.db.global.outgoingOnRight = false
reader:RefreshMessages()
flush()
equal(alignedBubble.lastPoint[1], "TOPLEFT", "single-side layout aligns outgoing messages left")
assert(alignedBubble.meta:GetText():match("^You"), "single-side layout preserves sender label")
Whispr.db.global.outgoingOnRight = true
reader:RefreshMessages()
flush()
equal(alignedBubble.lastPoint[1], "TOPRIGHT", "split layout restores outgoing alignment")
print("Outgoing message alignment toggle preserves sender identity and restores split layout.")

-- Walk a large history repeatedly: frames track viewport capacity, not history size.
Whispr.db.global.maxMessages = 1000
load("selection")
local stress
for index = 1, 500 do
    stress = History.Add(
        Whispr.db.char,
        Whispr.db.global,
        "Pool stress",
        index % 9 == 0 and string.rep("Wrapped message ", 40) or ("Message " .. index),
        index % 2 == 0,
        dayOne + index * 86400,
        false
    )
end

reader:Open(stress.key)
flush()
while reader.firstMessageID ~= stress.messages[1].id do
    reader:LoadOlderMessages()
    flush()
end

equal(#loadedMessages(reader), 500, "all five hundred messages available as layout data")

local function poolSize(window)
    return #window.bubbles + #(window.messagePool or {}), #window.dateHeaders + #(window.datePool or {})
end

local function walkHistory()
    local range = reader.scroll:GetVerticalScrollRange()
    for offset = 0, range, 79 do
        reader.scroll:SetVerticalScroll(offset)
        flush()
        local seen = {}
        for _, bubble in ipairs(reader.bubbles) do
            assert(not seen[bubble], "active frame assigned only once")
            seen[bubble] = true
            assert(
                bubble.y + bubble:GetHeight() >= offset - 80 and bubble.y <= offset + reader.scroll:GetHeight() + 80,
                "only viewport and overscan messages remain active"
            )
            equal(
                bubble.text:GetText(),
                addon.Format.Message(bubble.row.message.text, Whispr.db.global.smileys, 12, bubble.inviteKey),
                "reused frame displays assigned message"
            )
        end

        for _, bubble in ipairs(reader.messagePool) do
            assert(not seen[bubble], "active frame never appears in free pool")
            seen[bubble] = true
            equal(bubble:IsShown(), false, "free frames hidden")
            equal(bubble.messageID, nil, "free frames clear identity")
            equal(bubble.text:GetText(), "", "free frames clear message text")
            equal(bubble.deliveryFade, nil, "free frames stop delivery animation")
        end
    end
end

walkHistory()
local selectedBubble = reader.bubbles[1]
selectedBubble.selectionDragging = true
selectedBubble.selectionClickSuppressed = true
selectedBubble.selectionHighlights = { frame() }
reader.messageSelection = { bubble = selectedBubble, start = 1, finish = 3, selected = "Me" }
local tooltipHidden = false
local previousIsOwned, previousHide = GameTooltip.IsOwned, GameTooltip.Hide
GameTooltip.IsOwned = function(_, owner)
    return owner == selectedBubble
end

GameTooltip.Hide = function()
    tooltipHidden = true
end

reader.scroll:SetVerticalScroll(0)
flush()
equal(reader.messageSelection, nil, "recycling clears selection from previous message")
equal(selectedBubble.selectionHighlights[1]:IsShown(), false, "recycling clears selection highlights")
equal(selectedBubble.selectionDragging, nil, "recycling clears drag state")
equal(selectedBubble.selectionClickSuppressed, nil, "recycling clears suppressed link click")
assert(tooltipHidden, "recycling closes tooltip owned by previous message")
GameTooltip.IsOwned, GameTooltip.Hide = previousIsOwned, previousHide
local messageCapacity, dateCapacity = poolSize(reader)
assert(messageCapacity < 20 and dateCapacity < 20, "frame allocation bounded despite hundreds of messages and dates")
walkHistory()
local messagesAgain, datesAgain = poolSize(reader)
equal(messagesAgain, messageCapacity, "second history traversal allocates no new message frames")
equal(datesAgain, dateCapacity, "second history traversal allocates no new date frames")
reader:HideImmediately()
equal(#reader.bubbles, 0, "hide releases all active message frames")
equal(#reader.dateHeaders, 0, "hide releases all active date frames")
reader:ReleaseMessageFrames()
local hiddenMessages, hiddenDates = poolSize(reader)
equal(hiddenMessages, messageCapacity, "double release does not duplicate free messages")
equal(hiddenDates, dateCapacity, "double release does not duplicate free dates")
reader:Open(stress.key)
flush()
assert(#reader.bubbles > 0, "reopen reacquires visible messages")
reader.scroll:SetHeight(600)
reader:RefreshMessages()
flush()
assert(#reader.bubbles > 0, "larger viewport lays out pooled messages")
reader.scroll:SetHeight(180)
reader:RefreshMessages()
flush()
for _, bubble in ipairs(reader.bubbles) do
    assert(bubble.y <= reader.scroll:GetVerticalScroll() + 260, "smaller viewport releases offscreen messages")
end

-- Dense history and long messages use the same pool and maintain exact geometry.
for _, message in ipairs(stress.messages) do
    message.time = dayOne
end

reader.firstMessageID = stress.messages[1].id
reader:RefreshMessages()
flush()
walkHistory()
local denseCapacity = poolSize(reader)
assert(denseCapacity < 20, "dense history also stays bounded by viewport capacity")
local lastRow = loadedMessages(reader)[500]
equal(
    reader.scroll.content:GetHeight(),
    lastRow.y + lastRow.height + 6,
    "all offscreen rows contribute to scroll range"
)
print(
    "Viewport frame pooling passed: 500 messages, "
        .. denseCapacity
        .. " message frames and "
        .. dateCapacity
        .. " date frames."
)

reader:Open(demoConversation.key)
flush()
addon.Window = reader -- This isolated controller represents the live inbox for the extension.
reader.input:SetText("hello :)")
reader:ToggleEmotes()
local emojiDraft = reader.input:GetText()
assert(reader.emotePicker:IsShown(), "picker opens while built-in emoji extension is active")
addon.Extensions:SetEnabled("emoji", false)
flush()
assert(not reader.emotePicker:IsShown() and not reader.emoteButton:IsShown(), "disabling hides open picker and button")
equal(reader.input:GetText(), emojiDraft, "disabling preserves raw draft")
assert(not reader.input.text:find("|T", 1, true), "disabled draft displays plain smiley text")
reader:ToggleEmotes()
assert(not reader.emotePicker:IsShown(), "disabled picker cannot reopen")
addon.Extensions:SetEnabled("emoji", true)
flush()
assert(reader.emoteButton:IsShown(), "reenabling restores picker button")
equal(reader.input:GetText(), emojiDraft, "reenabling preserves raw draft")
assert(
    reader.input.text:find("|T", 1, true),
    "reenabling restores inline artwork: "
        .. tostring(addon.Extensions.entries.emoji.error)
        .. " / "
        .. reader.input.text
)
print("Built-in emoji live disable/enable, picker dismissal and draft preservation passed.")

-- Only the focused composer is exempt; saved drafts alone do not imply typing.
local typingHub = recreated()
typingHub.popouts = {}
typingHub:Create()
local typingPopout = recreated(typingHub, "typing-exception")
typingPopout:Create()
typingHub.popouts.test = typingPopout
Whispr.db.global.hideInCombat = true
Whispr.db.global.dontHideWhenTyping = true
typingHub:Show()
typingPopout:Show()
typingHub.input:SetFocus()
typingPopout.input:ClearFocus()
typingPopout.input:SetText("saved draft")
typingHub:CombatChanged(true)
equal(typingHub.frame:IsShown(), true, "focused inbox survives combat entry")
equal(typingPopout.frame:IsShown(), false, "unfocused popout with draft still hides")
equal(typingHub.hiddenForCombat, nil, "typing window not marked for restoration")
typingHub:CombatChanged(false)
equal(typingPopout.frame:IsShown(), true, "hidden popout restored after combat")
typingHub.input:ClearFocus()
typingPopout.input:SetFocus()
typingHub:CombatChanged(true)
equal(typingHub.frame:IsShown(), false, "unfocused inbox hides")
equal(typingPopout.frame:IsShown(), true, "focused popout survives combat entry")
typingPopout.input:ClearFocus()
equal(typingPopout.frame:IsShown(), true, "finishing typing does not trigger a new hide")
typingHub:CombatChanged(false)
typingHub.input:SetFocus()
typingPopout.input:SetFocus()
Whispr.db.global.dontHideWhenTyping = false
typingHub:CombatChanged(true)
equal(typingHub.frame:IsShown(), false, "disabled exception hides focused inbox")
equal(typingPopout.frame:IsShown(), false, "disabled exception hides focused popout")
typingHub:CombatChanged(false)
print("Combat entry typing exception, inbox/popouts, unfocused drafts and restoration passed.")

local extensionEvents = {}
local watcher = Whispr:NewExtension("window_test")

function watcher:OnEnable()
    for _, event in ipairs({
        "DRAFT_CHANGED",
        "WINDOW_OPENED",
        "WINDOW_CLOSED",
        "CONVERSATION_CREATED",
        "CONVERSATION_DELETED",
    }) do
        self:RegisterMessage(event, function(_, name, payload)
            extensionEvents[name] = payload
        end)
    end
end

flush()
reader.input:Insert("edit")
equal(extensionEvents.DRAFT_CHANGED.text, reader.input:GetText(), "draft event contains raw composer text")
reader:HideImmediately()
assert(
    extensionEvents.WINDOW_CLOSED.window and extensionEvents.WINDOW_CLOSED.separate == false,
    "window hide event has stable identity"
)
reader:Open("Extension Event Friend")
flush()
assert(extensionEvents.WINDOW_OPENED.window, "window show emits visibility event")
equal(extensionEvents.CONVERSATION_CREATED.name, "Extension Event Friend", "new empty conversation emits creation")
local deletedKey = reader.active
reader:Delete(deletedKey)
flush()
equal(extensionEvents.CONVERSATION_DELETED.key, deletedKey, "manual deletion event identifies removed conversation")
assert(not Whispr.db.char.conversations[deletedKey], "deletion event follows history removal")
watcher:Disable()
print("Window visibility, raw draft, empty conversation creation and deletion events passed.")

addon.Window = reader
local newIncoming =
    History.Add(Whispr.db.char, Whispr.db.global, "Background Friend", "Unread", false, os.time(), false)
Whispr.db.global.autoOpenConversations = false
reader:HideImmediately()
reader:Receive(newIncoming.key)
flush()
assert(not reader.frame:IsShown(), "auto-open disabled keeps inbox hidden")
equal(newIncoming.unread, 1, "hidden incoming message stays unread")
reader:Open(demoConversation.key)
flush()
reader.input:SetText("draft remains")
reader.input:SetFocus()
Whispr.db.global.autoSelectIncoming = false
reader:Receive(newIncoming.key)
flush()
equal(reader.active, demoConversation.key, "auto-select disabled preserves current conversation")
equal(reader.input:GetText(), "draft remains", "auto-select disabled preserves input")
assert(reader.input:HasFocus(), "auto-select disabled preserves keyboard focus")
equal(newIncoming.unread, 1, "background conversation remains unread")
reader:HideImmediately()
Whispr.db.global.autoOpenConversations = true
reader:Receive(newIncoming.key)
flush()
assert(reader.frame:IsShown(), "auto-open independently opens inbox")
equal(reader.active, demoConversation.key, "auto-open respects disabled auto-select")
Whispr.db.global.autoSelectIncoming = true
reader:Receive(newIncoming.key)
flush()
equal(reader.active, newIncoming.key, "reenabling auto-select restores routing")
Whispr.db.global.autoOpenConversations = false
Whispr.db.global.separateWindows = true
local existingPopouts = 0
for _ in pairs(reader.popouts) do
    existingPopouts = existingPopouts + 1
end

reader:Receive("not-open")
flush()
local afterPopouts = 0
for _ in pairs(reader.popouts) do
    afterPopouts = afterPopouts + 1
end

equal(afterPopouts, existingPopouts, "auto-open disabled creates no separate windows")
Whispr.db.global.separateWindows = false
print("Independent automatic opening and main-window selection preferences passed.")

Whispr.db.global.separateWindows = false
Whispr.db.global.autoOpenConversations = true
Whispr.db.keys = { char = "Current - Realm" }
local foreign = {
    sequence = 40,
    conversations = {
        ["archived friend"] = {
            key = "archived friend",
            name = "Archived Friend",
            updated = 40,
            unread = 1,
            messages = {},
        },
    },
}

for i = 1, 40 do
    foreign.conversations["archived friend"].messages[i] =
        { id = i, time = 1700000000 + i, text = "Old message " .. i, outgoing = i % 2 == 0 }
end

Whispr.db.sv = { char = { ["Current - Realm"] = Whispr.db.char, ["Other - Realm"] = foreign } }
Whispr.db.global.showAllCharacters = true
History.Invalidate()
foreign.conversations["archived friend"].character = { race = "Dwarf", class = "Shaman", classFile = "SHAMAN" }
CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS or {}
CLASS_ICON_TCOORDS.SHAMAN = { 0, 0.25, 0, 0.25 }
History.Invalidate()
reader:RefreshList()

local function archivedCard()
    for _, row in ipairs(reader.rows) do
        if row.key == "archived friend" then
            return row
        end
    end
end

equal(archivedCard().details:GetText(), "Dwarf · Shaman", "foreign card has saved identity before click")
local classIcon = archivedCard().avatar.icon.texture
reader:Open("archived friend")
flush()
equal(archivedCard().details:GetText(), "Dwarf · Shaman", "offline selection preserves card race/class")
equal(archivedCard().avatar.icon.texture, classIcon, "offline selection preserves class icon")
equal(reader.headerAvatar.icon.texture, classIcon, "selected offline header preserves class icon")
Whispr.db.char.conversations["archived friend"].character = nil
History.Invalidate()
reader:Select("archived friend")
flush()
equal(archivedCard().details:GetText(), "Dwarf · Shaman", "already-empty local identity recovered on selection")
equal(#loadedMessages(reader), 20, "combined conversation still pages latest twenty")
reader:LoadOlderMessages()
flush()
equal(#loadedMessages(reader), 40, "combined conversation loads older foreign messages")
equal(
    #Whispr.db.char.conversations["archived friend"].messages,
    0,
    "opening combined history creates only routing metadata"
)
local outgoingFound = false
for _, bubble in ipairs(reader.bubbles) do
    if bubble.row.message.outgoing then
        outgoingFound = true
        assert(bubble.meta:GetText():find("Other - Realm", 1, true), "foreign outgoing sender labeled")
    end
end

assert(outgoingFound, "foreign outgoing bubble displayed")
equal(foreign.conversations["archived friend"].unread, 0, "combined viewport marks foreign history read")
reader:ConfirmAction("delete", "archived friend")
-- Cache rebuilds from normal refreshes must not invalidate source identity.
local identity = History.Identity("archived friend")
History.Invalidate()
assert(History.Identity("archived friend") == identity, "source identity survives display cache rebuild")
print("Combined window pagination, source labels, routing-only local records and read state passed.")

-- Visibility must follow AceGUI's active-frame registry, not a pooled frame.
load("settings")
local dialog = { OpenFrames = {} }
local previousLibStub = LibStub
LibStub = function(name)
    if name == "AceConfigDialog-3.0" then
        return dialog
    end

    return previousLibStub(name)
end

assert(not addon.Settings:IsShown(), "settings starts closed")
local settingsFrame = frame()
dialog.OpenFrames.Whispr = { frame = settingsFrame }
assert(addon.Settings:IsShown(), "standard settings is visible")
Whispr.db.global.fadeWhenIdle = true
Whispr.db.global.windowOpacity = 0.9
reader.focused = false
reader.frame.mouseOver = false
reader.input.focused = false
reader:UpdateOpacity(100, true)
reader:UpdateOpacity(100)
equal(reader.frame.alpha, 0.9, "standard settings suppresses chat idle fade")
settingsFrame:Hide()
assert(not addon.Settings:IsShown(), "hidden settings is not active")
dialog.OpenFrames.Whispr = nil
settingsFrame:Show()
assert(not addon.Settings:IsShown(), "pooled frame reused by another addon is not Whispr settings")
print("Standard AceConfig visibility and fade suppression passed.")

local previousTyping = addon.Typing
addon.Typing = {
    Stop = function() end,
    IsTyping = function()
        return false
    end,

    Discover = function()
        error("opening a conversation must not send a discovery whisper")
    end,
}

local offlineReader = recreated()
offlineReader.popouts = {}
offlineReader.detached = {}
offlineReader:Open("Offline Saved Character")
flush()
offlineReader:Select("offline saved character")
flush()
assert(offlineReader.frame:IsShown(), "offline history can be opened without a discovery probe")
addon.Typing = previousTyping
print("Opening and selecting conversations never probes the recipient with addon whispers.")

Whispr.db.global.separateWindowWidth = 640
Whispr.db.global.separateWindowHeight = 420
local sizeHub = recreated()
sizeHub.popouts = {}
sizeHub.detached = {}
sizeHub:Create()
local sizeChat = History.Add(Whispr.db.char, Whispr.db.global, "Sized conversation", "Hello", false, 1, false)
local sizePopout = recreated(sizeHub, sizeChat.key)
sizeHub.popouts[sizeChat.key] = sizePopout
sizePopout:Create()
sizePopout:Show()
flush()
equal(sizePopout.frame:GetWidth(), 640, "new separate window uses configured width")
equal(sizePopout.frame:GetHeight(), 420, "new separate window uses configured height")
sizePopout.frame:SetSize(700, 460)
sizePopout:SaveGeometry()
local savedPopout = recreated(sizeHub, sizeChat.key)
savedPopout:Create()
equal(savedPopout.frame:GetWidth(), 700, "saved per-conversation width overrides default")
equal(savedPopout.frame:GetHeight(), 460, "saved per-conversation height overrides default")
local hubWidth, hubHeight = sizeHub.frame:GetWidth(), sizeHub.frame:GetHeight()
Whispr.db.global.separateWindowWidth = 600
Whispr.db.global.separateWindowHeight = 380
sizeHub:ApplySeparateSize()
flush()
equal(sizePopout.frame:GetWidth(), 600, "apply updates open separate width")
equal(sizePopout.frame:GetHeight(), 380, "apply updates open separate height")
equal(sizeHub.frame:GetWidth(), hubWidth, "apply leaves main window width unchanged")
equal(sizeHub.frame:GetHeight(), hubHeight, "apply leaves main window height unchanged")
equal(sizeChat.window.width, 600, "applied size saved for conversation")
print("Separate window defaults, saved overrides and applying defaults to open windows passed.")

Whispr.db.global.showAllCharacters = false
Whispr.db.global.separateWindows = false
Whispr.db.char = { sequence = 0, conversations = {} }
History.Invalidate()
local dockHub = recreated()
dockHub.detached = {}
dockHub.popouts = {}

local function dockChat(name)
    return History.Add(Whispr.db.char, Whispr.db.global, name, "hello", false, 1, false)
end

local dockA, dockB, dockC = dockChat("Dock A"), dockChat("Dock B"), dockChat("Dock C")

local function cardVisible(key)
    for _, row in ipairs(dockHub.rows) do
        if row:IsShown() and row.key == key then
            return true
        end
    end

    return false
end

dockHub:Open(dockB.key)
flush()
dockHub.input:SetText("draft for detached B")
dockHub:Detach(dockB.key)
flush()
equal(dockHub.active, dockA.key, "undocking selects next remaining card below")
assert(not cardVisible(dockB.key), "undocked conversation removed from main list")
equal(dockHub.detached[dockB.key].input:GetText(), "draft for detached B", "draft follows detached conversation")
dockHub:Detach(dockA.key)
flush()
equal(dockHub.active, dockC.key, "last card falls back to previous docked conversation")
local dockD = dockChat("Dock D")
dockHub:RefreshList()
dockHub:Detach(dockD.key)
flush()
equal(dockHub.active, dockC.key, "undocking inactive card preserves selection")
assert(not cardVisible(dockD.key), "inactive detached card removed immediately")
dockHub.detached[dockD.key]:HideImmediately()
dockHub:RefreshList()
assert(not cardVisible(dockD.key), "hidden undocked conversation stays excluded")
dockHub:Detach(dockC.key)
flush()
equal(dockHub.active, nil, "undocking final card leaves empty main view")
for _, row in ipairs(dockHub.rows) do
    assert(not row:IsShown(), "no stale detached cards remain")
end

dockHub.detached[dockB.key]:Dock()
flush()
equal(dockHub.active, dockB.key, "docking selects returned conversation")
assert(cardVisible(dockB.key), "docking restores conversation card")
equal(dockHub.input:GetText(), "draft for detached B", "docking preserves transferred draft")
print("Undocking filters cards, selects neighbors, preserves drafts and restores cards on docking.")

-- Rebuild controllers against the same saved data to model reload/login.
local openRecord = Whispr.db.char.conversations[dockA.key]
local closedRecord = Whispr.db.char.conversations[dockD.key]
dockHub.detached[dockA.key]:Show()
dockHub.detached[dockA.key].frame:SetSize(620, 410)
dockHub:SaveAllGeometry()
assert(openRecord.undocked and openRecord.undockedOpen, "open undocked state saved")
assert(closedRecord.undocked and not closedRecord.undockedOpen, "closed undocked state saved separately")
local restoredHub = recreated()
restoredHub.detached = {}
restoredHub.popouts = {}
restoredHub:RestoreUndocked()
flush()
assert(restoredHub.detached[dockA.key].frame:IsShown(), "reload restores open undocked window")
equal(restoredHub.detached[dockA.key].frame:GetWidth(), 620, "restored popout retains saved size")
assert(not restoredHub.detached[dockD.key].frame:IsShown(), "reload retains closed state without docking")
assert(not restoredHub.detached[dockB.key], "docked conversation does not reopen as popout")
assert(not restoredHub.detached[dockA.key].input:HasFocus(), "restore does not steal keyboard focus")
local reused = restoredHub.detached[dockA.key]
restoredHub:RestoreUndocked()
equal(restoredHub.detached[dockA.key], reused, "world reentry does not duplicate restored windows")
restoredHub.detached[dockA.key]:Dock()
flush()
assert(not openRecord.undocked, "docking clears saved undocked state")
Whispr.db.global.hideInCombat = true
combat = true
local combatHub = recreated()
combatHub.detached = {}
combatHub.popouts = {}
combatHub:RestoreUndocked()
flush()
assert(not combatHub.detached[dockC.key].frame:IsShown(), "reload in combat keeps restored windows hidden")
assert(combatHub.detached[dockC.key].hiddenForCombat, "open state deferred until combat ends")
combat = false
combatHub:CombatChanged(false)
flush()
assert(combatHub.detached[dockC.key].frame:IsShown(), "combat exit restores previously open undocked window")
local routing = { key = "routing", name = "Routing", messages = {}, undocked = true, updated = 1 }
Whispr.db.char.conversations.routing = routing
History.RemoveEmpty(Whispr.db.char)
assert(Whispr.db.char.conversations.routing == routing, "empty routing record retains undocked state across cleanup")
print("Undocked state survives reload, preserves geometry/visibility, clears on docking and respects combat.")

-- Sidebar search filters names without changing the selected chat or drafts.
Whispr.db.global.maxPeople = 100
local searchWillow = History.Add(Whispr.db.char, Whispr.db.global, "Search Willow", "hello", false, 1, false)
local searchRowan = History.Add(Whispr.db.char, Whispr.db.global, "Search Rowan", "hello", false, 2, false)
local searchLiteral = History.Add(Whispr.db.char, Whispr.db.global, "Search [Mage]", "hello", false, 3, false)
local searchWindow = recreated()
searchWindow.detached = {}
searchWindow:Open(searchWillow.key)
flush()
searchWindow.input:SetText("unfinished reply")

local function query(text)
    searchWindow.search:SetText(text)
    searchWindow.search.scripts.OnTextChanged(searchWindow.search)
end

query("  rOwAn  ")
equal(searchWindow.rows[1].key, searchRowan.key, "search trims whitespace and ignores case")
equal(searchWindow.rows[2]:IsShown(), false, "nonmatching rows hidden")
equal(searchWindow.active, searchWillow.key, "search preserves selected conversation")
equal(searchWindow.input:GetText(), "unfinished reply", "search preserves draft")
equal(searchWindow.people:GetVerticalScroll(), 0, "search resets list scroll")
query("[Mage]")
equal(searchWindow.rows[1].key, searchLiteral.key, "search treats pattern characters literally")
query("no-such-character")
equal(searchWindow.rows[1]:IsShown(), false, "no matches hides all rows")
equal(searchWindow.searchEmpty:IsShown(), true, "empty search result has feedback")
searchWindow.detached[searchRowan.key] = {}
query("Rowan")
equal(searchWindow.searchEmpty:IsShown(), true, "search excludes undocked conversations")
query("")
equal(searchWindow.searchEmpty:IsShown(), false, "clearing restores list")
equal(searchWindow.searchPlaceholder:IsShown(), true, "empty input shows search hint")
equal(searchWindow.searchClear:IsShown(), false, "empty input hides clear button")
print("Conversation search, draft preservation, literal matching and undocked filtering passed.")

CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS or {}
CLASS_ICON_TCOORDS.MAGE = { 0, 0.25, 0, 0.25 }
searchWillow.character = { classFile = "MAGE" }
History.Invalidate()
Whispr.db.global.showMessageClassIcons = true
searchWindow:RefreshMessages()
flush()
assert(searchWindow.bubbles[1].classIcon:IsShown(), "known sender gets a class icon")
Whispr.db.global.showMessageClassIcons = false
searchWindow:RefreshMessages()
flush()
assert(not searchWindow.bubbles[1].classIcon:IsShown(), "message icon option hides pooled icons")
Whispr.db.global.showMessageClassIcons = true
searchWillow.character = nil
History.Invalidate()
searchWindow:RefreshMessages()
flush()
assert(not searchWindow.bubbles[1].classIcon:IsShown(), "unknown sender does not inherit a pooled class icon")
print("Optional message class icons refresh and reset correctly on reused bubbles.")

function methods:SetJustifyV(value)
    self.justifyV = value
end

local groupedChat
for index, stamp in ipairs({ 1000, 1010, 1020, 1030, 1700 }) do
    groupedChat =
        History.Add(Whispr.db.char, Whispr.db.global, "Grouped Sender", "Message " .. index, index > 2, stamp, false)
end

groupedChat.character = { classFile = "MAGE" }
History.Invalidate()
local groupedWindow = recreated()
groupedWindow:Open(groupedChat.key)
flush()
local groupRows = {}
for _, row in ipairs(groupedWindow.messageRows) do
    if row.message then
        groupRows[#groupRows + 1] = row
    end
end

assert(not groupRows[1].grouped and groupRows[2].grouped, "consecutive sender shares one title")
assert(not groupRows[3].grouped and groupRows[4].grouped, "sender change starts a new group")
assert(not groupRows[5].grouped, "long pause starts a new title")
for _, bubble in ipairs(groupedWindow.bubbles) do
    equal(bubble.meta:IsShown(), not bubble.row.grouped, "only group starts display metadata")
    equal(bubble.text.justifyV, "TOP", "tight glyph bounds keep native selection aligned")
    equal(bubble.text:GetHeight(), bubble.textHeight, "text region fits the actual glyph height")
    local topPadding = -bubble.text.lastPoint[3] - bubble.bodyTop
    local bottomPadding = bubble:GetHeight() + bubble.text.lastPoint[3] - bubble.textHeight
    equal(
        topPadding - bubble.textBaselineOffset,
        bottomPadding + bubble.textBaselineOffset,
        "line box is centered before the single-line baseline adjustment"
    )
    if bubble.row.grouped then
        assert(not bubble.classIcon:IsShown(), "group continuations omit icon")
    end
end

local function menuAction(label)
    groupedWindow:ConversationMenu(groupedWindow.frame, searchWillow.key)
    for _, entry in ipairs(entries) do
        if entry.label == label then
            entry.action()
            return
        end
    end

    error("Missing menu action: " .. label)
end

menuAction("Pin conversation")
assert(groupedWindow.rows[1].pin:IsShown(), "pinned conversation shows a pin on its card")
assert(Whispr.db.char.conversations[searchWillow.key].pinned, "pin saved on conversation")
equal(History.Sorted(History.DisplayData())[1].key, searchWillow.key, "pinned conversation sorts before newer chats")
equal(groupedWindow.active, groupedChat.key, "pinning does not change active conversation")
menuAction("Unpin conversation")
for _, row in ipairs(groupedWindow.rows) do
    if row.key == searchWillow.key then
        assert(not row.pin:IsShown(), "unpinning removes the card pin")
    end
end

assert(not Whispr.db.char.conversations[searchWillow.key].pinned, "unpin clears saved preference")
assert(History.Sorted(History.DisplayData())[1].key ~= searchWillow.key, "unpin restores recency ordering")
local crop = {
    SetTexture = function() end,
    SetTexCoord = function(self, ...)
        self.coords = { ... }
    end,
}

assert(addon.UI.SetClassIcon(crop, "MAGE"), "class atlas exists")
assert(crop.coords[1] == 0.1 and crop.coords[2] == 0.9, "bundled icon uses transparent art without the original frame")
print("Grouped message headers, centered text, cropped class icons and saved conversation pinning passed.")

local shortChat = History.Add(Whispr.db.char, Whispr.db.global, "Long Header Name", "yes?", false, 2000, false)
local shortWindow = recreated()
shortWindow:Open(shortChat.key)
flush()
local shortBubble = shortWindow.bubbles[1]
assert(shortBubble.bodyWidth < shortBubble:GetWidth(), "short bubble is narrower than its sender heading")
equal(
    shortBubble.bodyWidth,
    shortBubble.text:GetStringWidth() + 22,
    "short text gets padding without a minimum-width box"
)
assert(shortBubble.bodyLeft == 0, "incoming short bubble aligns left")
equal(shortBubble.textBaselineOffset, 2, "single-line text compensates for native font leading")
equal(shortBubble.text:GetHeight(), 16, "baseline adjustment retains full descender and selection bounds")
History.Add(Whispr.db.char, Whispr.db.global, "Long Header Name", "ok", true, 2001, false)
shortWindow:RefreshMessages()
flush()
local reply = shortWindow.bubbles[#shortWindow.bubbles]
equal(reply.bodyLeft + reply.bodyWidth, reply:GetWidth(), "outgoing short bubble aligns right independently of heading")
print("Short bubble widths follow text rather than sender heading width.")
local baselineChat =
    History.Add(Whispr.db.char, Whispr.db.global, "Baseline Regression", "first line\nsecond line", false, 2010, false)
shortWindow:Open(baselineChat.key)
flush()
equal(shortWindow.bubbles[1].textBaselineOffset, 0, "explicit multiline message keeps original placement")
History.Add(
    Whispr.db.char,
    Whispr.db.global,
    "Baseline Regression",
    string.rep("wrapped text ", 60),
    false,
    2011,
    false
)
shortWindow:RefreshMessages()
flush()
equal(shortWindow.bubbles[#shortWindow.bubbles].textBaselineOffset, 0, "wrapped message keeps original placement")

do
    local longWord = string.rep("abcdefghij", 14)
    local originalGetHeight = methods.GetHeight

    function methods:GetHeight()
        if self.isFontString and self.height == 0 and self.text == longWord then
            return self.nonSpaceWrap and math.ceil(#longWord * 7 / self:GetWidth()) * 16 or 16
        end

        return originalGetHeight(self)
    end

    local wrapChat = History.Add(Whispr.db.char, Whispr.db.global, "Wrap Regression", longWord, false, 2012, false)
    History.Add(Whispr.db.char, Whispr.db.global, "Wrap Regression", "next message", false, 2013, false)
    shortWindow:Open(wrapChat.key)
    flush()
    local first, nextBubble = shortWindow.bubbles[1], shortWindow.bubbles[2]
    assert(first.text.nonSpaceWrap and shortWindow.messageMeasure.text.nonSpaceWrap, "both FontStrings wrap long words")
    equal(first.text:GetText(), longWord, "word wrapping preserves the complete message")
    equal(first.text.height, 0, "message text has no height cap")
    local initialHeight = first.text:GetHeight()
    assert(initialHeight > 16, "unbroken text takes multiple lines")
    equal(first.textHeight, initialHeight, "bubble uses the native wrapped height")
    equal(nextBubble.row.y, first.row.y + first.row.height + 6, "next message starts below the wrapped row")

    local originalWidth = shortWindow.scroll:GetWidth()
    shortWindow.scroll:SetWidth(originalWidth / 2)
    shortWindow:RefreshMessages()
    flush()
    first = shortWindow.bubbles[1]
    assert(first.textHeight > initialHeight, "a narrower view grows the message row")
    equal(first.row.height, first.textHeight + first.bodyTop + 15, "row height covers every wrapped line plus padding")
    shortWindow.scroll:SetWidth(originalWidth)
    methods.GetHeight = originalGetHeight
end

do
    local clipped = "Greetings |cff80ff80Tester|r! "
        .. "I wanted to send a longer whisper with enough ordinary words to fill multiple lines. Here is the ending."
    local originalGetStringHeight = methods.GetStringHeight

    function methods:GetStringHeight()
        if self.text:find("^Greetings ") then
            return 16
        end

        return originalGetStringHeight(self)
    end

    local clippedChat = History.Add(Whispr.db.char, Whispr.db.global, "Clipped Whisper", clipped, false, 2014, false)
    History.Add(Whispr.db.char, Whispr.db.global, "Clipped Whisper", "following message", false, 2015, false)
    shortWindow:Open(clippedChat.key)
    flush()
    local first, nextBubble = shortWindow.bubbles[1], shortWindow.bubbles[2]
    local wrapped = first.text:GetText()
    assert(wrapped:find("\n", 1, true), "message expands when native wrapping leaves it on one line")
    assert(wrapped:find("|cff80ff80Tester|r", 1, true), "manual breaks preserve name coloring")
    assert(wrapped:match("Here is the ending%.$"), "full message tail is rendered")
    equal(first.selectionLayout.source, clipped, "selection keeps the full original text")
    assert(first.textHeight > 16, "displayed text has more than one line")
    equal(first.text:GetStringHeight(), 16, "native text height still reports one line")
    equal(first.text:GetHeight(), first.textHeight, "display FontString gets space for every measured line")
    equal(first.row.height, first.textHeight + first.bodyTop + 15, "measured row fits the manually wrapped text")
    equal(nextBubble.row.y, first.row.y + first.row.height + 6, "following message is laid out below it")
    methods.GetStringHeight = originalGetStringHeight
end

shortWindow:Open(shortChat.key)
flush()
equal(shortWindow.bubbles[1].textBaselineOffset, 2, "recycled bubble restores single-line baseline")

-- Exercise real selection hooks alongside message opacity and frame reuse.
local dragIndex = 1

function methods:FindCharacterIndexAtCoordinate()
    return dragIndex, true
end

function methods:CalculateScreenAreaFromCharacterSpan()
    return { { left = 0, bottom = 0, width = 24, height = 14 } }
end

GetCursorPosition = function()
    return 0, 0
end

IsMouseButtonDown = function()
    return true
end

Whispr.db.global.animateWindows = true
local dragChat = History.Add(Whispr.db.char, Whispr.db.global, "Drag Test", "hello world", true, 2100, false)
dragChat.messages[1].pending = true
local dragWindow = recreated()
dragWindow:Open(dragChat.key)
flush()
local dragBubble = dragWindow.bubbles[1]

local function dragAndCheck()
    dragIndex = 1
    dragBubble.scripts.OnMouseDown(dragBubble, "LeftButton")
    dragIndex = 6
    dragBubble.scripts.OnUpdate(dragBubble, 0.3)
    assert(
        dragWindow.messageSelection and dragWindow.messageSelection.selected == "hello",
        "selection updates before releasing mouse"
    )
    assert(dragBubble.selectionHighlights[1]:IsShown(), "drag highlight is visible")
    addon.Selection.Clear(dragWindow)
end

dragAndCheck()
dragChat.messages[1].pending = nil
dragWindow:RefreshMessages()
flush()
dragAndCheck()
assert(dragBubble.deliveryFade == nil, "delivery animation completes while selecting")
dragWindow:ReleaseMessageFrames()
dragWindow:UpdateVisibleMessages()
dragBubble = dragWindow.bubbles[1]
dragAndCheck()
Whispr.db.global.animateWindows = false
dragWindow:RefreshMessages()
flush()
dragAndCheck()
print("Live drag selection survives delivery fades, disabled animations and pooled frame reuse.")

-- Rich messages must retain their images while selecting without invoking the
-- native FontString character APIs, including after pooled frame reuse.
function methods:GetUnboundedStringWidth()
    local text = self.text:gsub("|T.-|t", "xx"):gsub("|A.-|a", "xx")
    return #text * 7
end

local originalFormatMessage = addon.Format.Message
local selectionTexture = "|TInterface\\AddOns\\Whispr\\assets\\emotes\\happy.tga:16:16|t"
addon.Format.Message = function(text, ...)
    if text == "texture selection regression" then
        return "hello " .. selectionTexture
    end

    return originalFormatMessage(text, ...)
end

local richChat =
    History.Add(Whispr.db.char, Whispr.db.global, "Rich Selection", "texture selection regression", false, 2200, false)
dragWindow:Open(richChat.key)
flush()

local function checkRichSelection()
    local richBubble = dragWindow.bubbles[1]
    assert(richBubble.selectionLayout, "visible rich frame has measured selection layout")
    local displayed = richBubble.text:GetText()
    assert(displayed:find(selectionTexture, 1, true), "message still displays emoji")
    richBubble.text.FindCharacterIndexAtCoordinate = function()
        error("native hit test called on inline texture")
    end

    richBubble.text.CalculateScreenAreaFromCharacterSpan = function()
        error("native span query called on inline texture")
    end

    richBubble.text.GetLeft = function()
        return 0
    end

    richBubble.text.GetTop = function()
        return 100
    end

    local cursorY = 99
    GetCursorPosition = function()
        return 0, cursorY
    end

    richBubble.scripts.OnMouseDown(richBubble, "LeftButton")
    cursorY = -10000
    richBubble.scripts.OnUpdate(richBubble, 0.3)
    equal(dragWindow.messageSelection.selected, "hello :)", "rich selection copies emoji text")
    equal(richBubble.text:GetText(), displayed, "selection never deparses displayed emoji")
    richBubble.scripts.OnMouseUp(richBubble, "LeftButton")
    equal(dragWindow.copyBridge:GetText(), "hello :)", "rich selection reaches clipboard")
    addon.Selection.Clear(dragWindow)
end

checkRichSelection()
dragWindow:ReleaseMessageFrames()
dragWindow:UpdateVisibleMessages()
checkRichSelection()
addon.Format.Message = originalFormatMessage
print("Visible emoji selection bypasses native character APIs before and after pooled frame reuse.")

Window:Open(modeChat.key)
flush()
Window:ShowCopyText("https://example.com", "Copy link")
Window:ToggleEmotes()
equal(Window.url:GetFrameStrata(), "DIALOG", "copy dialog follows focused window")
equal(Window.url.shade:GetFrameStrata(), "DIALOG", "copy backdrop follows focused window")
equal(Window.emotePicker:GetFrameStrata(), "DIALOG", "picker follows focused window")
Window:SetWindowFocus(false)
equal(Window.url:GetFrameStrata(), "LOW", "copy dialog lowers with inactive window")
equal(Window.url.shade:GetFrameStrata(), "LOW", "copy backdrop lowers with inactive window")
equal(Window.emotePicker:GetFrameStrata(), "LOW", "picker lowers with inactive window")
Window:SetWindowFocus(true)
equal(Window.url:GetFrameStrata(), "DIALOG", "existing popup returns to foreground on activation")
print("Dynamic focus strata follow hub, popouts, copy dialogs and emoji pickers.")

local playerMenuModifiers = {}
Menu = {
    ModifyMenu = function(tag, callback)
        playerMenuModifiers[tag] = callback
    end,
}

MenuUtil.CreateButton = function(label, action)
    return { label = label, action = action, SetEnabled = noop }
end

UnitPopup_OpenMenu = function(which, context)
    MenuUtil.CreateContextMenu(nil, function(_, root)
        root.Insert = function(_, entry, index)
            table.insert(entries, index, entry)
        end

        root:CreateButton("Player name", noop)
        root:CreateButton("Native player action", noop)
        playerMenuModifiers["MENU_UNIT_" .. which](nil, root, context)
    end)
end

Window:ConversationMenu(Window.frame, modeChat.key)
equal(entries[1].label, "Player name", "native player title stays first")
equal(entries[2].label, "Open in separate window", "Whispr window action is first beneath player title")
equal(entries[3].label, "Native player action", "native player interactions follow window action")
local menuLabels = {}
for _, entry in ipairs(entries) do
    if entry.label then
        menuLabels[entry.label] = true
    end
end

assert(menuLabels["Pin conversation"] or menuLabels["Unpin conversation"], "pin action extends native menu")
assert(menuLabels["Delete conversation"] and menuLabels["Close window"], "conversation actions extend native menu")
assert(not menuLabels["Invite to group"], "native menu does not duplicate fallback player actions")
Window.headerAvatar.scripts.OnMouseUp(Window.headerAvatar, "RightButton")
equal(entries[2].label, "Open in separate window", "header avatar opens the same reordered player menu")
local moveCount = 0
for _, entry in ipairs(entries) do
    if entry.label == "Open in separate window" then
        moveCount = moveCount + 1
    end
end

equal(moveCount, 1, "window action is not duplicated at bottom")
local menuPopout = { owner = Window, Dock = noop }
MenuUtil.CreateContextMenu(nil, function(_, root)
    root.Insert = function(_, entry, index)
        table.insert(entries, index, entry)
    end

    root:CreateButton("Player name", noop)
    root:CreateButton("Native player action", noop)
    Window.AddConversationMenuEntries(menuPopout, root, modeChat.key)
end)

equal(entries[2].label, "Dock in main window", "popout dock action is also first beneath title")
print("Conversation cards and headers open native player menus with Whispr actions appended.")

Window:Open(modeChat.key)
flush()
Window.input:SetFocus()
IsModifiedClick = function(kind)
    return kind == "CHATLINK"
end

hovered = UIParent
Window.focusEvents.scripts.OnEvent()
equal(Window.focused, nil, "link click lowers the chat window")
equal(Window.frame:GetFrameStrata(), "LOW", "spellbook can remain above chat while linking")
equal(Window:FocusedInput(), Window.input, "link click preserves composer for delayed insertion")
Window.focusEvents.scripts.OnEvent()
equal(Window:FocusedInput(), Window.input, "multiple link clicks keep the same composer")
IsModifiedClick = function()
    return false
end

Window.focusEvents.scripts.OnEvent()
equal(Window:FocusedInput(), nil, "ordinary outside click releases preserved composer")
Window.input:SetFocus()
IsModifiedClick = function()
    return true
end

Window.focusEvents.scripts.OnEvent()
focusPop:Open(manualChat.key)
flush()
equal(Window.input:HasFocus(), false, "another conversation cannot retain the old link destination")
equal(focusPop.input:HasFocus(), true, "separate window owns the new insertion target")
focusPop:SetWindowFocus(false)
IsModifiedClick = nil
print("Shift-click linking preserves input without keeping the window above the spellbook.")

-- Exercise live skin changes on existing windows and pooled message surfaces.
function methods:CreateMaskTexture()
    return frame(nil, self)
end

function methods:AddMaskTexture(mask)
    self.mask = mask
end

function methods:SetDrawLayer() end

function methods:SetGradientAlpha(...)
    self.gradient = { ... }
end

function methods:SetFrameLevel(level)
    self.frameLevel = level
end

function methods:GetFrameLevel()
    return self.frameLevel or 1
end

function methods:SetColorTexture(...)
    self.color = { ... }
end

function methods:SetBackdrop(backdrop)
    self.backdrop = backdrop
end

function methods:SetVertexColor(...)
    self.vertexColor = { ... }
end

function methods:SetBackdropBorderColor(...)
    self.borderColor = { ... }
end

function methods:SetHorizTile(value)
    self.horizontalTile = value
end

function methods:SetVertTile(value)
    self.verticalTile = value
end

PortraitFrameFlatBaseMixin = {}
PANEL_BACKGROUND_COLOR = {
    GetRGB = function()
        return 0.12, 0.10, 0.08
    end,
}

CreateColor = function(red, green, blue, alpha)
    return { r = red, g = green, b = blue, a = alpha }
end

local theme = addon.Theme
addon.Window = Window
assert(theme:Apply("classic"))
assert(Window.background.native:IsShown(), "Classic adds native window chrome")
assert(Window.classicChrome:IsShown(), "Classic uses Blizzard's full portrait window")
equal(Window.classicChrome.TitleContainer.TitleText.text, "Whispr", "native title displays addon name")
equal(Window.settingsButton.parent, Window.classicChrome, "settings belongs to native title chrome")
equal(Window.infoButton.parent, Window.classicChrome, "about belongs to native title chrome")
equal(Window.conversationBand.lastPoint[3], -27, "Classic retains the requested content layout")
assert(
    Window.settingsButton:GetFrameLevel() > Window.classicChrome.NineSlice:GetFrameLevel(),
    "settings draws above the native title border"
)
assert(
    Window.infoButton:GetFrameLevel() > Window.classicChrome.NineSlice:GetFrameLevel(),
    "about draws above the native title border"
)
assert(Window.settingsButton:IsShown() and Window.infoButton:IsShown(), "title controls stay visible")
equal(Window.classicChrome.Bg:IsShown(), true, "native bag background is visible")
equal(Window.background.nativeFill:IsShown(), true, "solid backing prevents the world from bleeding through")
equal(Window.background.nativeFill.color[4], 1, "Classic backing remains opaque")
equal(Window.classicChrome.nativeBackgroundColor.a, 1, "native panel color uses opaque alpha")
equal(Window.sidebar.lastPoint[2], 12, "sidebar starts inside the native border")
equal(Window.sidebar.lastPoint[3], 8, "sidebar bottom stays inside the native border")
equal(Window.background.nativeFill.lastPoint[5], 8, "solid backing stays inside the bottom border")
equal(Window.classicChrome:GetPortrait().width, 36, "portrait matches Forever bag size")
equal(Window.classicChrome.layout, "HeldBagLayout", "window uses Forever's exact bag border layout")
assert(Window.classicChrome.nativeBackground, "native panel background colors are applied")
assert(not Window.classicChrome.NineSlice.TopEdge.lastPoint, "native title-strip anchors remain untouched")
equal(
    Window.settingsButton.surface.nativeFill.texture,
    "Interface\\Buttons\\SquareButtonTextures",
    "buttons use native square artwork"
)
Window.settingsButton.scripts.OnMouseDown()
Window.settingsButton.scripts.OnMouseUp()
assert(Window.classicInsets.messages.Bg:IsShown(), "content pane has a visible texture")
equal(
    Window.classicInsets.messages.Bg.texture,
    "Interface\\FrameGeneral\\UI-Background-Rock",
    "content uses native brown panel texture"
)
equal(Window.classicInsets.messages.Bg.vertexColor[4], 1, "textured panel remains opaque")
assert(Window.classicInsets.messages.shade.gradient, "panel has restrained shading")
local savedWidth = Window.frame:GetWidth()
Window.frame:SetWidth(540)
Window:Layout()
assert(Window.drawerToggle:IsShown(), "small combined windows show the conversation menu")
equal(Window.headerAvatar.lastPoint[2], 22, "compact header has no extra portrait indentation")
equal(Window.drawerToggle.lastPoint[2], Window.classicChrome:GetPortrait(), "compact menu anchors beside portrait")
equal(Window.drawerToggle.width, 22, "compact menu matches other title controls")
equal(Window.classicInsets.messages.parent, Window.frame, "panel background belongs to full container")
equal(Window.classicInsets.messages.lastPoint[2], Window.input, "panel ends above composer rather than viewport")
equal(Window.classicInsets.messages.lastPoint[3], "TOPRIGHT", "panel fills the reserved scrollbar gutter")
assert(
    Window.drawerToggle:GetFrameLevel() > Window.classicChrome.NineSlice:GetFrameLevel(),
    "compact menu draws above title artwork"
)
Window.frame:SetWidth(savedWidth)
Window:Layout()
assert(not Window.background.native.backdrop, "native chrome replaces the tooltip border")
assert(Window.input.surface.native:IsShown(), "flat composer receives native skin")
assert(not Window.input.surface.nativeInset, "Classic input avoids rounded native inset corners")
local inputColor = Window.input.surface.nativeFill.color[1]
Window.input.scripts.OnEditFocusGained(Window.input)
equal(Window.input.surface.nativeFill.color[1], inputColor, "input focus keeps the same dark fill")
equal(Window.input.surface.inputEdges[1].color[1], 0.44, "focus subtly highlights square border")
Window.input.scripts.OnEditFocusLost(Window.input)
equal(Window.input.surface.inputEdges[1].color[1], 0.25, "blur restores the quiet border")
equal(Window.messageGrain.alpha, 0, "grain does not obscure native texture")
local nativeWindow = Window.background.native
local pooled = addon.UI.Round(frame(), 5, 0.1, 0.1, 0.1)
pooled.role = "message"
pooled:SetInsets(24, 40, 0)
theme:Paint(pooled, "incomingColor")
local nativeBubble = pooled.native
assert(not nativeBubble.backdrop, "message bubbles avoid decorative tooltip outlines")
equal(nativeBubble.lastPoint[4], 0, "bubble body respects right inset")
pooled:Hide()
theme:Refresh()
equal(nativeBubble:IsShown(), false, "refresh keeps released surfaces hidden")
pooled:SetInsets(0, 0, 40)
pooled:SetShown(true)
theme:Paint(pooled, "outgoingColor")
equal(pooled.native, nativeBubble, "reused bubble retains its native backdrop")
equal(nativeBubble.lastPoint[4], -40, "reused bubble follows new alignment")
Whispr.db.global.backgroundOpacity = 0.35
theme:Refresh()
equal(pooled.nativeFill.color[4], 0.9, "Classic bubbles retain a readable fill at low panel opacity")
theme:Paint(pooled, "headerColor", false, true)
equal(pooled.nativeFill.color[4], 1, "Classic modal backgrounds remain opaque")
theme:Options().args.incomingColor.set(nil, 0.3, 0.2, 0.1)
assert(theme:GetSkin(), "custom colors retain Classic textures")
equal(theme:CurrentPreset(), "custom", "custom colors remain identified correctly")
assert(theme:Apply("default"))
equal(nativeWindow:IsShown(), false, "flat theme hides native chrome")
equal(Window.classicChrome:IsShown(), false, "flat theme hides portrait window")
assert(Window.brand:IsShown(), "flat theme restores original title")
equal(Window.settingsButton.parent, Window.titlebar, "flat theme restores settings parent")
equal(Window.infoButton.parent, Window.titlebar, "flat theme restores about parent")
equal(Window.conversationBand.lastPoint[3], -39, "flat theme restores toolbar layout")
equal(nativeBubble:IsShown(), false, "flat theme hides native message backdrops")
equal(Window.messageGrain.alpha, 0.35, "flat theme restores grain opacity")
assert(theme:Apply("classic"))
equal(Window.background.native, nativeWindow, "theme toggles reuse native chrome")
theme:Apply("default")
print("Classic live skin changes, custom colors, opacity, insets and backdrop reuse passed.")
