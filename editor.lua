local _, EC = ...

local frame
local selectedKey
local selectedItem

local function EnsureOverride(key)
    if not EC.db or not EC.db.profile then
        return nil
    end
    EC.db.profile.overrides = EC.db.profile.overrides or {}
    EC.db.profile.overrides[key] = EC.db.profile.overrides[key] or {}
    return EC.db.profile.overrides[key]
end

local function SplitLines(text)
    local lines = {}
    if type(text) ~= "string" then
        return lines
    end
    for line in text:gmatch("[^\r\n]+") do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            table.insert(lines, trimmed)
        end
    end
    return lines
end

local function JoinLines(lines)
    if type(lines) ~= "table" then
        return ""
    end
    return table.concat(lines, "\n")
end

local function MakeBackdrop(f)
    if not (f and f.SetBackdrop) then
        return
    end
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
end

local function CreateCycleButton(parent, labelText, items, onChanged)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetText(labelText)

    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(160, 22)
    button._items = items or {}
    button._value = ""
    button._onChanged = onChanged

    local function resolveLabel(value)
        for _, item in ipairs(button._items) do
            if item.value == value then
                return item.label
            end
        end
        return tostring(value or "")
    end

    function button:SetValue(value)
        button._value = value
        button:SetText(resolveLabel(value))
    end

    function button:GetValue()
        return button._value
    end

    button:SetScript("OnClick", function()
        local index = 1
        for i, item in ipairs(button._items) do
            if item.value == button._value then
                index = i
                break
            end
        end
        local nextIndex = index + 1
        if nextIndex > #button._items then
            nextIndex = 1
        end
        local nextItem = button._items[nextIndex]
        button:SetValue(nextItem.value)
        if button._onChanged then
            button._onChanged(nextItem.value)
        end
    end)

    return label, button
end

local function PrettyLabel(item)
    local trig = item.trig
    local parts = {}
    table.insert(parts, "[" .. tostring(item.packId or "") .. "]")
    if trig and trig.id then
        table.insert(parts, tostring(trig.id))
    end
    if trig and trig.category then
        table.insert(parts, tostring(trig.category))
    end
    if trig and trig.event then
        table.insert(parts, tostring(trig.event))
    end
    local spellName
    if trig and trig.conditions and (trig.conditions.spellName or trig.conditions.spell) then
        spellName = trig.conditions.spellName or trig.conditions.spell
    end
    if spellName then
        table.insert(parts, tostring(spellName))
    end
    return table.concat(parts, " ")
end

local function GetAllTriggersFiltered(search)
    local list = {}
    local s = (type(search) == "string" and search:lower()) or ""

    for packId, pack in pairs(EC.packs or {}) do
        if type(pack.triggers) == "table" then
            for idx, trig in ipairs(pack.triggers) do
                local rawId = trig.id or tostring(idx)
                local key = string.format("%s:%s", packId, rawId)
                local item = {
                    key = key,
                    id = rawId,
                    packId = packId,
                    trig = trig,
                }
                local label = PrettyLabel(item)
                item.label = label
                if s == "" or label:lower():find(s, 1, true) then
                    table.insert(list, item)
                end
            end
        end
    end

    table.sort(list, function(a, b)
        return a.key < b.key
    end)

    return list
end

local function RefreshDetails()
    if not frame then
        return
    end

    local trig = selectedItem and selectedItem.trig
    if not selectedKey or not trig then
        frame.detailsTitle:SetText("Select a trigger")
        frame.enabled:SetChecked(false)
        frame.cooldown:SetText("")
        frame.chance:SetText("")
        frame.channelButton:SetValue("")
        frame.messagesBox:SetText("")
        return
    end

    frame.detailsTitle:SetText(selectedKey .. "\n" .. PrettyLabel({ packId = selectedItem.packId or "", trig = trig }))

    local ov = EnsureOverride(selectedKey) or {}
    frame.enabled:SetChecked(ov.enabled ~= false)
    frame.cooldown:SetText(tostring(ov.cooldown or ""))
    frame.chance:SetText(tostring(ov.chance or ""))
    frame.channelButton:SetValue(ov.channel or "")

    local msgs = (type(ov.messages) == "table" and #ov.messages > 0) and ov.messages or trig.messages or {}
    frame.messagesBox:SetText(JoinLines(msgs))
end

local function BuildList()
    if not frame then
        return
    end

    local items = GetAllTriggersFiltered(frame.searchBox:GetText())
    frame._items = items

    FauxScrollFrame_Update(frame.scroll, #items, 14, 16)
    local offset = FauxScrollFrame_GetOffset(frame.scroll)

    for i = 1, 14 do
        local row = frame.rows[i]
        local idx = offset + i
        local item = items[idx]

        if item then
            row:Show()
            row.item = item
            row.text:SetText(item.key)
            row.sub:SetText(item.label)
            if selectedKey == item.key then
                row.highlight:Show()
                row.bg:SetColorTexture(0.15, 0.2, 0.3, 0.8)
            else
                row.highlight:Hide()
                row.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
            end
        else
            row:Hide()
        end
    end

    local selectedVisible = false
    if selectedKey then
        for i = 1, 14 do
            local item = items[offset + i]
            if item and item.key == selectedKey then
                selectedVisible = true
                break
            end
        end
    end

    if not selectedVisible then
        local first = items[offset + 1]
        if first then
            selectedKey = first.key
            selectedItem = first
            RefreshDetails()
        end
    end
end

function EC:OpenTriggerEditor()
    if InCombatLockdown and InCombatLockdown() then
        print("|cff00c8ff[EmoteControl]|r Cannot open editor during combat.")
        return
    end

    if frame and frame:IsShown() then
        frame:Hide()
        return
    end

    if not frame then
        frame = CreateFrame("Frame", "EmoteControlEditorFrame", UIParent, "BackdropTemplate")
        frame:SetSize(860, 540)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        MakeBackdrop(frame)

        local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -12)
        title:SetText("Emote Control - Trigger Editor")

        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)

        local searchLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        searchLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
        searchLabel:SetText("Search")

        local searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        searchBox:SetSize(260, 20)
        searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
        searchBox:SetAutoFocus(false)
        searchBox:SetScript("OnTextChanged", function()
            BuildList()
        end)
        frame.searchBox = searchBox

        local leftPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        leftPane:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -10)
        leftPane:SetSize(400, 430)
        MakeBackdrop(leftPane)

        local scroll = CreateFrame("ScrollFrame", "EmoteControlEditorScroll", leftPane, "FauxScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 0, -6)
        scroll:SetPoint("BOTTOMRIGHT", -28, 6)
        scroll:SetScript("OnVerticalScroll", function(self, offset)
            FauxScrollFrame_OnVerticalScroll(self, offset, 16, BuildList)
        end)
        frame.scroll = scroll

        frame.rows = {}
        for i = 1, 14 do
            local row = CreateFrame("Button", nil, leftPane)
            row:SetSize(370, 24)
            row:SetPoint("TOPLEFT", 4, -6 - (i - 1) * 28)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
            row.bg = bg

            local highlight = row:CreateTexture(nil, "ARTWORK")
            highlight:SetSize(3, 24)
            highlight:SetPoint("LEFT", row, "LEFT", 0, 0)
            highlight:SetColorTexture(0.2, 0.6, 1.0, 0.8)
            highlight:Hide()
            row.highlight = highlight

            local text = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            text:SetPoint("TOPLEFT", 10, -2)
            text:SetText("")
            row.text = text

            local sub = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            sub:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -1)
            sub:SetText("")
            sub:SetTextColor(0.8, 0.8, 0.8, 0.7)
            row.sub = sub

            row:SetScript("OnClick", function(self)
                if self.item then
                    selectedKey = self.item.key
                    selectedItem = self.item
                    RefreshDetails()
                    BuildList()
                end
            end)

            row:SetScript("OnEnter", function(self)
                if not self.item or selectedKey == self.item.key then
                    return
                end
                bg:SetColorTexture(0.15, 0.15, 0.15, 0.7)
            end)

            row:SetScript("OnLeave", function(self)
                if not self.item or selectedKey == self.item.key then
                    return
                end
                bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
            end)

            frame.rows[i] = row
        end

        local rightPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        rightPane:SetPoint("TOPLEFT", leftPane, "TOPRIGHT", 8, 0)
        rightPane:SetPoint("BOTTOMRIGHT", -16, 16)
        MakeBackdrop(rightPane)

        local detailsTitle = rightPane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        detailsTitle:SetPoint("TOPLEFT", 10, -10)
        detailsTitle:SetWidth(420)
        detailsTitle:SetJustifyH("LEFT")
        detailsTitle:SetText("Select a trigger")
        frame.detailsTitle = detailsTitle

        local enabled = CreateFrame("CheckButton", nil, rightPane, "UICheckButtonTemplate")
        enabled:SetPoint("TOPLEFT", detailsTitle, "BOTTOMLEFT", -2, -10)
        enabled.Text:SetText("Enabled")
        frame.enabled = enabled

        local cdLabel = rightPane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        cdLabel:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 2, -10)
        cdLabel:SetText("Cooldown override (seconds)")

        local cooldown = CreateFrame("EditBox", nil, rightPane, "InputBoxTemplate")
        cooldown:SetSize(80, 20)
        cooldown:SetPoint("LEFT", cdLabel, "RIGHT", 10, 0)
        cooldown:SetAutoFocus(false)
        cooldown:SetNumeric(true)
        frame.cooldown = cooldown

        local chanceLabel = rightPane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        chanceLabel:SetPoint("TOPLEFT", cdLabel, "BOTTOMLEFT", 0, -12)
        chanceLabel:SetText("Chance override (0-1)")

        local chance = CreateFrame("EditBox", nil, rightPane, "InputBoxTemplate")
        chance:SetSize(80, 20)
        chance:SetPoint("LEFT", chanceLabel, "RIGHT", 10, 0)
        chance:SetAutoFocus(false)
        chance:SetNumeric(true)
        frame.chance = chance

        local channelItems = {
            { label = "(use trigger)", value = "" },
            { label = "Party", value = "PARTY" },
            { label = "Raid", value = "RAID" },
            { label = "Instance", value = "INSTANCE" },
            { label = "Say", value = "SAY" },
            { label = "Yell", value = "YELL" },
            { label = "Emote", value = "EMOTE" },
            { label = "Guild", value = "GUILD" },
        }

        local channelLabel, channelButton = CreateCycleButton(rightPane, "Channel override", channelItems)
        channelLabel:SetPoint("TOPLEFT", chanceLabel, "BOTTOMLEFT", 0, -14)
        channelButton:SetPoint("LEFT", channelLabel, "RIGHT", 12, 0)
        channelButton:SetValue("")
        frame.channelButton = channelButton

        local msgLabel = rightPane:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        msgLabel:SetPoint("TOPLEFT", channelLabel, "BOTTOMLEFT", 0, -16)
        msgLabel:SetText("Phrases (one per line)")

        local boxFrame = CreateFrame("Frame", nil, rightPane, "BackdropTemplate")
        boxFrame:SetPoint("TOPLEFT", msgLabel, "BOTTOMLEFT", 0, -6)
        boxFrame:SetPoint("BOTTOMRIGHT", -10, 54)
        MakeBackdrop(boxFrame)

        local scrollMsg = CreateFrame("ScrollFrame", "EmoteControlEditorMsgScroll", boxFrame, "UIPanelScrollFrameTemplate")
        scrollMsg:SetPoint("TOPLEFT", 6, -6)
        scrollMsg:SetPoint("BOTTOMRIGHT", -26, 6)

        local edit = CreateFrame("EditBox", nil, scrollMsg)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(360)
        edit:SetText("")
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scrollMsg:SetScrollChild(edit)
        frame.messagesBox = edit

        local save = CreateFrame("Button", nil, rightPane, "UIPanelButtonTemplate")
        save:SetSize(120, 22)
        save:SetPoint("BOTTOMLEFT", 10, 16)
        save:SetText("Save")
        save:SetScript("OnClick", function()
            if not selectedKey or not selectedItem then
                return
            end

            local ov = EnsureOverride(selectedKey)
            if not ov then
                return
            end

            ov.enabled = enabled:GetChecked() and true or false

            local cd = tonumber(cooldown:GetText())
            if cd and cd > 0 then
                ov.cooldown = cd
            else
                ov.cooldown = nil
            end

            local ch = channelButton:GetValue()
            if type(ch) == "string" and ch ~= "" then
                ov.channel = EC:NormalizeChannel(ch)
            else
                ov.channel = nil
            end

            local chanceValue = tonumber(chance:GetText())
            if chanceValue and chanceValue > 0 then
                ov.chance = EC:Clamp(chanceValue, 0.01, 1)
            else
                ov.chance = nil
            end

            local lines = SplitLines(edit:GetText())
            if #lines > 0 then
                ov.messages = lines
            else
                ov.messages = nil
            end

            print("|cff00c8ff[EmoteControl]|r Saved override for " .. selectedKey)
            RefreshDetails()
        end)

        local reset = CreateFrame("Button", nil, rightPane, "UIPanelButtonTemplate")
        reset:SetSize(120, 22)
        reset:SetPoint("LEFT", save, "RIGHT", 10, 0)
        reset:SetText("Reset")
        reset:SetScript("OnClick", function()
            if not selectedKey then
                return
            end
            local db = EC.db and EC.db.profile
            if not db or type(db.overrides) ~= "table" then
                return
            end
            db.overrides[selectedKey] = nil
            RefreshDetails()
        end)

        frame:SetScript("OnShow", function()
            BuildList()
            RefreshDetails()
        end)
    end

    frame:Show()
    BuildList()
    RefreshDetails()
end