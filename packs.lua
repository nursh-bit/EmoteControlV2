local _, EC = ...

EC.packs = EC.packs or {}
EC.triggersByEvent = EC.triggersByEvent or {}

function EC:RegisterPack(pack)
    if not pack or not pack.id then
        return
    end
    self.packs[pack.id] = pack
    self:Debug("Registered pack", pack.id)
end

function EC:GetPackEnabled(packId)
    local enabled = self.db.profile.enablePacks[packId]
    if enabled == nil then
        return true
    end
    return enabled
end

function EC:BuildTriggerIndex()
    self.triggersByEvent = {}
    for packId, pack in pairs(self.packs) do
        if self:GetPackEnabled(packId) and type(pack.triggers) == "table" then
            for _, trigger in ipairs(pack.triggers) do
                trigger.packId = packId
                local event = trigger.event
                if event then
                    self.triggersByEvent[event] = self.triggersByEvent[event] or {}
                    table.insert(self.triggersByEvent[event], trigger)
                end
            end
        end
    end

    if self.RegisterTriggerEvents then
        self:RegisterTriggerEvents()
    end
end

function EC:RegisterCustomPack()
    local customPack = {
        id = "custom",
        name = "Custom Triggers",
        triggers = {},
    }

    for _, trigger in ipairs(self.db.profile.customTriggers) do
        table.insert(customPack.triggers, trigger)
    end

    self:RegisterPack(customPack)
end
