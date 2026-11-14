-- An invalid event aborts AceAddon OnEnable before whisper hooks are installed.
local addon = { Window = {}, Minimap = { Enable = function() end } }
assert(loadfile("tests/support/locale.lua"))(addon)
assert(loadfile("scripts/history.lua"))("Whispr", addon)
assert(loadfile("scripts/format.lua"))("Whispr", addon)
Whispr = {
    db = {
        char = {
            conversations = {
                empty = { messages = {} },
                sent = { messages = { { text = "hello", outgoing = true } } },
                received = { messages = { { text = "hi" } } },
            },
        },
    },
}

assert(loadfile("scripts/main.lua"))("Whispr", addon)
local supported = {
    PLAYER_LOGOUT = true,
    PLAYER_REGEN_DISABLED = true,
    PLAYER_REGEN_ENABLED = true,
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
    CHAT_MSG_AFK = true,
    CHAT_MSG_DND = true,
    GET_ITEM_INFO_RECEIVED = true,
    PLAYER_ENTERING_WORLD = true,
    PLAYER_TARGET_CHANGED = true,
    GROUP_ROSTER_UPDATE = true,
    FRIENDLIST_UPDATE = true,
    GUILD_ROSTER_UPDATE = true,
    PLAYER_FOCUS_CHANGED = true,
    UNIT_LEVEL = true,
    UNIT_NAME_UPDATE = true,
}

local registered, refreshed, hooked = {}, false, false

function Whispr:RegisterEvent(event, handler)
    assert(supported[event], "Unsupported startup event: " .. event)
    registered[event] = handler
end

function Whispr:InstallChatFilters() end

function Whispr:RefreshCharacters()
    refreshed = true
end

function Whispr:HookWhispers()
    hooked = true
end

Whispr:OnEnable()
assert(Whispr.running and refreshed and hooked, "startup must reach metadata refresh and whisper hooks")
assert(registered.GUILD_ROSTER_UPDATE, "guild metadata still refreshes on roster changes")

for _, event in ipairs({ "UNIT_NAME_UPDATE", "UNIT_LEVEL" }) do
    refreshed = false
    registered[event](event, "mouseover")
    registered[event](event, "nameplate1")
    assert(not refreshed, "hover and nameplate metadata cannot schedule a full roster refresh")
    registered[event](event, "party1")
    assert(refreshed, "party metadata still schedules a roster refresh")
end

print("Startup event validation and whisper hook installation passed.")

local geometrySaved = false
addon.Window.SaveAllGeometry = function()
    assert(Whispr.db.char.conversations.empty, "empty chats remain until persistence cleanup")
    geometrySaved = true
end

registered.PLAYER_LOGOUT()
assert(geometrySaved, "window geometry saved before history cleanup")
assert(not Whispr.db.char.conversations.empty, "empty chats discarded on reload/logout")
assert(Whispr.db.char.conversations.sent and Whispr.db.char.conversations.received, "both message directions persist")
print("Reload/logout retains message history and discards empty conversations.")

local restored = false
addon.Window.RestoreUndocked = function()
    restored = true
end

registered.PLAYER_ENTERING_WORLD()
assert(restored, "world entry restores saved undocked state")

local itemRefreshes = 0

local function refreshMessages()
    itemRefreshes = itemRefreshes + 1
end

addon.Window.frame = {
    IsShown = function()
        return true
    end,
}

addon.Window.RefreshMessages = refreshMessages
addon.Window.popouts = { { frame = addon.Window.frame, RefreshMessages = refreshMessages } }
addon.Format.pendingItemColors[123] = true
registered.GET_ITEM_INFO_RECEIVED("GET_ITEM_INFO_RECEIVED", 456, true)
assert(itemRefreshes == 0, "unrelated item loads do not refresh Whispr")
registered.GET_ITEM_INFO_RECEIVED("GET_ITEM_INFO_RECEIVED", 123, true)
assert(itemRefreshes == 2 and not addon.Format.pendingItemColors[123], "ready item refreshes the inbox and popouts")
