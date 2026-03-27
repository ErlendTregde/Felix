# Felix Steam Multiplayer Implementation Plan

## Summary

- Build Steam multiplayer as a new Felix-specific room/session layer, not a direct drop-in of the borrowed Steam code.
- First playable milestone: friends/invite Steam room, 2-4 human players, auto-seat into the first free chair, real seat camera/view, host-authoritative Felix rounds, cumulative session scores between rounds, and return to the same room after each round.
- Keep `Play vs AI` as a separate local mode using the current flow; Steam multiplayer never mixes bots into the match.
- Reuse the existing room/table scene, but split the current table logic into a persistent room/session controller plus a reusable round controller so later `leave seat, walk around, sit back down` can be added without replacing v1.

## Public Interfaces

- Add Felix-specific autoload/services: `SteamPlatformService`, `SteamRoomService`, and `FelixNetworkSession`.
- Add typed room/round models in code, with RPC payloads kept as plain dictionaries/arrays: `RoomState`, `SeatState`, `PlayerPublicState`, `PlayerPrivateState`, `RoundState`, and `SessionScoreboard`.
- Add a persistent `SteamRoomScene` root and extract a reusable `FelixRoundController` from the current local-only `GameTable` logic.
- Use client-to-host intent RPCs only: `request_ready_state`, `request_start_round`, `request_draw`, `request_swap`, `request_discard_drawn`, `request_ability_select`, `request_ability_confirm`, `request_match`, `request_give_card`, `request_knock`, and room/seat leave requests.
- Use host-to-client broadcasts for `room_snapshot`, `round_snapshot_public`, `private_hand_update`, `action_result`, `animation_event`, `round_end_summary`, and `session_score_update`.

## Implementation Phases

- Phase 0: Audit and trim the borrowed Steam folder. Remove duplicate game-state ownership, broken scene references, undefined `lobby_scene` usage, and any direct scene-changing from Steam callbacks. Clamp lobby size to 4 and make Steam code transport/lobby-only.
- Phase 1: Refactor Felix gameplay away from `player 0 is the human, everyone else is a bot.` Replace that with seat-based player mapping, local seat ownership, and a host-authoritative round state that owns the deck, discard, penalties, turn order, knock state, and scoring.
- Phase 1: Separate private and public card data. Every client receives public information for all players, but only its own hidden card identities and private viewing results. Opponent hidden cards stay as unknown backs until revealed by rules.
- Phase 1: Convert the current managers into presentation/input adapters driven by approved network events. Tweens and visuals still run locally, but only after host-approved actions with event/sequence IDs so clients cannot drift.
- Phase 2: Add the Steam room flow. Main menu branches to `Play vs AI` or `Steam Multiplayer`; host creates a friends/invite lobby; players join, are auto-seated in the existing seat index order `south=0`, `north=1`, `west=2`, `east=3`, see the room from their real seat, and mark ready. Only seated players count toward round start, and the host starts once all seated players are ready.
- Phase 2: Keep the room alive between rounds. At round end, return to room state, keep session scores for current room members, allow players to ready for another round, and let the host start the next round. If someone leaves between rounds, the room continues with the remaining 2-4 players.
- Phase 3: Implement the full networked Felix ruleset on top of the host model: initial viewing, draw/swap, discard-for-ability, all four abilities, fast matching, penalty cards, knock/final round, round-end reveal, winner calculation, and session score carryover.
- Phase 3: Reject invalid or stale actions on the host. Out-of-turn clicks, duplicate requests, stale card references, and mismatched seat ownership should never mutate state.
- Phase 4: Hardening and UX polish. Add Steam unavailable handling, invite/join failure messaging, lobby/full/started-state messaging, clean disconnect handling, and deterministic recovery back to the room.
- Post-v1 roadmap: add standing/walking room avatars and seat enter/leave in the same room scene; then add lobby text chat, in-room chat/proximity voice, and later rejoin/late-join once the room/session snapshot model is stable.

## Test Plan

- Verify Steam boot paths: Steam running, Steam missing, extension/config missing, create lobby, invite friend, join friend, leave lobby, and return to menu/AI mode cleanly.
- Verify room flow for 2, 3, and 4 players: seat assignment, real seat camera, ready state sync, host start gating, between-round rematch flow, and session score persistence.
- Verify gameplay sync for every rule: initial viewing secrecy, draw/swap, discard abilities, Jack/Queen swap paths, matching, penalties, knock/final round, round-end scoring, and starting the next round.
- Verify host authority under bad input: double-clicks, spammed RPCs, stale card IDs, wrong-seat actions, and lagged packets must be ignored without desync.
- Verify disconnect policy: lobby disconnect before start, player disconnect during round, host disconnect, and return of remaining players to room with clear messaging.
- Verify regression: current `Play vs AI` flow still behaves as it does now.

## Assumptions And References

- v1 is friends/invite-first, human-only, no bots inside Steam matches, no public lobby browser, no manual seat selection, no roaming, no chat, no rejoin, and no late join into an active round.
- v1 accepts the normal peer-hosted tradeoff: the host is authoritative and can technically inspect hidden state; true anti-cheat against the host would require dedicated server authority.
- Room membership is locked for active rounds in v1; new joins happen only before a round starts or after a round ends.
- Session scores persist while the room exists; there is no separate `overall lobby winner` or forced match-end rule yet.
- Reference basis:
  - [Godot high-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
  - [Godot example lobby implementation](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html#example-lobby-implementation)
  - [Godot best practices](https://docs.godotengine.org/en/stable/tutorials/best_practices/index.html)
  - [GodotSteam SteamMultiplayerPeer tutorial](https://godotsteam.com/tutorials/multiplayerpeer/)
  - [GodotSteam lobby tutorial](https://godotsteam.com/tutorials/lobbies/)
  - [Steam multiplayer forum thread](https://forum.godotengine.org/t/steam-multiplayer-questions/122894)

## Phase 1 Implementation Notes

- Felix now has a seat-based runtime model built around `SeatContext`, `RoundState`, `SlotRef`, `CardRef`, and `FelixRoundController`.
- The current local mode still uses one local human plus bots, but the local seat is no longer hardcoded to seat `0`; it can be overridden in setup for validation.
- Rules ownership now uses `owner_seat_id` on cards and grids. `owner_player` remains available only as a presentation convenience.
- `FelixRoundController` now brokers ready, draw, swap, discard, match, knock, turn advancement, and public/private round snapshot generation so Phase 2 can build on a single round authority layer.

## Phase 1.5 Identity And Seat Separation

- Add a stable participant layer for local and future Steam players so identity is no longer derived from seat index.
- Keep seats responsible for camera, lighting, knock-button placement, card-grid transforms, and turn order.
- Keep participant identity responsible for display name, avatar color/skin, controller type, and future `steam_id`.
- Make each `SeatContext` store the current occupant participant id so room snapshots can say who is sitting where without rewriting player identity.
- Build setup flow from `participant_profiles + seat_assignment`, not from `seat index = player identity`.
- Keep the current debug seat override semantics as `move the local participant to this seat`; this makes later Steam seat assignment behavior match local testing.
- Add separate setup-only debug camera tooling so we can preview another seat without moving occupants; this is useful for later room snapshot validation.
- Debug control split: `F1-F4` moves the local participant to a different seat.
- Debug control split: `Shift+F1-F4` previews another seat with camera and local fill lights while leaving occupants unchanged.

## Phase 2 Implementation Notes

- Felix now boots into a simple launcher scene with two entry points: `Play vs AI` and `Steam Multiplayer`.
- `AppFlow` owns scene routing between launcher, local play, and the Steam room so raw Steam callbacks no longer change scenes directly.
- The cleaned borrowed Steam layer is now wrapped by Felix services:
  - `SteamPlatformService` for Steam availability, lobby create/join/leave, and invite/join events.
  - `FelixNetworkSession` for `SteamMultiplayerPeer` lifecycle and disconnect events.
  - `SteamRoomService` for Felix room authority, seat assignment, ready states, room snapshots, and between-round session state.
- Felix room/session data now lives in typed models:
  - `RoomState`
  - `RoomMemberState`
  - `SeatState`
  - `SessionScoreboard`
- The room scene is now persistent and separate from gameplay:
  - `SteamRoomScene` reuses the shared table shell.
  - local seat camera and room lights follow the local seated Steam member.
  - ready state, host start gating, leave-room flow, and room snapshot refresh all run through `SteamRoomService`.
- Phase 2 currently stops at the room-to-round transition boundary:
  - host can create the room, auto-seat members, sync readiness, and trigger round entry.
  - round entry currently shows a controlled placeholder transition inside the room scene.
  - full synchronized Steam gameplay actions remain Phase 3 work.
- Steam invite and `+connect_lobby` startup flow is now handled through pending join state so the room service can open the Steam room even if the join request arrives very early during autoload startup.

## Phase 3 Implementation Notes

Phase 3 implements the full synchronized Felix gameplay layer on top of the working Phase 2 lobby/room system.

### Architecture

- **Host-authoritative**: host runs all game logic. Clients send *intent* RPCs. Host validates, executes, then broadcasts filtered snapshots.
- **`SteamRoundService` autoload** (`autoloads/steam_round_service.gd`): all gameplay RPCs live here (not on scene nodes) to survive scene transitions.  Holds `_round_controller: FelixRoundController`, `_pending_snapshots` buffer, and helpers `_get_seat_index_for_sender()` and `_broadcast_round_snapshot_to_all()`.
- **RPC naming convention**: client→host intent RPCs are `client_request_*`; host→all broadcasts are `_client_*` (prefixed underscore).
- **Private snapshots**: `FelixRoundController.get_private_snapshot_for(seat_id)` hides opponent card faces. Each peer receives only their own seat's private snapshot via `rpc_id`.
- **Pending-snapshot buffer**: RPCs that arrive before `game_table.tscn` finishes loading are buffered and drained when `bind_round_controller()` is called.

### Deck synchronisation

Host broadcasts the post-shuffle draw-pile order as `Array[int]` of `card_id`s. Clients call `DeckManager.apply_sequence(ids)` to reorder locally, guaranteeing identical draw results without a shared PRNG seed.

### Key gotchas

- **Never `rpc_id(1, ...)` from the host to itself** — always guard with `if not multiplayer.is_server()`.
- **Capture `card_data.card_id` before any `await` or `queue_free`** in host action handlers.
- **`match_claimed` is host-only truth** — no client-side match tracking needed; reject via `is_processing_match` guard.
- **`is_local` re-stamping**: host serializes `is_local` from its own perspective; guests override via `_restamp_local_flags()` in `_client_apply_room_snapshot`.

### Implementation steps

| Step | Milestone | Status |
|------|-----------|--------|
| 1 | Autoload skeleton + scene routing (all peers navigate IN_ROUND / WAITING) | ✅ Done |
| 2 | GameTable multiplayer init (correct names, cameras, REMOTE_HUMAN seats) | ✅ Done |
| 3 | Deal sync: deck sequence + private hand reveal | ✅ Done |
| 4 | Viewing phase sync: ready propagation, begin playing on all peers | ✅ Done |
| 5 | Turn loop: draw, swap, discard RPCs + client-side animation | ✅ Done |
| 6 | Abilities: look-own, look-opponent, blind-swap, look-and-swap (Queen) | ✅ Done |
| 7 | Matching: simultaneous right-click, rejection feedback, give-card flow | ✅ Done |
| 8 | Knock + final round: all peers see announcement, correct remaining turns | ✅ Done |
| 9 | Round end: reveal all, show scores, host returns room, session scoreboard | ✅ Done |

### Files created / modified in Phase 3

| File | Change |
|------|--------|
| `autoloads/steam_round_service.gd` | **NEW** — RPC hub, snapshot broadcaster, pending buffer |
| `project.godot` | `SteamRoundService` registered after `SteamRoomService` |
| `autoloads/app_flow.gd` | `open_multiplayer_round()` added |
| `autoloads/steam_room_service.gd` | `_client_room_transition` triggers `AppFlow` scene changes; `_restamp_local_flags()` added |
| `scripts/steam_room.gd` | `round_overlay` placeholder removed |
| `scripts/game_table.gd` | Multiplayer branches in `setup_players`, `_rebuild_participant_profiles`, `_on_play_again_pressed`; debug inputs guarded |
| `scripts/felix_round_controller.gd` | `bind`/`release` `SteamRoundService` in `init`/`_exit_tree` |
| `scripts/deck_manager.gd` | `apply_sequence(ids)` — Step 3 |
| `scripts/dealing_manager.gd` | Multiplayer deal flow, `apply_private_hand()` — Step 3 |
| `scripts/viewing_phase_manager.gd` | Route ready to RPC on clients — Step 4 |
| `scripts/knock_manager.gd` | Route knock button to RPC on clients — Step 8 |
| `scripts/ability_manager.gd` | Route ability inputs to RPCs on clients — Step 6 |
| `scripts/match_manager.gd` | Route right-click to RPC on clients — Step 7 |
