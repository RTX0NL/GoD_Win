# CCD - Collision Data

CCD is the collision detection mesh format used in Pokemon Colosseum and Pokemon XD for defining walkable surfaces, walls, interaction zones, warp triggers, and other spatial regions within game maps. Each room model (RDAT) is paired with a CCD file that provides the physical collision geometry the game engine uses for character movement, camera boundaries, and trigger detection.

## Identification

| Property | Value |
|----------|-------|
| Type ID | `0x06` |
| Extension | `.ccd` (file extension), `.col` (internal/legacy name) |
| Byte Order | Big-endian |

## Header

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | UInt32 | List start offset | Offset to the beginning of the entry list |
| 0x04 | 4 | UInt32 | Entry count | Number of collision entries |

## Entry Table

Each entry is 0x40 bytes. Measured on all 284 collision files of the US Colosseum and XD discs:

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 12 | Float32 ×3 | Translation | 0 in every file |
| 0x0C | 12 | Float32 ×3 | Rotation | 0 in every file |
| 0x18 | 12 | Float32 ×3 | Scale | 1, 1, 1 in every file |
| 0x24 | 20 | UInt32 ×5 | Block pointers | One per slot; 0 = unused |
| 0x38 | 8 | - | Not decoded | |

### Blocks

A block pointer leads to a block of triangles:

| Offset | Size | Type | Field |
|--------|------|------|-------|
| 0x00 | 4 | UInt32 | Triangle list offset |
| 0x04 | 4 | UInt32 | Triangle count |

Blocks in slots 0, 1, 2 and 4 continue with a uniform grid over their triangles, for 0x24 bytes in all:

| Offset | Size | Type | Field |
|--------|------|------|-------|
| 0x08 | 4 | UInt32 | Grid cell table offset (8 bytes per cell) |
| 0x0C | 4 | UInt32 | Triangle index list offset |
| 0x10 | 4 | UInt16 ×2 | Grid columns, rows |
| 0x14 | 8 | Float32 ×2 | Cell size (40 × 40 in the rooms checked) |
| 0x1C | 8 | Float32 ×2 | Grid origin (X, Z) |

Slot 3's blocks have no grid; their triangles follow the 8-byte header.

What each slot is for is inferred from the triangles:

| Slot | Holds | Evidence |
|------|-------|----------|
| 0 | Floors | Mostly upward-facing; surface types 0xFF00 and nearby |
| 1 | Walls | Vertical; surface types 1–7 |
| 2 | Trigger walls | The only slot whose interaction indexes aren't all 0 |
| 3 | A short list of walls | No grid |
| 4 | Walls | The same triangle counts as slot 1 |

## Triangle Data

Each triangle is 0x34 bytes and defines a single collision face:

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 4 | Float32 | Vertex 1 X | |
| 0x04 | 4 | Float32 | Vertex 1 Y | |
| 0x08 | 4 | Float32 | Vertex 1 Z | |
| 0x0C | 4 | Float32 | Vertex 2 X | |
| 0x10 | 4 | Float32 | Vertex 2 Y | |
| 0x14 | 4 | Float32 | Vertex 2 Z | |
| 0x18 | 4 | Float32 | Vertex 3 X | |
| 0x1C | 4 | Float32 | Vertex 3 Y | |
| 0x20 | 4 | Float32 | Vertex 3 Z | |
| 0x24 | 4 | Float32 | Normal X | Face normal vector X component |
| 0x28 | 4 | Float32 | Normal Y | Face normal vector Y component |
| 0x2C | 4 | Float32 | Normal Z | Face normal vector Z component |
| 0x30 | 2 | UInt16 | Type | Surface/collision type identifier |
| 0x32 | 2 | UInt16 | Interaction index | Index into the InteractionPoints table in common.rel |

### Surface Types

The type field determines how the game engine treats the collision surface (walkable floor, wall, ceiling, water, etc.). Different type values affect character movement speed, camera behavior, and visual effects.

### Interaction Index

The interaction index links collision triangles to entries in the InteractionPoints table stored in common.rel. This enables spatial triggers:

- Warp zones (transport player to another map)
- Door triggers (play door animation and transition)
- PC/healing machine zones
- NPC interaction ranges
- Item pickup areas
- Story event triggers

An interaction index of 0 or 0xFFFF typically indicates no interaction.

## Special Regions

Entries can define special-purpose collision regions beyond basic geometry:

- **Warps**: Transport the player to a different map or location within the same map
- **Doors**: Trigger door opening animations and map transitions
- **PC zones**: Define the interaction area for Pokemon Center healing machines
- **Camera boundaries**: Invisible walls that constrain the camera but not the player

## Relationship to RDAT

Each game map consists of a paired RDAT (room model) and CCD (collision data) file within the same FSYS archive:

- The **RDAT** provides the visual geometry rendered on screen
- The **CCD** provides the physical geometry used for collision detection

These are separate data structures with independent vertex data. The collision mesh is typically a simplified version of the visual mesh, with fewer triangles and no visual detail.

## Runtime System: GScolsys2

The game processes collision data through the `GScolsys2` (Genius Sonority Collision System 2) runtime, which consists of multiple specialized sub-modules:

| Sub-module | Purpose |
|------------|---------|
| walk | Ground collision for character movement (floor detection, slope handling) |
| hit | Obstacle collision (walls, solid objects) |
| thru | Pass-through collision (triggers that detect entry/exit without blocking) |
| check | Collision query system (ray casts, overlap tests) |
| human | Player-specific collision handling (interaction zone detection) |
| sun | Shadow/lighting collision (determines shadow casting surfaces) |

The collision system performs per-frame queries against the triangle mesh, testing the player's position and movement vector against relevant collision entries. Spatial partitioning via the entry table reduces the number of triangles tested per frame.

## Game-Specific Differences

- The CCD format is structurally the same between Colosseum and XD
- Differences are in the specific interaction types and interaction point table layouts within common.rel
- XD has additional interaction types for features not present in Colosseum (Pokespots, additional warp types)
