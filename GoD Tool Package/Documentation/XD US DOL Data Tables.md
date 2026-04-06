# Pokemon XD: Gale of Darkness (US) — DOL Data Table Reference

## DOL Section Mapping

| Section | File Offset | RAM Address | Size | RAM-File Delta |
|---------|------------|-------------|------|---------------|
| text0 | 0x00000100 | 0x80003100 | 9,472 | +0x80003000 |
| text1 | 0x00002600 | 0x800056A0 | 3,033,312 | +0x800030A0 |
| data0 | 0x002E6EE0 | 0x80005600 | 64 | +0x7FD1E720 |
| data1 | 0x002E6F20 | 0x80005640 | 96 | +0x7FD1E720 |
| data2 | 0x002E6F80 | 0x802E9F80 | 128 | +0x80003000 |
| data3 | 0x002E7000 | 0x802EA000 | 32 | +0x80003000 |
| data4 | 0x002E7020 | 0x802EA020 | 73,440 | +0x80003000 |
| data5 | 0x002F8F00 | 0x802FBF00 | 1,197,728 | +0x80003000 |
| data6 | 0x0041D5A0 | 0x804E7E20 | 2,464 | +0x800CA880 |
| data7 | 0x0041DF40 | 0x804EBDC0 | 16,064 | +0x800CDE80 |
| BSS | — | 0x804205C0 | 849,860 | — |
| Entry | — | 0x80003154 | — | — |

## Legacy Tool Offset Conversion Constants

```
kDolToRAMOffsetDifference       = 0x30A0  (code sections)
kDolTableToRAMOffsetDifference  = 0x3000  (data table sections)
kDolDataToRAMOffsetDifference   = 0xCDE80 (data7 section)
kRELtoRAMOffsetDifference       = 0xB18DC0 (common.rel)
```

For most data tables (data2-data5): `RAM = DOL_file_offset + 0x80003000`

## Data Tables in start.dol

### In data5 (0x802FBF00 — 0x804205A0)

| Table | DOL Offset | RAM Address | Label | Entry Size | Count | Source |
|-------|-----------|-------------|-------|-----------|-------|--------|
| MenuData | 0x2F98F0 | 0x802FC8F0 | lbl_802FC8F0 | 0x18 | 288 | SmallStructTables/MenuDataTable |
| Textures | (dynamic) | 0x803001A8 | lbl_803001A8 | 0x58 | 1019 | TexturesTable |
| StringTable1 (.msg) | 0x374FC0 | 0x80377FC0 | lbl_80377FC0 | — | size=96,444 | XGStringTable.dol() |
| StringTable2 (.msg) | 0x38C87C | 0x8038F87C | lbl_8038F87C | — | size=868 | XGStringTable.dol2() |
| StringTable3 (.msg) | 0x38CBE0 | 0x8038FBE0 | lbl_8038FBE0 | — | size=138,932 | XGStringTable.dol3() |
| StatusEffects | 0x3F93E0 | 0x803FC3E0 | lbl_803FC3E0 | 0x14 | 87 | StatusEffectsTable |
| Abilities | 0x3FCC50 | 0x803FFC50 | lbl_803FFC50 | 0x0C | 123 | AbilitiesTable |
| TMs/HMs | 0x4023A0 | 0x804053A0 | lbl_804053A0 | 0x08 | 58 | SmallStructTables/TMStruct |
| WZXMoveAnimations | 0x4095C8 | 0x8040C5C8 | lbl_8040C5C8 | 0x06 | 373 | PKXWZXTables |
| PKXTrainerModels | 0x409E88 | 0x8040CE88 | lbl_8040CE88 | 0x08 | 68 | PKXWZXTables |
| PKXPokemonModels | 0x40A0A8 | 0x8040D0A8 | lbl_8040D0A8 | 0x08 | 419 | PKXWZXTables |
| UnownPKXModels | 0x40CD08 | 0x8040FD08 | lbl_8040FD08 | 0x08 | 28 | PKXWZXTables |
| ShinyPKXPokemonModels | 0x40CDE8 | 0x8040FDE8 | lbl_8040FDE8 | 0x0A | 35 | PKXWZXTables |
| WZXAnimations | 0x40D0F0 | 0x804100F0 | lbl_804100F0 | 0x08 | 1399 | PKXWZXTables |
| DeoxysPKXModels | 0x40FF60 | 0x80412F60 | lbl_80412F60 | 0x08 | 4 | PKXWZXTables |
| DeoxysShinyPKXModels | 0x40FF80 | 0x80412F80 | lbl_80412F80 | 0x08 | 4 | PKXWZXTables |

### In data6 (0x804E7E20 — count value storage)

| Value | DOL Offset | RAM Address | Stored Value |
|-------|-----------|-------------|-------------|
| NumAbilities | 0x41DB38 | 0x804E83B8 | 78 |
| WZXMoveAnim count | 0x41DC68 | 0x804E84E8 | 373 |
| PKXTrainer count | 0x41DC70 | 0x804E84F0 | 68 |
| PKXPokemon count | 0x41DC78 | 0x804E84F8 | 419 |
| UnownPKX count | 0x41DC90 | 0x804E8510 | 28 |
| ShinyPKX count | 0x41DC98 | 0x804E8518 | 35 |
| DeoxysPKX count | 0x41DCA0 | 0x804E8520 | 4 |
| DeoxysShinyPKX count | 0x41DCA8 | 0x804E8528 | 4 |

## Struct Definitions

### Ability (0x0C bytes)
| Offset | Name | Type | Notes |
|--------|------|------|-------|
| 0x00 | unused | uint32 | |
| 0x04 | name_id | uint32 | msg ID |
| 0x08 | description_id | uint32 | msg ID |

### StatusEffect (0x14 bytes)
| Offset | Name | Type | Notes |
|--------|------|------|-------|
| 0x00 | effect_type | uint8 | |
| 0x01 | sub_index | uint8 | |
| 0x02 | unknown_1 | uint8 | |
| 0x03 | unknown_2 | uint8 | |
| 0x04 | number_of_turns | uint8 | 0 = infinite |
| 0x05 | unknown_flag_1 | uint8 | bool |
| 0x06 | unknown_flag_2 | uint8 | bool |
| 0x07 | unknown_flag_3 | uint8 | bool |
| 0x08 | unknown_3 | uint16 | |
| 0x0A | base_weather_id | uint16 | Non-permanent weather status |
| 0x0C | padding | uint32 | Filled at runtime |
| 0x10 | name_id | uint32 | msg ID (fight_common) |

### TM (0x08 bytes)
| Offset | Name | Type | Notes |
|--------|------|------|-------|
| 0x00 | is_hm | uint8 | boolean |
| 0x01 | padding | void[5] | |
| 0x06 | move_id | uint16 | |

### MenuData (0x18 bytes)
| Offset | Name | Type | Notes |
|--------|------|------|-------|
| 0x00 | unknown_1-7 | uint8[8] | |
| 0x08 | x_position | uint16 | |
| 0x0A | y_position | uint16 | |
| 0x0C | callback_1 | label (uint32) | Function pointer |
| 0x10 | callback_2 | label (uint32) | Function pointer |
| 0x14 | callback_3 | label (uint32) | Function pointer |
| 0x18 | callback_4 | label (uint32) | Function pointer |

### PKXModel (0x08 bytes)
| Offset | Name | Type | Notes |
|--------|------|------|-------|
| 0x00 | fsys_id | uint32 | |
| 0x04 | file_identifier | uint32 | |

### ShinyPKXModel (0x0A bytes)
| Offset | Name | Type | Notes |
|--------|------|------|-------|
| 0x00 | species_id | uint16 | |
| 0x02 | fsys_id | uint32 | |
| 0x06 | file_identifier | uint32 | |

### WZXAnimation (0x08 bytes)
| Offset | Name | Type | Notes |
|--------|------|------|-------|
| 0x00 | fsys_id | uint32 | |
| 0x04 | wzx_file_id | uint32 | |

### WZXMoveAnimation (0x06 bytes)
| Offset | Name | Type | Notes |
|--------|------|------|-------|
| 0x00 | attack_animation | uint16 | Index into WZX table |
| 0x02 | damage_animation | uint16 | Index into WZX table |
| 0x04 | special_animation | uint16 | Index into WZX table |

### TextureInfo (0x0C bytes, sub-struct)
| Offset | Name | Type | Notes |
|--------|------|------|-------|
| 0x00 | crop_x | uint16 | |
| 0x02 | crop_y | uint16 | |
| 0x04 | crop_width | uint16 | |
| 0x06 | crop_height | uint16 | |
| 0x08 | file_id | uint32 | FSYS file identifier |

### Texture (0x58 bytes, US/EU multi-language)
| Offset | Name | Type | Notes |
|--------|------|------|-------|
| 0x00 | unknown | uint32 | |
| 0x04 | unknown_2 | uint32 | |
| 0x08 | us_uk_info | TextureInfo | |
| 0x14 | german_info | TextureInfo | |
| 0x20 | french_info | TextureInfo | |
| 0x2C | italian_info | TextureInfo | |
| 0x38 | spanish_info | TextureInfo | |
| 0x44 | unknown_3 | uint32 | |
Note: JP version uses single-language struct (0x18 bytes) with only JP info.

## Notes

- **Symbol map (GXXE01.map)**: Only covers text section function symbols, NOT data labels. All data table labels are auto-generated `lbl_XXXXXXXX` format.
- **Count values in data6**: These addresses are NOT labeled because they're not referenced via lis/addi relocation pairs in the code. They're loaded via direct offsets.
- **Texture table address**: Computed dynamically from lis/addi pair at text1 DOL offset 0x799C2 → upper=0x8030, lower=0x01A8 → RAM=0x803001A8.
- **Tables in common.rel**: Pokemon stats, moves, items, types, natures, trainers, etc. are in common.rel (a separate REL file), not the DOL. Those use CommonIndexes with kRELtoRAMOffsetDifference = 0xB18DC0.
