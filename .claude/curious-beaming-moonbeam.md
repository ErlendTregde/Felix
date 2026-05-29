# Player Animations

> **Note on plan location:** You asked for the plan in `D:\godot\felix\.claude`, but plan mode requires me to write to this auto-generated path. Copy/move it after approval if you want it tracked in the repo.

## Context

Felix is a Godot 4 / Steam P2P card game (4 seats around a round table). Today, players are represented by featureless green capsules with no animation — there is no character art, no first-person hands, and no animation sync. Movement uses an FPS controller for walking around the room, but when seated the camera switches to an overhead/isometric view (`camera_controller.gd` + `_apply_local_seat_camera_view()` in `game_table.gd:880`).

We want a Liar's Bar–style presentation:
- **Local player**: first-person — FPS camera at eye height on the full-body rig, so arms and hands appear naturally in the lower frame. The body reacts expressively to every gameplay action (draw, swap, discard, knock, ability, win/lose, etc.).
- **Remote players**: visible as full 3D characters with idle / walk / sit / react animations.
- **All animations synced** in real time over the existing Steam multiplayer.
- **Single rig for everyone**: one full-body humanoid (no separate FPS hands rig). The same model is used whether you are the local player or a remote player.
- **Planned base model**: [Rigged Clothed Body by Abduleleah Alshreef (Sketchfab)](https://sketchfab.com/3d-models/rigged-clothed-body-9998b92d12554d67a2788aaf05e66729) — free, 15.4k tris. Download as GLB. Can be uploaded to Mixamo for animation retargeting.
- **Implementation order**: local player first (Phase 1–3), remote players after (Phase 4–5).

### Confirmed design decisions
1. **Seated camera = first-person.** The current overhead seated camera will be replaced with an FPS-from-the-seat view. The existing `camera_controller.gd` mouse-look smoothing logic should be ported into the seated FPS camera (clamped yaw/pitch around the seat's forward).
2. **Single full-body rig, no separate hands model.** The full-body character is used for both local and remote players. FPS feel comes from the camera being at eye height — the arms/hands appear naturally in the lower frame.
3. **Asset sourcing is out-of-scope.** The plan defines folder structure, expected rig conventions, and import settings. Planned model: Sketchfab "Rigged Clothed Body" (GLB), animations via Mixamo.
4. **Sync = event-driven RPCs.** Locomotion (idle/walk) is derived locally from already-synced position. One-shot action animations are broadcast as small RPCs through `steam_round_service.gd` and routed via the existing `Events` bus.

---

## Key files (read these before implementing)

| Purpose | Path |
|---|---|
| Local + remote body, FPS controller | `scripts/player_body.gd` |
| Player body scene | `scenes/players/player_body.tscn` |
| Seated camera (to be retired/repurposed) | `scripts/camera_controller.gd`, `scenes/main/camera_controller.tscn` |
| Sit/stand camera switching | `scripts/game_table.gd` (`_apply_local_seat_camera_view` ~L880, `_handle_local_stood`/`_handle_local_sat` ~L1265–1305) |
| Card-action RPC hub (where to add anim RPCs) | `autoloads/steam_round_service.gd` |
| Sit/stand + position RPC hub | `autoloads/steam_movement_service.gd` |
| Global signal bus (already has all the action signals we need) | `autoloads/events.gd` |
| Turn/draw/swap/discard logic (anim hook points) | `scripts/turn_manager.gd` |
| Ability logic (look/blind-swap/look-and-swap) | `scripts/ability_manager.gd` |
| Knock | `scripts/knock_manager.gd` |
| Match / fast-reaction | `scripts/match_manager.gd` |
| Card visual tweens (already exist, do not duplicate) | `scripts/card_3d.gd` |

---

## Architecture overview

**One rig per player** — the full-body character is always visible for everyone. The local player's FPS feel comes entirely from the camera being placed at eye height.

```
PlayerBody (CharacterBody3D)
├── CollisionShape3D
├── NameLabel / TalkIndicator  (existing)
├── BodyRig          (Node3D)        ← full humanoid, visible to ALL players
│   ├── Skeleton3D + MeshInstance3D  (character.glb)
│   └── AnimationPlayer + AnimationTree (locomotion + one-shots)
├── FPSCamera        (Camera3D, at head/eye height)  ← existing
└── MultiplayerSynchronizer (existing — position/rot only, unchanged)
```

- `BodyRig.visible = true` for everyone (local and remote).
- The local player's camera is at eye height — the character's arms and hands appear naturally in the lower frame without a separate rig.
- No separate hands model or hands rig needed.

### Sit/stand camera change (the big one)

Currently `_handle_local_sat` in `game_table.gd:1290+` releases the FPS camera and switches to `camera_controller`. **New behavior:**
- The FPS camera stays current at all times for the local player.
- On sit: snap the `PlayerBody` global transform to the seat's "seated" anchor (a new `SeatedAnchor` Node3D added under each `ChairZone`), disable physics movement, lock `mouse_rotation.x` (yaw) within ±25° of seat-forward (clamp), keep pitch ±15°. Reuse the smoothing constants from `camera_controller.gd:9-14` so the feel is preserved.
- On stand: re-enable physics movement, unlock yaw clamp.
- `camera_controller.gd` / `camera_controller.tscn` become **dead code** for the seated path. Either delete them or leave a deprecation comment; the `shake()` helper is still useful and should be moved to `player_body.gd` (the FPS camera now owns shake).
- `_apply_local_seat_camera_view()` and `_apply_local_seat_lighting()` either get deleted or rewritten to operate on the FPS camera directly.

### Animation event routing

A single new autoload **`autoloads/player_anim_director.gd`** owns the anim vocabulary and the network sync. It is the only place that knows about animation names.

```
Game logic (turn_manager / ability_manager / knock_manager / match_manager / scoring_manager)
        │  emits Events.* signals (already exist — no new signals needed)
        ▼
PlayerAnimDirector  (new autoload)
        │  on host: validates seat → calls SteamRoundService.broadcast_player_anim(seat, anim_id)
        │  on local: also plays immediately (no wait for round-trip)
        ▼
SteamRoundService.broadcast_player_anim  (new RPC, "authority", "call_remote", "reliable")
        ▼
PlayerBody.play_anim(anim_id)  →  plays on BodyRig (same for local and remote)
```

Locomotion (idle ↔ walk) is **not** routed through this. Each `PlayerBody` checks its own `velocity.length()` (local) or its lerped delta (remote) every `_process` and sets the AnimationTree blend param locally. No bandwidth cost.

### Anim vocabulary (string IDs in `PlayerAnimDirector`)

| ID | Triggered by | Animation clip |
|---|---|---|
| `idle` | default | breathing sway / idle stance |
| `walk` | velocity > 0.1 | walk cycle |
| `sit_down` / `stand_up` | sit/stand RPC | sit / stand transition |
| `seated_idle` | after sit | seated body, hands resting on table |
| `draw_card` | `Events.card_drawn` | reach forward to draw pile |
| `swap_card` | `Events.card_played` (swap) | reach + place card on grid |
| `discard_card` | `Events.card_discarded` | toss to discard pile |
| `look_own` / `look_opponent` | `Events.ability_activated` (7/8/9/10) | peek at card |
| `blind_swap` | `Events.ability_activated` (Jack) | shuffle gesture |
| `look_and_swap` | `Events.ability_activated` (Queen) | two-hand grab |
| `knock` | `Events.knock_announced` | fist slam table |
| `match_attempt` | `Events.match_attempted` | quick slap |
| `match_success` | `Events.match_successful` | fist pump |
| `penalty` | `Events.penalty_card_added` | head shake / slump |
| `win` | `Events.round_ended` (winner) | arms up / cheer |
| `lose` | `Events.round_ended` (loser) | facepalm / slump |
| `point_at` | ability targeting | point at target |

These IDs are the contract — animators on the user's side must name their clips to match (or maintain a `Dictionary` mapping in the director).

---

## Asset folder layout (user-supplied)

```
assets/
└── characters/
    └── body/
        ├── character.glb            # base mesh + skeleton (Sketchfab "Rigged Clothed Body")
        └── animations/
            ├── idle.glb
            ├── walk.glb
            ├── sit_down.glb
            ├── sit_idle.glb
            ├── stand_up.glb
            ├── draw_card.glb
            ├── discard_card.glb
            ├── knock.glb
            ├── win.glb
            ├── lose.glb
            └── ... (one per anim ID above)
```

**Sourcing animations:**
- Download the Sketchfab model as FBX, then upload to [mixamo.com](https://mixamo.com) — it will auto-rig and let you download any animation retargeted to the character's skeleton.
- Export each animation from Mixamo as FBX (without skin), convert to GLB with Blender or use Godot's FBX importer directly.

**Import settings (Godot import dock):**
- `animation/import`: on, root motion **off**
- `meshes/create_shadow_meshes`: on
- Use Godot 4's AnimationLibrary workflow: each anim GLB → saved as `.animlib` resource → all attached to one `AnimationPlayer` on `BodyRig`. This avoids duplicate skeletons and keeps `character.glb` as the single source of truth for the mesh/skeleton.

---

## Implementation steps

> **Order**: Local player first (Phases 1–3), then remote players (Phases 4–5), then polish (Phase 6).

### Phase 1 — LOCAL: BodyRig scaffolding
1. Create `scenes/players/body_rig.tscn`: Node3D root with a `BodyRig` script (`@export var model_scene: PackedScene`), a child `AnimationPlayer`, and an `AnimationTree` (StateMachine root). On `_ready()`, instance `model_scene` and add it as a child — this is the only place the character GLB is referenced. To swap characters later, change this one export. Drop a placeholder Box mesh as the default so it's visible in editor before art exists.
2. Add `BodyRig` as child of `scenes/players/player_body.tscn` per the hierarchy above. Replace the existing `AvatarMesh` (green capsule) with `BodyRig`.
3. Add `play_anim(anim_id: String)` and `set_locomotion(speed: float)` to `player_body.gd`. They call into `BodyRig`'s AnimationTree blend params / one-shot request nodes.
4. Once `character.glb` is imported: attach mesh + skeleton to `BodyRig`, attach animation libraries to `AnimationPlayer`.

### Phase 2 — LOCAL: Seated FPS camera
5. Add a `SeatedAnchor: Node3D` child under each `ChairZone` in `game_table.tscn`, at eye height looking toward the table center (roughly Y=+1.7 from the chair position, rotated to face the table).
6. Rewrite `game_table.gd:_handle_local_sat` (~L1265): instead of switching to `camera_controller`, snap `PlayerBody` global transform to the seated anchor, set `is_seated = true`, lock movement.
7. Rewrite `_handle_local_stood` (~L1290): clear `is_seated`, re-enable physics. Camera (FPS) never changes.
8. In `player_body.gd:_input`, when `is_seated`, clamp yaw to ±25° of seat-forward and pitch to ±15°. Use `smooth_speed = 5` lerp (same values as `camera_controller.gd:9-14`).
9. Move `camera_controller.gd:shake()` (L80) into `player_body.gd` as `shake_camera()`. Update `game_table.gd:287` debug bind to call it there.
10. Remove `camera_controller` instance from the game table scene. Remove `_apply_local_seat_camera_view` and `_apply_local_seat_lighting` from `game_table.gd`. Leave `camera_controller.gd` on disk with a deprecation comment.

### Phase 3 — LOCAL: Card action animations
11. Add `autoloads/player_anim_director.gd` and register it in `project.godot`.
12. In `PlayerAnimDirector._ready()`, connect to `Events` signals for all card actions (`card_drawn`, `card_discarded`, `card_played`, `ability_activated`, `knock_announced`, `match_attempted`, `match_successful`, `penalty_card_added`, `round_ended`).
13. Each handler checks if the actor is the **local player** and calls `local_body.play_anim(anim_id)` immediately. Remote sync (Phase 4) is added later.

### Phase 4 — REMOTE: Full-body sync
14. In `autoloads/steam_round_service.gd`, add:
    ```gdscript
    @rpc("authority", "call_remote", "reliable")
    func _client_play_player_anim(seat_index: int, anim_id: String) -> void

    func broadcast_player_anim(seat_index: int, anim_id: String) -> void
        # host-only; validates seat, RPCs all clients, also plays locally
    ```
    Pattern off the existing `_client_ability_observer_lift` in the same file.
15. Extend `PlayerAnimDirector` handlers: on host, also call `SteamRoundService.broadcast_player_anim(seat, anim_id)`. Add `is_self_originated` guard so the originating client doesn't double-play via RPC.
16. In `player_body.gd:_process`, derive locomotion speed: `velocity.length()` for local, `(global_position - _last_pos).length() / delta` for remote. Drive BodyRig's `parameters/locomotion/blend_position` AnimationTree param.

### Phase 5 — REMOTE: Sit/stand animations
17. Hook `PlayerAnimDirector` into `steam_movement_service.gd`'s existing `_client_player_sat` / `_client_player_stood` callbacks (these already fire on all clients). Play `sit_down` / `stand_up` one-shots on the affected body.

### Phase 6 — Polish
18. Per-player random idle phase offsets so all 4 bodies don't loop in lockstep.
19. Additive "look_at" layer on `BodyRig`'s AnimationTree: seated remote players subtly turn their head toward the active turn player.
20. `point_at` pose during ability targeting: while local player selects a target card, `BodyRig` blends into the point pose aimed at the raycast hit position.

---

## Testing & verification

Manual end-to-end (must run with two clients — Steam P2P needs real peers):
1. **Local FPS body**: Launch one client. You see the character's arms/torso in the lower frame (FPS perspective). Walk around — the body is visible to yourself. Open a second client; from peer 2's view, peer 1 also shows a full body walking around.
2. **Sit/stand**: Press E to sit. Camera does NOT cut — it smoothly snaps to the seated anchor with FPS perspective. Pitch/yaw clamp engages. Stand up — clamp releases, walking works.
3. **Card actions sync**: Host plays a card (draw/swap/discard/knock/ability). Verify on the other client that the actor's body plays the correct one-shot within ~1 frame of the action. Verify the local actor sees their own hands play the same animation immediately (no round-trip lag).
4. **Locomotion**: Walk around as peer 1. Peer 2 sees peer 1's body cycle between idle and walk based on movement.
5. **Win/lose**: Force a round-end. Winner plays cheer, losers play slump.
6. **Camera shake**: Press F (debug). FPS camera shakes (shake helper migrated successfully).
7. **No regression to card tweens**: `card_3d.gd` animations (`flip`, `move_to`, `elevate`) still play normally — they are independent of the player rigs.

Automated: there are no existing tests in the repo; smoke-test by launching the project in Godot editor (`godot --path D:/godot/felix`) and checking the editor doesn't error on the new autoload or scenes.

---

## Risks / things to watch

- **Sit anchor positioning**: if the eye-height anchor is too close to the table the body mesh clips through it; too far and the seated look feels wrong. Iterate once `character.glb` is in.
- **Body self-clipping in FPS**: the local player will see their own torso/legs below the camera. This is usually fine (like most FPS games), but if it's distracting, apply a per-object render layer mask to hide the local body from the local camera.
- **Swapping characters later**: change `BodyRig.model_scene` to point at a new GLB scene. AnimationLibraries are stored separately on the `AnimationPlayer`, so they survive the swap as long as the new model uses the same bone names (Mixamo standard). Different skeleton = re-export animations from Mixamo with the new model.
- **Sketchfab → Mixamo retargeting**: if the model's skeleton doesn't auto-rig cleanly on Mixamo, you may need to manually adjust the rig in Blender first. Check the T-pose and bone naming after import into Godot.
- **Action animation length vs game pacing**: card actions in `turn_manager.gd` fire instantly. If a `draw_card` anim is 1.2 sec, the card will already be in hand before the anim finishes — that's fine (anim is decorative). Gating card movement on animation would be a larger separate change.
- **Authority for self-originated anims**: the local player plays animations immediately (Phase 3). If the host rejects the action (rare), the anim already played. Acceptable for cosmetic anims.
- **`camera_controller.gd` retirement**: found callers — `game_table.gd:287` (shake), `game_table.gd:888` (set_view), `game_table.gd:1297-1299` (set_process / make_current). All are handled in Phase 2 steps above.
