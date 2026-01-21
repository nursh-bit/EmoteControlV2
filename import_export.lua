local _, EC = ...

local function escape(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\")
    value = value:gsub("\n", "\\n")
    value = value:gsub("\r", "")
    value = value:gsub("|", "\\|")
    return value
end

local function unescape(value)
    value = value:gsub("\\n", "\n")
    value = value:gsub("\\|", "|")
    value = value:gsub("\\\\", "\\")
    return value
end

function EC:ExportOverrides()
    local lines = { "EC2" }
    for key, override in pairs(self.db.profile.overrides) do
        local enabled = override.enabled == false and "0" or "1"
        local cooldown = tostring(override.cooldown or "")
        local chance = tostring(override.chance or "")
        local channel = tostring(override.channel or "")
        local messages = ""
        if type(override.messages) == "table" and #override.messages > 0 then
            messages = table.concat(override.messages, "\n")
        end
        local line = table.concat({
            escape(key),
            enabled,
            cooldown,
            chance,
            channel,
            escape(messages),
        }, "|")
        table.insert(lines, line)
    end
    return table.concat(lines, "\n")
end

function EC:ImportOverrides(payload)
    if type(payload) ~= "string" then
        return false, "Invalid payload"
    end
    local lines = {}
    for line in payload:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    if lines[1] ~= "EC2" then
        return false, "Unsupported format"
    end
    for i = 2, #lines do
        local parts = {}
        local buffer = ""
        local escaping = false
        for c in lines[i]:gmatch(".") do
            if escaping then
                buffer = buffer .. c
                escaping = false
            elseif c == "\\" then
                escaping = true
            elseif c == "|" then
                table.insert(parts, buffer)
                buffer = ""
            else
                buffer = buffer .. c
            end
        end
        table.insert(parts, buffer)

        local key = unescape(parts[1] or "")
        local enabled = parts[2] == "1"
        local cooldown = tonumber(parts[3] or "")
        local chance = tonumber(parts[4] or "")
        local channel = parts[5] and unescape(parts[5]) or nil
        local messagesRaw = parts[6] and unescape(parts[6]) or nil

        if key ~= "" then
            self.db.profile.overrides[key] = self.db.profile.overrides[key] or {}
            local override = self.db.profile.overrides[key]
            override.enabled = enabled
            if cooldown then
                override.cooldown = cooldown
            end
            if chance then
                override.chance = chance
            end
            if channel and channel ~= "" then
                override.channel = channel
            else
                override.channel = nil
            end
            if messagesRaw and messagesRaw ~= "" then
                local messages = {}
                for line in messagesRaw:gmatch("[^\n]+") do
                    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
                    if trimmed ~= "" then
                        table.insert(messages, trimmed)
                    end
                end
                if #messages > 0 then
                    override.messages = messages
                else
                    override.messages = nil
                end
            else
                override.messages = nil
            end
        end
    end
    return true
end
