# Felix Card Game - Complete Development Prompt

## 🎴 Game Overview
Create a 3D implementation of Felix Card Game in Godot Engine - a strategic memory card game for 2-4 players where the goal is to achieve the lowest score through card abilities, memory, and quick reactions.

---

## 📜 Complete Game Rules

### Setup
- **Players**: 2-4 players
- **Cards per player**: 4 cards arranged in a 2×2 grid, face-down
- **Initial Viewing**: At the BEGINNING of each round (before gameplay starts), each player looks at their 2 BOTTOM cards only
  - After all players have memorized their cards and confirmed they're ready, these cards are placed face-down and the game begins
  - **Important**: Those initial 2 bottom cards cannot be viewed again during gameplay unless a special ability allows it
  - Players must rely on memory!
- **Center**: Draw pile (face-down) and discard pile (face-up, top card visible)

### Objective
Have the lowest score when someone knocks and the final round completes.

### Turn Structure
On Your Turn:
1. Draw one card from the draw pile (look at it secretly)
2. Choose ONE option:
   - **Option A - Play the Ability**: Place the card face-up on the discard pile and use its special ability
   - **Option B - Swap with Your Deck**: Replace one of your 4 face-down cards with the drawn card. The replaced card goes face-up on the discard pile (NO ability is activated)

### Special Abilities (only when playing Option A)
- **7 or 8**: Look at one of your own face-down cards (must place it back face-down)
- **9 or 10**: Look at one of your neighbor's face-down cards
- **Jack (Knekt)**: Swap one of your face-down cards with one of your neighbor's face-down cards (blind swap)
- **Queen (Dronning)**: Look at one of your own cards AND one of your neighbor's cards, then you may swap them if you wish
- **Other cards**: No special ability

### Fast Reaction Rule (Happens Anytime!)
When a card is placed face-up on the discard pile, players can immediately:

**Match Your Own Card:**
- If you have a matching card in your deck, quickly grab it and slap it onto the discard pile
- This removes the card from your deck (good!)

**Match Someone Else's Card:**
- If you know another player has the matching card, grab THEIR card and slap it onto the discard pile
- **If correct**: You can take one of YOUR cards and place it on THEIR deck
- **If wrong**: You must take the card back AND receive a penalty card

**Penalty for Mistakes:**
- Take the wrong card = receive 1 penalty card added to your deck
- Any other mistake = 1 penalty card

### Draw Pile & Discard Pile Management
**Draw Pile (Left side):**
- Cards face-down
- Visually stacks up (taller pile = more cards)
- Players draw from top of this pile
- When empty, automatically refills from discard pile

**Discard Pile (Right side):**
- Cards **face-up** (top card visible to all players)
- Visually stacks up as cards are discarded
- Shows the card that was most recently played/swapped

**Reshuffle Rule:**
- When draw pile becomes empty:
  - All cards from discard pile transfer to draw pile
  - **Cards maintain their order** (FIFO - First In, First Out)
  - First card discarded becomes first card to draw
  - **No shuffling occurs** (preserves discard order for strategy)
  - Animated transfer with visual feedback

### Ending the Round
**Knocking:**
- When you think you have the lowest score, knock on the table
- Knocking counts as your turn (you don't draw)
- After knocking, each other player gets ONE final turn
- Then all players reveal their cards

**Scoring:**
- **Black King**: -1 point
- **Joker**: 1 point (note: 0 during play, but 1 at scoring)
- **Red King**: +25 points
- **Number cards (2-10)**: Face value (2=2 points, 3=3 points, etc.)
- **Jack**: 11 points
- **Queen**: 12 points

**Winner:**
- Lowest total score wins the round
- Winner starts the next round
- Continue playing rounds as desired

### Summary of Key Points
- ⚡ Always stay alert - matching cards can be played at ANY time, not just your turn
- 🧠 Memory is crucial - remember what cards you've seen (especially those initial 2 bottom cards!)
- 🎯 Knocking is risky - make sure you actually have the lowest score!
- ⚠️ Penalties add cards to your deck, making it harder to win

---

## 🎮 Current Implementation Status

### ✅ Completed Features (Phases 0-4)

**Phase 0: Core Architecture**
- Event bus system (autoloads/events.gd)
- Game manager with state machine (autoloads/game_manager.gd)
- Card data resource (scripts/card_data.gd)
- Player class (scripts/player.gd)
- Deck manager (scripts/deck_manager.gd) - 54 cards with FIFO reshuffle

**Phase 1: 3D Scene Foundation**
- Card3D scene with flip animation (scenes/cards/card_3d.tscn)
- Card3D script with interaction (scripts/card_3d.gd)
- Camera controller (scenes/main/camera_controller.tscn)
- Game table scene (scenes/main/game_table.tscn)
- Game table controller (scripts/game_table.gd)

**Phase 2: Dealing System**
- PlayerGrid scene (2×2 layout)
- PlayerGrid script with card management
- CardPile scene and script (draw/discard visuals)
- Multi-player setup (1-4 dynamic)
- Animated dealing with stagger
- Pile visuals update correctly

**Phase 3: Initial Viewing Phase**
- Viewing UI (scenes/ui/viewing_ui.tscn)
- Bottom 2 cards reveal
- Ready system (individual + all-ready check)
- Simultaneous viewing (all players at once)
- Auto-flip back when all ready

**Phase 4: Turn System (SIMPLIFIED VERSION)**
- Turn UI with indicator and instructions
- Draw mechanic (D key)
- **Current Implementation**: Always swap (Option B only)
  - No ability activation yet
  - No Option A (play ability) yet
- Position-based card viewing (tilts toward player)
- Swap interaction (click card to replace)
- Discard animation (face-up cards on pile)
- Bot AI (random selection with delay)
- Turn progression (cycles through players)
- FIFO pile reshuffle when draw pile empty

**Phase 4 Polish (JUST COMPLETED):**
- ✅ Fixed card swap ownership bug
- ✅ Discard pile shows face-up cards (white top card)
- ✅ Draw pile visual shrinks when cards drawn
- ✅ Discard pile visual grows when cards added
- ✅ FIFO reshuffle (no shuffle, maintains order)
- ✅ Interactive discard pile (hover + click)

**Phase 5: Special Abilities (COMPLETE):**
- ✅ Test deck toggle (T key) - 18 cards (7/8/9/10/Jack/Queen)
- ✅ Interactive discard pile with placeholder rectangle
- ✅ Ability system architecture (state tracking, helper functions)
- ✅ 7/8 ability (look at own card)
- ✅ 9/10 ability (look at neighbor's card - neighbor-only restriction)
- ✅ Jack ability (blind swap with neighbor)
- ✅ Queen ability (look and swap with choice UI)
- ✅ Neighbor detection logic (2-4 players)
- ✅ Consistent card viewing (position + angle)
- ✅ Grid placeholder rectangles (hollow borders)
- ✅ Elevation lock system (is_elevation_locked flag prevents hover interference)
- ✅ Swap choice UI for Queen ability
- ✅ Bot AI for abilities (50/50 decision, random targeting)
- ✅ Color-coded highlights per ability (gold/cyan/orange/purple/white)
- ✅ Pulsing breathing glow animation on all highlights
- ✅ Card rotation after swap (reparenting to correct grid)

### 🚧 Not Yet Implemented (Phases 5-10)

**Phase 5: Special Abilities** ✅ COMPLETE!
- ✅ Ability detection system
- ✅ Option A vs Option B choice (discard pile click vs card click)
- ✅ Test deck system (T key toggle)
- ✅ 7/8 ability (look at own card)
- ✅ 9/10 ability (look at neighbor card - neighbor-only enforced)
- ✅ Jack ability (blind swap with neighbor)
- ✅ Queen ability (look and swap with choice UI)
- ✅ Neighbor detection logic (2-4 players)
- ✅ Ability UI and targeting system
- ✅ Consistent card viewing animations
- ✅ Two-step card selection system with scoped elevation lock
- ✅ Elevation lock flag system (prevents hover interference during abilities)
- ✅ Swap choice UI (Swap/Don't Swap buttons)
- ✅ Bot AI for abilities (50/50 ability vs swap, random targeting)
- ✅ Color-coded highlights (Gold=own, Cyan=9/10, Orange=Jack, Purple=Queen, White=selected)
- ✅ Pulsing highlight animation (breathing glow, TRANS_SINE loop)
- ✅ Card rotation after swap fixed (reparent to new grid, inherit correct orientation)
- ✅ Jack/Queen re-selection at both steps (same-ownership click changes pick, resets Step 2)
- ✅ Queen SPACE confirmation before viewing (consistent with Jack)
- ✅ Queen side-by-side direction fixed for all 4 seats
- ✅ Initial viewing phase animated lift (cards rise side-by-side, like Queen ability)
- ✅ Bots visually view and auto-return cards (2.5 s delay)
- ✅ Human cards return to grid when Ready is pressed
- ✅ Square table (12×12), piles at ±0.8
- ✅ Player-indexed view helpers for per-player animations

**Phase 6: Fast Reaction Matching System** ✅ COMPLETE
- **Always-active matching** (no time window — works anytime during gameplay)
- **Right-click mechanic** (right-click a card to attempt a match against discard pile — final design, no drag-and-drop)
- **Match detection** (card rank must match top of discard pile)
- **Own card matching** (removes card from your deck; does NOT end your turn)
- **Opponent card matching** (success = their card discarded, you give them ANY one of your cards — main grid OR penalty cards | fail = you get a penalty card)
- **Penalty system** (8 fixed slots surrounding 2×2 grid; 9th+ cards stack at last slot with Y offset of 0.025 per overflow card)
- **Penalty card matching** (penalty cards can also be right-clicked to attempt a match)
- **One-match-per-update lock** (matching disabled until new card is placed on discard pile)
- **Drawn card replaces penalty slot** (when swapping a drawn card with a penalty card, the drawn card occupies the exact same slot index)
- **Matching mid-turn allowed** (matching works at any point; own-card match does not end the active turn)
- **Bot AI for matching:** Not implemented (future enhancement)

**Code Refactoring** ✅ COMPLETE
- **game_table.gd split into 7 managers** — CardViewHelper, DealingManager, ViewingPhaseManager, TurnManager, AbilityManager, BotAIManager, MatchManager
- **Each manager** is a standalone Node with `class_name`, receives `table` reference via `init()`
- **game_table.gd** reduced to orchestrator (~377 lines): input handling, setup, signal wiring, dispatch

**Bot AI Overhaul** ✅ COMPLETE
- **Bot swap targets all occupied slots** — main grid + penalty cards (was: single random main-grid slot)
- **Ability fallback** — if no swap targets exist, bot falls back to using ability (if drawn card has one)
- **Bot abilities work with penalty cards** — look own, look opponent, blind swap, look and swap all pick from full card pool
- **Helper functions** — `_get_all_cards(grid)`, `_get_card_return_position(grid, card)`, `_pick_random_card(grid)`

**Phase 7: Knocking and Scoring**
- **Knocking:** Any player (human or bot) may knock on their turn instead of drawing — knocking IS the turn (no card drawn)
- **Final round:** After a player knocks, every OTHER player gets exactly one more normal turn in order
- **Round end:** When the turn comes back to the knocker, all cards are immediately revealed
- **Scoring:** Each player sums the values of all their cards (main grid + penalty cards); special values apply (Black King = −1, Red King = +25, Joker = 1)
- **Winner:** Player with the LOWEST total score wins the round
- **Matching during final round:** Fast-reaction matching remains active throughout the final round
- Round end screen / winner announcement
- Multi-round score tracking

**Phase 8: Visual Polish & Juice**
- Particle effects (reveals, matches, abilities)
- Screen shake (knocking, penalties, matches)
- Smooth animation polish
- Visual feedback enhancement
- Celebration effects
- Sound effect hooks

**Phase 9: Low-Poly 3D Assets**
- Custom card models (low-poly)
- Table model (low-poly style)
- Player position markers
- UI elements (low-poly aesthetic)
- Material improvements
- Lighting

**Phase 10: Menu & Multi-Round System**
- Main menu
- Player count selection
- Round tracking
- Score persistence across rounds
- Settings/options
- Game flow polish

---

## 💻 Technical Requirements

### Engine & Version
- **Godot Engine 4.5+** (latest stable)
- 3D project with Forward Plus renderer
- Vulkan 1.3+

### Camera & Perspective
- Fixed 3D camera positioned above table at an angle
- Player does not move the camera
- Clear view of all player grids, center piles, and interaction areas
- Camera should feel like sitting at a card table
- Optional: Camera shake for important events

### Visual Style - "Juicy" Low-Poly

**Primary Inspiration:**
- [Godot UI Components by MrEliptik](https://github.com/MrEliptik/godot_ui_components) - Especially the [Balatro cards example](https://github.com/MrEliptik/godot_ui_components/tree/main/scenes/balatro)
- [Juicy Game Feel in Godot 4 Course](https://www.udemy.com/course/learn-how-to-make-a-game-juicy-in-godot-4/)
- [Godot Asset Library - UI Components](https://godotengine.org/asset-library/asset/4019)

**Required "Juice" Elements:**
- ✨ Smooth card animations (flip, hover, deal, draw, swap)
- 💫 Particle effects on card reveals, abilities, matches
- 📳 Screen shake on important events (knocking, swapping, penalties)
- 🎨 Smooth transitions and tweens everywhere
- ⚡ Satisfying visual feedback on every interaction
- 🌈 Glowing effects, highlights, and visual polish
- 🎯 Animated UI elements with scale, bounce, and rotation
- 🎊 Celebration effects for round wins
- 🔊 Ready for sound effect integration (hooks in code)

**Low-Poly Aesthetic:**
- Clean, simple geometry
- Flat shading or minimal lighting
- Bold, solid colors
- Stylized, not realistic
- Performance-friendly
- Clear readability

---

## 🏗️ Architecture & Best Practices

### Following Godot Best Practices
Reference: [Official Godot Best Practices](https://docs.godotengine.org/en/stable/tutorials/best_practices/index.html)

### Project Structure
```
felix/
├── autoloads/              # Global singletons
│   ├── events.gd           # Signal bus for game events
│   └── game_manager.gd     # State machine and turn management
├── scripts/                # Game logic
│   ├── card_data.gd        # Card resource class
│   ├── card_3d.gd          # Card behavior and interaction
│   ├── player.gd           # Player state management
│   ├── player_grid.gd      # 2×2 grid manager + penalty card slots
│   ├── deck_manager.gd     # Deck operations (shuffle, deal, FIFO)
│   ├── card_pile.gd        # Pile visuals (draw/discard)
│   ├── game_table.gd       # Main orchestrator (input, setup, dispatch)
│   ├── card_view_helper.gd # View positions, rotations, neighbors ⭐ Refactor
│   ├── dealing_manager.gd  # Card dealing with animation ⭐ Refactor
│   ├── viewing_phase_manager.gd # Initial viewing phase ⭐ Refactor
│   ├── turn_manager.gd     # Turn flow, drawing, swapping, reshuffle ⭐ Refactor
│   ├── ability_manager.gd  # All 4 card abilities (human) ⭐ Refactor
│   ├── bot_ai_manager.gd   # Bot turn logic + ability decisions ⭐ Refactor
│   ├── match_manager.gd    # Fast reaction matching system ⭐ Phase 6
│   ├── viewing_ui.gd       # Viewing phase UI ⭐ Phase 3
│   ├── turn_ui.gd          # Turn indicator UI ⭐ Phase 4
│   ├── swap_choice_ui.gd   # Queen ability swap choice UI ⭐ Phase 5
│   ├── camera_controller.gd
│   └── (game_table.gd was split into the 7 managers above)
├── scenes/
│   ├── main/
│   │   ├── game_table.tscn      # Main game scene
│   │   └── camera_controller.tscn
│   ├── cards/
│   │   ├── card_3d.tscn         # Card prefab
│   │   └── card_pile.tscn       # Pile prefab
│   ├── players/
│   │   └── player_grid.tscn     # Grid prefab
│   ├── ui/
│   │   ├── viewing_ui.tscn      # Viewing phase UI ⭐ Phase 3
│   │   ├── turn_ui.tscn         # Turn indicator ⭐ Phase 4
│   │   └── swap_choice_ui.tscn  # Queen ability UI ⭐ Phase 5
│   └── effects/
│       ├── particle_effects.tscn  # TODO: Phase 8
│       └── screen_shake.tscn      # TODO: Phase 8
├── resources/
│   ├── materials/          # Card materials
│   │   ├── card_front_material.tres (white)
│   │   └── card_back_material.tres (blue)
│   └── card_data/          # TODO: Card definitions as resources
├── assets/
│   ├── models/             # TODO: Phase 9 (low-poly 3D)
│   ├── textures/           # TODO: Phase 9
│   └── fonts/              # TODO: Phase 9
└── project.godot           # Autoloads configured
```

### Code Organization Principles
- **Single Responsibility**: Each script has one clear purpose
- **Signals for Communication**: Use Godot's signal system for loose coupling
- **Autoload for Global State**: Game manager and event bus as singletons
- **Scene Composition**: Build complex scenes from simple reusable components
- **Resource Files**: Use .tres files for data (card definitions, player configs)
- **Typed GDScript**: Use type hints for better code clarity and performance

---

## 🔧 Development Approach

### CRITICAL: Incremental Development
**Implement ONE feature at a time, test it thoroughly, then move to the next.**

### Phase Breakdown

**Phase 1: Basic Setup** ✅ COMPLETE
- Create project structure
- Set up camera and table scene
- Create basic card 3D model/mesh
- Test: Card appears in scene

**Phase 2: Card System** ✅ COMPLETE
- Card data structure (suit, value, score)
- Card visual representation (front/back textures)
- Card flip animation
- Test: Cards flip smoothly

**Phase 3: Deck & Dealing** ✅ COMPLETE
- Deck manager (52 cards + 2 jokers)
- Shuffling algorithm
- Deal 4 cards to each player in 2×2 grid
- FIFO reshuffle system
- Test: Cards deal to all players

**Phase 4: Initial Viewing Phase** ✅ COMPLETE
- Show bottom 2 cards to each player
- "I'm Ready" confirmation system
- Wait for all players, then flip cards face-down
- Test: Viewing phase works correctly

**Phase 5: Turn System** ✅ COMPLETE (SIMPLIFIED)
- Turn indicator
- Draw card action
- Swap mechanic (Option B only)
- Bot AI for automated opponents
- Position-based card viewing
- Test: Basic turn flow works

**Phase 6: Fast Reaction Matching System** ⬅️ NEXT
- Implement drag-and-drop for all cards (hold to drag, release to drop)
- Implement discard pile drop zone detection
- Implement match validation (rank matching)
- Implement own card matching (remove from deck)
- Implement opponent card matching (success/fail logic)
- Implement penalty card system (dynamic positioning around grid)
- Implement visual feedback (drag cursor, error effects)
- Implement matching lock/unlock system (one match per discard update)
- Test: Basic matching with own cards
- Test: Opponent matching (correct/incorrect)
- Test: Penalty card positioning
- Test: Matching during turns and abilities

**Phase 7: Fast Reaction System**
- Card matching detection
- Grabbing mechanics
- Penalty system
- Test: Matching works

**Phase 8: Knocking & Scoring**
- Knock button
- Final round logic
- Score calculation
- Round end screen
- Test: Complete round playthrough

**Phase 9: Polish & Juice**
- Add particle effects
- Add screen shake
- Add smooth animations
- Add visual feedback
- Test: Game feels satisfying

**Phase 10: Multi-Round & Menu**
- Track scores across rounds
- Main menu
- Player count selection
- Test: Full game flow

---

## 🎯 3D Implementation Details

### Card 3D Model
- Simple quad mesh with two-sided material
- Front side: card face texture (white placeholder)
- Back side: card back pattern (blue placeholder)
- Hover state: slight elevation (0.2 units) + glow
- Flip animation: rotate on Y-axis (0.4s with overshoot)

### Table Scene
- 3D plane for table surface (green)
- Designated areas for:
  - Each player's 2×2 grid (4 positions around table)
  - Center draw pile (left side)
  - Center discard pile (right side)
  - Player name/score indicators
- Position markers (Node3D) for easy layout

### Player Positions
- **Player 1 (South)**: (0, 0.05, 3.5) - Human player, facing north
- **Player 2 (North)**: (0, 0.05, -3.5) - Bot, facing south
- **Player 3 (West)**: (-4, 0.05, 0) - Bot, facing east
- **Player 4 (East)**: (4, 0.05, 0) - Bot, facing west

### Interaction
- Raycast-based card selection (click to interact)
- Hover highlights (card slightly lifts + collision debounce)
- Clear visual states (selectable, selected, disabled)
- Area3D for mouse detection
- Signal-based card_clicked events

### Visual Feedback Examples

**Card Flip:**
- Smooth rotation animation (0.4 seconds)
- Slight bounce at the end (overshoot easing)
- Particle sparkle effect (TODO: Phase 8)

**Card Draw:**
- Card moves from draw pile to player position
- Elevates and tilts toward player
- Flips face-up briefly
- Animates to grid position when swapped

**Card Match (TODO: Phase 6):**
- Card zooms to discard pile
- Trail effect during movement
- Impact particles on arrival
- Screen shake

**Ability Used (TODO: Phase 5):**
- Card glows with ability color
- Particle burst
- Camera slight zoom

**Knock (TODO: Phase 7):**
- Large visual indicator (fist icon)
- Screen shake
- Warning overlay for other players

---

## 🎮 State Management

### Game States
```gdscript
enum GameState {
    SETUP,              # Player count selection
    DEALING,            # Cards being dealt
    INITIAL_VIEWING,    # Memorization phase
    PLAYING,            # Normal gameplay
    ABILITY_ACTIVE,     # Waiting for ability target (TODO: Phase 5)
    FAST_REACTION,      # Matching window open (TODO: Phase 6)
    KNOCKED,            # Final turns after knock (TODO: Phase 7)
    ROUND_END           # Scoring (TODO: Phase 7)
}
```

### State Machine Pattern
```gdscript
# game_manager.gd
var current_state: GameState = GameState.SETUP

func change_state(new_state: GameState):
    exit_state(current_state)
    current_state = new_state
    enter_state(current_state)
```

---

## 🔑 Key Godot Features Used

- **Tweens**: For all animations (card movement, rotation, scale)
- **Signals**: For game events and loose coupling
- **Resources**: For card data definitions
- **Autoloads**: For game manager and event bus
- **Area3D + RayCast3D**: For card interaction
- **async/await**: For animation sequencing
- **Timer nodes**: For debouncing and delays
- **Particles (GPUParticles3D)**: TODO: Phase 8
- **AnimationPlayer**: TODO: Phase 8
- **ViewportTexture**: TODO: If needed for UI

---

## ✅ Testing Checklist (Per Feature)

Before moving to next feature, verify:
- ✅ No errors in console
- ✅ Feature works as intended
- ✅ Edge cases handled
- ✅ Visual feedback is clear
- ✅ Code is clean and commented
- ✅ Signals properly connected/disconnected
- ✅ Memory management (queue_free() when needed)

---

## 📝 Development Notes

### Current Test Controls
**Setup Phase:**
- 1/2/3/4 - Change player count
- ENTER - Deal cards
- T - Toggle test mode (7/8/9/10/Jack/Queen ability cards)
- Y - Toggle match test mode (deck with only 7s and 8s — for testing matching)

**Viewing Phase:**
- Ready Button - Mark yourself ready
- A - Auto-ready all other players (testing shortcut)

**Playing Phase:**
- D - Draw a card
- Left-click card - Swap with drawn card (Option B)
- Right-click card - Attempt fast-reaction match against discard pile (always active)
- Click discard pile - Use ability (Option A)
- SPACE - Confirm ability viewing

**Debug:**
- SPACE - Flip all cards (when not in ability mode)
- F - Camera shake (placeholder)

### Code Refactoring (Completed)
- game_table.gd was split into 7 focused manager scripts for maintainability
- Each manager receives a `table` reference via `init(game_table)` and is added as a child node
- **CardViewHelper** — view positions, rotations, sideways directions, seat markers, neighbor lookups
- **DealingManager** — card dealing with staggered animation
- **ViewingPhaseManager** — initial viewing phase (bottom 2 cards, ready system)
- **TurnManager** — turn flow, card drawing, swapping, discard, pile reshuffling
- **AbilityManager** — all 4 human ability flows (look own, look opponent, blind swap, look and swap)
- **BotAIManager** — bot turn logic, ability decisions, penalty card awareness
- **MatchManager** — fast reaction matching, give-card selection, penalty system
- game_table.gd remains the orchestrator: input handling, setup, and dispatching to managers

### Known Limitations (To Address in Future Phases)
- No knocking/scoring system yet (Phase 7)
- Bot AI does not perform fast-reaction matching (future enhancement)
- Placeholder materials (white/blue)
- No sound effects
- No particle effects
- Bot AI is random (no memory/strategy)

### Performance Considerations
- Card pooling (TODO: if needed for many effects)
- Optimize animations and particles
- Minimize draw calls with atlas textures (TODO: Phase 9)
- Use visibility layers for optimization

---

## 🎯 Final Notes

**Priority**: Correctness first, then juice/polish

**Modularity**: Each component should be reusable

**Readability**: Clear variable names and comments

**Performance**: Optimize animations and particles

**Accessibility**: Clear visual indicators for all game states

**Remember**: Build one feature at a time, test it thoroughly, then move forward. The goal is a polished, satisfying card game that feels amazing to play! 🎴✨

---

**Last Updated**: Phase 6 Complete + Code Refactoring + Bot AI Overhaul  
**Current Phase**: Phase 6 Complete — Ready for Phase 7 (Knocking and Scoring)  
**Progress**: ~80% of full game implemented
