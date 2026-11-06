local _, addon = ...
local Selection = {}
addon.Selection = Selection

local function textureText(texture)
    local asset = texture:match("emotes\\([^\\:]+)%.tga")
    for _, entry in ipairs(addon.EmotePicker or {}) do
        if entry.asset == asset then
            return entry.text
        end
    end

    local marker = texture:match("UI%-RaidTargetingIcon_(%d+)")
    return marker and ("{rt" .. marker .. "}") or "[image]"
end

-- Native hit tests return byte positions in the rendered string. Strip markup
-- after slicing visible spans, so a partial item label never copies a link payload.
function Selection.CopyText(text, first, last)
    local result, cursor = {}, 1
    while cursor <= #text do
        local tail = text:sub(cursor)
        local hidden = tail:match("^|c%x%x%x%x%x%x%x%x")
            or tail:match("^|r")
            or tail:match("^|H.-|h")
            or tail:match("^|h")
        local texture = tail:match("^|T.-|t") or tail:match("^|A.-|a")
        local literal = tail:match("^||")
        local token = hidden or texture or literal or tail:match("^[%z\1-\127\194-\244][\128-\191]*") or tail:sub(1, 1)
        local stop = cursor + #token - 1
        if not hidden and stop >= first and cursor <= last then
            if texture then
                result[#result + 1] = textureText(texture)
            else
                result[#result + 1] = literal and "|" or token
            end
        end

        cursor = stop + 1
    end

    return table.concat(result)
end

function Selection.Clear(window)
    local state = window.messageSelection
    if not state then
        return
    end

    window.messageSelection = nil
    state.bubble.selectionDragging = nil
    for _, texture in ipairs(state.bubble.selectionHighlights or {}) do
        texture:Hide()
    end

    if window.copyBridge then
        window.copyBridge:ClearFocus()
    end
end

-- Use explicit breaks for inline images and when native wrapping clips text.
-- The same breaks drive the visible text and the selection rectangles.
function Selection.Prepare(bubble, rendered, width, naturalWidth)
    local font = bubble.text
    local fontPath, fontSize, fontFlags = font:GetFont()
    local unwrapped = naturalWidth and naturalWidth > width and font:GetHeight() < fontSize * 2
    if not rendered:find("|[TA]") and not unwrapped and not (font.IsTruncated and font:IsTruncated()) then
        bubble.selectionLayout = nil
        return
    end

    local spacing = font:GetSpacing()
    local cached = bubble.selectionLayout
    if
        cached
        and cached.source == rendered
        and cached.width == width
        and cached.fontPath == fontPath
        and cached.fontSize == fontSize
        and cached.fontFlags == fontFlags
        and cached.spacing == spacing
    then
        font:SetHeight(math.ceil(cached.height))
        font:SetText(cached.rendered)
        return
    end

    local probe = bubble.selectionMeasure
    if not probe then
        probe = bubble:CreateFontString(nil, "ARTWORK")
        probe:Hide()
        probe:SetWordWrap(false)
        bubble.selectionMeasure = probe
    end

    probe:SetFont(fontPath, fontSize, fontFlags)
    probe:SetSpacing(spacing)
    probe:SetWidth(0)
    probe:SetHeight(0)

    local function measure(text)
        probe:SetText(text)
        return probe.GetUnboundedStringWidth and probe:GetUnboundedStringWidth() or probe:GetStringWidth()
    end

    local tokens, cursor, prefix = {}, 1, ""
    while cursor <= #rendered do
        local tail = rendered:sub(cursor)
        local hidden = tail:match("^|c%x%x%x%x%x%x%x%x")
            or tail:match("^|r")
            or tail:match("^|H.-|h")
            or tail:match("^|h")
        local token = hidden
            or tail:match("^|T.-|t")
            or tail:match("^|A.-|a")
            or tail:match("^||")
            or tail:match("^[%z\1-\127\194-\244][\128-\191]*")
            or tail:sub(1, 1)
        if hidden then
            prefix = prefix .. hidden
        else
            tokens[#tokens + 1] = {
                raw = prefix .. token,
                metric = token,
                prefix = prefix,
                first = cursor,
                last = cursor + #token,
                space = token == " " or token == "\t",
                newline = token == "\n",
            }

            prefix = ""
        end

        cursor = cursor + #token
    end

    local lines, line = {}, { raw = "", metric = "", tokens = {}, first = 1 }

    local function flush(nextIndex)
        lines[#lines + 1] = line
        line = { raw = "", metric = "", tokens = {}, first = nextIndex or #rendered + 1 }
    end

    for index, token in ipairs(tokens) do
        if token.newline then
            line.raw = line.raw .. token.prefix
            flush(token.last)
        else
            -- Move whole words, then split only words wider than the bubble.
            if not token.space and (index == 1 or tokens[index - 1].space or tokens[index - 1].newline) then
                local word = ""
                for nextIndex = index, #tokens do
                    local nextToken = tokens[nextIndex]
                    if nextToken.space or nextToken.newline then
                        break
                    end

                    word = word .. nextToken.metric
                end

                if #line.tokens > 0 and measure(line.metric .. word) > width then
                    flush(token.first)
                end
            end

            local right = measure(line.metric .. token.metric)
            local skipSpace = false
            if #line.tokens > 0 and right > width then
                flush(token.first)
                right = measure(token.metric)
                if token.space then
                    line.raw = line.raw .. token.prefix
                    skipSpace = true
                end
            end

            if not skipSpace then
                token.left = measure(line.metric)
                token.right = right
                line.tokens[#line.tokens + 1] = token
                line.raw = line.raw .. token.raw
                line.metric = line.metric .. token.metric
            end
        end
    end

    line.raw = line.raw .. prefix
    flush()
    -- Measure each line without the visible FontString's height constraint.
    local output, height = {}, 0
    for index, entry in ipairs(lines) do
        output[index] = entry.raw
        probe:SetText(entry.metric)
        entry.top = index == 1 and 0 or height + spacing
        entry.height = math.max(fontSize, probe:GetStringHeight())
        height = entry.top + entry.height
    end

    local wrapped = table.concat(output, "\n")
    font:SetHeight(math.ceil(height))
    font:SetText(wrapped)
    bubble.selectionLayout = {
        source = rendered,
        width = width,
        fontPath = fontPath,
        fontSize = fontSize,
        fontFlags = fontFlags,
        spacing = spacing,
        rendered = wrapped,
        lines = lines,
        height = height,
    }
end

local function textureHit(bubble, x, y)
    local layout = bubble.selectionLayout
    local left, top = bubble.text:GetLeft(), bubble.text:GetTop()
    if not left or not top then
        return
    end

    local px, py = x - left, top - y
    if py < 0 then
        return 1, false
    elseif py > layout.height then
        return #layout.source + 1, false
    end

    local chosen = layout.lines[#layout.lines]
    for _, line in ipairs(layout.lines) do
        if py < line.top + line.height then
            chosen = line
            break
        end
    end

    local index = chosen.first
    for _, token in ipairs(chosen.tokens) do
        index = token.last
        if px < (token.left + token.right) / 2 then
            index = token.first
            break
        end
    end

    return index, px >= 0 and px <= layout.width and py >= 0 and py <= layout.height
end

local function textureAreas(bubble, first, last)
    local layout, areas = bubble.selectionLayout, {}
    for _, line in ipairs(layout.lines) do
        local left, right
        for _, token in ipairs(line.tokens) do
            if token.first < last and token.last > first then
                left = left or token.left
                right = token.right
            end
        end

        if left and right > left then
            areas[#areas + 1] = {
                left = left,
                bottom = bubble.text:GetHeight() - line.top - line.height,
                width = right - left,
                height = line.height,
            }
        end
    end

    return areas
end

local function hit(bubble)
    local scale = bubble:GetEffectiveScale()
    local x, y = GetCursorPosition()
    if bubble.selectionLayout then
        return textureHit(bubble, x / scale, y / scale)
    end

    return bubble.text:FindCharacterIndexAtCoordinate(x / scale, y / scale)
end

function Selection.Paint(window, endpoint)
    local state = window.messageSelection
    if not state then
        return
    end

    local bubble = state.bubble
    if not endpoint then
        return
    end

    state.finish = endpoint
    local first, last = math.min(state.start, endpoint), math.max(state.start, endpoint)
    local areas = {}
    if first ~= last then
        areas = bubble.selectionLayout and textureAreas(bubble, first, last)
            or bubble.text:CalculateScreenAreaFromCharacterSpan(first, last)
            or {}
    end

    bubble.selectionHighlights = bubble.selectionHighlights or {}
    for index, area in ipairs(areas or {}) do
        local texture = bubble.selectionHighlights[index]
        if not texture then
            texture = bubble:CreateTexture(nil, "ARTWORK", nil, -1)
            texture:SetColorTexture(0.2, 0.55, 0.85, 0.45)
            bubble.selectionHighlights[index] = texture
        end

        texture:ClearAllPoints()
        texture:SetPoint("BOTTOMLEFT", bubble.text, "BOTTOMLEFT", area.left, area.bottom)
        texture:SetSize(area.width, area.height)
        texture:Show()
    end

    for index = #(areas or {}) + 1, #bubble.selectionHighlights do
        bubble.selectionHighlights[index]:Hide()
    end

    state.selected = Selection.CopyText(bubble.selectionRendered, first, last - 1)
end

local function copyBridge(window)
    if window.copyBridge then
        return window.copyBridge
    end

    -- WoW only exposes unrestricted clipboard copying through its native edit
    -- control. This invisible bridge contains just the selection, never renders
    -- message text, and never changes the visible FontString or saved history.
    local bridge = CreateFrame("EditBox", nil, window.frame)
    window.copyBridge = bridge
    bridge:SetSize(1, 1)
    -- The native edit caret can remain visible despite the field's alpha.
    -- Keep the clipboard control outside the screen while it holds focus.
    bridge:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -100, -100)
    bridge:SetAutoFocus(false)
    bridge:SetFontObject(GameFontHighlight)
    bridge:SetAlpha(0)
    bridge:EnableMouse(false)
    bridge:SetScript("OnTextChanged", function(editor)
        local state = window.messageSelection
        if state and editor:GetText() ~= state.selected then
            editor:SetText(state.selected)
            editor:HighlightText()
        end
    end)

    bridge:SetScript("OnEscapePressed", function()
        Selection.Clear(window)
    end)

    bridge:SetScript("OnEnterPressed", function()
        Selection.Clear(window)
    end)

    bridge:SetScript("OnEditFocusLost", function()
        Selection.Clear(window)
    end)

    bridge:SetScript("OnHide", function()
        Selection.Clear(window)
    end)

    bridge:RegisterEvent("GLOBAL_MOUSE_DOWN")
    bridge:SetScript("OnEvent", function()
        local state = window.messageSelection
        if state and not state.bubble:IsMouseOver() then
            Selection.Clear(window)
        end
    end)

    return bridge
end

function Selection.Attach(window, bubble)
    if not bubble.text.FindCharacterIndexAtCoordinate or not bubble.text.CalculateScreenAreaFromCharacterSpan then
        return
    end

    bubble:EnableMouse(true)
    bubble:HookScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then
            return
        end

        Selection.Clear(window)
        local index, inside = hit(bubble)
        if not index or not inside then
            return
        end

        window.messageSelection = { bubble = bubble, start = index, finish = index, selected = "" }
        bubble.selectionDragging = true
        window.input:ClearFocus()
    end)

    local function finish()
        if not bubble.selectionDragging then
            return
        end

        Selection.Paint(window, hit(bubble))
        bubble.selectionDragging = nil
        local state = window.messageSelection
        if not state or state.selected == "" then
            Selection.Clear(window)
            return
        end

        -- Avoid following a link when the gesture was a drag across its label.
        bubble.selectionClickSuppressed = true
        C_Timer.After(0, function()
            bubble.selectionClickSuppressed = nil
        end)

        local bridge = copyBridge(window)
        bridge:SetText(state.selected)
        bridge:SetFocus()
        bridge:HighlightText()
    end

    bubble:HookScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            finish()
        end
    end)

    bubble:HookScript("OnUpdate", function()
        if not bubble.selectionDragging then
            return
        end

        if IsMouseButtonDown("LeftButton") then
            Selection.Paint(window, hit(bubble))
        else
            finish()
        end
    end)

    bubble:HookScript("OnHide", function()
        if window.messageSelection and window.messageSelection.bubble == bubble then
            Selection.Clear(window)
        end
    end)
end

function Selection.Update(window, bubble, rendered, width, messageID, geometry)
    if
        bubble.selectionRendered ~= rendered
        or bubble.selectionWidth ~= width
        or bubble.messageID ~= messageID
        or bubble.selectionGeometry ~= geometry
    then
        if window.messageSelection and window.messageSelection.bubble == bubble then
            Selection.Clear(window)
        end
    end

    bubble.selectionRendered, bubble.selectionWidth, bubble.selectionGeometry = rendered, width, geometry
end
