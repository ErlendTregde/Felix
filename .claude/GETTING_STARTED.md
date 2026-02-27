# Getting Started with Felix Card Game

## 🚀 Quick Start

### Prerequisites
- **Godot Engine 4.5** or later ([Download here](https://godotengine.org/download))
- No additional dependencies required

### Opening the Project
1. Launch Godot Engine
2. Click **Import**
3. Navigate to this folder and select `project.godot`
4. Click **Import & Edit**

### First Run
1. In the Godot Editor, open [scenes/main/game_table.tscn](scenes/main/game_table.tscn) in the Scene panel
2. Press **F6** (or click the "Play Scene" button with the clapperboard icon)
3. The test scene will launch with 4 cards visible

## 🎮 Test Controls

| Input | Action |
|-------|--------|
| **ENTER** | Deal 4 cards to each player (with staggered animation) ⭐ |
| **1 / 2 / 3 / 4** | Change player count (resets game) ⭐ |
| **T** | Toggle test deck (7/8/9/10/Jack/Queen ability cards) ⭐ Phase 5 |
| **Y** | Toggle match test deck (only 7s and 8s) ⭐ Phase 6 |
| **D** | Draw card (during your turn) |
| **Left Click (card)** | Swap drawn card / select target for ability |
| **Right Click (card)** | Attempt match against discard pile (always active) \u2b50 Phase 6 |
| **Left Click (discard pile)** | Use ability (Option A - play drawn card to discard) |
| **SPACE** | Confirm ability viewing (after selecting target card) |
| **A** | Auto-ready all bots (viewing phase shortcut) |
| **F** | Trigger camera shake effect |

## 🧪 What You'll See

### Visual Elements
- **Green table surface** - The playfield
- **Draw pile (center-left)** - Stack of blue cards ready to deal
- **Discard pile (center-right)** - Empty at start
- **Player positions** - Marked around the table (2 players by default)

### Interactive Features
- **Press ENTER to deal** - Cards animate from draw pile to players
- **Dynamic player count** - Press 1-4 to change number of players
- **Hover Effect** - Cards elevate slightly when mouse hovers over them
- **Flip Animation** - Smooth 0.4s rotation with bounce
- **Highlight Effect** - Cyan glow appears after clicking a card (1 second duration)
- **Console Output** - Card information printed when clicked

### Dealing Animation
1. Press **ENTER** to start
2. Cards fly from draw pile to each player's grid
3. Each player receives 4 cards in a 2×2 layout
4. Dealing is staggered (0.15s between each card)
5. Draw pile count decreases as cards are dealt

### Expected Console Output
```
=== Felix Card Game - Game Table Ready ===
Felix Card Game - Event Bus initialized
Felix Card Game - GameManager initialized
DeckManager initialized
Created deck with 54 cards
Deck shuffled - 54 cards in draw pile

Press ENTER to deal cards
Press 1-4 to change player count
Press SPACE to flip all cards
Press F to shake camera

Setup Player 1 at position (0, 0.05, 3.5)
Setup Player 2 at position (0, 0.05, -3.5)
2 player(s) ready!

=== Dealing Cards to 2 Player(s) ===
PlayerGrid 0 initialized
Card initialized: 5♦
Card added to Player 0 grid position 0: 5♦
PlayerGrid 1 initialized
Card initialized: K♠
Card added to Player 1 grid position 0: K♠
...
Dealing complete! All players have 4 cards.
```

## 📂 Key Files to Explore

### Scripts (Core Logic)
- **18 script files** across autoloads/ and scripts/
- **game_table.gd** — Main orchestrator (input, setup, signal wiring, dispatch)
- **7 Manager scripts** (refactored from game_table.gd):
  - [scripts/card_view_helper.gd](scripts/card_view_helper.gd) — View positions, rotations, neighbor lookups
  - [scripts/dealing_manager.gd](scripts/dealing_manager.gd) — Card dealing with animation
  - [scripts/viewing_phase_manager.gd](scripts/viewing_phase_manager.gd) — Initial viewing phase
  - [scripts/turn_manager.gd](scripts/turn_manager.gd) — Turn flow, draw, swap, reshuffle
  - [scripts/ability_manager.gd](scripts/ability_manager.gd) — Human ability flows (7/8, 9/10, J, Q)
  - [scripts/bot_ai_manager.gd](scripts/bot_ai_manager.gd) — Bot turn logic + penalty card awareness
  - [scripts/match_manager.gd](scripts/match_manager.gd) — Fast reaction matching system
- [scripts/card_data.gd](scripts/card_data.gd) - Card properties and scoring rules
- [scripts/card_3d.gd](scripts/card_3d.gd) - Card behavior and animations
- [scripts/player.gd](scripts/player.gd) - Player state management
- [scripts/player_grid.gd](scripts/player_grid.gd) - 2×2 grid + penalty cards
- [scripts/deck_manager.gd](scripts/deck_manager.gd) - Deck operations
- [scripts/card_pile.gd](scripts/card_pile.gd) - Pile visuals
- [autoloads/events.gd](autoloads/events.gd) - Global signal bus
- [autoloads/game_manager.gd](autoloads/game_manager.gd) - Game state machine

### Scenes (Visual Elements)
- [scenes/main/game_table.tscn](scenes/main/game_table.tscn) - Main playfield ⭐ START HERE
- [scenes/cards/card_3d.tscn](scenes/cards/card_3d.tscn) - Card prefab (reusable)
- [scenes/main/camera_controller.tscn](scenes/main/camera_controller.tscn) - Fixed camera view

## 🛠️ Development Status

**Phase 6 is COMPLETE (including all bug fixes, code refactoring, and bot AI overhaul)!**

✅ **Implemented (Phases 0–6):**
- Card 3D representation with flip animations
- Deck creation and shuffling (54 cards)
- Basic interaction (click, hover, highlight)
- Multi-player setup (1-4 players)
- Dealing animation and grid system
- Initial viewing phase — cards lift side-by-side (Queen-ability style); bots auto-return after 2.5 s
- Turn system (draw + swap, bot AI)
- Special abilities (7/8, 9/10, Jack, Queen)
- Jack/Queen re-selection at both steps; SPACE confirmation before viewing
- Neighbor detection (physical seating based)
- Color-coded pulsing highlights per ability
- Card rotation fixed after swap
- Bot AI for all abilities
- Square 12×12 table, piles at ±0.8
- **Fast-reaction right-click matching (always active)**
- **Penalty card system (8 slots + overflow stacking)**
- **Give-card selection after matching opponent’s card**
- **Match test deck toggle (Y key)**
- **game_table.gd refactored into 7 focused manager scripts** (orchestrator pattern)
- **Bot AI overhauled** (penalty card awareness, all-slots search, ability fallback helpers)

🚧 **Coming Next (Phase 7):**
- Knocking mechanic (replaces drawing on your turn)
- Final round logic (everyone else gets one more turn)
- Score calculation and winner determination
- Phase 8: Visual polish
- Phase 9: Low-poly assets
- Phase 10: Menu system

## 🎯 Testing the Card System

### Test Different Cards
The deck is shuffled randomly, so each run will show different cards. Cards have special properties:

**Special Cards:**
- **Black King (K♣/K♠)** = -1 point
- **Red King (K♥/K♦)** = +25 points
- **Joker** = 1 point
- **7 or 8** = "Look at own card" ability
- **9 or 10** = "Look at opponent card" ability
- **Jack** = "Blind swap" ability
- **Queen** = "Look and swap" ability

### Check Card Info
Click any card and check the console output:
```
=== Card Clicked: 7♥ ===
  Score: 7
  Ability: LOOK_OWN
  Is face up: false
```

## 🐛 Troubleshooting
5. **Try changing player count** - See how grid positioning works
6. **Inspect dealing sequence** - Check [scripts/game_table.gd](scripts/game_table.gd) `deal_cards_to_all_players()`

### Cards Don't Appear
- Check Output panel (bottom) for errors
- Verify [scenes/cards/card_3d.tscn](scenes/cards/card_3d.tscn) exists
- Try restarting the scene (F6)

### Cards Are Invisible
- Materials may not be loading - check [resources/materials/](resources/materials/)
- Try viewing from different camera angle in editor

### Click Detection Not Working
- Ensure you're clicking the card mesh (not empty space)
- Check collision layers in Project Settings

### Console Shows Errors
- Most common: Path issues (file not found)
- Solution: Check file paths match exactly (case-sensitive on Linux/Mac)

## 📚 Next Steps

### For Developers
1. Review [README.md](README.md) for full development roadmap
2. Explore the codebase structure in [scripts/](scripts/)
3. Check out the event system in [autoloads/events.gd](autoloads/events.gd)
4. Read inline comments in scripts (every function documented)

### For Players
The game is not yet playable! This is a development prototype. Check back later for:
- Full 2-4 player gameplay
- Turn-based card mechanics
- Special abilities
- Scoring system
- UI and menus

## 💡 Tips

- **Press F1** in editor for Godot documentation
- **Ctrl+Shift+F** to search across all scripts
- **Remote Debug** tab shows live scene tree when running
- **Output panel** shows print statements and errors

## 🤝 Contributing

This is an active development project. Key areas for contribution:
- Card visual assets (low-poly 3D models or textures)
- Animation polish and "juice"
- Sound effects2 Complete (Foundation + Dealing
- UI/UX design
- Gameplay testing and balance

---

**Project Version:** Phase 5 Complete + Bug Fixes + Polish  
**Engine:** Godot 4.5 (Forward Plus)  
**Last Updated:** February 19, 2026
