local _, EC = ...

function EC:OnPlayerLogin()
    self:InitializeUI()
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
        spellId = spellId,
        spellName = spellName,
        amount = amount,
    }

    self:HandleEvent("COMBAT_LOG_EVENT_UNFILTERED", ctx)
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
