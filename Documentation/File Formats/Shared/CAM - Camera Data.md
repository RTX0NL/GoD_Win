# CAM - Camera Data

CAM is the camera animation data format used for scripted camera movements during cutscenes, area introductions, and battle sequences. The format internals are not fully reverse-engineered, but the runtime API is well-documented from disassembly.

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x18` |
| Byte Order | Big-endian |

## Overview

CAM files define keyframed camera paths including position, target, field of view, and timing data. These are loaded and played back by the GScamera runtime system to produce smooth camera movements during gameplay.

## Runtime System (XD)

The GScamera system in XD exposes 40+ functions for camera management:

### Lifecycle

| Function | Description |
|----------|-------------|
| `GScameraCreate` | Allocate and initialize a camera instance |
| `GScameraLoad` | Load camera animation data from a CAM file |

### Animation Playback

| Function | Description |
|----------|-------------|
| `GScameraStartAnimation` | Begin playing the loaded animation |
| `GScameraSetAnimIndex` | Select which animation to play (files may contain multiple) |
| `GScameraGetAnimFrame` | Query the current frame of the playing animation |

### Direct Control

| Function | Description |
|----------|-------------|
| `GScameraLookAt` | Set camera position and look-at target directly |
| `GScameraSetPerspective` | Set field of view and projection parameters |

### State Management

| Function | Description |
|----------|-------------|
| `GScameraPush` | Push current camera state onto a stack |
| `GScameraPop` | Restore the previously pushed camera state |

The push/pop mechanism allows temporary camera changes (e.g., a cutscene camera interrupting gameplay) with clean restoration of the previous camera state.

### Viewport Control

The system also provides viewport and scissor control functions for managing the rendered area, used for split-screen effects and UI camera setups.

## Current Status

The internal binary layout of CAM files has not been fully reverse-engineered. The runtime API is known from XD disassembly and symbol maps, but the keyframe data encoding, interpolation parameters, and animation index structure within the file remain to be documented.
