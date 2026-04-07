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

Each entry is 0x40 bytes and defines a collision region:

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0x00 | 36 | - | Region metadata | Bounding box, flags, region type |
| 0x24 | 4 | UInt32 | Triangle data pointer 1 | Offset to primary triangle list |
| 0x28 | 4 | UInt32 | Triangle data pointer 2 | Offset to secondary triangle list |
| 0x2C | 4 | UInt32 | Triangle data pointer 3 | Offset to additional triangle data |
| 0x30 | 4 | UInt32 | Triangle data pointer 4 | Offset to additional triangle data |
| 0x34 | 12 | - | Special region data | Pointers for warps, doors, PC zones, etc. |

Not all pointer fields are used by every entry. Unused pointers are set to 0.

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
