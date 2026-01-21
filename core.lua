local _, EC = ...

EC.lastTriggerTimes = EC.lastTriggerTimes or {}
EC.lastMessageTimes = EC.lastMessageTimes or {}
EC.rateWindow = EC.rateWindow or {}

function EC:Initialize()
    EmoteControlDB = EmoteControlDB or {}
    self.db = EmoteControlDB
    self:MergeDefaults(self.db, self.defaults)
    self.userActivated = false

    self:RegisterCustomPack()
    self:BuildTriggerIndex()
    self:RegisterTriggerEvents()
    self:SetupSlashCommands()

    self:Debug("Initialized", self.version)
end

function EC:RegisterTriggerEvents()
    -- WoW 12.0.0: Don't modify event registration during combat
    if InCombatLockdown() then
        self:Debug("Deferred event registration until out of combat")
        -- Register a handler to do this when combat ends
        if not self.pendingEventUpdate then
            self.pendingEventUpdate = true
            self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return
    end
    
    self.registeredEvents = self.registeredEvents or {}
    for _, event in ipairs(self.registeredEvents) do
        self.frame:UnregisterEvent(event)
    end
    self.registeredEvents = {}

    local virtualEvents = {
        COMBAT_CRITICAL_HIT = true,
        COMBAT_DODGED = true,
        COMBAT_PARRIED = true,
        COMBAT_INTERRUPTED = true,
    }

    local needsCombatLog = false
    for event in pairs(self.triggersByEvent) do
        if virtualEvents[event] then
            needsCombatLog = true
        end
    end

    for event in pairs(self.triggersByEvent) do
        if not virtualEvents[event] then
            self.frame:RegisterEvent(event)
            table.insert(self.registeredEvents, event)
        end
    end

    if needsCombatLog and not self.triggersByEvent["COMBAT_LOG_EVENT_UNFILTERED"] then
        self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        table.insert(self.registeredEvents, "COMBAT_LOG_EVENT_UNFILTERED")
    end
    
    self.pendingEventUpdate = false
end

function EC:RequestEventUpdate()
    if self.pendingEventUpdate then
        return
    end
    self.pendingEventUpdate = true
    if InCombatLockdown() then
        self:Debug("Queued event update until out of combat")
        self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if self.pendingEventUpdate then
                self:RegisterTriggerEvents()
            end
        end)
    else
        self:RegisterTriggerEvents()
    end
end

function EC:SetupSlashCommands()
    SLASH_EMOTECONTROL1 = "/emotecontrol"
    SLASH_EMOTECONTROL2 = "/ec"
    SlashCmdList["EMOTECONTROL"] = function(msg)
        self:HandleSlashCommand(msg)
    end
end

function EC:HandleSlashCommand(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    self.userActivated = true

    if cmd == "on" then
        self.db.profile.enabled = true
        print("|cff00c8ff[EmoteControl]|r Enabled")
    elseif cmd == "off" then
        self.db.profile.enabled = false
        print("|cff00c8ff[EmoteControl]|r Disabled")
    elseif cmd == "channel" and rest ~= "" then
        self.db.profile.channel = self:NormalizeChannel(rest)
        print("|cff00c8ff[EmoteControl]|r Channel set to", self.db.profile.channel)
    elseif cmd == "pack" and rest ~= "" then
        local packId, state = rest:match("^(%S+)%s*(.*)$")
        if packId then
            if state == "on" then
                self.db.profile.enablePacks[packId] = true
            elseif state == "off" then
                self.db.profile.enablePacks[packId] = false
            end
            self:BuildTriggerIndex()
            print("|cff00c8ff[EmoteControl]|r Pack", packId, "set to", self:GetPackEnabled(packId) and "on" or "off")
        end
    elseif cmd == "export" then
        local data = self:ExportOverrides()
        self:ShowExportFrame(data)
    elseif cmd == "import" then
        self:ShowImportFrame()
    elseif cmd == "builder" then
        self:ToggleTriggerBuilder()
    elseif cmd == "debug" and rest ~= "" then
        if rest == "on" then
            self.db.profile.debug = true
        elseif rest == "off" then
            self.db.profile.debug = false
        end
        print("|cff00c8ff[EmoteControl]|r Debug", self.db.profile.debug and "on" or "off")
    elseif cmd == "output" and rest ~= "" then
        if rest == "on" then
            self.db.profile.outputEnabled = true
        elseif rest == "off" then
            self.db.profile.outputEnabled = false
        end
        print("|cff00c8ff[EmoteControl]|r Output", self.db.profile.outputEnabled and "on" or "off")
    elseif cmd == "ui" or cmd == "options" then
        self:OpenOptions()
    else
        print("|cff00c8ff[EmoteControl]|r Commands:")
        print("/ec on | off")
        print("/ec channel <say|party|raid|guild|yell>")
        print("/ec pack <packId> on|off")
        print("/ec export | import")
        print("/ec builder")
        print("/ec debug on|off")
        print("/ec output on|off")
        print("/ec options")
    end
end

function EC:GetEffectiveCooldown(trigger, channel)
    local override = self:GetOverride(trigger)
    if override and override.cooldown then
        return override.cooldown
    end
    if trigger.cooldown then
        return trigger.cooldown
    end
    local base = self.db.profile.cooldown or 8
    if channel == "EMOTE" then
        return self.db.profile.cooldownEmote or base
    end
    return self.db.profile.cooldownChat or base
end

function EC:BuildContext(event, ...)
    local playerName, playerClass, playerRace, playerLevel = self:GetPlayerInfo()
    local targetName, targetClass, targetRace = self:GetTargetInfo()
    local GetSpellInfo = rawget(_G, "GetSpellInfo")

    local instanceName, instanceType, instanceDifficultyID, instanceDifficultyName
    if GetInstanceInfo then
        instanceName, instanceType, instanceDifficultyID = GetInstanceInfo()
        if instanceDifficultyID and GetDifficultyInfo then
            local diffName = GetDifficultyInfo(instanceDifficultyID)
            instanceDifficultyName = diffName
        end
    end

    local continentName
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            local mapInfo = C_Map.GetMapInfo(mapID)
            if mapInfo and mapInfo.parentMapID then
                local parentInfo = C_Map.GetMapInfo(mapInfo.parentMapID)
                continentName = parentInfo and parentInfo.name or nil
            end
        end
    end

    local ctx = {
        event = event,
        playerName = playerName,
        playerClass = playerClass,
        playerRace = playerRace,
        playerLevel = playerLevel,
        targetName = targetName,
        targetClass = targetClass,
        targetRace = targetRace,
        zone = GetZoneText(),
        subZone = GetSubZoneText(),
        spec = self:GetSpecName(),
        time = date("%H:%M"),
        date = date("%Y-%m-%d"),
        weekday = date("%A"),
        groupSize = self:GetGroupSize(),
        instanceName = instanceName,
        instanceType = instanceType,
        instanceDifficulty = instanceDifficultyName,
        continent = continentName,
    }

    if event == "PLAYER_LEVEL_UP" then
        local level = ...
        ctx.level = level
    elseif event == "ACHIEVEMENT_EARNED" then
        local id = ...
        local name = GetAchievementInfo(id)
        ctx.achievementId = id
        ctx.achievementName = name
    elseif event == "CHAT_MSG_LOOT" then
        local message = ...
        ctx.loot = message
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellId = ...
        if unit == "player" then
            ctx.spellId = spellId
            -- WoW 10.0+ uses C_Spell API
            if C_Spell and C_Spell.GetSpellName then
                ctx.spellName = C_Spell.GetSpellName(spellId)
            elseif GetSpellInfo then
                ctx.spellName = GetSpellInfo(spellId)
            end
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        ctx.zone = GetZoneText()
        ctx.subZone = GetSubZoneText()
    end

    return ctx
end

function EC:GetOutputChannel(trigger)
    local override = self:GetOverride(trigger)
    if override and override.channel then
        return self:NormalizeChannel(override.channel)
    end
    -- Support direct channel property in trigger
    if trigger.channel then
        return self:NormalizeChannel(trigger.channel)
    end
    return self:NormalizeChannel(self.db.profile.channel)
end

function EC:GetOverride(trigger)
    local key = self:GetTriggerKey(trigger)
    return self.db.profile.overrides[key]
end

function EC:GetTriggerKey(trigger)
    return string.format("%s:%s", trigger.packId or "", trigger.id or "")
end

function EC:ShouldFireTrigger(trigger, ctx)
    local override = self:GetOverride(trigger)
    if override and override.enabled == false then
        return false
    end

    if self.db.profile.requireActivation and not self.userActivated then
        return false
    end

    if not self.db.profile.outputEnabled then
        return false
    end

    if self.db.profile.onlyOutOfCombat and UnitAffectingCombat("player") then
        return false
    end

    if self.db.profile.onlyInGroup and not IsInGroup() then
        return false
    end

    if self.db.profile.onlyInRaid and not IsInRaid() then
        return false
    end

    if self.db.profile.onlyInInstance then
        local inInstance = IsInInstance()
        if not inInstance then
            return false
        end
    end

    if self.db.profile.muteInInstances then
        local inInstance = IsInInstance()
        if inInstance then
            return false
        end
    end

    if self.db.profile.muteInCities and IsResting() then
        return false
    end

    if not self:CheckConditions(trigger, ctx) then
        return false
    end

    local cond = trigger.conditions or trigger
    local defaults = trigger.packDefaults or trigger.defaults
    local randomChance = cond.randomChance
    if randomChance == nil and defaults then
        randomChance = defaults.randomChance
    end
    if randomChance and math.random() > randomChance then
        return false
    end

    local chance = override and override.chance or trigger.chance or 1
    if chance < 1 and math.random() > chance then
        return false
    end

    local channel = self:GetOutputChannel(trigger)
    local cooldown = self:GetEffectiveCooldown(trigger, channel)
    if not self:IsCooldownReady(trigger, cooldown) then
        return false
    end

    if not self:CheckRateLimit() then
        return false
    end

    return true
end

function EC:CheckConditions(trigger, ctx)
    -- Support old pack format with conditions table and pack defaults
    local cond = trigger.conditions or trigger
    local defaults = trigger.packDefaults or trigger.defaults
    local function pick(key)
        if cond[key] ~= nil then
            return cond[key]
        end
        if defaults and defaults[key] ~= nil then
            return defaults[key]
        end
        return nil
    end
    local function toList(value)
        if value == nil then
            return nil
        end
        if type(value) == "table" then
            return value
        end
        return { value }
    end
    local function matchPattern(pattern, text)
        if not pattern or not text then
            return false
        end
        if not pattern:find("%*") then
            return pattern == text
        end
        local escaped = pattern:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
        local luaPattern = "^" .. escaped:gsub("%*", ".*") .. "$"
        return text:match(luaPattern) ~= nil
    end
    local function matchAny(patterns, text)
        local list = toList(patterns)
        if not list then
            return false
        end
        for _, pattern in ipairs(list) do
            if matchPattern(pattern, text) then
                return true
            end
        end
        return false
    end
    
    if trigger.event == "COMBAT_LOG_EVENT_UNFILTERED" and trigger.subEvent and ctx.subEvent ~= trigger.subEvent then
        return false
    end

    -- Class check (support both string and table)
    local classList = toList(pick("class"))
    if classList then
        if not self:TableContains(classList, ctx.playerClass) then
            return false
        end
    end
    
    -- Race check (support both string and table)
    local raceList = toList(pick("race"))
    if raceList then
        if not self:TableContains(raceList, ctx.playerRace) then
            return false
        end
    end
    
    -- Spec name check
    local specList = toList(pick("spec"))
    if specList and ctx.spec then
        if not self:TableContains(specList, ctx.spec) then
            return false
        end
    end
    
    -- Spec ID check (for old packs)
    local specID = pick("specID")
    if specID then
        local specIndex = GetSpecialization()
        if specIndex then
            -- GetSpecializationInfo returns: id, name, description, icon, role, classFile
            local currentSpecID = GetSpecializationInfo(specIndex)
            if currentSpecID ~= specID then
                return false
            end
        else
            return false
        end
    end
    
    -- Spell ID check for UNIT_SPELLCAST_SUCCEEDED
    local spellID = pick("spellID")
    if spellID and ctx.spellId and ctx.spellId ~= spellID then
        return false
    end
    if spellID and not ctx.spellId then
        return false
    end
    
    -- Spell name check for UNIT_SPELLCAST_SUCCEEDED
    local spellName = pick("spellName")
    if spellName then
        if not ctx.spellName or not matchAny(spellName, ctx.spellName) then
            return false
        end
    end

    local unit = pick("unit")
    if unit and unit ~= "player" then
        if not UnitExists(unit) then
            return false
        end
    end

    local inCombat = pick("inCombat")
    if inCombat ~= nil and (inCombat ~= UnitAffectingCombat("player")) then
        return false
    end

    local groupSizeMin = pick("groupSizeMin")
    local groupSizeMax = pick("groupSizeMax")
    if groupSizeMin or groupSizeMax then
        local size = self:GetGroupSize()
        if groupSizeMin and size < groupSizeMin then
            return false
        end
        if groupSizeMax and size > groupSizeMax then
            return false
        end
    end

    local requireTarget = pick("requireTarget")
    if requireTarget and not ctx.targetName then
        return false
    end

    local healthBelow = pick("healthBelow")
    if healthBelow then
        local hp = UnitHealth("player") / math.max(1, UnitHealthMax("player"))
        if hp > healthBelow then
            return false
        end
    end

    local aura = pick("aura")
    if aura then
        -- WoW 10.0+ API compatibility
        local hasAura = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName("player", aura, "HELPFUL|HARMFUL") ~= nil
        if not hasAura then
            -- Fallback for older clients
            hasAura = AuraUtil and AuraUtil.FindAuraByName(aura, "player") ~= nil
        end
        if not hasAura then
            return false
        end
    end

    return true
end

function EC:IsCooldownReady(trigger, cooldown)
    local key = self:GetTriggerKey(trigger)
    local last = self.lastTriggerTimes[key] or 0
    if (GetTime() - last) < cooldown then
        return false
    end
    return true
end

function EC:MarkTriggerFired(trigger)
    local key = self:GetTriggerKey(trigger)
    self.lastTriggerTimes[key] = GetTime()
end

function EC:CheckRateLimit()
    local now = GetTime()
    local limit = self.db.profile.rateLimit
    local window = self.db.profile.rateWindowSeconds or 60

    self.rateWindow = self.rateWindow or {}
    local newWindow = {}

    for _, t in ipairs(self.rateWindow) do
        if now - t < window then
            table.insert(newWindow, t)
        end
    end

    self.rateWindow = newWindow
    if #self.rateWindow >= limit then
        return false
    end

    table.insert(self.rateWindow, now)
    return true
end

function EC:BuildMessage(trigger, ctx)
    local message = self:RandomItem(trigger.messages)
    if not message then
        return nil
    end

    local formatted = self:FormatMessage(message, ctx)
    self:MarkTriggerFired(trigger)
    return formatted
end

function EC:FormatMessage(message, ctx)
    local output = message
    -- Support both {token} and <token> formats
    local function replace(pattern, value)
        output = output:gsub("{" .. pattern .. "}", value or "")
        output = output:gsub("<" .. pattern .. ">", value or "")
    end
    
    replace("player", ctx.playerName)
    replace("target", ctx.targetName)
    replace("zone", ctx.zone)
    replace("subzone", ctx.subZone)
    replace("class", ctx.playerClass)
    replace("race", ctx.playerRace)
    replace("spec", ctx.spec)
    replace("time", ctx.time)
    replace("date", ctx.date)
    replace("level", tostring(ctx.level or ctx.playerLevel or ""))
    replace("achievement", ctx.achievementName)
    replace("loot", ctx.loot)
    replace("spell", ctx.spellName)
    replace("source", ctx.sourceName)
    replace("dest", ctx.destName)
    replace("instanceName", ctx.instanceName)
    replace("instance", ctx.instanceName)
    replace("instanceDifficulty", ctx.instanceDifficulty)
    replace("instanceType", ctx.instanceType)
    replace("group-size", tostring(ctx.groupSize or ""))
    replace("weekday", ctx.weekday)
    replace("continent", ctx.continent)
    return output
end

function EC:SendMessage(message, channel, ctx)
    if not message or message == "" then
        return
    end

    if not self.db.profile.outputEnabled then
        return
    end

    if self.chatReady == false then
        return
    end

    channel = self:NormalizeChannel(channel)

    -- WoW 12.0.0: Channel validation and fallback
    if channel == "PARTY" and not IsInGroup() then
        channel = "SAY"
    elseif channel == "RAID" and not IsInRaid() then
        channel = "SAY"
    elseif channel == "GUILD" and not IsInGuild() then
        channel = "SAY"
    elseif channel == "INSTANCE" then
        local inInstance, instanceType = IsInInstance()
        if not inInstance or not (instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena" or instanceType == "scenario") then
            channel = "SAY"
        end
    end
    
    -- WoW 12.0.0: Restrict automated chat in instances to prevent abuse
    local inInstance = IsInInstance()
    if inInstance and (channel == "SAY" or channel == "YELL") then
        -- Don't spam in dungeons/raids with SAY/YELL
        if self.db.profile.debug then
            self:Debug("Suppressed message in instance:", channel)
        end
        return
    end

    local canSend = rawget(_G, "ChatEdit_CanSend")
    if canSend and not canSend() then
        return
    end

    if C_ChatInfo and C_ChatInfo.CanSendChatMessage then
        local ok = C_ChatInfo.CanSendChatMessage(channel)
        if ok == false then
            return
        end
    end
    
    -- WoW 12.0.0: Use pcall to catch SendChatMessage restrictions
    local success, err = pcall(function()
        SendChatMessage(message, channel)
    end)
    
    if not success and self.db.profile.debug then
        self:Debug("Chat message failed:", err)
    end
end

function EC:OpenOptions()
    if self.optionsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(self.optionsCategory)
        return
    end
    local openToCategory = rawget(_G, "InterfaceOptionsFrame_OpenToCategory")
    if self.optionsPanel and openToCategory then
        openToCategory(self.optionsPanel)
        openToCategory(self.optionsPanel)
    end
end
