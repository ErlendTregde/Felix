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
