local _, EC = ...

local function deepCopy(src)
    if type(src) ~= "table" then
        return src
    end
    local out = {}
    for k, v in pairs(src) do
        out[k] = deepCopy(v)
    end
    return out
end

function EC:DeepCopy(src)
    return deepCopy(src)
end

function EC:MergeDefaults(db, defaults)
    if type(defaults) ~= "table" then
        return
    end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(db[k]) ~= "table" then
                db[k] = {}
            end
            self:MergeDefaults(db[k], v)
        else
            if db[k] == nil then
                db[k] = v
            end
        end
    end
end

function EC:Debug(...)
    if self.db and self.db.profile and self.db.profile.debug then
        print("|cff00c8ff[EmoteControl]|r", ...)
    end
end

function EC:Clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

function EC:TableContains(list, value)
    if type(list) ~= "table" then
        return false
    end
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

function EC:GetSpecName()
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    -- GetSpecializationInfo returns: id, name, description, icon, role, classFile
    local _, name = GetSpecializationInfo(specIndex)
    return name
end

function EC:GetGroupSize()
    if IsInRaid() then
        return GetNumGroupMembers()
    end
    if IsInGroup() then
        return GetNumSubgroupMembers() + 1
    end
    return 1
end

function EC:GetPlayerInfo()
    local name = UnitName("player")
    local class = select(2, UnitClass("player"))
    local race = select(2, UnitRace("player"))
    local level = UnitLevel("player")
    return name, class, race, level
end

function EC:GetTargetInfo()
    if not UnitExists("target") then
        return nil
    end
    local name = UnitName("target")
    local class = select(2, UnitClass("target"))
    local race = select(2, UnitRace("target"))
    return name, class, race
end

function EC:RandomItem(list)
    if type(list) ~= "table" or #list == 0 then
        return nil
    end
    return list[math.random(1, #list)]
end

function EC:NormalizeChannel(channel)
    if not channel or channel == "" then
        return "SAY"
    end
    channel = string.upper(channel)
    
    -- WoW 12.0.0: Validate channel
    local validChannels = {
        ["SAY"] = true,
        ["YELL"] = true,
        ["PARTY"] = true,
        ["RAID"] = true,
        ["GUILD"] = true,
        ["EMOTE"] = true,
        ["INSTANCE"] = true,
    }
    
    if not validChannels[channel] then
        return "SAY"
    end
    
    return channel
end
