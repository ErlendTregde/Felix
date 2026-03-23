# Felix Code Review: Game Potential & Godot Best Practices

## Game Assessment

**Felix is a genuinely good game concept.** It's a compact, competitive 3D card game with:

- Interesting information asymmetry (hidden cards, ability reveals)
- Tense multi-player dynamics (fast-reaction matching, knock system)
- Clean rules with depth (ability cards, penalty system, score arithmetic)
- Strong Steam multiplayer ambition (lobby, friends, session scores across rounds)

The 3D presentation is distinctive — a physical table, animated card flips, smooth camera — which sets it apart from typical 2D card games. With polished multiplayer, this has real potential on Steam.

---

## Critical Issues (Fix First)

### 1. God Class: `game_table.gd` (~1500+ lines)

`GameTable` is doing the work of 5+ classes. It:
- Orchestrates every gameplay manager
- Holds mutable game state (`drawn_card`, `is_executing_ability`, etc.)
- Owns camera, lighting, and UI
- Handles card grid placement
- Processes input routing

**Godot best practice:** Nodes should have a single responsibility. Scene roots should delegate, not orchestrate.

**Fix:** Extract into focused sub-scenes/controllers:
- `AbilityController` — ability selection state machine
- `MatchController` — fast-reaction matching state
- `ViewingController` — initial view phase
- Keep `GameTable` only as a thin coordinator

---

### 2. Magic Numbers Everywhere

Config values are scattered across files with no central location:

```gdscript
# game_table.gd
const TABLE_SURFACE_Y: float = 6.76  # "must match baked transform"
const SEAT_CAMERA_RADIUS: float = 9.5
const SEAT_CAMERA_HEIGHT_OFFSET: float = 3.2

# card_3d.gd
const CARD_MESH_SCALE := Vector3(0.085, 0.085, 0.085)
```

**Godot best practice:** Use an `@export` Resource or a dedicated `Config` autoload for layout constants. This makes tweaking layout at runtime or via inspector possible without touching code.

**Fix:** Create `autoloads/table_config.gd` (or a `TableConfig` Resource) with all spatial/visual constants exported.

---

### 3. Dual-Path Logic in `game_manager.gd`

`GameManager` still supports both the old `players[]` array and the new `seat_contexts[]` array simultaneously. Methods like `are_all_players_ready()` and `set_player_ready()` check both paths.

**Godot best practice:** Complete refactors before layering new systems. Dual-path logic is a maintenance trap and a source of subtle bugs.

**Fix:** Remove the `players[]` path entirely. If tests or old scenes still reference it, update them.

---

### 4. Instance ID as Card Identity (`card_ref.gd`)

`CardRef` stores Godot `instance_id` to reference cards across the network. Godot instance IDs are memory addresses — they become stale if a card node is freed and recreated (which happens on round reset).

**Godot best practice:** Never use instance IDs as stable identifiers across frames or network boundaries. Assign explicit, stable UUIDs or integer IDs at card creation.

**Fix:** Add `card_id: int` (assigned from an incrementing counter in `DeckManager`) and use that for all networking and snapshot serialization instead of instance IDs.

---

### 5. Missing Bounds Checks on Seat Array Access

Multiple places loop with `for i in range(4)` or index `seat_contexts[i]` without verifying the array has 4 elements. A 2-player game or a disconnected player mid-game can cause out-of-bounds crashes.

**Godot best practice:** Validate array sizes before access. For seat indices, use a named enum and size-check defensive guards.

**Fix:**
```gdscript
enum Seat { SOUTH = 0, NORTH = 1, WEST = 2, EAST = 3 }

func get_seat(idx: int) -> SeatContext:
    if idx < 0 or idx >= seat_contexts.size():
        push_error("Invalid seat index: %d" % idx)
        return null
    return seat_contexts[idx]
```

---

## Architecture Issues (Fix Before Phase 3)

### 6. No RPC Validation

`_server_request_ready_state` doesn't verify the sender is an actual seated member. In Phase 3, every RPC must validate:
- Sender is the peer who owns that seat
- Action is legal in the current game state
- No duplicate/stale actions (use sequence numbers or action IDs)

**Godot best practice:** Treat all incoming RPCs as untrusted. The host must be authoritative — never apply actions without validation.

**Fix pattern:**
```gdscript
@rpc("any_peer")
func _server_request_action(action: Dictionary) -> void:
    var sender_id := multiplayer.get_remote_sender_id()
    if not _is_sender_authorized(sender_id, action):
        push_warning("Unauthorized RPC from peer %d" % sender_id)
        return
    _apply_validated_action(action)
```

---

### 7. Full RoundState Sent to All Clients (Private Data Leak)

`RoundState` contains all cards including hidden ones. Broadcasting it to all clients leaks opponent hand data.

**Godot best practice:** Generate filtered snapshots per client — include only data that seat is allowed to see (own cards face-up, opponents' card counts/face-up state only).

**Fix:** Add `RoundState.filtered_for_seat(seat_index: int) -> Dictionary` that redacts hidden card data before broadcasting to each peer.

---

### 8. Enum Instead of String Phase Names

`SteamRoomService` uses string literals like `"IDLE"`, `"WAITING"`, `"IN_ROUND"`, `"CONNECTING"` for room phase state.

**Godot best practice:** Use enums for state machines. Strings are typo-prone, unrefactorable, and slower to compare.

**Fix:**
```gdscript
# In room_state.gd
enum RoomPhase { IDLE, CONNECTING, WAITING, IN_ROUND }
```

---

### 9. Snapshot Format Has No Version Field

`RoundState.to_dict()` / `from_dict()` have no schema version. Any future change to the snapshot format will silently corrupt old data or crash on deserialization.

**Godot best practice:** Always include a `"version": 1` field in serialized formats. Add a version check in `from_dict()` and fail gracefully if mismatched.

---

### 10. `BotAIManager` Calls Non-Existent Method

```gdscript
var btn = table.knock_manager.get_button(bot_id)  # Line 72
```

`KnockManager` has `show_button_for()` but no `get_button()`. This crashes at runtime whenever a bot tries to knock.

**Fix:** Implement `get_button(seat_index: int) -> Node` in `KnockManager`, or refactor bot knocking to call `show_button_for()` directly.

---

## Godot-Specific Best Practices

### 11. Use `@export` Groups for Inspector Clarity

Long scripts with many exported variables should use `@export_group` to organize the inspector.

```gdscript
@export_group("Layout")
@export var camera_radius: float = 9.5
@export var camera_height_offset: float = 3.2

@export_group("Timing")
@export var deal_delay: float = 0.1
@export var flip_duration: float = 0.3
```

---

### 12. Prefer `Tween` Over `AnimationPlayer` for Code-Driven Animations

Card flip animations are driven from code. Using `create_tween()` is more flexible and composable than `AnimationPlayer` for procedural animations.

```gdscript
func flip_card(face_up: bool) -> void:
    var tween := create_tween()
    tween.tween_property(self, "rotation:y", target_rotation, 0.3).set_trans(Tween.TRANS_SINE)
    await tween.finished
```

---

### 13. Use `push_error()` / `push_warning()` Consistently

Several error conditions silently return `null` with no logging. In Godot, use `push_error()` for bugs (programmer errors) and `push_warning()` for runtime edge cases. These appear in the Godot debugger and help ship fewer bugs.

---

### 14. Signal Connections: Use Typed Callables

Prefer `signal.connect(method)` over `connect("signal_name", callable)` string-based connections (Godot 4 style). Most of the codebase already does this, but a few older connect calls use strings — clean those up for refactor safety.

---

### 15. Avoid `call_deferred` as a Workaround

Several places use `call_deferred` to fix initialization order issues. This often signals that the scene tree setup needs rethinking. In Godot 4, prefer `@onready` and `await get_tree().process_frame` for initialization sequencing, rather than deferring arbitrary method calls.

---

### 16. `RefCounted` vs `Node` for Data Models

Data models (`RoundState`, `RoomState`, `SeatContext`, `CardRef`) correctly extend `RefCounted`. Keep this pattern — these should never be added to the scene tree. Mixing them with Nodes would cause memory leaks and lifecycle confusion.

This is already done correctly; just document it as an intentional constraint.

---

## Lower Priority / Polish

### 17. No Loading Screen / Async Asset Loading
All assets appear to load synchronously. For larger card texture sets or if the deck is expanded, add `ResourceLoader.load_threaded_request()` with a loading screen.

### 18. No Disconnect Recovery Plan
Phase 3 needs a defined answer to: "What happens when the host disconnects mid-round?" Options:
- **Host migration** (complex)
- **Round abort + return to room** (simpler, ship first)
- **Rejoin support** (most user-friendly)

### 19. Bot Difficulty Settings
`BotAIManager` has a single behavior path. Exposing `knock_probability_ramp`, `ability_use_rate`, etc. as exported config would allow difficulty scaling without code changes.

### 20. No Audio System
No sound effects or music mentioned anywhere. Even placeholder audio (card flip, match success/fail) dramatically improves game feel.

---

## Summary Priority List

| Priority | Issue | Impact |
|----------|-------|--------|
| 🔴 Critical | Fix `BotAIManager.get_button()` crash | Game-breaking |
| 🔴 Critical | Remove dual-path logic from `GameManager` | Bug source |
| 🔴 Critical | Replace instance IDs with stable card IDs | Multiplayer-breaking |
| 🟠 High | Add RPC sender validation (Phase 3 blocker) | Security/correctness |
| 🟠 High | Filtered snapshots per seat (Phase 3 blocker) | Cheating prevention |
| 🟠 High | Split `GameTable` into focused controllers | Maintainability |
| 🟡 Medium | Move magic numbers to config resource | Maintainability |
| 🟡 Medium | Add enum for room/game phases | Code clarity |
| 🟡 Medium | Add snapshot version field | Forward compatibility |
| 🟢 Low | Export groups in inspector | Dev ergonomics |
| 🟢 Low | Audio system | Game feel |
| 🟢 Low | Bot difficulty settings | Player experience |
