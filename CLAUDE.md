# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Felix is a 3D memory card game (2-4 players) built in Godot 4.6 with Steam multiplayer. Players manage a 2×2 card grid, use special abilities, and try to end rounds with the lowest score. See [README.md](README.md) for game rules.

## Development Setup

- **Engine:** Godot 4.6 — open `project.godot` in the Godot editor
- **Steam:** Requires GodotSteam DLLs in the project root and `steam_appid.txt` containing `480`
- **Multiplayer testing:** Run two instances simultaneously with separate Steam accounts
- **Main game entry:** Launch directly from `scenes/main/game_table.tscn` to skip the menu

## Architecture

### Autoloads (Singletons)

| Autoload | Responsibility |
|---|---|
| `Events` | Global signal bus — all cross-component communication goes through here |
| `GameManager` | Master state machine (SETUP→DEALING→VIEWING→PLAYING→ABILITY_ACTIVE→KNOCKED→ROUND_END), turn tracking, player readiness |
| `AppFlow` | Scene navigation between launcher/game/multiplayer |
| `CardMeshLibrary` | GLB mesh + material cache (avoids reloading assets) |
| `SteamPlatformService` | Steam P2P wrapper |
| `FelixNetworkSession` | Multiplayer session lifecycle |
| `SteamRoomService` | Lobby operations |
| `SteamRoundService` | Round state sync via RPC |
| `SteamMovementService` | Player seating/positioning |
| `VoiceChatService` | Voice chat |

### Manager Pattern

`game_table.gd` is the orchestrator — it owns all sub-managers and passes itself via `init(game_table)`. Never add bulk logic to `game_table.gd`; delegate to focused managers:

- `dealing_manager.gd` — staggered deal animations
- `viewing_phase_manager.gd` — initial bottom-2-card reveal
- `turn_manager.gd` — draw/swap/discard flow, reshuffle
- `ability_manager.gd` — 7/8 (look own), 9/10 (look neighbor), Jack (blind swap), Queen (look+swap)
- `match_manager.gd` — right-click rank matching and penalty logic
- `knock_manager.gd` — knock button, final round tracking, end-of-round reveal
- `scoring_manager.gd` — score calculation + multi-round accumulation
- `bot_ai_manager.gd` — bot turn automation with penalty awareness
- `card_view_helper.gd` — view positions, rotations, neighbor detection

### Signal Bus Pattern

All cross-component communication uses `Events.gd`. Connect with:
```gdscript
Events.some_signal.connect(_on_some_signal)
```
Never emit signals directly between unrelated nodes — route through Events.

### Key Data Types

- `CardData` (Resource) — suit, rank, ability enum, scoring value
- `Player` — cards array, score, control type (HUMAN/BOT/REMOTE), ready/knocked flags
- `PlayerGrid` — 2×2 main slots + penalty overflow slots (up to 8 surrounding + stack)
- `SeatContext` — maps local seat index to game seat for multiplayer

### Table Layout Constants

- **Table surface Y:** 6.76 (baked into GLB mesh — don't change)
- **Grid positions:** ±6.5 Z for 4-player, ±3.5 Z for 2-player
- **Piles:** Draw at (−0.8, y, 0), Discard at (+0.8, y, 0)
- **Camera:** Radius 9.5, height 3.2 above surface

### Card Abilities

| Rank | Ability | Behavior |
|---|---|---|
| 7, 8 | LOOK_OWN | Peek at one of your own face-down cards |
| 9, 10 | LOOK_OPPONENT | Peek at a neighbor's card (neighbor-restricted) |
| Jack | BLIND_SWAP | Swap a card with a neighbor without looking |
| Queen | LOOK_AND_SWAP | Look at a neighbor's card, then optionally swap |

### Scoring

- Black King = −1, Red King = +25, Joker = 1, others = face value
- Penalty cards score separately (same rules)
- Multi-round: scores accumulate across rounds

## Key Conventions

- **Animations:** Use `create_tween()` — auto-cleaned up by Godot. Card flip is 0.4s EASE_OUT bounce.
- **Input locking:** `turn_manager` locks input during async operations; always unlock in the finally path.
- **Multiplayer seat mapping:** Use `GameManager.seat_contexts` to map local seat → game seat. Never hardcode seat 0 = local player.
- **Penalty slots:** When drawing a card or placing during abilities, check penalty slots first (`player_grid.has_penalty_cards()`).
- **Phase docs:** Detailed implementation history is in [.claude/](.claude/) — check `DevelopmentProgress.md` for current phase status.
