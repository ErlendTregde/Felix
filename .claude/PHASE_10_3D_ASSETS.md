# Phase 10: 3D Characters, Environment & First-Person Camera

## 🎯 Vision
Transform Felix from a top-down prototype into a **first-person card game** inspired by Liar's Bar. The player sits at a table in a dimly-lit speakeasy/poker den, sees their own cat hands, and faces off against 1-3 bot cat characters across the table.

**Theme:** Cats playing cards in a shady back-room bar  
**Aesthetic:** Low-poly with moody atmosphere (warm overhead lamp, dark corners, brick walls)  
**Perspective:** First-person (you see your hands + opponents' upper bodies)

---

## 📐 Reference: Liar's Bar
- First-person seated at a round table
- Opponents visible as full upper-body characters
- Dimly lit room with warm overhead lights
- Dark, atmospheric environment (brick, wood, clutter)
- Character names floating above heads
- Player only sees their own hands on the table

---

## 🔧 Technical Approach

### 3D Model Pipeline
- **Blender** for character models, hand rigs, and room pieces
- **Export format:** `.glb` (binary glTF) — Godot's preferred format
- **Free assets** where possible (furniture, props, room elements)
- **Custom models** for cat characters and hands (Blender)
- **Animations** rigged in Blender with AnimationPlayer in Godot

### Key Technical Challenges
1. **Camera switch** — Current top-down camera → first-person seated camera
2. **Hand animation sync** — Player hands must follow game actions in real-time
3. **Card re-positioning** — Cards must be visible and interactive from first-person view
4. **Bot character placement** — Opponents sit around table with idle animations
5. **Lighting overhaul** — Replace flat Godot lighting with atmospheric scene lighting

---

## 📋 Sub-Phase Breakdown

### Phase 10A: Primitive Blockout & Camera Switch
**Goal:** Get the game working in first-person with placeholder shapes before any real art.

- [ ] **First-person camera setup**
  - New camera position: seated at table, eye-level (~1.2m above floor)
  - Camera looks forward across the table
  - Keep existing game_table.tscn as backup (duplicate scene)
  - Cards must be reachable/visible from this angle
  
- [ ] **Room blockout (primitives)**
  - Floor plane (dark wood color)
  - 4 walls (dark brick color, BoxMesh)
  - Ceiling plane
  - Ceiling light placeholder (OmniLight3D or SpotLight3D hanging down)
  - Room size: roughly 6m × 6m × 3m (cozy, not huge)
  
- [ ] **Table blockout**
  - Round/oval table (CylinderMesh, dark wood color)
  - Replace current green plane with circular table
  - Proper height (~0.75m from floor)
  
- [ ] **Character seat blockout**
  - Player position: closest edge of table (first-person, no body visible)
  - Bot positions: CapsuleMesh placeholders at other seats
  - 2-player: opponent directly across
  - 3-player: two opponents at left and right
  - 4-player: three opponents across and to sides

- [ ] **Card position adjustment**
  - Recalculate card grid positions for first-person view
  - Player's cards: near edge of table, slightly below camera
  - Opponent cards: across the table, slightly angled toward player
  - Draw/discard piles: center of round table
  
- [ ] **Verify all game mechanics still work**
  - Dealing animation
  - Viewing phase
  - Turn system (draw, swap, ability)
  - Fast-reaction matching
  - Knocking & scoring
  - Round end reveal

**Deliverable:** The full game playable from first-person with primitive shapes. No art needed yet.

---

### Phase 10B: Room Environment
**Goal:** Build the actual room environment with proper models and lighting.

- [ ] **Table model**
  - Round wooden table (Blender or free asset)
  - Dark wood material with subtle grain
  - Proper legs/base
  
- [ ] **Room structure**
  - Brick walls (texture or low-poly bricks)
  - Wooden floor (planks texture)
  - Dark ceiling
  - Baseboards / trim (optional detail)
  
- [ ] **Lighting setup**
  - Single overhead pendant lamp above table (main light source)
  - Warm color temperature (~3000K, orangey)
  - Shadows enabled (soft shadows)
  - Very dim ambient light (dark corners)
  - Optional: wall sconces with red/orange glow (like Liar's Bar)
  - WorldEnvironment node with dark ambient + subtle fog
  
- [ ] **Props and atmosphere**
  - Chairs at each seat position (simple wooden chairs)
  - Shelves on walls (bottles, books — free assets or simple meshes)
  - Optional: hanging decorations, picture frames, clock
  - Optional: dust particles (GPUParticles3D, very subtle)
  
- [ ] **Environment polish**
  - Post-processing: slight vignette, warm color grading
  - Fog for depth (optional)
  - Shadow quality tuning

**Deliverable:** Atmospheric poker den room with proper lighting. Characters still placeholders.

---

### Phase 10C: Player Hands
**Goal:** First-person cat paw/hand model with animations linked to all game actions.

- [ ] **Hand model (Blender)**
  - Stylized cat paws/hands (low-poly, fur-colored)
  - Left and right hand
  - Rigged with bones for finger/paw movement
  - Textured (simple flat color or painted texture)
  
- [ ] **Hand animations (Blender → Godot)**
  - **Idle** — Hands resting on table edge, slight breathing movement
  - **Draw card** — Right hand reaches to draw pile, picks up card, brings back
  - **Place card / Swap** — Hand moves card to grid position
  - **Discard** — Hand places card on discard pile
  - **Knock** — Fist knocks on table (or presses knock button)
  - **Flip card** — Hand flips a card over
  - **Right-click match** — Quick grab and slap onto discard pile
  - **View card** — Hand picks up card, tilts toward camera
  - **Ability targeting** — Hand hovers/points at target card
  
- [ ] **Animation integration with game logic**
  - AnimationPlayer or AnimationTree for blending
  - Each game action triggers corresponding hand animation
  - Cards attach to hand bone during movement (reparent or follow)
  - Smooth transitions between states
  - Timing sync: animation completes → game action resolves
  
- [ ] **Card attachment system**
  - Card follows hand bone while being held
  - Smooth pickup/release transitions
  - Card orientation matches hand angle

**Deliverable:** Player sees cat paws performing all card actions. Cards visually held/moved by hands.

---

### Phase 10D: Bot Characters
**Goal:** Cat character models for opponents with basic animations.

- [ ] **Cat character model (Blender)**
  - Upper body only (waist up — lower body hidden by table)
  - Low-poly stylized cat
  - Head, torso, arms, hands/paws
  - Rigged with skeleton (head, spine, arms, hands)
  - 3-4 color/breed variants (different fur colors/patterns)
    - Example: Orange tabby, black cat, gray/white, siamese
  
- [ ] **Character animations (Blender)**
  - **Idle** — Subtle breathing, occasional ear twitch, head movement
  - **Draw card** — Reach to draw pile
  - **Place card** — Move card to position
  - **Knock** — Fist on table
  - **React to events** — Head turn, lean forward (optional, for juice)
  - **Think** — Chin scratch, look around (during bot "thinking" delay)
  - **Win/Lose** — Happy/sad reaction at round end (optional)
  
- [ ] **Character placement**
  - Sitting in chairs around table
  - Proper positioning relative to their card grid
  - Face toward center of table
  - Name labels floating above heads (Label3D)
  
- [ ] **Animation integration**
  - Bot game actions trigger character animations
  - AnimationPlayer per character
  - Idle animation loops when not acting
  - Smooth blend between idle → action → idle

**Deliverable:** Cat opponents visible across the table, animated during their turns.

---

### Phase 10E: Polish & Integration
**Goal:** Final pass to make everything cohesive.

- [ ] **Card visual upgrade**
  - Better card textures (actual card faces with rank/suit)
  - Card back design (themed to match bar aesthetic)
  - Maybe slight wear/texture on cards
  
- [ ] **UI repositioning**
  - Turn UI, viewing UI, knock button — all repositioned for first-person
  - Score labels adjusted for new camera angle
  - Round-end UI overlay
  
- [ ] **Audio hooks** (not implementing audio yet, just the trigger points)
  - Card flip sound trigger
  - Card place sound trigger
  - Knock sound trigger
  - Ambient bar sounds trigger point
  
- [ ] **Performance check**
  - Profile FPS with all characters + room
  - LOD if needed for distant objects
  - Shadow optimization

**Deliverable:** Complete visual overhaul — the game looks and feels like a polished card game in a bar.

---

## 🗂️ Asset Requirements

### Must Create (Blender)
| Asset | Type | Priority |
|-------|------|----------|
| Player cat paws/hands | Rigged model + animations | HIGH |
| Cat character (upper body) | Rigged model + animations | MEDIUM |
| 3-4 cat color variants | Texture/material swaps | MEDIUM |

### Can Use Free Assets or Simple Meshes
| Asset | Type | Source Ideas |
|-------|------|-------------|
| Round wooden table | Static mesh | Blender / free asset |
| Wooden chairs | Static mesh | Blender / free asset |
| Room walls/floor | Planes with textures | Godot primitives + textures |
| Shelves, bottles, props | Static meshes | Free asset packs |
| Ceiling lamp | Static mesh + light | Simple Blender model |
| Card textures | 2D textures | Can generate / find free |

### Textures Needed
| Texture | Use |
|---------|-----|
| Dark wood (table, floor) | MeshInstance3D material |
| Brick (walls) | Wall material |
| Cat fur (2-4 colors) | Character materials |
| Card faces (ranks + suits) | Card front materials |
| Card back design | Card back material |

---

## ⚠️ Important Considerations

### Camera Transition Plan
The switch from top-down to first-person is the BIGGEST change. We must:
1. Keep the old camera system as fallback (toggle-able for debugging)
2. Remap all card positions for the new perspective
3. Ensure raycasting still works for card interaction from first-person
4. Test EVERY game mechanic after the camera switch

### Multiplayer-Readiness (Future)
While not implementing multiplayer now, keep these in mind:
- Each player's "view" should be data-driven (position index → camera/hand setup)
- Character models can be assigned per player, not hardcoded
- Hand animations are per-player-seat, not global
- Network state sync will only need game data, not visual state

### Animation Timing
Hand animations must sync with existing tween-based card animations:
- Option 1: Hand animation drives card movement (cards attached to hand bones)
- Option 2: Card tweens play alongside hand animations (synchronized timing)
- Option 3: Hybrid — hand holds card via bone, tween handles the arc/path

### Step-by-Step Priority
```
10A (Blockout)     → Get game working in first-person (NO art needed)
10B (Room)         → Build the atmosphere
10C (Player Hands) → Most impactful visual upgrade
10D (Bot Chars)    → Bring opponents to life
10E (Polish)       → Tie it all together
```

---

## 📊 Estimated Scope

| Sub-Phase | Primary Work | Complexity |
|-----------|-------------|------------|
| 10A: Blockout | Camera + primitives + card repositioning | Medium (code-heavy) |
| 10B: Room | Blender modeling + lighting + Godot setup | Medium (art + setup) |
| 10C: Hands | Blender rigging + animation + code integration | HIGH (most complex) |
| 10D: Bots | Blender modeling + animation + placement | Medium-High |
| 10E: Polish | Textures + UI + optimization | Medium |

**Phase 10C (Player Hands) is the hardest part** — it requires:
- 3D modeling skill (hand/paw model)
- Rigging (bone setup for fingers)
- Animation (multiple hand poses)
- Code integration (AnimationPlayer ↔ game actions)
- Card attachment (bone follow system)

---

## 🎮 Current Status

- [ ] Phase 10A: Primitive Blockout & Camera Switch
- [ ] Phase 10B: Room Environment
- [ ] Phase 10C: Player Hands
- [ ] Phase 10D: Bot Characters
- [ ] Phase 10E: Polish & Integration

**Status:** Planning Complete — Ready to start Phase 10A

---

**Created:** February 27, 2026  
**Last Updated:** February 27, 2026
