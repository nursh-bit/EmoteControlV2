local _, EC = ...

EC.defaults = {
    profile = {
        enabled = true,
        outputEnabled = true,
        requireActivation = true,
        channel = "SAY",
        cooldown = 8,
        cooldownChat = 8,
        cooldownEmote = 12,
        rateLimit = 6,
        rateWindowSeconds = 60,
        testChannel = "SAY",
        debug = false,
        onlyInGroup = false,
        onlyInRaid = false,
        onlyInInstance = false,
        onlyOutOfCombat = false,
        muteInCities = false,
        muteInInstances = false,
        enablePacks = {},
        overrides = {},
        customTriggers = {},
    },
}
