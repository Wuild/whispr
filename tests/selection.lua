local addon = {}
assert(loadfile("tests/support/locale.lua"))(addon)
assert(loadfile("extensions/emoji/emotes.lua"))("Whispr", addon)
assert(loadfile("extensions/emoji/renderer.lua"))("Whispr", addon)
assert(loadfile("tests/support/emoji-filters.lua"))(addon)
assert(loadfile("scripts/format.lua"))("Whispr", addon)
assert(loadfile("scripts/selection.lua"))("Whispr", addon)
local Selection = addon.Selection

local function equal(a, b, label)
    assert(a == b, (label or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local queue = {}
C_Timer = {
    After = function(_, callback)
        queue[#queue + 1] = callback
    end,
}

local function flush()
    for _, f in ipairs(queue) do
        f()
    end

    queue = {}
end

local function frame()
    local f = { scripts = {}, text = "", shown = true }

    function f:SetScript(event, callback)
        self.scripts[event] = callback
    end

    function f:HookScript(event, callback)
        self:SetScript(event, callback)
    end

    function f:SetSize(w, h)
        self.width, self.height = w, h
    end

    function f:SetPoint(...)
        self.point = { ... }
    end

    function f:SetAlpha(a)
        self.alpha = a
    end

    function f:EnableMouse(value)
        self.mouse = value
    end

    function f:SetAutoFocus(value)
        self.autoFocus = value
    end

    function f:SetFontObject() end

    function f:RegisterEvent() end

    function f:SetColorTexture(...)
        self.color = { ... }
    end

    function f:ClearAllPoints() end

    function f:CreateTexture()
        return frame()
    end

    function f:GetEffectiveScale()
        return 2
    end

    function f:GetText()
        return self.text
    end

    function f:SetText(text)
        self.text = text
        if self.scripts.OnTextChanged then
            self.scripts.OnTextChanged(self)
        end
    end

    function f:SetFocus()
        self.focus = true
    end

    function f:ClearFocus()
        local was = self.focus
        self.focus = false
        if was and self.scripts.OnEditFocusLost then
            self.scripts.OnEditFocusLost(self)
        end
    end

    function f:HasFocus()
        return self.focus
    end

    function f:HighlightText()
        self.highlighted = true
    end

    function f:Show()
        self.shown = true
    end

    function f:Hide()
        self.shown = false
    end

    return f
end

CreateFrame = function(kind)
    equal(kind, "EditBox", "only clipboard bridge uses editor")
    return frame()
end

GameFontHighlight = {}
UIParent = frame()
local x, y, index, inside, down = 40, 80, 1, true, true
GetCursorPosition = function()
    return x, y
end

IsMouseButtonDown = function()
    return down
end

local window = { frame = frame(), input = frame() }
window.input:SetFocus()
local bubble = frame()
bubble.text = frame()
local message = "hello world"
bubble.text:SetText(message)

function bubble.text:FindCharacterIndexAtCoordinate(px, py)
    equal(px, 20, "scaled pointer x")
    equal(py, 40, "scaled pointer y")
    return index, inside
end

function bubble.text:CalculateScreenAreaFromCharacterSpan(first, last)
    equal(first, 1, "span starts at first byte")
    equal(last, 6, "exclusive end boundary")
    return { { left = 0, bottom = 16, width = 24, height = 14 }, { left = 0, bottom = 0, width = 10, height = 14 } }
end

Selection.Attach(window, bubble)
Selection.Update(window, bubble, message, 100, 1)
bubble.messageID = 1
bubble.scripts.OnMouseDown(bubble, "LeftButton")
equal(window.input:HasFocus(), false, "selection releases composer")
index = 6
bubble.scripts.OnUpdate()
equal(window.messageSelection.selected, "hello", "selected visible text")
equal(#bubble.selectionHighlights, 2, "wrapped span draws both rectangles")
bubble.scripts.OnMouseUp(bubble, "LeftButton")
equal(window.copyBridge:GetText(), "hello", "clipboard contains selection only")
equal(window.copyBridge.alpha, 0, "clipboard has no visible text or caret")
equal(window.copyBridge.point[2], UIParent, "clipboard anchored to the screen")
equal(window.copyBridge.point[3], "BOTTOMLEFT", "clipboard sits outside the screen")
equal(window.copyBridge.point[4], -100, "clipboard caret kept off-screen horizontally")
equal(window.copyBridge.point[5], -100, "clipboard caret kept off-screen vertically")
equal(window.copyBridge.mouse, false, "clipboard cannot intercept clicks")
window.copyBridge:SetText("typing or paste")
equal(window.copyBridge:GetText(), "hello", "clipboard remains selected text")
equal(bubble.text:GetText(), message, "typing never changes visible message")
Selection.Update(window, bubble, message, 100, 1)
assert(window.messageSelection, "unchanged render preserves selection")
Selection.Update(window, bubble, message, 80, 1)
equal(window.messageSelection, nil, "resize clears stale highlight geometry")
equal(bubble.selectionHighlights[1].shown, false, "highlights clear")
equal(window.copyBridge:HasFocus(), false, "clipboard releases keyboard")
flush()
index = 6
Selection.Update(window, bubble, message, 80, 1)
bubble.scripts.OnMouseDown(bubble, "LeftButton")
index = 1
bubble.scripts.OnUpdate()
equal(window.messageSelection.selected, "hello", "reverse drag copies same range")
bubble.scripts.OnMouseUp(bubble, "LeftButton")
window.copyBridge.scripts.OnEscapePressed()
equal(window.messageSelection, nil, "Escape clears selection")
index = 1
bubble.scripts.OnMouseDown(bubble, "LeftButton")
bubble.scripts.OnMouseUp(bubble, "LeftButton")
equal(window.messageSelection, nil, "simple click does not take copy focus")
equal(Selection.CopyText("é漢字", 1, 5), "é漢", "UTF-8 byte spans remain intact")
local link = "|cffabcdef|Hitem:123|h[Sword]|h|r"
equal(Selection.CopyText(link, 1, #link), "[Sword]", "copies item label without markup")
local namedLink = "|cnIQ3:|Hitem:123|h[Sword ||h]|h|r"
equal(Selection.CopyText(namedLink, 1, #namedLink), "[Sword |h]", "copies named color links without markup")
local a = assert(link:find("Sword", 1, true))
equal(Selection.CopyText(link, a, a + 2), "Swo", "partial hyperlink label")
local smile = "|TInterface\\AddOns\\Whispr\\assets\\emotes\\happy.tga:18|t"
equal(Selection.CopyText(smile, 1, #smile), ":)", "smiley selection copies a text face")
equal(Selection.CopyText("a||b\nc", 1, 6), "a|b\nc", "pipes and line breaks survive")
print("Read-only drag selection, wrapping, reverse selection, UTF-8, link labels and hidden clipboard passed.")

index = 1
Selection.Update(window, bubble, message, 80, 1, "position-a")
bubble.scripts.OnMouseDown(bubble, "LeftButton")
index = 6
bubble.scripts.OnUpdate()
assert(window.messageSelection, "selection exists before geometry change")
Selection.Update(window, bubble, message, 80, 1, "position-b")
assert(not window.messageSelection, "group and layout changes clear stale selection rectangles")

local nativeHit = bubble.text.FindCharacterIndexAtCoordinate
local nativeSpan = bubble.text.CalculateScreenAreaFromCharacterSpan

local function unsafeNativeCall()
    error("inline textures must never reach native selection APIs")
end

-- Deterministic font metrics: glyphs 5px, images 16px, lines 16px + 2px spacing.
local function visible(text)
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
end

local function metrics(f)
    function f:GetFont()
        return "font", 12, ""
    end

    function f:GetSpacing()
        return 2
    end

    function f:GetStringWidth()
        local text, textures = visible(self.text):gsub("|T.-|t", "")
        local atlases
        text, atlases = text:gsub("|A.-|a", "")
        local _, glyphs = text:gsub("[%z\1-\127\194-\244][\128-\191]*", "")
        return glyphs * 5 + (textures + atlases) * 16
    end

    function f:GetStringHeight()
        local _, lines = self.text:gsub("\n", "")
        return 16 + lines * 18
    end

    function f:GetHeight()
        return self.height or self:GetStringHeight()
    end

    function f:GetLeft()
        return 0
    end

    function f:GetTop()
        return 100
    end

    function f:SetFont() end

    function f:SetSpacing() end

    function f:SetWordWrap(enabled)
        self.wordWrap = enabled
    end

    function f:SetWidth() end

    function f:SetHeight(height)
        self.height = height > 0 and height or nil
    end

    return f
end

function bubble:CreateFontString()
    return metrics(frame())
end

metrics(bubble.text)
bubble.text:SetWordWrap(true)
bubble.text.FindCharacterIndexAtCoordinate = unsafeNativeCall
bubble.text.CalculateScreenAreaFromCharacterSpan = unsafeNativeCall
for _, rendered in ipairs({ smile, "hello " .. smile .. " world", "hello |A:some-atlas:16:16|a world" }) do
    bubble.text:SetText(rendered)
    Selection.Prepare(bubble, rendered, 80)
    Selection.Update(window, bubble, rendered, 80, 2)
    x, y = 0, 190 -- scale 2: beginning of the first line
    bubble.scripts.OnMouseDown(bubble, "LeftButton")
    assert(window.messageSelection, "texture messages start selection")
    x, y = 160, 0 -- below the last line
    bubble.scripts.OnUpdate()
    equal(window.messageSelection.selected, Selection.CopyText(rendered, 1, #rendered), "drag copies texture message")
    assert(bubble.selectionHighlights[1].shown, "texture drag has visible highlight")
    bubble.scripts.OnMouseUp(bubble, "LeftButton")
    equal(window.copyBridge:GetText(), Selection.CopyText(rendered, 1, #rendered), "texture message clipboard")
    Selection.Clear(window)
end

local wrapped = "hello " .. smile .. " |cnIQ3:world|r"
local originalGetStringHeight = bubble.text.GetStringHeight
bubble.text.GetStringHeight = function()
    return 16
end

Selection.Prepare(bubble, wrapped, 50)
Selection.Update(window, bubble, wrapped, 50, 2)
equal(#bubble.selectionLayout.lines, 2, "native-width wrapping keeps words together")
equal(bubble.text:GetText(), "hello " .. smile .. "\n|cnIQ3:world|r", "named color takes no space when wrapping")
equal(bubble.text:GetHeight(), 34, "emoji message gets room for both lines when its reported text height is clipped")
bubble.text.GetStringHeight = originalGetStringHeight
-- Select only the emoji, forward and backward, using its measured rectangle.
for _, direction in ipairs({ 1, -1 }) do
    x, y = (direction == 1 and 30 or 46) * 2, 190
    bubble.scripts.OnMouseDown(bubble, "LeftButton")
    x = (direction == 1 and 46 or 30) * 2
    bubble.scripts.OnUpdate()
    equal(window.messageSelection.selected, ":)", "emoji-only selection in both directions")
    equal(bubble.selectionHighlights[1].width, 16, "highlight matches texture width")
    Selection.Clear(window)
end

Selection.Prepare(bubble, wrapped, 30)
equal(#bubble.selectionLayout.lines, 3, "resize recalculates texture layout")
assert(bubble.text.wordWrap, "resizing keeps multiline rendering enabled for texture text")
local utf = "é " .. smile .. " 漢"
Selection.Prepare(bubble, utf, 100)
Selection.Update(window, bubble, utf, 100, 4)
x, y = 0, 190
bubble.scripts.OnMouseDown(bubble, "LeftButton")
x = 200
bubble.scripts.OnUpdate()
equal(window.messageSelection.selected, "é :) 漢", "UTF-8 and emoji copy together")
Selection.Clear(window)

bubble.text.FindCharacterIndexAtCoordinate = nativeHit
bubble.text.CalculateScreenAreaFromCharacterSpan = nativeSpan
bubble.text:SetText(message)
Selection.Prepare(bubble, message, 80)
equal(bubble.selectionLayout, nil, "pooled plain-text frame drops texture layout")
Selection.Update(window, bubble, message, 80, 3)
x, y, index = 40, 80, 1
bubble.scripts.OnMouseDown(bubble, "LeftButton")
index = 6
bubble.scripts.OnUpdate()
equal(window.messageSelection.selected, "hello", "reused frame still selects plain text")
Selection.Clear(window)
print("Texture selection, reverse emoji spans, UTF-8, wrapping, resizing and frame reuse passed.")
