local addon = {}
assert(loadfile("tests/support/locale.lua"))(addon)
assert(loadfile("extensions/emoji/emotes.lua"))("Whispr", addon)
assert(loadfile("extensions/emoji/renderer.lua"))("Whispr", addon)
assert(loadfile("tests/support/emoji-filters.lua"))(addon)
for _, name in ipairs({ "format", "composer" }) do
    assert(loadfile("scripts/" .. name .. ".lua"))("Whispr", addon)
end

Whispr = { db = { global = { smileys = true, chatFontSize = 14 } } }

local function equal(a, b, label)
    assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local input = { text = "", cursor = 0, scripts = {} }

function input:GetText()
    return self.text
end

function input:GetCursorPosition()
    return self.cursor
end

function input:SetCursorPosition(pos)
    self.cursor = pos
end

function input:SetMaxBytes(n)
    self.maxBytes = n
end

function input:HookScript(event, action)
    self.scripts[event] = action
end

function input:SetText(text)
    self.text = text
    self.cursor = #text
    if self.scripts.OnTextChanged then
        self.scripts.OnTextChanged(self, false)
    end
end

function input:Insert(text)
    local first, last = self.cursor, self.cursor
    if self.selection then
        first, last = unpack(self.selection)
        self.selection = nil
    end

    self.text = self.text:sub(1, first) .. text .. self.text:sub(last + 1)
    self.cursor = first + #text
    if self.scripts.OnTextChanged then
        self.scripts.OnTextChanged(self, true)
    end
end

local nativeInsert = input.Insert
addon.Composer.Attach(input)
input:SetText("hello :) https://example.com/:D")
equal(input:GetText(), "hello :) https://example.com/:D", "display decorations never escape into sent draft")
assert(input.text:find("|T", 1, true), "smiley rendered in editbox")
assert(input.text:find("|Hwhisprinput:", 1, true), "composer links rendered")
equal(input:GetCursorPosition(), #input:GetText(), "raw caret at end")
input:SetCursorPosition(6)
input:Insert("é ")
equal(input:GetText(), "hello é :) https://example.com/:D", "UTF-8 insertion before emoji")
equal(input:GetCursorPosition(), 9, "raw caret after insertion")
input:SetText("hi :")
nativeInsert(input, ")")
equal(input:GetText(), "hi :) ", "native typing forms smiley")
assert(input.text:find("|T", 1, true), "native typing triggers rendering")
input:Insert("test")
equal(input:GetText(), "hi :) test", "appending ordinary text preserves bytes")
assert(input.text:find("|T", 1, true), "trailing space preserves emoji when typing next word")
input:SetText("https://example.com")
input:Insert("/longer")
equal(input:GetText(), "https://example.com/longer", "URL grows without losing typed suffix")
local item = "|cff00ff00|Hitem:123|h[Item :D]|h|r"
input:SetText(item .. " XD")
equal(input:GetText(), item .. " XD ", "native item link intact")
input.selection = { 0, #input.text }
input:Insert("replacement :P")
equal(input:GetText(), "replacement :P ", "selection replacement")
input:SetText(string.rep("a", 252) .. " :)")
equal(#input:GetText(), 255, "255 raw bytes accepted despite large display markup")
input:Insert("x")
equal(#input:GetText(), 255, "overflow rejected without truncating formatting")
input:SetText(":D")
addon.Filters:Remove("emoji")
input:RefreshFormatting()
equal(input.text, ":D ", "disable smileys restores editable text")
assert(loadfile("tests/support/emoji-filters.lua"))(addon)
input:RefreshFormatting()
assert(input.text:find("|T", 1, true), "enable restores smiley")
print("Live composer parsing, raw drafts, caret mapping, selections, UTF-8 and byte limits passed.")

-- Simulate native backspace: ordinary bytes delete individually, links atomically.
local function backspace()
    local cursor = input.cursor
    local _, spans = addon.Format.InputPlain(input.text)
    local start = cursor - 1
    for _, span in ipairs(spans) do
        if span.displayEnd == cursor then
            start = span.displayStart
            break
        end
    end

    input.text = input.text:sub(1, start) .. input.text:sub(cursor + 1)
    input.cursor = start
    input.scripts.OnTextChanged(input, true)
end

input:SetText("hi :)")
backspace()
equal(input:GetText(), "hi :)", "backspace removes auto-space without restoring it")
equal(input:GetCursorPosition(), 5, "caret stays after emoji when space removed")
input:RefreshFormatting()
equal(input:GetText(), "hi :)", "later formatting does not restore deleted space")
backspace()
equal(input:GetText(), "hi ", "next backspace removes emoji link")
equal(input:GetCursorPosition(), 3, "caret follows deleted emoji")
input:Insert(":D")
equal(input:GetText(), "hi :D ", "newly inserted emoji still receives space")
input:SetText(":) :D")
backspace()
backspace()
backspace()
backspace()
equal(input:GetText(), "", "consecutive emojis can be fully erased")
input:SetText("before :) after")
input:SetCursorPosition(10)
backspace()
equal(input:GetText(), "before :)after", "middle space can be deleted")
backspace()
equal(input:GetText(), "before :after", "joined token returns to plain text and remains deletable")
backspace()
equal(input:GetText(), "before after", "middle emoji can be deleted without losing suffix")
print("Backspace removes emoji spacing and links without reinserting deleted text.")

for _, wrapper in ipairs({ "|cffffffff", "|cnPURE_GREEN_COLOR:", "" }) do
    input.text = wrapper .. "|Hwhisprinput:3a29|h|Temoji:18|t|h" .. (wrapper ~= "" and "|r" or "") .. " "
    input.cursor = #input.text
    equal(input:GetText(), ":) ", "edited display wrapper still decodes emoji")
    equal(input:GetCursorPosition(), 3, "edited wrapper preserves raw caret")
    input:RefreshFormatting()
    equal(input:GetText(), ":) ", "formatting repairs edited wrapper")
end

print("Emoji decoding and caret mapping tolerate edited display color wrappers.")

local edits = 0
input.onDraftEdited = function()
    edits = edits + 1
end

input:SetText("restored draft")
input:RefreshFormatting()
equal(edits, 0, "restoring and formatting drafts never announces typing")
nativeInsert(input, "!")
equal(edits, 1, "native typing announces one edit")
input:Insert(" :) ")
equal(edits, 2, "picker insertion announces one edit despite formatting callbacks")
input:RefreshFormatting()
equal(edits, 2, "unchanged formatting does not repeat typing notification")
