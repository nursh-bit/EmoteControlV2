local _, EC = ...

function EC:CreateTriggerBuilder()
    if self.builderFrame then
        return
    end

    local frame = CreateFrame("Frame", "EmoteControlTriggerBuilder", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(420, 320)
    frame:SetPoint("CENTER")
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -8)
    frame.title:SetText("Emote Control Trigger Builder")

    local function createLabel(text, x, y)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", x, y)
        label:SetText(text)
        return label
    end

    local function createEditBox(x, y, width)
        local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        edit:SetAutoFocus(false)
        edit:SetSize(width or 260, 24)
        edit:SetPoint("TOPLEFT", x, y)
        return edit
    end

    createLabel("Event (e.g. PLAYER_LEVEL_UP)", 16, -40)
    frame.eventBox = createEditBox(16, -60, 360)

    createLabel("Message (use {player}, {zone}, {level}, etc)", 16, -96)
    frame.messageBox = createEditBox(16, -116, 360)

    createLabel("Chance (0-1)", 16, -152)
    frame.chanceBox = createEditBox(16, -172, 120)

    createLabel("Cooldown (seconds)", 180, -152)
    frame.cooldownBox = createEditBox(180, -172, 120)

    local addButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    addButton:SetSize(120, 24)
    addButton:SetPoint("BOTTOMLEFT", 16, 16)
    addButton:SetText("Add Trigger")

    addButton:SetScript("OnClick", function()
        local event = frame.eventBox:GetText() or ""
        local message = frame.messageBox:GetText() or ""
        if event == "" or message == "" then
            print("|cff00c8ff[EmoteControl]|r Event and message are required.")
            return
        end
        local chance = tonumber(frame.chanceBox:GetText() or "")
        local cooldown = tonumber(frame.cooldownBox:GetText() or "")

        local trigger = {
            id = "custom_" .. time(),
            event = event,
            messages = { message },
            chance = chance,
            cooldown = cooldown,
        }

        EC:AddCustomTrigger(trigger)
        frame.eventBox:SetText("")
        frame.messageBox:SetText("")
        frame.chanceBox:SetText("")
        frame.cooldownBox:SetText("")
    end)

    local closeButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    closeButton:SetSize(120, 24)
    closeButton:SetPoint("BOTTOMRIGHT", -16, 16)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    self.builderFrame = frame
end

function EC:ToggleTriggerBuilder()
    if InCombatLockdown() then
        print("|cff00c8ff[EmoteControl]|r Cannot open builder during combat.")
        return
    end
    self:CreateTriggerBuilder()
    if self.builderFrame:IsShown() then
        self.builderFrame:Hide()
    else
        self.builderFrame:Show()
    end
end

function EC:AddCustomTrigger(trigger)
    if not trigger or not trigger.event or not trigger.messages then
        return
    end
    table.insert(self.db.profile.customTriggers, trigger)
    self:RegisterCustomPack()
    self:BuildTriggerIndex()
    print("|cff00c8ff[EmoteControl]|r Added custom trigger.")
end
