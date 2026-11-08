SOUNDKIT = { TELL_MESSAGE = 1 }
PlaySoundFile = function() end
local addon, timers, filters = {}, {}, {}
assert(loadfile("tests/support/locale.lua"))(addon)

local function load(name)
    assert(loadfile("scripts/" .. name .. ".lua"))("Whispr", addon)
end

local function equal(a, b, label)
    assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

time = function()
    return 1
end

C_Timer = {
    After = function(_, callback)
        timers[#timers + 1] = callback
    end,
}

ChatFrameUtil = {
    AddMessageEventFilter = function(event, callback)
        filters[event] = callback
    end,
}

addon.Window = {
    Refresh = function() end,
    RefreshCharacters = function() end,
    Receive = function() end,
    IsReading = function()
        return true
    end,
}

addon.Characters = { Update = function() end }
addon.BattleNet = { Resolve = function() end }
assert(loadfile("extensions/emoji/emotes.lua"))("Whispr", addon)
assert(loadfile("extensions/emoji/renderer.lua"))("Whispr", addon)
assert(loadfile("tests/support/emoji-filters.lua"))(addon)
load("format")
load("history")
Whispr = {
    running = true,
    db = { char = { conversations = {}, sequence = 0 }, global = { maxPeople = 5, maxMessages = 20 } },
}

addon.Minimap = { Disable = function() end }
load("sounds")
load("main")
local conversation = addon.History.Add(Whispr.db.char, Whispr.db.global, "Friend Name", "hello", false, 1)
local input = { text = "send immediately" }

function input:GetText()
    return self.text
end

function input:SetText(text)
    self.text = text
end

function input:SetFocus() end

local window = {
    active = conversation.key,
    input = input,
    drafts = {},
    IsReading = function()
        return true
    end,
}

local dispatched = false
C_ChatInfo = {
    SendChatMessage = function(text, kind, _, name)
        dispatched = true
        equal(text, "send immediately", "unmodified outgoing message")
        equal(kind, "WHISPER", "character whisper transport")
        equal(name, "Friend Name", "full recipient name")
    end,
}

Whispr:Send(window)
equal(dispatched, true, "send is immediate without a timer")
equal(#conversation.messages, 2, "pending bubble is immediate")
equal(conversation.messages[2].pending, true, "pending remains distinct from confirmed")
Whispr:Whisper("CHAT_MSG_WHISPER_INFORM", "send immediately", "Friend Name")
equal(#conversation.messages, 2, "confirmation does not duplicate history")
equal(conversation.messages[2].pending, nil, "server confirms pending bubble")
for _, callback in ipairs(timers) do
    callback()
end

equal(conversation.messages[2].unconfirmed, nil, "confirmed message never times out")
Whispr:InstallChatFilters()
equal(
    filters.CHAT_MSG_WHISPER(nil, "CHAT_MSG_WHISPER", "reply", "Friend Name"),
    true,
    "handled whispers hidden from stock chat"
)
equal(
    filters.CHAT_MSG_BN_WHISPER(nil, "CHAT_MSG_BN_WHISPER", "reply", "Unknown"),
    false,
    "unresolved Battle.net message is not hidden"
)
equal(filters.CHAT_MSG_SYSTEM, nil, "delivery errors are not filtered")
Whispr:OnDisable()
equal(
    filters.CHAT_MSG_WHISPER(nil, "CHAT_MSG_WHISPER", "reply", "Friend Name"),
    false,
    "disabled addon leaves normal chat intact"
)
local routed = false
addon.Window.Receive = function()
    routed = true
end

addon.Extensions = {
    ConversationEvent = function() end,
    Emit = function(_, event, payload)
        if event == "MESSAGE_RECEIVED" then
            assert(routed, "incoming event emitted after automatic window routing")
            routed = false
        end
    end,
}

print("Immediate sending, pending reconciliation, timeout and safe chat filtering passed.")
Whispr.running = true
Whispr.db.global.suppressWhispers = false
equal(
    filters.CHAT_MSG_WHISPER(nil, "CHAT_MSG_WHISPER", "reply", "Friend Name"),
    false,
    "normal chat suppression can be disabled"
)
local sounds = 0
PlaySoundFile = function(path, channel)
    equal(path, "Interface\\AddOns\\Whispr\\assets\\sounds\\soft-ping.ogg", "custom whisper chime")
    equal(channel, "Master", "notification channel")
    sounds = sounds + 1
end

InCombatLockdown = function()
    return true
end

Whispr.db.global.newMessageSound = false -- Old saved setting no longer silences incoming whispers.
Whispr:Whisper("CHAT_MSG_WHISPER", "combat reply", "Friend Name")
equal(sounds, 1, "incoming whisper sounds in combat")
Whispr:Whisper("CHAT_MSG_WHISPER_INFORM", "outgoing", "Friend Name")
equal(sounds, 1, "outgoing whispers do not bleep")
local selectedPath
PlaySoundFile = function(path)
    selectedPath = path
end

Whispr.db.global.notificationSound = "linux-bell"
Whispr:PlayMessageSound(true)
equal(selectedPath, addon.Sounds:Path("linux-bell"), "preview plays selected sound")
Whispr.db.global.notificationSound = "missing"
Whispr:PlayMessageSound()
equal(selectedPath, addon.Sounds:Path("linux-message"), "invalid selection falls back")

-- A retained setting from older installations cannot select removed assets.
Whispr.db.global.boostNotificationVolume = true
Whispr:PlayMessageSound(true)
equal(selectedPath, addon.Sounds:Path("linux-message"), "legacy boost preference uses original sample")

for key in pairs(addon.Sounds.labels) do
    local path = addon.Sounds:Path(key):gsub("^Interface\\AddOns\\Whispr\\", ""):gsub("\\", "/")
    assert(not path:find("linux-", 1, true), "sound assets use their picker names")
    assert(not path:find("loud/", 1, true), "all sound choices use original samples")
    local file = assert(io.open(path, "rb"), "missing notification sound: " .. path)
    file:close()
end

local rawEmojis = {}
for _, emote in ipairs(addon.EmotePicker) do
    rawEmojis[#rawEmojis + 1] = emote.text .. " "
end

local allEmojis = table.concat(rawEmojis)
local wireEmojis = allEmojis:gsub("|", "||")
local rendered = addon.Format.Input(allEmojis, true, 14)
local sent
C_ChatInfo.SendChatMessage = function(text)
    sent = text
end

for _, draft in ipairs({
    rendered,
    rendered:gsub("|cff68bfff", "|cffffffff"),
    (rendered:gsub("|cff68bfff", ""):gsub("|r", "")),
}) do
    input.text = draft
    Whispr:Send(window)
    equal(sent, wireEmojis, "all picker emojis send only original text aliases")
    equal(conversation.messages[#conversation.messages].text, wireEmojis, "history stores plain emoji text")
end

local item = "|cff0070dd|Hitem:123:0:0|h[Item Name]|h|r"
input.text = item .. " " .. rendered
Whispr:Send(window)
equal(sent, item .. " " .. wireEmojis, "valid native item link preserved alongside emoji row")

local namedItem = "|cnIQ3:|Hitem:123:0:0|h[Item Name ||h :D]|h|r"
input.text = addon.Format.Input(namedItem .. " :) ", true, 14)
Whispr:Send(window)
equal(sent, namedItem .. " :) ", "named color and escaped pipe in the link label survive sending")

for _, link in ipairs({
    "|cff71d5ff|Hspell:116|h[Frostbolt]|h|r",
    "|cff4e96f7|Htalent:123:1|h[Talent]|h|r",
}) do
    input.text = link
    Whispr:Send(window)
    equal(sent, link, "spell and talent links reach whisper transport intact")
end

local count = #conversation.messages
local notice

function Whispr:Print(text)
    notice = text
end

sent = nil
input.text = "broken |Hwhisprinput:3a29|h"
Whispr:Send(window)
equal(sent, nil, "broken composer escape never reaches chat transport")
equal(#conversation.messages, count, "invalid draft creates no pending message")
equal(input.text, "broken |Hwhisprinput:3a29|h", "invalid draft retained for editing")
assert(notice, "invalid formatting explains why draft was kept")
print("Full picker emoji row, edited color wrappers, native links and malformed send guard passed.")

equal(addon.Format.Outgoing(":| :|| :-|"), ":|| :|| :-||", "literal pipes escaped exactly once")
assert(addon.Format.Message(":||", true):find("neutral.tga", 1, true), "escaped neutral emoji renders from chat echo")

local soundCalls = 0
PlaySoundFile = function()
    soundCalls = soundCalls + 1
end

Whispr.db.global.notificationSoundEnabled = false
Whispr:PlayMessageSound()
equal(soundCalls, 0, "muted notifications make no sound")
Whispr:PlayMessageSound(true)
equal(soundCalls, 1, "manual preview still plays while muted")
Whispr.db.global.notificationSoundEnabled = true
Whispr:PlayMessageSound()
equal(soundCalls, 2, "reenabling restores message sound")
print("Notification sound mute and explicit preview behavior passed.")

addon.Window.frame = {
    IsShown = function()
        return true
    end,
}

addon.Window.IsReading = function()
    return true
end

local beforeIncoming = soundCalls
Whispr:Whisper("CHAT_MSG_WHISPER", "visible conversation", "Friend Name")
equal(soundCalls, beforeIncoming + 1, "open active conversation still plays incoming sound")
addon.Window.IsReading = function()
    return false
end

Whispr:Whisper("CHAT_MSG_WHISPER", "another conversation", "Other Friend")
equal(soundCalls, beforeIncoming + 2, "open inbox still plays sound for inactive conversation")
local refresh = addon.Window.Refresh
addon.Window.Refresh = function()
    error("simulated redraw failure")
end

local ok = pcall(Whispr.Whisper, Whispr, "CHAT_MSG_WHISPER", "render failure", "Friend Name")
assert(not ok, "test exercises the failing redraw")
equal(soundCalls, beforeIncoming + 3, "redraw failure cannot suppress incoming sound")
addon.Window.Refresh = refresh
print("Incoming sounds play with an open window and before redraw failures.")
