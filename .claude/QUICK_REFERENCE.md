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
| **D** | Draw card (during your turn) |
| **SPACE** | Confirm ability / Flip all cards |
| **A** | Auto-ready all bots (viewing phase shortcut) |
| **Click Card** | Swap card (during turn) / View card (ability) |
| **Click Discard** | Use ability (Option A) |
| **F** | Camera shake |
| **Hover Card** | Card elevates |

## 📂 Project Structure
```
felix/
├── autoloads/           ← Global systems
│   ├── events.gd        ← Signal bus
│   └── game_manager.gd  ← State machine
├── scripts/             ← Core logic
│   ├── card_data.gd     ← Card definitions
│   ├── card_3d.gd       ← Card behavior ⭐
│   ├── player.gd        ← Player state
│   ├── deck_manager.gd  ← Deck operations
│   ├── camera_controller.gd
│   └── game_table.gd    ← Main controller
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

## 📝 Next Phase (Phase 6 - Fast Reaction Matching System)
- [ ] Drag-and-drop mechanic (hold to drag, release to match)
- [ ] Always-active matching (no time window)
- [ ] Match detection (rank matching against top discard)
- [ ] Own card matching (removes from deck)
- [ ] Opponent card matching (success/fail outcomes)
- [ ] Penalty card system (positioned around 2×2 grid)
- [ ] Visual feedback (drag cursor, error effects)
- [ ] One-match-per-update lock system
- [ ] Bot AI: Not in Phase 6 (future enhancement)

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
- **Q** = "Look and 2 Complete | **Version:** Dealing System  
**Ready to:** Deal cards and test multi-player
---

**Status:** Phase 0-1 Complete | **Version:** Foundation  
**Ready to:** Click cards and test animations!
