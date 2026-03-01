# 🎴 Felix Card Game - Quick Reference

## 🚀 Launch Instructions
1. Open Godot 4.5
2. Import project (`project.godot`)
3. Open `scenes/main/game_table.tscn`
4. Press **F6** to run

## 🎮 Test Controls
| Key | Action |
|-----|--------|
| **ENTER** | Deal cards to all players |
| **1/2/3/4** | Set player count (1-4) |
| **T** | Toggle test deck (7/8/9/10/Jack ability cards) ⭐ Phase 5 |
| **Y** | Toggle match test deck (only 7s and 8s) ⭐ Phase 6 |
| **D** | Draw card (during your turn) |
| **SPACE** | Confirm ability / Flip all cards |
| **A** | Auto-ready all bots (viewing phase shortcut) |
| **Click Card** | Swap card (during turn) / View card (ability) |
| **Right Click Card** | Match attempt against discard pile (always active) \u2b50 Phase 6 |
| **Click Discard** | Use ability (Option A) |
| **Click KNOCK button** | Knock instead of drawing (ends your turn) ⭐ Phase 8 |
| **F** | Camera shake |
| **Hover Card** | Card elevates |

## 📂 Project Structure
```
felix/
├── autoloads/           ← Global systems
│   ├── events.gd        ← Signal bus
│   └── game_manager.gd  ← State machine
├── scripts/             ← Core logic (18 files)
│   ├── card_data.gd     ← Card definitions
│   ├── card_3d.gd       ← Card behavior ⭐
│   ├── player.gd        ← Player state
│   ├── player_grid.gd   ← 2×2 grid + penalty cards
│   ├── deck_manager.gd  ← Deck operations
│   ├── card_pile.gd     ← Pile visuals
│   ├── game_table.gd    ← Main orchestrator (input, setup, dispatch)
│   ├── card_view_helper.gd  ← View positions, rotations, neighbors
│   ├── dealing_manager.gd   ← Card dealing animation
│   ├── viewing_phase_manager.gd ← Initial viewing phase
│   ├── turn_manager.gd      ← Turn flow, draw, swap, reshuffle
│   ├── ability_manager.gd   ← Human ability flows (7/8, 9/10, J, Q)
│   ├── bot_ai_manager.gd    ← Bot turn logic + penalty awareness
│   ├── match_manager.gd     ← Fast reaction matching system
│   ├── viewing_ui.gd        ← Viewing phase UI
│   ├── turn_ui.gd           ← Turn indicator UI
│   ├── swap_choice_ui.gd    ← Queen ability swap choice UI
│   └── camera_controller.gd ← Camera effects
├── scenes/
│   ├── main/
│   │   └── game_table.tscn  ← RUN THIS! ⭐⭐⭐
│   └── cards/
│       └── card_3d.tscn     ← Card prefab
└── resources/materials/     ← Card textures

```

## ✅ What's Working
- ✅ Card flip animations (smooth + bounce)
- ✅ Click interaction (raycast detection)
- ✅ Hover effects (card elevation)
- ✅ Highlight system (emissive glow)
- ✅ 54-card deck (shuffled)
- ✅ Event system (signal bus)
- ✅ State machine (7 states ready)
- ✅ Camera shake effect
- ✅ **Multi-player setup (1-4 players)**
- ✅ **Dealing animation (cards fly to grids)**
- ✅ **PlayerGrid system (2×2 layout)**
- ✅ **Draw pile visual (card stack)**
- ✅ **Discard pile (face-up cards)**
- ✅ **Initial viewing - side-by-side lift animation** (cards rise like Queen ability)
- ✅ **Bots visually view their cards** (lift → flip → auto-return after 2.5 s)
- ✅ **Human cards return on Ready press**
- ✅ **Turn system (draw + swap)**
- ✅ **Bot AI (automated turns)**
- ✅ **Test deck toggle (T key)**
- ✅ **7/8 Ability (look at own)**
- ✅ **9/10 Ability (look at neighbor only)** ← neighbor-restricted
- ✅ **Jack Ability (blind swap with neighbor)**
- ✅ **Jack/Queen Re-selection** at both steps
- ✅ **Queen SPACE confirmation** before viewing
- ✅ **Queen Ability (look and swap with choice UI)**
- ✅ **Bot AI for Abilities** ⭐ Phase 5 COMPLETE!
- ✅ **Unified Cyan Highlights** (bright pulse=targetable, dark solid=selected)
- ✅ **Highlight exact card size + inherits card rotation**
- ✅ **Full highlight cleanup** (queue_free on removal)
- ✅ **Square table (12×12)**
- ✅ **Piles centered (±0.8)**
- ✅ **Proactive FIFO reshuffle** (before turn, not mid-draw; verified with full game log)
- ✅ **Reshuffle arc animation** (up to 10 glowing ghost cards arc discard→draw)
- ✅ **Input locked during reshuffle** (`is_player_turn = false` at start of `start_next_turn()`)
- ✅ **Top discard card preserved** during reshuffle; 1-card edge case handled
- ✅ **Seat marker crash fixed** (`add_child` before `global_position`)
- ✅ **Right-click card matching** (always active; final mechanic — no drag-and-drop)
- ✅ **Opponent card match → give any card** (main grid or penalty card)
- ✅ **Penalty card system** (8 slots around 2×2 grid; 9th+ stacks with Y-offset)
- ✅ **Penalty card matching** (penalty cards are right-clickable)
- ✅ **One-match-per-update lock** (`match_claimed` until new discard)
- ✅ **Drawn card swaps penalty slot** (replaces at exact slot index)
- ✅ **Match test deck (Y key)** (52 cards of only 7s and 8s)
- ✅ **Give-card state lifecycle fixed** (`_unlock_matching` no longer resets `is_choosing_give_card`)
- ✅ **Deferred turn resume** (`give_card_needs_turn_start` flag)
- ✅ **Penalty card ownership** (explicit assignment + defensive fallback)
- ✅ **game_table.gd refactored into 7 manager scripts** (orchestrator pattern + init(table))
- ✅ **Bot AI overhauled** (penalty card awareness, all-slots search, ability fallback)
- ✅ **Knock action** (human click KNOCK button; bot random knock with low chance)
- ✅ **Final round** (all non-knockers get one more normal turn)
- ✅ **Round-end card reveal** (staggered flip animation)
- ✅ **Scoring** (main grid + penalty; Black King = −1, Red King = +25, Joker = 1)
- ✅ **Round end UI** (scores, winner, Play Again button)
- ✅ **Multi-round score tracking** (total_score persists across rounds)
- ✅ **Bot knock AI** (very low random chance, increases each turn)
- ✅ **KnockManager + ScoringManager** (clean separate scripts)

## 📝 Phase 9 — Visual Polish (In Progress)
- ✅ GLB table + chairs model (Sketchfab import, 45° rotation, radius 6.0)
- ✅ Bot character visuals (capsule + head, color-coded per seat)
- ✅ Card mesh scale (0.085 — fits placeholder rectangles)
- ✅ Amber-gold highlight (emission-only, no pulse/scale animation)
- ✅ UI overhaul (4 scenes rewritten — white text, no panel backgrounds)
- ✅ 3D discard label (Label3D billboard above pile, rank name)
- ✅ Card shininess fix (roughness ≥ 0.85, specular 0.15; spotlight 8 → 5)
- [ ] Particle effects (reveals, matches, abilities)
- [ ] Screen shake (knocking, penalties, matches)
- [ ] Celebration effects
- [ ] Sound effect hooks

## 🐛 Debug Tips
- Check **Output** panel for console logs
- **Remote** tab shows live scene tree
- Press **F1** in editor for docs
- Card info prints on click

## 📖 Documentation
- [README.md](README.md) - Full roadmap
- [GETTING_STARTED.md](GETTING_STARTED.md) - Detailed guide
- [IMPLEMENTATION.md](IMPLEMENTATION.md) - Technical details

## 🎯 Expected Console Output
```
=== Felix Card Game - Game Table Ready ===
Created deck with 54 cards
Deck shuffled - 54 cards in draw pile
=== Testing Card Spawn ===
Spawned card 1: 7♥ at (-0.8, 0, -0.5)
Spawned card 2: K♠ at (0.8, 0, -0.5)
...
Press SPACE to flip test cards
Press F to shake camera
```

## 🎨 Card System Features
```gdscript
# Flip card
card.flip()

# Highlight card
card.highlight(Color.CYAN)
card.remove_highlight()

# Move card
card.move_to(Vector3(0, 0, 0), 0.5)

# Get card info
print(card.card_data.get_short_name())  # "7♥"
print(card.card_data.get_score())       # 7
```

## 🔥 Special Cards
- **K♣/K♠** (Black King) = -1 point
- **K♥/K♦** (Red King) = +25 points
- **🃏** (Joker) = 1 point
- **7/8** = "Look at own card" ability
- **9/10** = "Look at opponent" ability
- **J** = "Blind swap" ability
- **Q** = "Look and swap" ability

---

**Status:** Phase 9 In Progress (Visual Polish) | **Next:** Particles, Screen Shake, Sound
