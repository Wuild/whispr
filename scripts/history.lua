local _, addon = ...
local History = { censoredLines = setmetatable({}, { __mode = "k" }) }
addon.History = History

-- Account history rows project the original saved message through __index.
function History.SourceMessage(message)
    local projection = getmetatable(message)
    return projection and projection.__index or message
end

function History.Key(name)
    return string.lower((name or ""):match("^%s*(.-)%s*$"))
end

function History.Sorted(data, query)
    local result = {}
    query = string.lower(query or "")
    for _, conversation in pairs(data.conversations) do
        if query == "" or string.find(string.lower(conversation.name), query, 1, true) then
            result[#result + 1] = conversation
        end
    end

    table.sort(result, function(a, b)
        if (a.pinned == true) ~= (b.pinned == true) then
            return a.pinned == true
        end

        if a.updated == b.updated then
            return a.key < b.key
        end

        return a.updated > b.updated
    end)

    return result
end

-- Empty chats are session-only; do not apply this during normal UI refreshes.
function History.RemoveEmpty(data)
    History.Invalidate()
    for key, conversation in pairs(data.conversations) do
        if
            not conversation.undocked
            and not conversation.pinned
            and (not conversation.messages or next(conversation.messages) == nil)
        then
            data.conversations[key] = nil
        end
    end
end

function History.Trim(data, settings)
    History.Invalidate()
    -- Retire the old archive flag without losing saved conversations.
    for _, conversation in pairs(data.conversations) do
        conversation.archived = nil
    end

    local sorted = History.Sorted(data)
    for index, conversation in ipairs(sorted) do
        if index > settings.maxPeople then
            data.conversations[conversation.key] = nil
        else
            while #conversation.messages > settings.maxMessages do
                table.remove(conversation.messages, 1)
            end

            conversation.unread = math.min(conversation.unread or 0, #conversation.messages)
        end
    end
end

function History.Add(data, settings, name, text, outgoing, timestamp, read, identity, chatLineID)
    local key = identity or History.Key(name)
    if key == "" then
        return
    end

    data.sequence = data.sequence + 1
    local conversation = data.conversations[key]
    local created = not conversation
    if not conversation then
        conversation = { key = key, name = name, messages = {}, unread = 0 }
        data.conversations[key] = conversation
    end

    conversation.name = name
    conversation.archived = nil
    conversation.updated = data.sequence
    local message = {
        id = data.sequence,
        text = text,
        outgoing = outgoing,
        time = timestamp,
    }

    conversation.messages[#conversation.messages + 1] = message
    if
        not outgoing
        and not (HasAnySecretValues and HasAnySecretValues(chatLineID))
        and type(chatLineID) == "number"
        and text:find("|Hcensoredmessage:" .. chatLineID .. "|h", 1, true)
    then
        History.censoredLines[message] = chatLineID
    end

    if read then
        conversation.unread = 0
    elseif not outgoing then
        conversation.unread = conversation.unread + 1
    end

    History.Trim(data, settings)
    if created and addon.Extensions then
        addon.Extensions:ConversationEvent("CONVERSATION_CREATED", conversation)
    end

    return conversation
end

function History.Confirm(data, key, text)
    local conversation = data.conversations[key]
    if not conversation then
        return
    end

    for _, message in ipairs(conversation.messages) do
        if message.outgoing and (message.pending or message.unconfirmed) and message.text == text then
            message.pending, message.unconfirmed = nil, nil
            History.Invalidate()
            if addon.Extensions then
                addon.Extensions:ConversationEvent(
                    "MESSAGE_DELIVERY_CHANGED",
                    conversation,
                    { message = message, status = "confirmed" }
                )
            end

            return conversation
        end
    end
end

local function copyCharacter(info)
    if not info then
        return
    end

    local copy = {}
    for field, value in pairs(info) do
        if field ~= "area" then
            copy[field] = value
        end
    end

    return copy
end

local function mergeIdentity(target, source)
    if not source then
        return
    end

    if not target.character then
        target.character = copyCharacter(source)
        return
    end

    -- Fill identity gaps in older routing-only records. Do not resurrect a
    -- cleared guild from an older character's history.
    for _, field in ipairs({ "guid", "race", "class", "classFile" }) do
        if not target.character[field] or target.character[field] == "" then
            target.character[field] = source[field]
        end
    end
end

-- Account view is a projection; source messages remain in their character stores.
function History.Sources()
    local db = Whispr.db
    local sources = { { name = db.keys and db.keys.char or "current", data = db.char } }
    if db.global.showAllCharacters then
        for name, data in pairs(db.sv and db.sv.char or {}) do
            if data ~= db.char and type(data.conversations) == "table" then
                sources[#sources + 1] = { name = name, data = data }
            end
        end
    end

    return sources
end

function History.Invalidate()
    History.accountView = nil
end

function History.DisplayData()
    if not Whispr.db.global.showAllCharacters then
        return Whispr.db.char
    end

    if History.accountView then
        return History.accountView
    end

    local view = { conversations = {} }
    for _, source in ipairs(History.Sources()) do
        for key, conversation in pairs(source.data.conversations) do
            if source.data == Whispr.db.char or not conversation.demo then
                local merged = view.conversations[key]
                if not merged then
                    merged = {}
                    for field, value in pairs(conversation) do
                        merged[field] = value
                    end

                    merged.character = copyCharacter(conversation.character)
                    local current = Whispr.db.char.conversations[key]
                    merged.pinned = current and current.pinned == true or false
                    merged.messages, merged.unread, merged.updated = {}, 0, 0
                    view.conversations[key] = merged
                end

                mergeIdentity(merged, conversation.character)
                merged.unread = merged.unread + (conversation.unread or 0)
                for _, message in ipairs(conversation.messages or {}) do
                    local id = string.format("%020.3f:%s:%020d", message.time or 0, source.name, message.id or 0)
                    local row = setmetatable({ id = id, sourceCharacter = source.name }, { __index = message })
                    merged.messages[#merged.messages + 1] = row
                    merged.updated = math.max(merged.updated, message.time or 0)
                end
            end
        end
    end

    for _, conversation in pairs(view.conversations) do
        table.sort(conversation.messages, function(a, b)
            return a.id < b.id
        end)
    end

    History.accountView = view
    return view
end

function History.Get(key)
    return History.DisplayData().conversations[key]
end

function History.EnsureCurrent(key)
    local data = Whispr.db.char
    if data.conversations[key] then
        local conversation = data.conversations[key]
        if Whispr.db.global.showAllCharacters then
            local displayed = History.Get(key)
            if displayed then
                mergeIdentity(conversation, displayed.character)
            end

            History.Invalidate()
        end

        return conversation
    end

    local source = History.Get(key)
    if not source then
        return
    end

    data.sequence = (data.sequence or 0) + 1
    local conversation = {
        key = key,
        name = source.name,
        transport = source.transport,
        battleTag = source.battleTag,
        demo = source.demo,
        character = copyCharacter(source.character),
        messages = {},
        unread = 0,
        updated = data.sequence,
    }

    data.conversations[key] = conversation
    History.Invalidate()
    return conversation
end

function History.MarkRead(key)
    for _, source in ipairs(History.Sources()) do
        local conversation = source.data.conversations[key]
        if conversation then
            conversation.unread = 0
        end
    end

    History.Invalidate()
end

function History.Delete(key)
    for _, source in ipairs(History.Sources()) do
        source.data.conversations[key] = nil
    end

    History.Invalidate()
end

function History.Identity(key)
    for _, source in ipairs(History.Sources()) do
        if source.data.conversations[key] then
            return source.data.conversations[key]
        end
    end
end
