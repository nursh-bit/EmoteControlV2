local _, EC = ...

local function CreateCheckbox(parent, label, tooltip, onChanged)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check.text = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    check.text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    check.text:SetText(label)
    check.tooltipText = tooltip
    check:SetScript("OnClick", function(self)
        onChanged(self:GetChecked())
    end)
    return check
end

local function CreateDropdown(parent, label, items, onChanged)
    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetText(label)
    title:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 16, 20)

    UIDropDownMenu_Initialize(dropdown, function(frame, level)
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dropdown, item)
                onChanged(item)
            end
            info.value = item
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    return dropdown
end

function EC:CreateOptionsPanel()
    local container = rawget(_G, "InterfaceOptionsFramePanelContainer") or UIParent
    local panel = CreateFrame("Frame", "EmoteControlOptions", container)
    panel.name = "Emote Control"

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Emote Control")

    local enabledCheck = CreateCheckbox(panel, "Enable addon", "Toggle Emote Control", function(value)
        self.db.profile.enabled = value
    end)
    enabledCheck:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)

    local outputCheck = CreateCheckbox(panel, "Enable output", "Allow automated messages", function(value)
        self.db.profile.outputEnabled = value
        self.userActivated = true
    end)
    outputCheck:SetPoint("TOPLEFT", enabledCheck, "BOTTOMLEFT", 0, -8)

    local debugCheck = CreateCheckbox(panel, "Debug output", "Print debug information", function(value)
        self.db.profile.debug = value
    end)
    debugCheck:SetPoint("TOPLEFT", outputCheck, "BOTTOMLEFT", 0, -8)

    local channelDropdown = CreateDropdown(panel, "Output channel", { "SAY", "YELL", "PARTY", "RAID", "GUILD", "EMOTE", "INSTANCE" }, function(value)
        self.db.profile.channel = value
    end)
    channelDropdown:SetPoint("TOPLEFT", debugCheck, "BOTTOMLEFT", -16, -24)

    local cooldownSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    cooldownSlider:SetPoint("TOPLEFT", channelDropdown, "BOTTOMLEFT", 24, -32)
    cooldownSlider:SetMinMaxValues(2, 60)
    cooldownSlider:SetValueStep(1)
    cooldownSlider:SetObeyStepOnDrag(true)
    local cooldownLabel = cooldownSlider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cooldownLabel:SetPoint("TOP", cooldownSlider, "BOTTOM", 0, -2)
    cooldownLabel:SetText("Global cooldown (seconds)")
    cooldownSlider:SetScript("OnValueChanged", function(_, value)
        self.db.profile.cooldown = math.floor(value)
    end)

    local rateSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    rateSlider:SetPoint("TOPLEFT", cooldownSlider, "BOTTOMLEFT", 0, -40)
    rateSlider:SetMinMaxValues(1, 20)
    rateSlider:SetValueStep(1)
    rateSlider:SetObeyStepOnDrag(true)
    local rateLabel = rateSlider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rateLabel:SetPoint("TOP", rateSlider, "BOTTOM", 0, -2)
    rateLabel:SetText("Rate limit per minute")
    rateSlider:SetScript("OnValueChanged", function(_, value)
        self.db.profile.rateLimit = math.floor(value)
    end)

    local builderButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    builderButton:SetSize(160, 24)
    builderButton:SetPoint("TOPLEFT", rateSlider, "BOTTOMLEFT", -20, -28)
    builderButton:SetText("Open Trigger Builder")
    builderButton:SetScript("OnClick", function()
        self.userActivated = true
        self:ToggleTriggerBuilder()
    end)

    local testButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    testButton:SetSize(140, 24)
    testButton:SetPoint("LEFT", builderButton, "RIGHT", 12, 0)
    testButton:SetText("Test Output")
    testButton:SetScript("OnClick", function()
        self.userActivated = true
        local ctx = self:BuildContext("TEST")
        local message = self:FormatMessage("EmoteControl test: {player} in {zone} at {time}", ctx)
        self:SendMessage(message, self.db.profile.channel, ctx)
    end)

    local packTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    packTitle:SetPoint("TOPLEFT", builderButton, "BOTTOMLEFT", 0, -18)
    packTitle:SetText("Packs")

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", packTitle, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetSize(360, 140)

    local packList = CreateFrame("Frame", nil, scrollFrame)
    packList:SetSize(340, 140)
    scrollFrame:SetScrollChild(packList)
    self.packList = packList
    self.packChecks = {}

    local function buildPackList()
        for _, check in ipairs(self.packChecks) do
            check:Hide()
        end
        self.packChecks = {}

        local ids = {}
        for packId in pairs(self.packs or {}) do
            table.insert(ids, packId)
        end
        table.sort(ids)

        local y = -4
        for _, packId in ipairs(ids) do
            local pack = self.packs[packId]
            local label = pack and pack.name or packId
            local check = CreateCheckbox(packList, label .. " (" .. packId .. ")", "Enable/disable this pack", function(value)
                self.db.profile.enablePacks[packId] = value
                self:BuildTriggerIndex()
                self.userActivated = true
            end)
            check:SetPoint("TOPLEFT", 4, y)
            check:SetChecked(self:GetPackEnabled(packId))
            table.insert(self.packChecks, check)
            y = y - 20
        end
        packList:SetHeight(math.max(140, -y + 8))
    end

    panel.refresh = function()
        enabledCheck:SetChecked(self.db.profile.enabled)
        outputCheck:SetChecked(self.db.profile.outputEnabled)
        debugCheck:SetChecked(self.db.profile.debug)
        UIDropDownMenu_SetSelectedValue(channelDropdown, self.db.profile.channel)
        cooldownSlider:SetValue(self.db.profile.cooldown)
        rateSlider:SetValue(self.db.profile.rateLimit)
        buildPackList()
    end

    -- WoW 11.0+: Use new Settings API if available, fallback to old InterfaceOptions
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "Emote Control")
        Settings.RegisterAddOnCategory(category)
        self.optionsCategory = category
    elseif rawget(_G, "InterfaceOptions_AddCategory") then
        rawget(_G, "InterfaceOptions_AddCategory")(panel)
    end
    
    self.optionsPanel = panel
end

function EC:ShowExportFrame(data)
    if not self.exportFrame then
        local frame = CreateFrame("Frame", "EmoteControlExport", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(420, 260)
        frame:SetPoint("CENTER")
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        frame.title:SetPoint("TOP", 0, -8)
        frame.title:SetText("Emote Control Export")

        local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetSize(380, 180)
        editBox:SetPoint("TOP", 0, -40)
        editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
        frame.editBox = editBox

        self.exportFrame = frame
    end

    self.exportFrame.editBox:SetText(data or "")
    self.exportFrame.editBox:HighlightText()
    self.exportFrame:Show()
end

function EC:ShowImportFrame()
    if not self.importFrame then
        local frame = CreateFrame("Frame", "EmoteControlImport", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(420, 280)
        frame:SetPoint("CENTER")
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        frame.title:SetPoint("TOP", 0, -8)
        frame.title:SetText("Emote Control Import")

        local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetSize(380, 180)
        editBox:SetPoint("TOP", 0, -40)
        editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
        frame.editBox = editBox

        local button = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
        button:SetSize(120, 24)
        button:SetPoint("BOTTOM", 0, 16)
        button:SetText("Import")
        button:SetScript("OnClick", function()
            local payload = frame.editBox:GetText() or ""
            local ok, err = self:ImportOverrides(payload)
            if ok then
                print("|cff00c8ff[EmoteControl]|r Import complete")
                frame:Hide()
            else
                print("|cff00c8ff[EmoteControl]|r Import failed:", err)
            end
        end)

        self.importFrame = frame
    end

    self.importFrame.editBox:SetText("")
    self.importFrame:Show()
end

function EC:InitializeUI()
    self:CreateOptionsPanel()
end
