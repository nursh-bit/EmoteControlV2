local _, EC = ...

EC.lastTriggerTimes = EC.lastTriggerTimes or {}
EC.lastMessageTimes = EC.lastMessageTimes or {}
EC.rateWindow = EC.rateWindow or {}

function EC:Initialize()
    EmoteControlDB = EmoteControlDB or {}
    self.db = EmoteControlDB
    self:MergeDefaults(self.db, self.defaults)

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

    for event in pairs(self.triggersByEvent) do
        self.frame:RegisterEvent(event)
        table.insert(self.registeredEvents, event)
    end
    
    self.pendingEventUpdate = false
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
    else
        print("|cff00c8ff[EmoteControl]|r Commands:")
        print("/ec on | off")
        print("/ec channel <say|party|raid|guild|yell>")
        print("/ec pack <packId> on|off")
        print("/ec export | import")
        print("/ec builder")
    end
end

function EC:BuildContext(event, ...)
    local playerName, playerClass, playerRace, playerLevel = self:GetPlayerInfo()
    local targetName, targetClass, targetRace = self:GetTargetInfo()

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
            else
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

    if not self:CheckConditions(trigger, ctx) then
        return false
    end

    local chance = override and override.chance or trigger.chance or 1
    if chance < 1 and math.random() > chance then
        return false
    end

    local cooldown = override and override.cooldown or trigger.cooldown or self.db.profile.cooldown
    if not self:IsCooldownReady(trigger, cooldown) then
        return false
    end

    if not self:CheckRateLimit() then
        return false
    end

    return true
end

function EC:CheckConditions(trigger, ctx)
    -- Support old pack format with conditions table
    local cond = trigger.conditions or trigger
    
    if trigger.event == "COMBAT_LOG_EVENT_UNFILTERED" and trigger.subEvent and ctx.subEvent ~= trigger.subEvent then
        return false
    end

    -- Class check (support both string and table)
    if cond.class then
        local classList = type(cond.class) == "table" and cond.class or { cond.class }
        if not self:TableContains(classList, ctx.playerClass) then
            return false
        end
    end
    
    -- Race check (support both string and table)
    if cond.race then
        local raceList = type(cond.race) == "table" and cond.race or { cond.race }
        if not self:TableContains(raceList, ctx.playerRace) then
            return false
        end
    end
    
    -- Spec name check
    if cond.spec and ctx.spec then
        local specList = type(cond.spec) == "table" and cond.spec or { cond.spec }
        if not self:TableContains(specList, ctx.spec) then
            return false
        end
    end
    
    -- Spec ID check (for old packs)
    if cond.specID then
        local specIndex = GetSpecialization()
        if specIndex then
            -- GetSpecializationInfo returns: id, name, description, icon, role, classFile
            local currentSpecID = GetSpecializationInfo(specIndex)
            if currentSpecID ~= cond.specID then
                return false
            end
        else
            return false
        end
    end
    
    -- Spell ID check for UNIT_SPELLCAST_SUCCEEDED
    if cond.spellID and ctx.spellId and ctx.spellId ~= cond.spellID then
        return false
    end
    
    -- Spell name check for UNIT_SPELLCAST_SUCCEEDED
    if cond.spellName and ctx.spellName and ctx.spellName ~= cond.spellName then
        return false
    end
    if cond.inCombat ~= nil and (cond.inCombat ~= UnitAffectingCombat("player")) then
        return false
    end

    if cond.groupSizeMin or cond.groupSizeMax then
        local size = self:GetGroupSize()
        if cond.groupSizeMin and size < cond.groupSizeMin then
            return false
        end
        if cond.groupSizeMax and size > cond.groupSizeMax then
            return false
        end
    end

    if cond.requireTarget and not ctx.targetName then
        return false
    end

    if cond.healthBelow then
        local hp = UnitHealth("player") / math.max(1, UnitHealthMax("player"))
        if hp > cond.healthBelow then
            return false
        end
    end

    if cond.aura then
        -- WoW 10.0+ API compatibility
        local hasAura = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName("player", cond.aura, "HELPFUL|HARMFUL")
        if not hasAura then
            -- Fallback for older clients
            hasAura = AuraUtil and AuraUtil.FindAuraByName(cond.aura, "player")
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
    local window = 60

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
    return output
end

function EC:SendMessage(message, channel, ctx)
    if not message or message == "" then
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
    
    -- WoW 12.0.0: Use pcall to catch SendChatMessage restrictions
    local success, err = pcall(function()
        SendChatMessage(message, channel)
    end)
    
    if not success and self.db.profile.debug then
        self:Debug("Chat message failed:", err)
    end
end
