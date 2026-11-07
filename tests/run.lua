SOUNDKIT = { TELL_MESSAGE = 1 }
PlaySoundFile = function() end
local addon = {}
assert(loadfile("tests/support/locale.lua"))(addon)

local function load(name)
    assert(loadfile("scripts/" .. name .. ".lua"))("Whispr", addon)
end

local function equal(actual, expected, label)
    assert(
        actual == expected,
        (label or "mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
    )
end

load("history")
assert(loadfile("extensions/emoji/emotes.lua"))("Whispr", addon)
assert(loadfile("extensions/emoji/renderer.lua"))("Whispr", addon)
assert(loadfile("tests/support/emoji-filters.lua"))(addon)
load("format")
local History, Format = addon.History, addon.Format
local data = { conversations = {}, sequence = 0 }
local settings = { maxPeople = 2, maxMessages = 2 }
History.Add(data, settings, "First Last", "one", false, 1)
History.Add(data, settings, "Other Person", "two", false, 1)
History.Add(data, settings, "FIRST LAST", "three", true, 1)
equal(#History.Sorted(data), 2, "case insensitive identity")
equal(History.Sorted(data)[1].key, "first last", "sequence resolves same-second ordering")
History.Add(data, settings, "First Last", "four", false, 2)
equal(#data.conversations["first last"].messages, 2, "message cap")
equal(data.conversations["first last"].messages[1].text, "three", "oldest message evicted")
History.Add(data, settings, "Third Person", "five", false, 3)
equal(data.conversations["other person"], nil, "least recently used person evicted")
History.Add(data, settings, "Third Person", "six", false, 3, true)
equal(data.conversations["third person"].unread, 0, "visible bottom marks read")
settings.maxPeople, settings.maxMessages = 1, 1
History.Trim(data, settings)
equal(#History.Sorted(data), 1, "settings trim people immediately")
equal(#History.Sorted(data)[1].messages, 1, "settings trim messages immediately")
local link = "|cff0070dd|Hitem:123:0:0|h[Some :D https://example.com item]|h|r"
equal(Format.Message(link, true), link, "native item links untouched")

do
    local bare = "|Hitem:123:0:0|h[Some :D https://example.com item]|h"
    local quality, queried
    C_Item = {
        GetItemInfo = function(itemLink)
            queried = itemLink
            return "Some item", nil, quality
        end,
    }

    ITEM_QUALITY_COLORS = { [3] = { hex = "|cff0070dd" } }
    equal(Format.Message(bare, true), bare, "uncached links stay clickable")
    equal(queried, bare, "item lookup receives the complete link")
    assert(Format.pendingItemColors[123], "waits for the item's data")

    quality = 3
    equal(Format.Message("Use " .. bare .. " here", true), "Use " .. link .. " here", "fills in missing rarity color")
    equal(Format.Input(bare, true, 14), bare, "draft keeps the original item link")
    local named = "|cnIQ2:" .. bare .. "|r"
    equal(Format.Message(named, true), named, "existing named rarity color is preserved")
    C_Item, ITEM_QUALITY_COLORS = nil, nil
end

assert(Format.Message(":D =D :P ;)", true):find("excited.tga", 1, true))
equal(Format.Message(":D =D :P", false), ":D =D :P", "disabled smileys")
assert(
    Format.Message(":D", true, 14):find(":16:16:0:-2:32:32:4:28:4:28|t", 1, true),
    "smileys align to the text baseline"
)
assert(
    Format.Message("<3", true, 28):find(":30:30:0:-4:32:32:4:28:4:28|t", 1, true),
    "larger fonts do not introduce a vertical shift"
)
assert(
    Format.Message(":)", true, 10):find(":12:12:0:-1:32:32:4:28:4:28|t", 1, true),
    "small chat fonts keep proportional smileys"
)
local url = "https://example.com/path?q=:D&x=1"
local rendered = Format.Message(url .. ".", true)
local payload = rendered:match("|Hwhisprurl:(.-)|h")
equal(Format.Decode(payload), url, "URL round trip and punctuation")
equal(Format.Decode("xyz"), nil, "malformed URL payload")
equal(Format.Preview(link), "[Some :D https://example.com item]", "plain preview")
equal(Format.Message("|Tsome-texture:16|t :D", true):sub(1, 22), "|Tsome-texture:16|t |T", "texture preserved")

-- Exercise the native whisper handoff with a delayed client parser and secret
-- values, rather than sending messages from the slash-command hook itself.
local queue, opened = {}, {}
C_Timer = {
    After = function(_, callback)
        queue[#queue + 1] = callback
    end,
}

local function flush()
    local pending = queue
    queue = {}
    for _, callback in ipairs(pending) do
        callback()
    end
end

Whispr = {}
addon.Window = {
    Open = function(_, ...)
        opened[#opened + 1] = { ... }
    end,
}

HasAnySecretValues = function(...)
    for i = 1, select("#", ...) do
        if select(i, ...) == "SECRET" then
            return true
        end
    end
end

ChatFrameUtil = {
    DeactivateChat = function(box)
        box.hidden = true
    end,
}

load("sounds")
load("main")
local box = { attributes = { chatType = "WHISPER", tellTarget = "First Last" }, text = "/w First Last" }

function box:GetAttribute(key)
    return self.attributes[key]
end

function box:SetAttribute(key, value)
    self.attributes[key] = value
end

function box:GetText()
    return self.text
end

function box:SetText(text)
    self.text = text
end

function box:UpdateHeader()
    Whispr:RouteEditBox(self)
end

Whispr:RouteEditBox(box)
Whispr:RouteEditBox(box)
box.text = "a preserved draft"
flush()
equal(#opened, 1, "one handoff despite multiple header updates")
equal(opened[1][1], "First Last", "full name retained")
equal(opened[1][2], "a preserved draft", "post-parser draft transferred")
equal(box.hidden, true, "native composer deactivated")
equal(box.attributes.chatType, "SAY", "native whisper mode reset")
box.attributes.chatType, box.attributes.tellTarget = "WHISPER", "SECRET"
Whispr:RouteEditBox(box)
flush()
equal(#opened, 1, "secret targets ignored")
box.attributes.tellTarget = "Someone Else"
Whispr:RouteEditBox(box)
box.attributes.chatType = "PARTY"
flush()
equal(#opened, 1, "changed chat mode is not intercepted")
print("History, formatting, and native whisper routing checks passed.")
equal(
    Format.Message("inv invite", true, 14, "first last"),
    "inv invite",
    "keyword parsing belongs to optional extension"
)
local hooks = {}
hooksecurefunc = function(owner, name, callback)
    if type(owner) == "string" then
        hooks[owner] = name
    else
        hooks[name] = callback
    end
end

ChatFrameUtil.ReplyTell = function() end
ChatFrameUtil.ReplyTell2 = function() end
Whispr.db = { char = { conversations = { ["first last"] = {}, ["other person"] = {}, ["bnet:test#1234"] = {} } } }
Whispr.lastWhisper = "first last"
Whispr.lastToldWhisper = "other person"
Whispr:HookWhispers()
local beforeReply = #opened
hooks.ReplyTell("reply draft")
equal(#opened, beforeReply, "reply does not focus during shortcut character event")
flush()
equal(opened[#opened][1], "first last", "reply opens filtered incoming target")
equal(opened[#opened][2], "reply draft", "reply preserves supplied draft")
hooks.ReplyTell2()
flush()
equal(opened[#opened][1], "other person", "reply-to-last-sent uses outgoing target")
Whispr.lastWhisper = "bnet:test#1234"
hooks.ReplyTell()
flush()
equal(opened[#opened][1], "bnet:test#1234", "reply uses stable Battle.net identity")

hooks.ReplyTell("R is real draft text")
flush()
equal(opened[#opened][2], "R is real draft text", "reply never removes legitimate R from drafts")
local beforeRapid = #opened
hooks.ReplyTell()
hooks.ReplyTell2()
flush()
equal(#opened, beforeRapid + 1, "latest pending reply wins")
equal(opened[#opened][1], "other person", "rapid reply shortcuts retain latest target")

-- Classic text faces: all aliases resolve to a bundled texture, including pipes.
for alias, asset in pairs(addon.Emotes) do
    local rendered = Format.Message(alias, true, 14)
    assert(rendered:find("emotes\\" .. asset .. ".tga:", 1, true), "missing smiley: " .. alias)
    local file = assert(io.open("assets/emotes/" .. asset .. ".tga", "rb"))
    file:close()
    equal(Format.Message(alias, false), alias, "disabled alias " .. alias)
end

for _, text in ipairs({ ":coffee:", ":party:", ":smile:", "😀", "word:D", "XDword", "C:/folder", "abc|def" }) do
    equal(Format.Message(text, true), text, "non-smiley text preserved")
end

assert(Format.Message(":):P", true):find("happy.tga", 1, true))
assert(Format.Message(":):P", true):find("tongue.tga", 1, true))
assert(Format.Message(":'(!", true):match("|t!$"), "punctuation preserved")
equal(Format.Message("|Hitem:1|h[:| :D]|h", true), "|Hitem:1|h[:| :D]|h", "native label preserved")
local colored = Format.Message("|cffffffff:| |r", true)
assert(colored:find("neutral.tga", 1, true), "neutral face before color reset")
print("Classic smiley pack checks passed.")
