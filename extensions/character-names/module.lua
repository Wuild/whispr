local _, addon = ...
local L = addon.L

addon.Locale:OnReady(function()
    local Names = Whispr:NewExtension("character_names", {
        name = L["Character names"],
        version = "1.0.0",
        builtin = true,
        description = L["Color known character names by class in messages and drafts. Uses conversations and game rosters; unknown or ambiguous names stay unchanged. Sent text is unchanged."],
    })

    addon.CharacterNames = Names

    local function boundary(char)
        if char == "" then
            return true
        end

        local byte = char:byte()
        return byte < 128 and not char:match("[%w_%-]")
    end

    function Names:BuildCache()
        local characters = addon.Characters
        if self.revision == characters.revision and self.names then
            return
        end

        self.revision = characters.revision
        local aliases = {}

        local function add(name, info)
            if type(name) ~= "string" or not info or not info.classFile then
                return
            end

            if HasAnySecretValues and HasAnySecretValues(name, info.classFile) then
                return
            end

            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.classFile]
            if not color then
                return
            end

            local identity = characters.NameKey(name)
            if not identity then
                return
            end

            local hex = string.format(
                "%02x%02x%02x",
                math.floor(color.r * 255 + 0.5),
                math.floor(color.g * 255 + 0.5),
                math.floor(color.b * 255 + 0.5)
            )

            local function alias(value)
                value = value:lower()
                if value == "" then
                    return
                end

                local current = aliases[value]
                if current and (current.identity ~= identity or current.hex ~= hex) then
                    aliases[value] = { ambiguous = true }
                elseif not current then
                    aliases[value] = { identity = identity, hex = hex, target = name }
                end
            end

            alias(name)
            alias(identity)
            local realm = GetNormalizedRealmName and GetNormalizedRealmName()
            if realm and not (HasAnySecretValues and HasAnySecretValues(realm)) and not identity:find("-", 1, true) then
                alias(identity .. "-" .. realm)
            end

            -- A realm-less alias is safe only when all known matches identify the
            -- same character, not merely two characters with the same class.
            alias(identity:match("^([^%-]+)") or identity)
        end

        -- Retain a bounded session cache when a target/group member leaves the
        -- live roster. Saved conversations provide known classes after a reload.
        self.known = self.known or {}

        local function remember(name, info)
            if type(name) ~= "string" or not info or not info.classFile then
                return
            end

            if HasAnySecretValues and HasAnySecretValues(name, info.classFile) then
                return
            end

            local identity = characters.NameKey(name)
            if not identity then
                return
            end

            self.sequence = (self.sequence or 0) + 1
            self.known[identity] = { name = name, classFile = info.classFile, sequence = self.sequence }
        end

        local data = addon.History.DisplayData()
        for _, conversation in pairs(data.conversations) do
            if conversation.transport ~= "bnet" and not conversation.demo then
                remember(conversation.name, conversation.character)
            end
        end

        for name, info in pairs(characters.sources or {}) do
            remember(name, info)
        end

        -- Own names are useful even when viewing only the current character's history.
        local db = Whispr.db
        for _, saved in pairs(db.sv and db.sv.char or {}) do
            local player = saved.playerCharacter
            if player then
                remember(player.name, player)
            end
        end

        local known = {}
        for identity, info in pairs(self.known) do
            known[#known + 1] = { identity = identity, info = info }
        end

        table.sort(known, function(a, b)
            return a.info.sequence > b.info.sequence
        end)

        for index, entry in ipairs(known) do
            if index <= 1000 then
                add(entry.info.name, entry.info)
            else
                self.known[entry.identity] = nil
            end
        end

        self.names, self.initials = {}, {}
        for name, details in pairs(aliases) do
            if not details.ambiguous then
                self.names[#self.names + 1] = { name = name, hex = details.hex, target = details.target }
            end
        end

        table.sort(self.names, function(a, b)
            if #a.name == #b.name then
                return a.name < b.name
            end

            return #a.name > #b.name
        end)

        for _, entry in ipairs(self.names) do
            local first = entry.name:sub(1, 1)
            self.initials[first] = self.initials[first] or {}
            table.insert(self.initials[first], entry)
        end
    end

    function Names:Render(_, text, inputMode, wrap)
        local settings = self:GetSettings()
        if (inputMode and not settings.drafts) or (not inputMode and not settings.messages) then
            return text
        end

        self:BuildCache()
        if #self.names == 0 then
            return text
        end

        local lower, result, cursor, plainStart = text:lower(), {}, 1, 1
        while cursor <= #text do
            local matched
            if boundary(text:sub(cursor - 1, cursor - 1)) then
                for _, entry in ipairs(self.initials[lower:sub(cursor, cursor)] or {}) do
                    local stop = cursor + #entry.name - 1
                    if lower:sub(cursor, stop) == entry.name and boundary(text:sub(stop + 1, stop + 1)) then
                        matched = entry
                        break
                    end
                end
            end

            if matched then
                result[#result + 1] = text:sub(plainStart, cursor - 1)
                local stop = cursor + #matched.name - 1
                local raw = text:sub(cursor, stop)
                local color = "|cff" .. matched.hex
                if inputMode then
                    result[#result + 1] = wrap(raw, color .. raw .. "|r")
                else
                    local target = raw:lower() == matched.target:lower() and raw or matched.target
                    result[#result + 1] = color .. addon.Format.NameLink(target, raw) .. "|r"
                end

                cursor, plainStart = stop + 1, stop + 1
            else
                cursor = cursor + 1
            end
        end

        result[#result + 1] = text:sub(plainStart)
        return table.concat(result)
    end

    function Names:Refresh()
        self.names, self.revision = nil, nil

        local function refresh(window)
            if not window or not window.frame then
                return
            end

            if window.input and window.input.RefreshFormatting then
                window.input:RefreshFormatting()
            end

            window:RefreshMessages()
        end

        refresh(addon.Window)
        for _, window in pairs(addon.Window and addon.Window.popouts or {}) do
            refresh(window)
        end
    end

    function Names:OnInitialize()
        self:RegisterDefaults({ messages = true, drafts = true })
        self:RegisterOptions({
            type = "group",
            name = L["Name colors"],
            args = {
                messages = { type = "toggle", name = L["Color names in messages"], order = 1, width = "full" },
                drafts = { type = "toggle", name = L["Color names while typing"], order = 2, width = "full" },
                hint = {
                    type = "description",
                    order = 3,
                    name = L["Class colors are learned from friends, guild and group rosters, targets and saved conversations. Full names with realms are supported. No lookups or messages are sent to discover unknown characters."],
                },
            },

            set = function(info, value)
                self:GetSettings()[info[#info]] = value
                self:Refresh()
            end,
        })
    end

    function Names:OnEnable()
        self:RegisterFilter("FORMAT_NAME_TEXT", "Render")
        self:RegisterMessage("CHARACTERS_UPDATED", "Refresh")
        self:Refresh()
    end

    function Names:OnDisable()
        self:Refresh()
    end
end)
