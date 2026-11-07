local addon = {}
assert(loadfile("tests/support/locale.lua"))(addon)

local function load(name)
    assert(loadfile("scripts/" .. name .. ".lua"))("Whispr", addon)
end

Whispr = { db = { global = { extensions = {} } } }
GetNormalizedRealmName = function()
    return "Home"
end

RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
local chats = {
    bob = { name = "Bob", character = { classFile = "WARRIOR" } },
    full = {
        name = "First Last",
        character = { classFile = "MAGE" },
    },
}

addon.History = {
    Key = function(name)
        return name:lower()
    end,

    DisplayData = function()
        return { conversations = chats }
    end,
}

load("characters")
load("format")
load("extensions")
addon.Characters.sources = { alice = { classFile = "MAGE" } }
assert(loadfile("extensions/character-names/module.lua"))("Whispr", addon)
assert(loadfile("extensions/keywords/module.lua"))("Whispr", addon)
addon.Extensions:Start()
local names = addon.CharacterNames
assert(names:IsEnabled(), "independent name extension enabled")

local function render(text)
    return addon.Format.Message(text, true, 14)
end

local function coloredName(name, color, target)
    return "|cff" .. color .. "|Hwhisprname:" .. addon.Format.Encode(target or name) .. "|h" .. name .. "|h|r"
end

assert(
    render("Ask Alice, BOB and First Last.")
        == "Ask "
            .. coloredName("Alice", "40c7eb")
            .. ", "
            .. coloredName("BOB", "c79c6e")
            .. " and "
            .. coloredName("First Last", "40c7eb")
            .. ".",
    "known names use class colors, preserve case, and link to the character"
)
for _, text in ipairs({
    "Alicea",
    "xAlice",
    "Alice-Unknown",
    "unknown",
    "|Hplayer:Alice|h[Alice]|h",
    "https://site/Alice",
    "|TAlice:12|t",
}) do
    assert(render(text) == text or text:find("https://", 1, true), "partial and protected names unchanged: " .. text)
end

local url = render("https://site/Alice")
assert(not url:find("|cff40c7eb", 1, true), "URL display not recolored")
local raw = "Ask Alice and Bob about First Last!"
local draft = addon.Format.Input(raw, true, 14)
assert(draft:find("|cff40c7ebAlice", 1, true), "composer class colors displayed")
assert(addon.Format.InputPlain(draft) == raw, "composer decorations unwrap exactly")
assert(addon.Format.Outgoing(draft) == raw, "sent text contains no generated colors or local links")
local _, spans = addon.Format.InputPlain(draft)
assert(#spans == 3, "each name has one atomic input span including multiword names")
for _, span in ipairs(spans) do
    assert(addon.Format.InputCursor(span.rawEnd, spans, true) == span.displayEnd, "raw cursor maps past colored name")
end

local options = names.options
options.set({ "drafts" }, false)
assert(addon.Format.Input(raw, true, 14) == raw, "draft colors independently disabled")
assert(render("Alice") ~= "Alice", "message colors stay enabled")
options.set({ "drafts" }, true)
addon.Characters.sources["alice-away"] = { classFile = "WARRIOR" }
addon.Characters.revision = 1
assert(render("Alice") == "Alice", "ambiguous realm-less names not guessed")
assert(render("Alice-Away") == coloredName("Alice-Away", "c79c6e"), "foreign realm is kept in the link")
assert(
    render("Alice-Home") == coloredName("Alice-Home", "40c7eb", "alice"),
    "local realm name resolves the local character"
)
addon.Characters.sources.alice = { classFile = "WARRIOR" }
addon.Characters.sources["alice-away"] = nil
addon.Characters.revision = 2
assert(render("Alice-Home") == coloredName("Alice-Home", "c79c6e", "alice"), "roster revision refreshes cached class")
assert(render("Alice-Away") == coloredName("Alice-Away", "c79c6e"), "learned name retained after leaving roster")
assert(render("Alice") == "Alice", "cached foreign identity keeps short name ambiguous")
addon.Extensions:SetEnabled("character_names", false)
assert(
    render("Bob") == "Bob" and addon.Format.Input(raw, true, 14) == raw,
    "disable removes display and composer filters"
)
addon.Extensions:SetEnabled("character_names", true)
assert(render("Bob") == coloredName("Bob", "c79c6e"), "reenable restores coloring")
addon.Characters.sources.inv = { classFile = "MAGE" }
addon.Characters.revision = 3
local combined = addon.Format.Message("Alice-Home inv", true, 14, "sender")
assert(combined:find(coloredName("Alice-Home", "c79c6e", "alice"), 1, true), "names colored alongside keyword actions")
assert(
    combined:find("|cffffff00|Hwhisprkeyword:", 1, true) and combined:find("|h[inv]|h|r", 1, true),
    "keyword action retains yellow bracket styling"
)
assert(not combined:find("|cff40c7ebinv", 1, true), "name matching does not recolor keyword label")
for index = 1, 1100 do
    addon.Characters.sources["known" .. index] = { classFile = "MAGE" }
end

addon.Characters.revision = 4
render("Bob")
local count = 0
for _ in pairs(names.known) do
    count = count + 1
end

assert(count == 1000, "session name cache bounded")

local current, alt = { conversations = {} }, { conversations = {} }
Whispr.db.char = alt
Whispr.db.sv = { char = { current = current, alt = alt } }
addon.Client = { hasLastNames = true }
UnitExists = function(unit)
    return unit == "player"
end

UnitIsPlayer = function()
    return true
end

UnitNameUnmodified = function()
    return "My", "Alt"
end

UnitGUID = function()
    return "Player-1-alt"
end

UnitClass = function()
    return "Mage", "MAGE"
end

UnitRace = function()
    return "Human"
end

addon.Characters.RefreshSources(alt)
assert(render("My Alt") == coloredName("My Alt", "40c7eb"), "logged-in character gets class colors")

Whispr.db.char = current
UnitNameUnmodified = function()
    return "My", "Main"
end

UnitClass = function()
    return "Warrior", "WARRIOR"
end

names.known = nil -- A login starts without the previous character's session cache.
addon.Characters.RefreshSources(current)
assert(
    render("My Main and My Alt") == coloredName("My Main", "c79c6e") .. " and " .. coloredName("My Alt", "40c7eb"),
    "owned characters are highlighted after switching even without account history or roster entries"
)
local ownDraft = addon.Format.Input("My Alt", true, 14)
assert(ownDraft:find("|cff40c7ebMy Alt|r", 1, true), "offline own characters are highlighted in drafts")
assert(addon.Format.Outgoing(ownDraft) == "My Alt", "own name highlighting leaves sent text unchanged")
print("Class name colors, boundaries, realms, cache refresh, composer round-trip and lifecycle passed.")
