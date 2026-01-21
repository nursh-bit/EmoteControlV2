local addonName, EC = ...
_G[addonName] = EC

EC.name = addonName
EC.version = "2.0.0"

EC.frame = CreateFrame("Frame")
EC.frame:Hide()

EC.frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            EC:Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        EC:OnPlayerLogin()
    else
        EC:OnEvent(event, ...)
    end
end)

EC.frame:RegisterEvent("ADDON_LOADED")
EC.frame:RegisterEvent("PLAYER_LOGIN")
