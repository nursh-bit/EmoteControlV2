local _, EC = ...

EC:RegisterPack({
    id = "core",
    name = "Core Pack",
    triggers = {
        {
            id = "level_up",
            event = "PLAYER_LEVEL_UP",
            cooldown = 120,
            messages = {
                "Ding! {player} just hit level {level}.",
                "{player} leveled to {level}. Time to celebrate!",
            },
        },
        {
            id = "zone_change",
            event = "ZONE_CHANGED_NEW_AREA",
            cooldown = 60,
            messages = {
                "Now entering {zone}.",
                "{player} has arrived in {zone}.",
            },
        },
        {
            id = "achievement",
            event = "ACHIEVEMENT_EARNED",
            cooldown = 90,
            messages = {
                "Achievement unlocked: {achievement}!",
                "{player} earned {achievement}.",
            },
        },
        {
            id = "loot",
            event = "CHAT_MSG_LOOT",
            cooldown = 30,
            messages = {
                "Looted: {loot}",
                "Shiny! {loot}",
            },
            chance = 0.3,
        },
        {
            id = "player_death",
            event = "PLAYER_DEAD",
            cooldown = 120,
            messages = {
                "{player} has fallen in {zone}.",
                "RIP {player}.",
            },
        },
        {
            id = "cleu_kill",
            event = "COMBAT_LOG_EVENT_UNFILTERED",
            subEvent = "UNIT_DIED",
            requireTarget = false,
            cooldown = 45,
            chance = 0.2,
            messages = {
                "{dest} just died.",
                "Another one bites the dust: {dest}.",
            },
        },
    },
})
