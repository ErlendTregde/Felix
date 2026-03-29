# Felix Proximity Voice Chat

## Overview

Felix uses **proximity voice chat** to let players hear each other based on 3D distance, similar to games like PEAK and Lethal Company. Players who are close sound loud and clear; players who are far away become quieter and eventually inaudible. Audio is spatialized so you can tell which direction a voice is coming from.

### Key Features

- Real-time voice chat over Steam P2P networking
- 3D positional audio tied to each player's body
- Distance-based volume falloff (inverse distance attenuation)
- Wall/object occlusion with muffled audio effect
- Push-to-talk (V key) and mute toggle (M key)
- Dedicated "Voice" audio bus for independent volume control

---

## Architecture

```
 LOCAL PLAYER                           REMOTE PLAYER
 ============                           =============

 Microphone                             VoicePlayer3D
     |                                  (AudioStreamPlayer3D)
     v                                       ^
 Steam.startVoiceRecording()                 |
     |                                  push_audio(pcm)
     v                                       ^
 Steam.getVoice()                            |
   (compressed Opus bytes)            Steam.decompressVoice()
     |                                       ^
     v                                       |
 _broadcast_voice.rpc() ----[network]----> _broadcast_voice()
   (unreliable_ordered, channel 2)
```

### Components

| Component | File | Role |
|-----------|------|------|
| **VoiceChatService** | `autoloads/voice_chat_service.gd` | Central manager autoload. Handles mic capture, RPC broadcast, receive routing, mute/PTT. |
| **VoicePlayer3D** | `scripts/voice_player_3d.gd` | Per-remote-player node. AudioStreamPlayer3D with AudioStreamGenerator for 3D playback + occlusion. |
| **Voice Bus** | `default_bus_layout.tres` | Dedicated audio bus with limiter and high-pass filter. |

---

## Setup Guide

### Prerequisites

1. **GodotSteam** plugin installed and enabled (the project already uses it for multiplayer)
2. **Microphone** connected to the computer
3. **Steam** running with a logged-in account

### What Was Added

#### New Files
- `autoloads/voice_chat_service.gd` -- Voice manager autoload
- `scripts/voice_player_3d.gd` -- Per-player 3D audio component
- `default_bus_layout.tres` -- Audio bus layout with Voice bus
- `docs/VOICE_CHAT.md` -- This documentation

#### Modified Files
- `project.godot` -- Added `VoiceChatService` autoload and input actions
- `scripts/steam_room.gd` -- Attaches VoicePlayer3D to remote players, starts/stops voice
- `scripts/game_table.gd` -- Same voice integration for gameplay scene

#### Input Actions Added
| Action | Key | Behavior |
|--------|-----|----------|
| `voice_push_to_talk` | V | Hold to transmit (when PTT mode is enabled) |
| `voice_toggle_mute` | M | Toggle microphone mute on/off |

#### Autoload Registration
`VoiceChatService` is registered after `SteamMovementService` in the autoload list.

---

## How It Works

### 1. Voice Capture (Steam Voice API)

When a player enters a multiplayer scene (steam_room or game_table), `VoiceChatService.start_voice()` is called. This tells Steam to begin recording from the microphone using `Steam.startVoiceRecording()`.

Every ~20ms (50Hz), the service polls `Steam.getAvailableVoice()` on a fixed physics tick. If voice data is available, it calls `Steam.getVoice()` which returns **compressed Opus audio** as a `PackedByteArray`. This is extremely bandwidth-efficient (~3-6 KB/s compared to ~192 KB/s for raw PCM).

### 2. Network Transport

The compressed voice data is sent to all peers via an RPC:

```gdscript
@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _broadcast_voice(compressed_data: PackedByteArray, sender_seat: int)
```

- **`unreliable_ordered`**: Voice is latency-sensitive and tolerates packet loss, but must arrive in order to avoid garbled playback.
- **Channel 2**: Dedicated channel to avoid competing with room RPCs (ch 0) and gameplay RPCs (ch 1).

### 3. Decompression & Routing

On the receiving end, `Steam.decompressVoice()` converts the Opus bytes back to 16-bit PCM audio at 48000 Hz. The PCM data is routed to the correct `VoicePlayer3D` node based on `sender_seat` index.

### 4. 3D Playback

Each remote player has a `VoicePlayer3D` node (extends `AudioStreamPlayer3D`) attached to their `PlayerBody` at head height (Y=10). It uses an `AudioStreamGenerator` plus a small jitter queue so bursts, packet jitter, and brief stalls do not immediately underrun playback.

Godot's built-in 3D audio handles:
- **Spatialization**: Audio pans left/right based on the speaker's position relative to the listener
- **Distance attenuation**: Volume decreases with distance using inverse distance model
- **Max distance**: Beyond 70 units, the voice is inaudible

### 5. Occlusion

Each `VoicePlayer3D` has a child `RayCast3D` that points toward the local player's camera. If the ray hits a wall (collision layer 1), the system:
- Reduces volume by 12 dB
- Lowers the attenuation filter cutoff to 2000 Hz (muffled effect)
- Smoothly lerps both values to avoid audio pops

---

## Configuration

### VoicePlayer3D Properties

These can be adjusted in `scripts/voice_player_3d.gd`:

| Property | Default | Description |
|----------|---------|-------------|
| `max_distance` | 70.0 | Maximum audible distance (units) |
| `unit_size` | 8.0 | Reference distance for volume normalization |
| `attenuation_model` | `INVERSE_DISTANCE` | How volume decreases with distance |
| `max_db` | 0.0 | Maximum volume boost at close range |
| `OCCLUDED_VOLUME_REDUCTION` | 12.0 dB | Volume reduction when occluded by a wall |
| `OCCLUDED_FILTER_CUTOFF` | 2000 Hz | Low-pass filter when occluded (muffled) |
| `SILENCE_THRESHOLD` | 0.25s | Time without data before "not talking" |

### VoiceChatService Settings

| Property | Default | Description |
|----------|---------|-------------|
| `_push_to_talk` | `false` | `false` = open mic, `true` = hold V to talk |
| `VOICE_POLL_INTERVAL` | 0.02s | How often to poll Steam for voice data |
| `VOICE_SAMPLE_RATE` | 48000 | PCM sample rate for decompression |

### Switching to Push-to-Talk

By default, the microphone is always open. To switch to push-to-talk mode:

```gdscript
VoiceChatService.set_push_to_talk(true)
```

In PTT mode, audio is only captured while holding the V key.

### Audio Bus

The **Voice** bus (in `default_bus_layout.tres`) has:
1. **AudioEffectLimiter** -- Prevents voice from clipping (ceiling: -0.1 dB)
2. **AudioEffectHighPassFilter** -- Removes low-frequency rumble/breath noise (cutoff: 80 Hz)

You can adjust the Voice bus volume in the Godot Audio tab or at runtime:
```gdscript
AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), -6.0)
```

---

## Lifecycle & Edge Cases

### Scene Transitions

Voice is started/stopped per scene:
- **Enter steam_room or game_table**: `VoiceChatService.start_voice()` is called in `_ready()`
- **Exit scene**: `tree_exiting` signal triggers `VoiceChatService.stop_voice()`
- The autoload survives scene changes; `_voice_players` dictionary is cleared and rebuilt in each scene

### Late Joiners

When a new player joins, `_spawn_all_player_bodies()` re-runs in steam_room.gd. The new body gets a `VoicePlayer3D` attached and registered. Voice works immediately.

### Disconnects

`FelixNetworkSession.player_left` fires, and `VoiceChatService._on_player_left()` unregisters the voice player. The `PlayerBody` (and its child `VoicePlayer3D`) is freed by the scene script.

### No Microphone

If no microphone is available, `Steam.getAvailableVoice()` returns a non-zero status code. The system gracefully does nothing -- no crash, just no outgoing voice. Other players' voices are still received and played.

### Buffer Management

- **Underrun** (no data arriving): `VoicePlayer3D` re-enters a short prefill phase after a skip so playback restarts with a small cushion instead of a single late packet.
- **Overrun** (too much data): voice chunks are queued first, then drained toward a target playback buffer. If latency grows too large, stale queued audio is trimmed so speech stays near real time.

---

## Troubleshooting

### No voice heard from other players

1. Check that Steam is running and initialized (`SteamManager.is_steam_available()`)
2. Verify microphone is not muted (press M to toggle)
3. Check Steam overlay settings: Steam > Settings > Voice > ensure correct input device
4. Ensure players are within `max_distance` (default: 70 units)
5. Check the Voice audio bus volume in Godot's Audio tab

### Voice is choppy or delayed

1. Check network quality between peers (Steam P2P handles NAT traversal)
2. Try increasing `VoicePlayer3D.GENERATOR_BUFFER_LENGTH_SECONDS` (default: 0.25s) if your players have unusually jittery connections
3. Ensure `VOICE_POLL_INTERVAL` is not set too high (default: 0.02s = 50Hz)

### Echo / feedback

1. Players should use headphones to prevent speaker audio from re-entering the microphone
2. Steam Voice API includes basic echo cancellation, but headphones are recommended
3. Switch to push-to-talk mode if echo is persistent

### Voice too quiet or too loud

Adjust `VoicePlayer3D` properties:
- `unit_size` -- Increase for louder voice at the same distance, decrease for quieter
- `max_db` -- Maximum volume boost when very close
- Voice bus volume via `AudioServer.set_bus_volume_db()`

---

## API Reference

### VoiceChatService (Autoload)

#### Signals
| Signal | Parameters | Description |
|--------|------------|-------------|
| `player_talking` | `seat_index: int, is_talking: bool` | Emitted when a player starts/stops talking |

#### Methods
| Method | Description |
|--------|-------------|
| `start_voice()` | Begin voice capture and broadcasting |
| `stop_voice()` | Stop capture and clear all voice players |
| `set_local_seat(seat_index)` | Set local player's seat (don't play own audio) |
| `register_voice_player(seat_index, node)` | Register a VoicePlayer3D for a seat |
| `unregister_voice_player(seat_index)` | Remove a registered VoicePlayer3D |
| `set_muted(muted)` | Enable/disable microphone |
| `toggle_mute()` | Toggle mute state |
| `is_muted()` | Returns current mute state |
| `set_push_to_talk(enabled)` | Switch between open mic and PTT mode |
| `is_push_to_talk()` | Returns current PTT state |

### VoicePlayer3D (Component)

#### Methods
| Method | Parameters | Description |
|--------|------------|-------------|
| `push_audio` | `pcm_data: PackedByteArray` | Push 16-bit mono PCM samples into the playback buffer |

#### Properties
| Property | Type | Description |
|----------|------|-------------|
| `_occlusion_enabled` | `bool` | Enable/disable wall occlusion (default: true) |
| `_is_talking` | `bool` | Whether this player is currently transmitting voice |
| `_is_occluded` | `bool` | Whether a wall is between this player and the listener |
