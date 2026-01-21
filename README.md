# Emote Control

Event-driven WoW addon that watches game events and emits randomized, template-based chat messages.

## Features
- Event trigger packs with conditions, cooldowns, and rate limiting
- Tokenized messages (player/target/zone/spec/loot/etc.)
- UI options panel
- Custom trigger builder
- Import/export of overrides

## Slash Commands
- `/ec on` / `/ec off`
- `/ec channel <say|yell|party|raid|guild>`
- `/ec pack <packId> on|off`
- `/ec export` / `/ec import`
- `/ec builder`

## Tokens
- `{player}`, `{target}`, `{zone}`, `{subzone}`, `{class}`, `{race}`, `{spec}`
- `{time}`, `{date}`, `{level}`, `{achievement}`, `{loot}`, `{spell}`, `{source}`, `{dest}`
