local _, EC = ...

function EC:OnPlayerLogin()
    self.chatReady = false
    if C_Timer and C_Timer.After then
        C_Timer.After(5, function()
            self.chatReady = true
        end)
    else
        self.chatReady = true
    end
    self:Debug("Player login")
end

function EC:OnEvent(event, ...)
    if not self.db or not self.db.profile.enabled then
        return
    end
    
    -- WoW 12.0.0: Handle deferred event registration
    if event == "PLAYER_REGEN_ENABLED" and self.pendingEventUpdate then
        self:RegisterTriggerEvents()
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:HandleCombatLog()
        return
    end

    self:HandleEvent(event, ...)
end

function EC:HandleCombatLog()
    local timestamp, subEvent, hideCaster,
        sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
        destGUID, destName, destFlags, destRaidFlags,
        spellId, spellName, spellSchool,
        amount = CombatLogGetCurrentEventInfo()

    local ctx = {
        event = "COMBAT_LOG_EVENT_UNFILTERED",
        subEvent = subEvent,
        sourceGUID = sourceGUID,
        sourceName = sourceName,
        destGUID = destGUID,
        destName = destName,
        targetName = destName,
        spellId = spellId,
        spellName = spellName,
        amount = amount,
    }

    self:HandleEvent("COMBAT_LOG_EVENT_UNFILTERED", ctx)

    -- Combat-derived virtual events are disabled for testing
    -- if subEvent == "SWING_DAMAGE" or subEvent == "SPELL_DAMAGE" or subEvent == "RANGE_DAMAGE" or subEvent == "SPELL_PERIODIC_DAMAGE" then
    --     local critical = select(21, CombatLogGetCurrentEventInfo())
    --     if critical then
    --         self:HandleEvent("COMBAT_CRITICAL_HIT", ctx)
    --     end
    -- elseif subEvent == "SWING_MISSED" or subEvent == "SPELL_MISSED" or subEvent == "RANGE_MISSED" then
    --     local missType = select(12, CombatLogGetCurrentEventInfo())
    --     if missType == "DODGE" then
    --         self:HandleEvent("COMBAT_DODGED", ctx)
    --     elseif missType == "PARRY" then
    --         self:HandleEvent("COMBAT_PARRIED", ctx)
    --     end
    -- elseif subEvent == "SPELL_INTERRUPT" then
    --     self:HandleEvent("COMBAT_INTERRUPTED", ctx)
    -- end
end

function EC:HandleEvent(event, ...)
    local triggers = self.triggersByEvent[event]
    if not triggers then
        return
    end

    local ctx
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        ctx = ...
    else
        ctx = self:BuildContext(event, ...)
    end

    for _, trigger in ipairs(triggers) do
        if self:ShouldFireTrigger(trigger, ctx) then
            local message = self:BuildMessage(trigger, ctx)
            if message then
                self:SendMessage(message, self:GetOutputChannel(trigger), ctx)
            end
        end
    end
end
