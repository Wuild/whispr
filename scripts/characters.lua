local _, addon = ...
local Characters = { sources = {}, online = {} }
addon.Characters = Characters

local function secret(...)
    return HasAnySecretValues and HasAnySecretValues(...)
end

local function key(name)
    if secret(name) or type(name) ~= "string" then
        return
    end

    return addon.History.Key(name)
end

local function classToken(className)
    for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
        for token, localized in pairs(names) do
            if localized == className then
                return token
            end
        end
    end
end

local function known(value)
    return type(value) == "string"
        and value ~= ""
        and value:lower() ~= "unknown"
        and value:lower() ~= "offline"
        and value ~= UNKNOWN
        and value ~= UNKNOWNOBJECT
        and value ~= PLAYER_OFFLINE
end

function Characters.Merge(conversation, details)
    if conversation.character then
        conversation.character.area = nil
    end

    if not details or details.offline == true then
        return
    end

    Characters.revision = (Characters.revision or 0) + 1
    conversation.character = conversation.character or {}
    local info = conversation.character
    for _, field in ipairs({ "guid", "race", "class", "classFile", "guild", "level" }) do
        local value = details[field]
        if not secret(value) then
            if field == "level" then
                if type(value) == "number" and value > 0 then
                    info.level = value
                end
            elseif field == "guild" and value == false then
                info.guild = nil
            elseif known(value) then
                info[field] = value
            end
        end
    end

    if not info.classFile and info.class then
        info.classFile = classToken(info.class)
    end

    if addon.History.Invalidate then
        addon.History.Invalidate()
    end
end

local function fromGUID(conversation, guid)
    if secret(guid) or type(guid) ~= "string" or not guid:match("^Player%-") then
        return
    end

    Characters.Merge(conversation, { guid = guid })
    if not GetPlayerInfoByGUID then
        return
    end

    local class, classFile, race = GetPlayerInfoByGUID(guid)
    Characters.Merge(conversation, { class = class, classFile = classFile, race = race })
end

local function unitDetails(unit)
    if not UnitExists or not UnitExists(unit) or not UnitIsPlayer(unit) then
        return
    end

    if UnitIsConnected then
        local connected = UnitIsConnected(unit)
        if secret(connected) or connected == false then
            return
        end
    end

    local name, realm
    if addon.Client and addon.Client.hasLastNames and UnitNameUnmodified then
        local first, last = UnitNameUnmodified(unit)
        if secret(first, last) then
            return
        end

        name = first
        if first and last and last ~= "" then
            name = first .. " " .. last
        end
    else
        name, realm = UnitFullName(unit)
    end

    local guid = UnitGUID(unit)
    local class, classFile = UnitClass(unit)
    local race = UnitRace(unit)
    local guild = GetGuildInfo and GetGuildInfo(unit)
    if secret(name, realm, guid, class, classFile, race) or not name then
        return
    end

    local fullName = realm and realm ~= "" and (name .. "-" .. realm) or name
    local details =
        { guid = guid, class = class, classFile = classFile, race = race, level = UnitLevel and UnitLevel(unit) }
    if GetGuildInfo and not secret(guild) then
        details.guild = guild or false
    end

    return fullName, details
end

local function lookup(name)
    local normalized = key(name)
    if not normalized then
        return
    end

    if addon.Client and addon.Client.hasLastNames then
        normalized = normalized:gsub("^(%S-)%-(%S-)(%-.*)$", "%1 %2%3")
        normalized = normalized:gsub("^([^%s%-]+)%-([^%s%-]+)$", "%1 %2")
    end

    -- Realm-less names are local. Only collapse a suffix for our own realm.
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm and not secret(realm) then
        local suffix = "-" .. string.lower(realm)
        if normalized:sub(-#suffix) == suffix then
            normalized = normalized:sub(1, -#suffix - 1)
        end
    end

    return normalized
end

function Characters.Update(conversation, guid)
    if not conversation or conversation.transport == "bnet" then
        return
    end

    local id = lookup(conversation.name)
    local visible = {}
    -- A currently connected unit (or incoming whisper GUID) is fresher evidence
    -- than a roster's possibly stale offline flag.
    for _, unit in ipairs({ "target", "focus" }) do
        local name, details = unitDetails(unit)
        if name and lookup(name) == id then
            visible[#visible + 1] = details
        end
    end

    local freshGUID = not secret(guid) and type(guid) == "string" and guid:match("^Player%-")
    if Characters.online[id] == false and not freshGUID and #visible == 0 then
        return
    end

    Characters.Merge(conversation, Characters.sources[id])
    -- Selecting an old conversation must not re-query its saved GUID: offline
    -- lookups can return placeholder class/race strings and erase good history.
    if freshGUID or Characters.online[id] == true or #visible > 0 then
        fromGUID(conversation, guid or (conversation.character and conversation.character.guid))
    end

    for _, details in ipairs(visible) do
        Characters.Merge(conversation, details)
    end
end

Characters.NameKey = lookup

function Characters.SameName(first, second)
    local a, b = lookup(first), lookup(second)
    return a ~= nil and b ~= nil and a == b
end

function Characters.RefreshSources(data)
    Characters.revision = (Characters.revision or 0) + 1
    Characters.sources, Characters.online = {}, {}

    local function add(name, details, online)
        local id = lookup(name)
        if id then
            if secret(online) then
                return
            end

            if online == false then
                if Characters.online[id] == nil then
                    Characters.online[id] = false
                end

                return
            end

            if online == true then
                Characters.online[id] = true
            end

            local record = { character = Characters.sources[id] }
            Characters.Merge(record, details)
            Characters.sources[id] = record.character
        end
    end

    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        for index = 1, C_FriendList.GetNumFriends() do
            local friend = C_FriendList.GetFriendInfoByIndex(index)
            if friend then
                add(
                    friend.name,
                    { guid = friend.guid, class = friend.className, level = friend.level },
                    friend.connected
                )
            end
        end
    end

    if GetNumGuildMembers and GetGuildRosterInfo then
        local guild = GetGuildInfo and GetGuildInfo("player")
        for index = 1, GetNumGuildMembers() do
            local name, _, _, level, class, _, _, _, online, _, classFile, _, _, _, _, _, guid =
                GetGuildRosterInfo(index)
            add(name, { guid = guid, class = class, classFile = classFile, guild = guild, level = level }, online)
        end
    end

    local playerName, playerDetails = unitDetails("player")
    if playerName then
        add(playerName, playerDetails, true)
        if known(playerDetails.classFile) then
            local realm = GetNormalizedRealmName and GetNormalizedRealmName()
            if
                not (addon.Client and addon.Client.hasLastNames)
                and not playerName:find("-", 1, true)
                and not secret(realm)
                and known(realm)
            then
                playerName = playerName .. "-" .. realm
            end

            local player = data.playerCharacter or {}
            player.name, player.classFile = playerName, playerDetails.classFile
            data.playerCharacter = player
        end
    end

    local units = { "target", "focus" }
    for index = 1, 4 do
        units[#units + 1] = "party" .. index
    end

    for index = 1, 40 do
        units[#units + 1] = "raid" .. index
    end

    for _, unit in ipairs(units) do
        local name, details = unitDetails(unit)
        if name then
            add(name, details, true)
        end
    end

    for _, conversation in pairs(data.conversations) do
        Characters.Update(conversation)
    end

    if addon.Extensions then
        addon.Extensions:Emit("CHARACTERS_UPDATED")
    end
end

function Characters.Label(conversation)
    if conversation and conversation.transport == "bnet" then
        return "Battle.net"
    end

    local info = conversation and conversation.character
    if not info then
        return ""
    end

    local parts = {}
    if info.race then
        local race = info.race
        if race:lower():match("%f[%a]skyborn[e]?%f[%A]") then
            race = "Skyborn"
        end

        parts[#parts + 1] = race
    end

    if info.class then
        parts[#parts + 1] = info.class
    end

    return table.concat(parts, " · ")
end

function Characters.Color(conversation)
    local info = conversation and conversation.character
    return info and info.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.classFile]
end
