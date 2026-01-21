local _, EC = ...

EC.defaults = {
    profile = {
        enabled = true,
        outputEnabled = true,
        requireActivation = true,
        channel = "SAY",
        cooldown = 8,
        rateLimit = 6,
        debug = false,
        enablePacks = {},
        overrides = {},
        customTriggers = {},
    },
}
