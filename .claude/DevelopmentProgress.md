# Felix Card Game - Development Progress

## 🎴 Project Overview
A strategic 3D memory card game for 2-4 players built in Godot 4.5, featuring low-poly aesthetics with juicy game feel.

## ✅ Completed (Phase 0-8)

### Core Architecture
- ✅ **Event Bus System** ([autoloads/events.gd](autoloads/events.gd)) - Global signal system for decoupled communication
- ✅ **Game Manager** ([autoloads/game_manager.gd](autoloads/game_manager.gd)) - State machine and round controller
- ✅ **Card Data Resource** ([scripts/card_data.gd](scripts/card_data.gd)) - Card properties, scoring, and abilities
- ✅ **Player Class** ([scripts/player.gd](scripts/player.gd)) - Player state and hand management
- ✅ **Deck Manager** ([scripts/deck_manager.gd](scripts/deck_manager.gd)) - 54-card deck with shuffle/deal

### 3D Scene Foundation  
- ✅ **Card3D Scene** ([scenes/cards/card_3d.tscn](scenes/cards/card_3d.tscn)) - 3D card with flip animation
- ✅ **Card3D Script** ([scripts/card_3d.gd](scripts/card_3d.gd)) - Interaction, animation, highlighting
- ✅ **Camera Controller** ([scenes/main/camera_controller.tscn](scenes/main/camera_controller.tscn)) - Fixed perspective with shake
- ✅ **Game Table Scene** ([scenes/main/game_table.tscn](scenes/main/game_table.tscn)) - Main playfield with position markers
- ✅ **Game Table Script** ([scripts/game_table.gd](scripts/game_table.gd)) - Main orchestrator (input, setup, dispatch)

### Manager Scripts (Refactored from game_table.gd)
- ✅ **CardViewHelper** ([scripts/card_view_helper.gd](scripts/card_view_helper.gd)) - View positions, rotations, neighbor lookups, seat markers
- ✅ **DealingManager** ([scripts/dealing_manager.gd](scripts/dealing_manager.gd)) - Card dealing with staggered animation
- ✅ **ViewingPhaseManager** ([scripts/viewing_phase_manager.gd](scripts/viewing_phase_manager.gd)) - Initial viewing phase (bottom 2 cards, ready system)
- ✅ **TurnManager** ([scripts/turn_manager.gd](scripts/turn_manager.gd)) - Turn flow, drawing, swapping, discard, pile reshuffling
- ✅ **AbilityManager** ([scripts/ability_manager.gd](scripts/ability_manager.gd)) - All 4 human ability flows
- ✅ **BotAIManager** ([scripts/bot_ai_manager.gd](scripts/bot_ai_manager.gd)) - Bot turn logic, ability decisions, penalty card support
- ✅ **MatchManager** ([scripts/match_manager.gd](scripts/match_manager.gd)) - Fast reaction matching, give-card, penalty system
- ✅ **KnockManager** ([scripts/knock_manager.gd](scripts/knock_manager.gd)) - Knock action, final round tracking, round-end card reveal
- ✅ **ScoringManager** ([scripts/scoring_manager.gd](scripts/scoring_manager.gd)) - Score calculation, winner determination, multi-round tracking

### Player Grid System (Phase 2)
- ✅ **PlayerGrid Scene** ([scenes/players/player_grid.tscn](scenes/players/player_grid.tscn)) - Reusable 2×2 card grid
- ✅ **PlayerGrid Script** ([scripts/player_grid.gd](scripts/player_grid.gd)) - Grid layout and card management
- ✅ **CardPile Scene** ([scenes/cards/card_pile.tscn](scenes/cards/card_pile.tscn)) - Visual card stack
- ✅ **CardPile Script** ([scripts/card_pile.gd](scripts/card_pile.gd)) - Draw/discard pile visuals
- ✅ **Multi-player Setup** - Dynamic 1-4 player configuration
- ✅ **Dealing Animation** - Cards animate from center to player grids with stagger

### Initial Viewing Phase (Phase 3)
- ✅ **Viewing UI** ([scenes/ui/viewing_ui.tscn](scenes/ui/viewing_ui.tscn)) - Memorization phase interface
- ✅ **Bottom 2 Cards Reveal** - Players can view their bottom row cards
- ✅ **Ready System** - Players press Ready button when done memorizing
- ✅ **All-Player Ready Check** - Game progresses when all players ready
- ✅ **Simultaneous Viewing** - All players view at once (not sequential)

### Turn System (Phase 4)
- ✅ **Turn UI** ([scenes/ui/turn_ui.tscn](scenes/ui/turn_ui.tscn)) - Turn indicator and instructions
- ✅ **Draw Mechanic** - Press D to draw a card from draw pile
- ✅ **Swap Action** - Click one of your cards to replace it with drawn card
- ✅ **Bot AI** - Automated turns for computer players (random selection)
- ✅ **Turn Progression** - Cycles through all players in order
- ✅ **Position-Based Card Viewing** - Drawn cards tilt toward player's position
- ✅ **Discard Animation** - Old cards move to discard pile when swapped
- ✅ **Discard Pile Interaction** - Click pile to use abilities (Option A vs Option B)
- ✅ **FIFO Reshuffle** - Draw pile refills from discard maintaining order

### Special Abilities (Phase 5 - COMPLETE!)
- ✅ **Test Deck Toggle** - Press T for ability-focused deck (7/8/9/10/Jack/Queen)
- ✅ **Interactive Discard Pile** - Hover effect, click detection, placeholder rectangle
- ✅ **7/8 Ability** - Look at one of your own cards
- ✅ **9/10 Ability** - Look at one neighbor's card (neighbor-only restriction enforced)
- ✅ **Jack Ability** - Blind swap with neighbor (complete with visual feedback)
- ✅ **Queen Ability** - Look at own + neighbor card, choose to swap or not
- ✅ **Card Viewing Animation** - Consistent position and angle for all viewed cards
- ✅ **Grid Placeholders** - White outline rectangles at all card positions
- ✅ **Neighbor Detection** - Physical seating-based neighbor logic for all player counts
- ✅ **Elevation Lock System** - Scoped locking prevents hover interference during abilities
- ✅ **Swap Choice UI** - Dedicated UI for Queen ability swap/don't swap decision
- ✅ **Bot AI for Abilities** - Bots use abilities with random targeting and decisions
- ✅ **Color-Coded Highlights** - Unified cyan for all targetable cards; darker cyan for selected/confirmed card
- ✅ **Pulsing Highlight Animation** - Breathing glow effect; solid for selected cards
- ✅ **Highlight Exact Card Size** - Overlay matches card face dimensions exactly and inherits card rotation
- ✅ **Highlight Cleanup** - Full queue_free on removal (no lingering nodes)
- ✅ **Jack/Queen Re-selection** - Click same ownership-type card to change selection at either step
- ✅ **Queen SPACE Confirmation** - Both cards selected → press SPACE to proceed to viewing (mirrors Jack flow)
- ✅ **Queen Side-by-Side Direction** - Cards spread correctly (perpendicular to view direction) for all 4 player seats

### Phase 5 Bug Fixes & Polish
- ✅ **Initial Viewing Phase Lift Animation** - Cards animate up side-by-side (like Queen ability) instead of simple in-place flip
- ✅ **Bots Visually View Cards** - All bots lift, flip, and return their bottom cards; auto-ready after 2.5 s
- ✅ **Human Card Return on Ready** - Pressing Ready animates cards back before marking ready
- ✅ **Square Table** - Table mesh changed to 12×12 (was 12×8)
- ✅ **Piles Moved to Center** - Draw pile at x=−0.8, Discard pile at x=+0.8 (was ±2.0)
- ✅ **Player-Indexed View Helpers** - `get_card_view_position_for(idx)`, `get_card_view_rotation_for(idx)`, `get_card_view_sideways_for(idx)` enable per-player animations

### Phase 5 Reshuffle Overhaul & Fixes
- ✅ **Seat Marker Crash Fixed** - `create_seat_markers()` now calls `add_child()` before setting `global_position` (was causing 37 `is_inside_tree()` errors)
- ✅ **Proactive Reshuffle** - Reshuffle now happens at the START of `start_next_turn()` before any input is enabled (was mid-draw inside `deal_card()`)
- ✅ **Top Card Preserved** - `perform_reshuffle()` keeps the newest discard card visible; only older cards transfer to draw pile
- ✅ **FIFO Reshuffle Verified** - Full 54-card game confirmed: first card ever discarded (`9♦`) was first card drawn after the 37-card reshuffle
- ✅ **1-Card Edge Case Fixed** - `can_reshuffle()` now allows size ≥ 1; lone discard card moves to draw pile instead of silently breaking the turn
- ✅ **Input Lockout During Reshuffle** - `is_player_turn = false` + draw pile disabled at the very top of `start_next_turn()` before the reshuffle await; prevents D key / pile click during animation
- ✅ **Dramatic Reshuffle Animation** - Up to 10 glowing blue `BoxMesh` ghost cards arc from discard to draw pile with 0.07 s stagger

### Materials
- ✅ Card front material (placeholder - white)
- ✅ Card back material (placeholder - blue)

## 📜 Game Rules & Mechanics

### Setup
- 2-4 players sit around a table
- 54-card deck (52 standard + 2 jokers)
- Each player receives 4 cards face-down in a 2×2 grid
- Remaining cards form the **draw pile** (left side of table)
- Empty **discard pile** (right side of table)

### Initial Viewing Phase
1. All players simultaneously flip their **bottom 2 cards** to memorize them
2. Players press **"I'm Ready"** when done memorizing
3. When all players ready, cards flip back face-down
4. Game begins with Player 1's turn

### Turn Structure (Each Player's Turn)
1. **Draw a card** from the draw pile (press D)
   - Card animates to player's position
   - Card briefly shows face-up, tilted toward player
2. **Choose an action:**
   - Click one of your 4 cards to **swap** it with the drawn card
   - The old card moves to discard pile **(face-up)**
   - The new card takes its place **(face-down)**
3. Turn passes to next player

### Draw Pile & Discard Pile Rules
- **Draw Pile (Left):**
  - Cards face-down
  - Visually stacks up (taller pile = more cards)
  - Players draw from top of this pile
  - When empty, refill from discard pile

- **Discard Pile (Right):**
  - Cards **face-up** (top card visible to all)
  - Visually stacks up as cards are discarded
  - Shows the card that was most recently swapped

- **Reshuffle Rule:**
  - When draw pile becomes empty:
  - All cards from discard pile transfer to draw pile
  - **Cards maintain their order** (FIFO - First In, First Out)
  - First card discarded becomes first card to draw
  - Animated transfer with stacking effect
  - No shuffling occurs (preserves discard order)

### Bot Behavior
- Computer players automatically take turns
- 1 second "thinking" delay
- Randomly selects one of their 4 cards to swap
- Follows same rules as human players

### Card Ownership
- Each card in a player's grid "belongs" to that player
- Players can only swap their own cards during their turn
- Cards retain ownership even after being swapped in

### Visual Feedback
- **Current Turn:** UI shows whose turn it is
- **Action Prompt:** Instructions displayed (e.g., "Press D to draw")
- **Card Animation:** Drawn cards tilt toward their player's seat
- **Pile Heights:** Draw/discard piles grow/shrink based on card count
- **Discard Visibility:** Top card of discard shows its face (color/rank)

## 🎮 Testing the Current Build

### How to Run
1. Open project in Godot 4.5
2. Run the `game_table.tscn` scene (F5 or F6)
3. You should see:
   - Green table surface
   - Draw pile at center-left (stack of blue cards)
   - Empty discard pile at center-right
   - No cards on table yet

### Test Controls
**Setup Phase:**
- **1/2/3/4** - Change player count (1-4 players)
- **ENTER** - Deal 4 cards to each player (with animation!)
- **T** - Toggle test mode (deck with only 7/8/9/10/Jack/Queen ability cards)
- **Y** - Toggle match test mode (deck with only 7s and 8s)

**Viewing Phase:**
- **Ready Button** - Click to mark yourself ready
- **A** - Auto-ready all other players (testing shortcut)

**Playing Phase (Your Turn):**
- **D** - Draw a card from the draw pile
- **Left-click a card** - Swap the clicked card with your drawn card (Option B)
- **Right-click a card** - Attempt fast-reaction match against discard pile (always active)
- **Click discard pile** - Use ability of drawn card (Option A)
- **SPACE** - Confirm ability viewing (after selecting target card)

**Debug/Testing:**
- **SPACE** - Flip all cards simultaneously (when not in ability mode)
- **F** - Trigger camera shake effect
- **Click any card (outside turn)** - Flip card + see info in console

### Expected Behavior (Full Game Flow)
1. **Setup:** Press **1-4** to choose player count
2. **Dealing:** Press **ENTER** to start dealing
   - Watch cards animate from draw pile to player positions
   - Each player gets 4 cards in a 2×2 grid (face-down)
   - Players positioned around table:
     - Player 1: South (bottom, facing north) - Human player
     - Player 2: North (top, facing south) - Bot
     - Player 3: West (left, facing east) - Bot
     - Player 4: East (right, facing west) - Bot
3. **Viewing Phase:**
   - Bottom 2 cards flip face-up for all players
   - Click **"I'm Ready"** button when done memorizing
   - Press **A** to auto-ready bots (testing shortcut)
   - Cards flip back face-down when all ready
4. **Turn System:**
   - Player 1 (you) goes first
   - Press **D** to draw a card (animates from draw pile)
   - Card shows face-up, tilted toward you
   - Click one of your 4 grid cards to swap
   - Old card moves to discard pile (face-up)
   - New card takes its place (face-down)
   - Bot players auto-play their turns (1s delay)
   - Repeat for each player in turn order

### Expected Console Output
```
=== Felix Card Game - Game Table Ready ===
DeckManager initialized
Created deck with 54 cards
Deck shuffled - 54 cards in draw pile

Press ENTER to deal cards
Press 1-4 to change player count
...

Setup Player 1 at position (0, 0.05, 3.5)
Setup Player 2 at position (0, 0.05, -3.5)
2 player(s) ready!

=== Dealing Cards to 2 Player(s) ===
PlayerGrid 0 initialized
Card initialized: 5♦
Card added to Player 0 grid position 0: 5♦
...
Dealing complete! All players have 4 cards.
```

## 📝 Next Steps (Future Phases)

### Phase 6 Complete! ✅
All fast-reaction matching mechanics fully implemented and bug-fixed.

### Phase 8 Complete! ✅ (Knocking & Scoring)
- ✅ **Knock UI** — Circular "KNOCK" button appears on human player's turn
- ✅ **Knock Action** — Player/bot knocks instead of drawing (entire turn consumed)
- ✅ **Final Round Tracking** — GameManager tracks remaining final turns per player
- ✅ **Final Round Turns** — All non-knocker players get exactly one more normal turn
- ✅ **Round End Reveal** — All cards flip face-up with staggered animation when final round ends
- ✅ **Scoring** — Sum all card values (main grid + penalty); Black King = −1, Red King = +25, Joker = 1
- ✅ **Winner Determination** — Lowest score wins the round
- ✅ **Round End UI** — Shows scores per player (round + total), winner announcement, "Play Again" button
- ✅ **Multi-Round Score Tracking** — Total scores persist across rounds
- ✅ **Bot Knock AI** — Very low random chance to knock, increasing slightly each turn
- ✅ **Matching During Final Round** — Fast-reaction matching remains fully active
- ✅ **Turn UI Updates** — "[FINAL ROUND]" prefix shown during knocked state
- ✅ **Play Again** — Resets deck, grids, penalty cards, bot counter; re-deals cards
- ✅ **Clean Architecture** — KnockManager + ScoringManager as separate Node scripts (follows existing pattern)

### Upcoming Phases
- **Phase 9:** SKIPPED (polish will be done during/after Phase 10)
- **Phase 10:** 3D Characters, Environment & First-Person Camera (see [PHASE_10_3D_ASSETS.md](PHASE_10_3D_ASSETS.md))
- **Phase 11:** Menu and multi-round system
- **Future:** Multiplayer support

## 🏗️ Project Structure
```
felix/
├── autoloads/          # Global singletons
│   ├── events.gd       # Signal bus
│   └── game_manager.gd # State machine
├── scripts/            # Game logic (18 scripts)
│   ├── card_data.gd    # Card resource class
│   ├── card_3d.gd      # Card behavior
│   ├── player.gd       # Player state
│   ├── player_grid.gd  # 2×2 grid + penalty cards
│   ├── deck_manager.gd # Deck operations
│   ├── card_pile.gd    # Pile visuals
│   ├── game_table.gd   # Main orchestrator
│   ├── card_view_helper.gd   # ⭐ View positions, rotations, neighbors
│   ├── dealing_manager.gd    # ⭐ Dealing animation
│   ├── viewing_phase_manager.gd # ⭐ Initial viewing phase
│   ├── turn_manager.gd       # ⭐ Turn flow, draw, swap, reshuffle
│   ├── ability_manager.gd    # ⭐ Human ability flows
│   ├── bot_ai_manager.gd     # ⭐ Bot AI + penalty card support + knock
│   ├── match_manager.gd      # ⭐ Fast reaction matching
│   ├── knock_manager.gd      # ⭐ Knock action + round-end reveal
│   ├── scoring_manager.gd    # ⭐ Score calculation + multi-round
│   ├── viewing_ui.gd   # Viewing phase UI
│   ├── turn_ui.gd      # Turn indicator UI
│   ├── swap_choice_ui.gd # Queen ability UI
│   ├── knock_ui.gd     # Knock button UI
│   ├── round_end_ui.gd # Round end scores UI
│   └── camera_controller.gd
├── scenes/
│   ├── main/
│   │   ├── game_table.tscn      # Main game scene
│   │   └── camera_controller.tscn
│   ├── cards/
│   │   ├── card_3d.tscn         # Card prefab
│   │   └── card_pile.tscn       # Pile prefab
│   ├── players/
│   │   └── player_grid.tscn     # Grid prefab
│   └── ui/
│       ├── viewing_ui.tscn      # Viewing phase UI
│       ├── turn_ui.tscn         # Turn indicator
│       ├── swap_choice_ui.tscn  # Queen ability UI
│       ├── knock_ui.tscn        # Knock button UI
│       └── round_end_ui.tscn    # Round end scores UI
├── resources/
│   └── materials/      # Card materials
└── project.godot       # Autoloads configured
```

## 🎯 Key Features Implemented

### Card System
- **Flip Animation** - 0.4s rotation with overshoot bounce
- **Hover Effect** - Cards elevate on mouse over
- **Click Detection** - Area3D with raycast interaction
- **Highlighting** - Emissive glow for selection states
- **Smooth Movement** - Tween-based positioning with overshoot

### Player Grid System (NEW!)
- **2×2 Layout** - Automatic card positioning
- **Dynamic Sizing** - Configurable grid spacing
- **Card Management** - Add, remove, replace cards
- **Batch Operations** - Highlight all, flip all, set interactability
- **Position Tracking** - Global position calculation for animations

### Dealing System (Phase 2)
- **Animated Dealing** - Cards fly from draw pile to players
- **Staggered Animation** - 0.15s delay between each card
- **Multi-player Support** - 1-4 players dynamically configured
- **Visual Feedback** - Draw pile count updates during dealing
- **Player Positioning** - Automatic layout around table

### Viewing System (Phase 3)
- **Bottom Row Reveal** - Players simultaneously view bottom 2 cards
- **Ready System** - Individual ready states with progress tracking
- **UI Feedback** - Shows waiting count and instructions
- **Auto-flip Back** - Cards return to face-down when all ready

### Turn System (Phase 4)
- **Turn Indicator UI** - Shows current player, action, and instructions
- **Draw Mechanic** - Keyboard input (D) to draw card with animation
- **Card Preview** - Drawn card shows face-up with tilt toward player
- **Position-Aware Animation** - Different offsets/rotations per player seat
- **Swap Interaction** - Click-to-swap with smooth transitions
- **Discard Animation** - Cards animate to discard pile before removal
- **Bot AI** - Random card selection with delay for natural feel
- **Turn Progression** - Automatic cycling through all players

### Game Architecture
- **54 Card Deck** - 52 standard + 2 jokers with correct scoring
- **Fisher-Yates Shuffle** - Proper random distribution
- **State Machine** - 7 game states (Setup → Dealing → Playing → etc.)
- **Signal-Based Events** - 20+ signals for decoupled communication

## 🐛 Known Issues & Future Work

### All Core Gameplay Working!
Phases 0–8 are complete. The full gameplay loop is functional.

### Recent Fixes
- ✅ `!is_inside_tree()` errors fixed in `knock_manager.gd` (add_child before global_position)
- ✅ Round-end card reveal now starts from the knocker
- ✅ Camera shake removed from knock action

### Future Phases
- **Phase 9:** Visual polish and juice (particles, screen shake, animation polish)
- **Phase 10:** Low-poly 3D assets
- **Phase 11:** Menu and multi-round system

## 📝 Notes
- All scripts follow Godot best practices (composition over inheritance)
- Scene structure uses position markers for easy layout adjustment
- Card data includes ability types for future phase implementation
- Player grids are reusable components for clean architecture
- Dealing animation uses async/await for smooth sequencing
- Turn system implements Balatro-style gameplay (player vs bots)
- Position-based animations provide immersive 3D perspective
- Bot AI uses randomization for unpredictable but fair gameplay
- Discard pile maintains FIFO order for strategic depth
- **Code Refactoring (game_table.gd split):**
  - game_table.gd was split into 7 focused manager scripts for maintainability
  - Each manager is a standalone Node with class_name, receives `table` reference via `init(game_table)`
  - CardViewHelper: view positions, rotations, sideways directions, seat markers, neighbor lookups
  - DealingManager: card dealing with staggered animation
  - ViewingPhaseManager: initial viewing phase (bottom 2 cards, ready system, bot auto-ready)
  - TurnManager: turn flow, card drawing, swapping, discard, pile reshuffling (~506 lines)
  - AbilityManager: all 4 human ability flows (~913 lines)
  - BotAIManager: bot turn logic + ability decisions + penalty card awareness (~605 lines)
  - MatchManager: fast reaction matching, give-card selection, penalty system (~404 lines)
  - game_table.gd reduced from ~1500+ lines to ~377 lines (orchestrator only)
- **Bot AI Overhaul:**
  - Bot now considers ALL occupied slots (main grid + penalty cards) when choosing a swap target
  - If no swap targets exist but drawn card has an ability, bot falls back to using the ability
  - All 4 bot ability functions (look own, look opponent, blind swap, look and swap) pick from full card pool (main + penalty)
  - Helper functions added: `_get_all_cards(grid)`, `_get_card_return_position(grid, card)`, `_pick_random_card(grid)`
  - Cards return to correct position after bot abilities (works for both main-grid and penalty cards)
- **Phase 5 Features:**
  - Test deck system for ability testing (T key toggle, 18 cards: 7/8/9/10/Jack/Queen)
  - Interactive discard pile with hover/click detection
  - Ability system with state tracking (is_executing_ability, current_ability)
  - All four ability types fully implemented (7/8, 9/10, Jack, Queen)
  - Consistent card viewing position and angle for all interactions
  - Helper functions for code reusability (tilt_card_towards_viewer, get_card_view_position, get_neighbors)
  - Placeholder rectangles using QuadMesh for clean borders
  - Two-step card selection for Jack and Queen abilities
  - Neighbor detection based on physical seating (2-4 players)
  - Visual feedback: selected cards elevate and lock at raised position (using is_elevation_locked flag)
  - Scoped locking: only ability cards stay elevated, hover system unaffected for other cards
  - Swap choice UI for Queen ability (Swap/Don't Swap buttons)
  - Side-by-side card viewing for Queen ability
  - Bot AI for abilities: 50/50 ability vs swap decision, random targeting, random Queen swap choice
- **Phase 5 Bug Fixes:**
  - 9/10 ability now correctly restricted to physical neighbors only (fixed in highlight loop, click validation, and bot targeting)
  - Highlight mesh orientation fixed (QuadMesh rotated -90° on X axis to lie flat on card surface)
  - Highlight position set to float just above card surface (Y=0.006)
  - Pulsing glow animation added (looping TRANS_SINE tween, 0.7s breathing cycle)
  - Color-coded highlights per ability: single cyan for all targetable cards; darker solid cyan for selected/confirmed card
  - Card rotation after swap fixed: cards now reparented to new grid so rotation inherits correctly
  - Applied reparenting fix to all 4 swap functions: confirm_blind_swap, _on_swap_chosen, bot_execute_blind_swap, bot_execute_look_and_swap
  - Highlight mesh now exactly matches card face size (0.64 × 0.89) and inherits card flip rotation as child node
  - Full queue_free cleanup on remove_highlight (no lingering MeshInstance3D nodes)
- **Phase 5 Extra Bug Fixes & Polish:**
  - Jack ability await race condition fixed: guards after every `await` prevent stale coroutines from re-locking deselected cards
  - Jack re-selection: clicking a same-ownership card switches selection at Step 1 or Step 2 (resets Step 2 if needed)
  - Queen re-selection: same re-selection logic as Jack at both steps
  - Queen now uses SPACE confirmation before proceeding to viewing (matches Jack UX)
  - Queen side-by-side spread direction fixed for all 4 seats using `get_card_view_sideways_for(idx)` (was always world-X, broke east/west players)
  - Initial viewing phase: cards now lift to viewing position side-by-side rather than flat in-place flip
  - Bots animate their viewing (lift, flip face-up, tilt, then auto-return after 2.5 s)
  - Human: pressing Ready returns cards to grid first, then marks ready
  - Table changed to 12×12 square mesh
  - Draw/Discard piles moved to ±0.8 (closer to center)  
  - Player-indexed view helpers added: `get_card_view_position_for`, `get_card_view_rotation_for`, `get_card_view_sideways_for`
- **Phase 5 Reshuffle Overhaul & Fixes:**
  - Seat marker crash fixed: `add_child(mesh_instance)` called BEFORE `mesh_instance.global_position` (was causing 37 `is_inside_tree()` errors on startup)
  - `deal_card()` rewritten: no longer reshuffles inline; returns null if draw pile empty
  - `can_reshuffle()` added: `draw_pile.is_empty() and not discard_pile.is_empty()` — allows single-card discard
  - `perform_reshuffle()` added: preserves newest discard card (top); moves rest to draw in FIFO order; handles lone-card edge case (moves it to draw, discard becomes empty); returns transferred count
  - `animate_pile_reshuffle()` added: spawns up to 10 glowing blue BoxMesh ghost cards arcing from discard→draw with 0.07 s stagger; replaces old `_on_pile_reshuffled()` no-op
  - `start_next_turn()` updated: sets `is_player_turn = false` + disables draw pile FIRST, then `if deck_manager.can_reshuffle(): await animate_pile_reshuffle()` before any turn logic
  - FIFO correctness verified by full 54-card 4-player game log (`9♦` first discarded → first drawn after 37-card reshuffle)

---

**Last Updated:** Phase 8 Complete — Starting Phase 10
**Next Milestone:** Phase 10A — Primitive Blockout & First-Person Camera
