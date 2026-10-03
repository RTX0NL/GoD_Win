# REL routes — per-file analysis

Generated from the real US, PAL and JP discs of both games by
`scripts/analysis/gen_rel_routes.py`; regenerate rather than edit. Every REL is
analysed on its own, so each PAL language copy has its own row.

**Where names come from** (`source`):

- `map` — the game's own names: the `relglobal.o` globals the REL's `_prolog`
  registers its tables into, read through the region's symbol map at its one
  offset (XD US `0xC8208`, PAL `0xC7DE8`, JP `0xC80A0`) and accepted only when they
  fit the tables' shape (`X` / `X_number` / `X_top`, built on this file's own name
  for a map table).
- `shape` — XD: no name fits, so floor kinds come from record sizes. These are
  the debug and leftover maps, linked against a development build: their
  registrations go to addresses that don't move between regions.
- `rooms` / `rooms+size` — Colosseum: `common.rel`'s `Rooms` say which field each
  registered global is; `+size` means a group no room references took the one
  kind its record size allows (render 0x28, entry 0x10, character 0x24, berry 4).
- `legacy:pocketMenu` — the legacy tool's names, accepted because its
  (table, count) pairs and 0x4C first record match the module exactly.
- `none` — nothing names it: it registers nothing, or neither names nor record
  sizes fit. Routed `untyped`.

**Custom symbols** — a target the REL's code uses that no registration names:
**none, in any map or module of either game on any region.** The only ones are
`common.rel`'s tail (its own operations) and `tableres2`'s ten resource slots,
named by hand (`tableRes_0`…`9`).

## XD US

| Sources | map: 209, none: 8, shape: 42 |
|---|---|

| REL | Source | Matcher |
|---|---|---|
| `/Assets/Misc/B1_1/B1_1.rel` | shape | `floor_retail_char_pos_resource` |
| `/Assets/Misc/B1_2/B1_2.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/B1_3/B1_3.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/B1_6/B1_6.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/M2_cave_1F_1/M2_cave_1F_1.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/M2_cave_1F_2/M2_cave_1F_2.rel` | shape | `floor_colosseumFormat_char_pos_resource` |
| `/Assets/Misc/M2_cave_2F_1/M2_cave_2F_1.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/M2_cave_2F_2/M2_cave_2F_2.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/M2_cave_3F_1/M2_cave_3F_1.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/M2_cave_3F_1_bf/M2_cave_3F_1_bf.rel` | map | `floor_retail_resource` |
| `/Assets/Misc/M2_cave_3F_2/M2_cave_3F_2.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/Script_test/Script_test.rel` | shape | `floor_retail_char_field_camera_pos_resource` |
| `/Assets/Misc/TEST000/TEST000.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/TEST001/TEST001.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/TEST002/TEST002.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/TEST003/TEST003.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/TEST004/TEST004.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/tv_test/tv_test.rel` | shape | `floor_prototype_field_camera_offscreen_pos_resource` |
| `/Assets/Misc/waza_viewer/waza_viewer.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/worldmap/worldmap_menu.rel` | map | `module_worldmapXD_data` |
| `/Assets/Scenes/ending_Scene01/ending_Scene01.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene02/ending_Scene02.rel` | none | `untyped` |
| `/Assets/Scenes/ending_Scene03/ending_Scene03.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene04/ending_Scene04.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene05_1/ending_Scene05_1.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene05_2/ending_Scene05_2.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene06_1/ending_Scene06_1.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene06_2/ending_Scene06_2.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene06_3/ending_Scene06_3.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene07/ending_Scene07.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene08/ending_Scene08.rel` | shape | `floor_retail_resource` |
| `/Assets/Scenes/ending_Scene09/ending_Scene09.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene10/ending_Scene10.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene11/ending_Scene11.rel` | none | `untyped` |
| `/Assets/Scenes/ending_Scene12_1/ending_Scene12_1.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene12_2/ending_Scene12_2.rel` | shape | `floor_retail_resource` |
| `/Assets/Scenes/ending_SpecialScene01/ending_SpecialScene01.rel` | shape | `floor_retail_char` |
| `/Assets/Scenes/ending_SpecialScene02/ending_SpecialScene02.rel` | shape | `floor_retail_char` |
| `/Assets/Scenes/mechkyogre_movedemo/worldmap_menu.rel` | map | `module_worldmapXD_data` |
| `/Data/Relocatable Modules/D1_garage_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_garage_B1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D1_garage_B2_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_garage_B2_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D1_labo_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_labo_B1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_labo_B1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D1_labo_B2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_labo_B3.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D1_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_cloud_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_cloud_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_cloud_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_cloud_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_cloud_4.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_crater_colo.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_crater_colo_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_magma_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_magma_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_magma_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_magma_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_pc_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_pc_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_rest_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_3.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_4.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_5.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_6.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_7.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_8.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_9.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_valley_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_valley_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_valley_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_valley_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B1_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B1_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B1_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B2_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B2_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B2_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_bridge.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_cabine.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_deck.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_deck_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_casino_colo.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_casino_colo_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_dome_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_dome_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_dome_2_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_dome_3.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_dome_4.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_out.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_out_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_2_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_3.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_3_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D5_factory_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D5_factory_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_3F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_4F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_hat.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_hat_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D5_factory_top.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_top_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D5_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_cruiser.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_dome_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_dome_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_dome_2F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_dome_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_dome_B1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_fort_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_fort_2F_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_2F_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_2F_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_3F_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_3F_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_4F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_5F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_6F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_out_all.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_out_dome.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_out_dome_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_out_foot.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_out_foot_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D7_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D7_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/French/pda_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/German/pda_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/Italian/pda_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/M1_carde_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_gym_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_gym_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M1_gym_B1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_houseA_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M1_houseA_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M1_houseA_2F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M1_houseB_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M1_houseC_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M1_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M1_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M1_pc_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_pc_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M1_shop_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_shop_2F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_stadium_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M1_water_colo.rel` | map | `floor_retail_pos_resource` |
| `/Data/Relocatable Modules/M1_water_colo_bf.rel` | shape | `floor_colosseumFormat_resource` |
| `/Data/Relocatable Modules/M1_water_colo_field.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M2_building_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_building_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M2_building_2F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_building_3F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_building_4F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M2_earth_colo.rel` | map | `floor_retail_pos_resource` |
| `/Data/Relocatable Modules/M2_enter_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_enter_1F_2.rel` | shape | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_guild_1F_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_guild_1F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_hotel_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_houseA_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M2_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M2_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M2_police_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M2_shop_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_uranai_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_windmill_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_cave_1F_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_cave_1F_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M3_cave_1F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_houseA_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_houseB_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M3_houseC_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M3_houseC_2F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_houseD_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_out.rel` | map | `floor_retail_char_field_camera_pos_resource_kinomi` |
| `/Data/Relocatable Modules/M3_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M3_pc_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_shop_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_shrine_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_shrine_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M3_shrine_1F_rl.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M5_apart_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_apart_2F.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M5_labo_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_labo_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_labo_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_labo_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M5_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M6_crab_1F.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_crab_2F.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_crab_B1.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_houseA.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_houseB.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_houseC.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_houseD.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_junk_1F.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_junk_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M6_pc_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_pc_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_shop_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_shop_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_3F.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_4F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_top.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_top_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/S1_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S1_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/S1_shop_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/S2_bossroom_1.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S2_building_1F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/S2_building_1F_2_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/S2_building_2F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/S2_building_3F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/S2_hallway_1.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S2_out_1.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S2_out_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/S2_out_3.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S2_snatchroom_1.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S3_labo_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_labo_1F_EH.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_labo_B1low.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_labo_B1up.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/Spanish/pda_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/T1_ancient_colo.rel` | map | `floor_retail_pos_resource` |
| `/Data/Relocatable Modules/esaba_A.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/esaba_A_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/esaba_B.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/esaba_B_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/esaba_C.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/esaba_C_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/mail.rel` | map | `module_mailDarkPokemonList` |
| `/Data/Relocatable Modules/opening_event.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/pda_menu.rel` | map | `module_pdapokemonsortdata` |
| `/Data/Relocatable Modules/peopleViewer001.rel` | shape | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/pocket_menu.rel` | map | `module_shopData` |
| `/Data/Relocatable Modules/tableres2.rel` | none | `tableres2` |
| `/Data/Relocatable Modules/toolbattle_menu.rel` | map | `module_tutorialdata` |
| `/Data/Relocatable Modules/worldmap_menu.rel` | none | `untyped` |

## XD PAL

| Sources | map: 221, none: 4, shape: 42 |
|---|---|

| REL | Source | Matcher |
|---|---|---|
| `/Assets/Misc/B1_1/B1_1.rel` | shape | `floor_retail_char_pos_resource` |
| `/Assets/Misc/B1_2/B1_2.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/B1_3/B1_3.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/B1_6/B1_6.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/M2_cave_1F_1/M2_cave_1F_1.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/M2_cave_1F_2/M2_cave_1F_2.rel` | shape | `floor_colosseumFormat_char_pos_resource` |
| `/Assets/Misc/M2_cave_2F_1/M2_cave_2F_1.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/M2_cave_2F_2/M2_cave_2F_2.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/M2_cave_3F_1/M2_cave_3F_1.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/M2_cave_3F_1_bf/M2_cave_3F_1_bf.rel` | map | `floor_retail_resource` |
| `/Assets/Misc/M2_cave_3F_2/M2_cave_3F_2.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/Script_test/Script_test.rel` | shape | `floor_retail_char_field_camera_pos_resource` |
| `/Assets/Misc/TEST000/TEST000.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/TEST001/TEST001.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/TEST002/TEST002.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/TEST003/TEST003.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/TEST004/TEST004.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/tv_test/tv_test.rel` | shape | `floor_prototype_field_camera_offscreen_pos_resource` |
| `/Assets/Misc/waza_viewer/waza_viewer.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/worldmap/worldmap_menu.rel` | map | `module_worldmapXD_data` |
| `/Assets/Scenes/ending_Scene01/ending_Scene01.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene02/ending_Scene02.rel` | none | `untyped` |
| `/Assets/Scenes/ending_Scene03/ending_Scene03.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene04/ending_Scene04.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene05_1/ending_Scene05_1.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene05_2/ending_Scene05_2.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene06_1/ending_Scene06_1.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene06_2/ending_Scene06_2.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene06_3/ending_Scene06_3.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene07/ending_Scene07.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene08/ending_Scene08.rel` | shape | `floor_retail_resource` |
| `/Assets/Scenes/ending_Scene09/ending_Scene09.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene10/ending_Scene10.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene11/ending_Scene11.rel` | none | `untyped` |
| `/Assets/Scenes/ending_Scene12_1/ending_Scene12_1.rel` | shape | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene12_2/ending_Scene12_2.rel` | shape | `floor_retail_resource` |
| `/Assets/Scenes/ending_SpecialScene01/ending_SpecialScene01.rel` | shape | `floor_retail_char` |
| `/Assets/Scenes/ending_SpecialScene02/ending_SpecialScene02.rel` | shape | `floor_retail_char` |
| `/Assets/Scenes/mechkyogre_movedemo/worldmap_menu.rel` | map | `module_worldmapXD_data` |
| `/Data/Relocatable Modules/D1_garage_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_garage_B1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D1_garage_B2_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_garage_B2_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D1_labo_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_labo_B1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_labo_B1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D1_labo_B2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_labo_B3.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D1_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_cloud_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_cloud_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_cloud_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_cloud_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_cloud_4.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_crater_colo.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_crater_colo_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_magma_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_magma_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_magma_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_magma_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_pc_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_pc_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_rest_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_3.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_4.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_5.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_6.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_7.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_8.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_9.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_valley_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_valley_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_valley_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_valley_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B1_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B1_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B1_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B2_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B2_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B2_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_bridge.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_cabine.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_deck.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_deck_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_casino_colo.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_casino_colo_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_dome_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_dome_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_dome_2_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_dome_3.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_dome_4.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_out.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_out_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_2_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_3.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_3_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D5_factory_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D5_factory_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_3F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_4F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_hat.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_hat_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D5_factory_top.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_top_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D5_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_cruiser.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_dome_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_dome_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_dome_2F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_dome_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_dome_B1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_fort_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_fort_2F_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_2F_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_2F_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_3F_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_3F_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_4F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_5F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_6F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_out_all.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_out_dome.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_out_dome_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_out_foot.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_out_foot_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D7_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D7_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/French/pda_menu.rel` | map | `module_pdapokemonsortdata` |
| `/Data/Relocatable Modules/French/pocket_menu.rel` | map | `module_shopData` |
| `/Data/Relocatable Modules/French/toolbattle_menu.rel` | map | `module_tutorialdata` |
| `/Data/Relocatable Modules/German/pda_menu.rel` | map | `module_pdapokemonsortdata` |
| `/Data/Relocatable Modules/German/pocket_menu.rel` | map | `module_shopData` |
| `/Data/Relocatable Modules/German/toolbattle_menu.rel` | map | `module_tutorialdata` |
| `/Data/Relocatable Modules/Italian/pda_menu.rel` | map | `module_pdapokemonsortdata` |
| `/Data/Relocatable Modules/Italian/pocket_menu.rel` | map | `module_shopData` |
| `/Data/Relocatable Modules/Italian/toolbattle_menu.rel` | map | `module_tutorialdata` |
| `/Data/Relocatable Modules/M1_carde_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_gym_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_gym_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M1_gym_B1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_houseA_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M1_houseA_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M1_houseA_2F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M1_houseB_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M1_houseC_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M1_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M1_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M1_pc_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_pc_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M1_shop_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_shop_2F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_stadium_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M1_water_colo.rel` | map | `floor_retail_pos_resource` |
| `/Data/Relocatable Modules/M1_water_colo_bf.rel` | shape | `floor_colosseumFormat_resource` |
| `/Data/Relocatable Modules/M1_water_colo_field.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M2_building_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_building_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M2_building_2F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_building_3F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_building_4F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M2_earth_colo.rel` | map | `floor_retail_pos_resource` |
| `/Data/Relocatable Modules/M2_enter_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_enter_1F_2.rel` | shape | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_guild_1F_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_guild_1F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_hotel_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_houseA_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M2_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M2_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M2_police_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M2_shop_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_uranai_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_windmill_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_cave_1F_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_cave_1F_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M3_cave_1F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_houseA_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_houseB_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M3_houseC_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M3_houseC_2F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_houseD_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_out.rel` | map | `floor_retail_char_field_camera_pos_resource_kinomi` |
| `/Data/Relocatable Modules/M3_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M3_pc_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_shop_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_shrine_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_shrine_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M3_shrine_1F_rl.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M5_apart_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_apart_2F.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M5_labo_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_labo_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_labo_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_labo_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M5_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M6_crab_1F.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_crab_2F.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_crab_B1.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_houseA.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_houseB.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_houseC.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_houseD.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_junk_1F.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_junk_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M6_pc_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_pc_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_shop_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_shop_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_3F.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_4F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_top.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_top_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/S1_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S1_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/S1_shop_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/S2_bossroom_1.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S2_building_1F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/S2_building_1F_2_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/S2_building_2F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/S2_building_3F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/S2_hallway_1.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S2_out_1.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S2_out_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/S2_out_3.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S2_snatchroom_1.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S3_labo_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_labo_1F_EH.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_labo_B1low.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_labo_B1up.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/Spanish/pda_menu.rel` | map | `module_pdapokemonsortdata` |
| `/Data/Relocatable Modules/Spanish/pocket_menu.rel` | map | `module_shopData` |
| `/Data/Relocatable Modules/Spanish/toolbattle_menu.rel` | map | `module_tutorialdata` |
| `/Data/Relocatable Modules/T1_ancient_colo.rel` | map | `floor_retail_pos_resource` |
| `/Data/Relocatable Modules/esaba_A.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/esaba_A_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/esaba_B.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/esaba_B_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/esaba_C.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/esaba_C_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/mail.rel` | map | `module_mailDarkPokemonList` |
| `/Data/Relocatable Modules/opening_event.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/pda_menu.rel` | map | `module_pdapokemonsortdata` |
| `/Data/Relocatable Modules/peopleViewer001.rel` | shape | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/pocket_menu.rel` | map | `module_shopData` |
| `/Data/Relocatable Modules/tableres2.rel` | none | `tableres2` |
| `/Data/Relocatable Modules/toolbattle_menu.rel` | map | `module_tutorialdata` |
| `/Data/Relocatable Modules/worldmap_menu.rel` | none | `untyped` |

## XD JP

| Sources | map: 225, none: 3, shape: 26 |
|---|---|

| REL | Source | Matcher |
|---|---|---|
| `/Assets/Misc/B1_1/B1_1.rel` | shape | `floor_prototype_char_pos_resource` |
| `/Assets/Misc/B1_2/B1_2.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/B1_3/B1_3.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/B1_6/B1_6.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/M2_cave_1F_1/M2_cave_1F_1.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/M2_cave_1F_2/M2_cave_1F_2.rel` | shape | `floor_colosseumFormat_char_pos_resource` |
| `/Assets/Misc/M2_cave_2F_1/M2_cave_2F_1.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/M2_cave_2F_2/M2_cave_2F_2.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/M2_cave_3F_1/M2_cave_3F_1.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/M2_cave_3F_1_bf/M2_cave_3F_1_bf.rel` | map | `floor_retail_resource` |
| `/Assets/Misc/M2_cave_3F_2/M2_cave_3F_2.rel` | shape | `floor_colosseumFormat_resource_pos_char` |
| `/Assets/Misc/Script_test/Script_test.rel` | shape | `floor_retail_char_field_camera_pos_resource` |
| `/Assets/Misc/TEST000/TEST000.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/TEST001/TEST001.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/TEST002/TEST002.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/TEST003/TEST003.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/TEST004/TEST004.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/tv_test/tv_test.rel` | shape | `floor_prototype_field_camera_offscreen_pos_resource` |
| `/Assets/Misc/waza_viewer/waza_viewer.rel` | shape | `floor_prototype_resource` |
| `/Assets/Misc/worldmap/worldmap_menu.rel` | map | `module_worldmap_cameradata` |
| `/Assets/Scenes/ending_Scene01/ending_Scene01.rel` | map | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene02/ending_Scene02.rel` | none | `untyped` |
| `/Assets/Scenes/ending_Scene03/ending_Scene03.rel` | map | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene04/ending_Scene04.rel` | map | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene05_1/ending_Scene05_1.rel` | map | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene05_2/ending_Scene05_2.rel` | map | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene06_1/ending_Scene06_1.rel` | map | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene06_2/ending_Scene06_2.rel` | map | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene06_3/ending_Scene06_3.rel` | map | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene07/ending_Scene07.rel` | map | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene08/ending_Scene08.rel` | map | `floor_retail_resource` |
| `/Assets/Scenes/ending_Scene09/ending_Scene09.rel` | map | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene10/ending_Scene10.rel` | map | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene11/ending_Scene11.rel` | none | `untyped` |
| `/Assets/Scenes/ending_Scene12_1/ending_Scene12_1.rel` | map | `floor_retail_char_resource` |
| `/Assets/Scenes/ending_Scene12_2/ending_Scene12_2.rel` | map | `floor_retail_resource` |
| `/Assets/Scenes/ending_SpecialScene01/ending_SpecialScene01.rel` | map | `floor_retail_char` |
| `/Assets/Scenes/ending_SpecialScene02/ending_SpecialScene02.rel` | map | `floor_retail_char` |
| `/Assets/Scenes/mechkyogre_movedemo/worldmap_menu.rel` | map | `module_worldmap_cameradata` |
| `/Data/Relocatable Modules/D1_garage_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_garage_B1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D1_garage_B2_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_garage_B2_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D1_labo_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_labo_B1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_labo_B1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D1_labo_B2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_labo_B3.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D1_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D1_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_cloud_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_cloud_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_cloud_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_cloud_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_cloud_4.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_crater_colo.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_crater_colo_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_magma_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_magma_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_magma_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_magma_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_pc_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_pc_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_rest_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_3.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_4.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_5.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_6.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_7.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_8.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_rest_9.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D2_valley_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_valley_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D2_valley_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D2_valley_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B1_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B1_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B1_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B2_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B2_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_B2_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_bridge.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_cabine.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_deck.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D3_ship_deck_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_casino_colo.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_casino_colo_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_dome_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_dome_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_dome_2_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_dome_3.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_dome_4.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_out.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_out_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_2_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_3.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/D4_tower_1F_3_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D5_factory_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D5_factory_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_3F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_4F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_hat.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_hat_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D5_factory_top.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_factory_top_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D5_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D5_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_cruiser.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_dome_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_dome_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_dome_2F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_dome_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_dome_B1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_fort_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_fort_2F_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_2F_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_2F_3.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_3F_1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_3F_2.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_4F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_5F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_6F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_fort_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_out_all.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_out_dome.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_out_dome_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D6_out_foot.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D6_out_foot_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/D7_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/D7_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M1_carde_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_gym_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_gym_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M1_gym_B1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_houseA_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M1_houseA_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M1_houseA_2F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M1_houseB_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M1_houseC_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M1_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M1_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M1_pc_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_pc_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M1_shop_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_shop_2F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M1_stadium_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M1_water_colo.rel` | map | `floor_retail_pos_resource` |
| `/Data/Relocatable Modules/M1_water_colo_bf.rel` | shape | `floor_colosseumFormat_resource` |
| `/Data/Relocatable Modules/M1_water_colo_field.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M2_building_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_building_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M2_building_2F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_building_3F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_building_4F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M2_earth_colo.rel` | map | `floor_retail_pos_resource` |
| `/Data/Relocatable Modules/M2_enter_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_enter_1F_2.rel` | shape | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_guild_1F_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_guild_1F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_hotel_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_houseA_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M2_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M2_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M2_police_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M2_shop_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_uranai_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M2_windmill_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_cave_1F_1.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_cave_1F_1_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M3_cave_1F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_houseA_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_houseB_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M3_houseC_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M3_houseC_2F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_houseD_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_out.rel` | map | `floor_retail_char_field_camera_pos_resource_kinomi` |
| `/Data/Relocatable Modules/M3_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M3_pc_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_shop_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_shrine_1F.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/M3_shrine_1F_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M3_shrine_1F_rl.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M5_apart_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_apart_2F.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M5_labo_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_labo_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_labo_B1.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_labo_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M5_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M5_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M6_crab_1F.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_crab_2F.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_crab_B1.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_houseA.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_houseB.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_houseC.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_houseD.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_junk_1F.rel` | map | `floor_retail_char_field_camera_offscreen_pos_resource` |
| `/Data/Relocatable Modules/M6_junk_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/M6_pc_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_pc_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_shop_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_shop_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_2F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_3F.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_4F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_top.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/M6_tower_top_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/S1_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S1_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/S1_shop_1F.rel` | map | `floor_retail_char_offscreen_pos_resource` |
| `/Data/Relocatable Modules/S2_bossroom_1.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S2_building_1F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/S2_building_1F_2_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/S2_building_2F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/S2_building_3F_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/S2_hallway_1.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S2_out_1.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S2_out_2.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/S2_out_3.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S2_snatchroom_1.rel` | shape | `floor_colosseumFormat_resource_char` |
| `/Data/Relocatable Modules/S3_labo_1F.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_labo_1F_EH.rel` | map | `floor_retail_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_labo_B1low.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_labo_B1up.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_out.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/S3_out_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/T1_ancient_colo.rel` | map | `floor_retail_pos_resource` |
| `/Data/Relocatable Modules/esaba_A.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/esaba_A_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/esaba_B.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/esaba_B_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/esaba_C.rel` | map | `floor_retail_char_field_camera_pos_resource` |
| `/Data/Relocatable Modules/esaba_C_bf.rel` | map | `floor_retail_resource` |
| `/Data/Relocatable Modules/mail.rel` | map | `module_mailDarkPokemonList` |
| `/Data/Relocatable Modules/opening_event.rel` | map | `floor_retail_char_pos_resource` |
| `/Data/Relocatable Modules/pda_menu.rel` | map | `module_pdapokemonsortdata` |
| `/Data/Relocatable Modules/peopleViewer001.rel` | shape | `floor_prototype_char_pos_resource` |
| `/Data/Relocatable Modules/pocket_menu.rel` | map | `module_shopData` |
| `/Data/Relocatable Modules/toolbattle_menu.rel` | map | `module_trainer_face_data` |
| `/Data/Relocatable Modules/worldmap_menu.rel` | none | `untyped` |

## Colosseum US

| Sources | legacy:pocketMenu: 1, none: 4, rooms: 159, rooms+size: 3 |
|---|---|

| REL | Source | Matcher |
|---|---|---|
| `/Assets/Misc/waza_viewer/waza_viewer.rel` | rooms+size | `floor_render` |
| `/Data/Relocatable Modules/D1_garage_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_garage_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_garage_B2_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_garage_B2_2.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D1_labo_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_labo_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_labo_B1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D1_labo_B2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_labo_B3.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_out.rel` | rooms | `floor_render_camera_entry_char` |
| `/Data/Relocatable Modules/D1_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_cloud_1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_cloud_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_cloud_2.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_cloud_3.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_cloud_4.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_crater_colo.rel` | rooms | `floor_render_camera_entry_char` |
| `/Data/Relocatable Modules/D2_crater_colo_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_magma_1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_magma_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_magma_2.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_magma_3.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_out.rel` | rooms | `floor_render_camera_entry_char` |
| `/Data/Relocatable Modules/D2_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_pc_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_pc_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_rest_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_3.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_4.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_5.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_6.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_7.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_8.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_9.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_valley_1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_valley_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_valley_2.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_valley_3.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D4_casino_colo.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_casino_colo_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_dome_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_10.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_11.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_2_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_dome_3.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_4.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_5.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_6.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_7.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_8.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_9.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_out.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_out_2.rel` | rooms | `floor_render_camera_entry_char` |
| `/Data/Relocatable Modules/D4_tower_1F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_1F_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_tower_1F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_1F_2_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_tower_1F_3.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_1F_3_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_tower_2F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_2F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_2F_2_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_tower_2F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M1_carde_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_gym_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_gym_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M1_gym_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_houseA_1F.rel` | rooms | `floor_render_entry_char_offscreen` |
| `/Data/Relocatable Modules/M1_houseA_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M1_houseA_2F.rel` | rooms | `floor_render_offscreen_entry_char` |
| `/Data/Relocatable Modules/M1_houseB_1F.rel` | rooms | `floor_render_offscreen_entry_char` |
| `/Data/Relocatable Modules/M1_houseC_1F.rel` | rooms | `floor_render_entry_char_offscreen` |
| `/Data/Relocatable Modules/M1_out.rel` | rooms | `floor_entry_char_camera_render` |
| `/Data/Relocatable Modules/M1_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M1_pc_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_pc_B1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M1_shop_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_shop_2F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_stadium_1F.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M1_water_colo.rel` | rooms | `floor_render_entry` |
| `/Data/Relocatable Modules/M2_building_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_building_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M2_building_2F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_building_3F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_building_4F.rel` | rooms | `floor_render_offscreen_entry_char` |
| `/Data/Relocatable Modules/M2_cave_1F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_1F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_2F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_2F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_3F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_3F_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M2_cave_3F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_earth_colo.rel` | rooms | `floor_render_entry` |
| `/Data/Relocatable Modules/M2_enter_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_enter_1F_2.rel` | rooms | `floor_char_entry_render` |
| `/Data/Relocatable Modules/M2_guild_1F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_guild_1F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_hotel_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_houseA_1F.rel` | rooms | `floor_render_entry_offscreen_char` |
| `/Data/Relocatable Modules/M2_out.rel` | rooms | `floor_render_camera_char_entry` |
| `/Data/Relocatable Modules/M2_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M2_police_1F.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M2_shop_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_uranai_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_windmill_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_windmill_2F.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/M3_cave_1F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_cave_1F_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M3_cave_1F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_houseA_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_houseB_1F.rel` | rooms | `floor_render_entry_offscreen_char` |
| `/Data/Relocatable Modules/M3_houseC_1F.rel` | rooms | `floor_render_entry_offscreen_char` |
| `/Data/Relocatable Modules/M3_houseC_2F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_houseD_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_out.rel` | rooms+size | `floor_render_camera_entry_char_berry` |
| `/Data/Relocatable Modules/M3_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M3_pc_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_shop_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_shrine_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_shrine_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M3_shrine_1F_rl.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M4_bottom_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_bottom_colo.rel` | rooms | `floor_render_entry` |
| `/Data/Relocatable Modules/M4_cylinder_colo.rel` | rooms | `floor_render_entry` |
| `/Data/Relocatable Modules/M4_enter_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_enter_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_hotel_1F.rel` | rooms | `floor_render_entry_char_offscreen` |
| `/Data/Relocatable Modules/M4_hotel_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_houseA_1F.rel` | rooms | `floor_render_entry_offscreen_char` |
| `/Data/Relocatable Modules/M4_houseA_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M4_junk_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_junk_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_kanpo_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_labo_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_labo_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_out.rel` | rooms | `floor_render_camera_entry_offscreen_char` |
| `/Data/Relocatable Modules/M4_out_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/M4_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M4_shop_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_subway_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_subway_B2_1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M4_subway_B2_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M4_subway_B2_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_subway_B3.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M4_train_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/S1_out.rel` | rooms | `floor_camera_char_entry_render` |
| `/Data/Relocatable Modules/S1_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/S1_shop_1F.rel` | rooms | `floor_offscreen_char_entry_render` |
| `/Data/Relocatable Modules/S2_bossroom_1.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/S2_building_1F_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/S2_building_1F_2_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/S2_building_2F_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/S2_building_3F_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/S2_hallway_1.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/S2_out_1.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/S2_out_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/S2_out_3.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/S2_snatchroom_1.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/T1_ancient_colo.rel` | rooms+size | `floor_render_entry` |
| `/Data/Relocatable Modules/mail.rel` | none | `untyped` |
| `/Data/Relocatable Modules/pda_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/pocket_menu.rel` | legacy:pocketMenu | `module_pocketMenu` |
| `/Data/Relocatable Modules/toolbattle_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/worldmap_menu.rel` | none | `untyped` |

## Colosseum PAL

| Sources | legacy:pocketMenu: 5, none: 12, rooms: 159, rooms+size: 3 |
|---|---|

| REL | Source | Matcher |
|---|---|---|
| `/Assets/Misc/waza_viewer/waza_viewer.rel` | rooms+size | `floor_render` |
| `/Data/Relocatable Modules/D1_garage_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_garage_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_garage_B2_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_garage_B2_2.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D1_labo_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_labo_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_labo_B1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D1_labo_B2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_labo_B3.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_out.rel` | rooms | `floor_render_camera_entry_char` |
| `/Data/Relocatable Modules/D1_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_cloud_1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_cloud_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_cloud_2.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_cloud_3.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_cloud_4.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_crater_colo.rel` | rooms | `floor_render_camera_entry_char` |
| `/Data/Relocatable Modules/D2_crater_colo_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_magma_1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_magma_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_magma_2.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_magma_3.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_out.rel` | rooms | `floor_render_camera_entry_char` |
| `/Data/Relocatable Modules/D2_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_pc_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_pc_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_rest_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_3.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_4.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_5.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_6.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_7.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_8.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_9.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_valley_1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_valley_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_valley_2.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_valley_3.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D4_casino_colo.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_casino_colo_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_dome_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_10.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_11.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_2_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_dome_3.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_4.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_5.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_6.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_7.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_8.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_9.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_out.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_out_2.rel` | rooms | `floor_render_camera_entry_char` |
| `/Data/Relocatable Modules/D4_tower_1F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_1F_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_tower_1F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_1F_2_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_tower_1F_3.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_1F_3_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_tower_2F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_2F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_2F_2_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_tower_2F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/French/pda_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/French/pocket_menu.rel` | legacy:pocketMenu | `module_pocketMenu` |
| `/Data/Relocatable Modules/French/toolbattle_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/German/pda_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/German/pocket_menu.rel` | legacy:pocketMenu | `module_pocketMenu` |
| `/Data/Relocatable Modules/German/toolbattle_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/Italian/pda_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/Italian/pocket_menu.rel` | legacy:pocketMenu | `module_pocketMenu` |
| `/Data/Relocatable Modules/Italian/toolbattle_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/M1_carde_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_gym_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_gym_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M1_gym_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_houseA_1F.rel` | rooms | `floor_render_entry_char_offscreen` |
| `/Data/Relocatable Modules/M1_houseA_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M1_houseA_2F.rel` | rooms | `floor_render_offscreen_entry_char` |
| `/Data/Relocatable Modules/M1_houseB_1F.rel` | rooms | `floor_render_offscreen_entry_char` |
| `/Data/Relocatable Modules/M1_houseC_1F.rel` | rooms | `floor_render_entry_char_offscreen` |
| `/Data/Relocatable Modules/M1_out.rel` | rooms | `floor_entry_char_camera_render` |
| `/Data/Relocatable Modules/M1_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M1_pc_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_pc_B1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M1_shop_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_shop_2F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_stadium_1F.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M1_water_colo.rel` | rooms | `floor_render_entry` |
| `/Data/Relocatable Modules/M2_building_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_building_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M2_building_2F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_building_3F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_building_4F.rel` | rooms | `floor_render_offscreen_entry_char` |
| `/Data/Relocatable Modules/M2_cave_1F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_1F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_2F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_2F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_3F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_3F_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M2_cave_3F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_earth_colo.rel` | rooms | `floor_render_entry` |
| `/Data/Relocatable Modules/M2_enter_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_enter_1F_2.rel` | rooms | `floor_char_entry_render` |
| `/Data/Relocatable Modules/M2_guild_1F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_guild_1F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_hotel_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_houseA_1F.rel` | rooms | `floor_render_entry_offscreen_char` |
| `/Data/Relocatable Modules/M2_out.rel` | rooms | `floor_render_camera_char_entry` |
| `/Data/Relocatable Modules/M2_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M2_police_1F.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M2_shop_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_uranai_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_windmill_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_windmill_2F.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/M3_cave_1F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_cave_1F_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M3_cave_1F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_houseA_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_houseB_1F.rel` | rooms | `floor_render_entry_offscreen_char` |
| `/Data/Relocatable Modules/M3_houseC_1F.rel` | rooms | `floor_render_entry_offscreen_char` |
| `/Data/Relocatable Modules/M3_houseC_2F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_houseD_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_out.rel` | rooms+size | `floor_render_camera_entry_char_berry` |
| `/Data/Relocatable Modules/M3_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M3_pc_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_shop_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_shrine_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_shrine_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M3_shrine_1F_rl.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M4_bottom_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_bottom_colo.rel` | rooms | `floor_render_entry` |
| `/Data/Relocatable Modules/M4_cylinder_colo.rel` | rooms | `floor_render_entry` |
| `/Data/Relocatable Modules/M4_enter_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_enter_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_hotel_1F.rel` | rooms | `floor_render_entry_char_offscreen` |
| `/Data/Relocatable Modules/M4_hotel_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_houseA_1F.rel` | rooms | `floor_render_entry_offscreen_char` |
| `/Data/Relocatable Modules/M4_houseA_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M4_junk_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_junk_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_kanpo_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_labo_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_labo_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_out.rel` | rooms | `floor_render_camera_entry_offscreen_char` |
| `/Data/Relocatable Modules/M4_out_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/M4_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M4_shop_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_subway_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_subway_B2_1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M4_subway_B2_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M4_subway_B2_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_subway_B3.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M4_train_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/S1_out.rel` | rooms | `floor_camera_char_entry_render` |
| `/Data/Relocatable Modules/S1_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/S1_shop_1F.rel` | rooms | `floor_offscreen_char_entry_render` |
| `/Data/Relocatable Modules/S2_bossroom_1.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/S2_building_1F_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/S2_building_1F_2_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/S2_building_2F_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/S2_building_3F_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/S2_hallway_1.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/S2_out_1.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/S2_out_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/S2_out_3.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/S2_snatchroom_1.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/Spanish/pda_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/Spanish/pocket_menu.rel` | legacy:pocketMenu | `module_pocketMenu` |
| `/Data/Relocatable Modules/Spanish/toolbattle_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/T1_ancient_colo.rel` | rooms+size | `floor_render_entry` |
| `/Data/Relocatable Modules/mail.rel` | none | `untyped` |
| `/Data/Relocatable Modules/pda_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/pocket_menu.rel` | legacy:pocketMenu | `module_pocketMenu` |
| `/Data/Relocatable Modules/toolbattle_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/worldmap_menu.rel` | none | `untyped` |

## Colosseum JP

| Sources | legacy:pocketMenu: 1, none: 4, rooms: 159, rooms+size: 3 |
|---|---|

| REL | Source | Matcher |
|---|---|---|
| `/Assets/Misc/waza_viewer/waza_viewer.rel` | rooms+size | `floor_render` |
| `/Data/Relocatable Modules/D1_garage_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_garage_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_garage_B2_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_garage_B2_2.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D1_labo_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_labo_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_labo_B1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D1_labo_B2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_labo_B3.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D1_out.rel` | rooms | `floor_render_camera_entry_char` |
| `/Data/Relocatable Modules/D1_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_cloud_1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_cloud_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_cloud_2.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_cloud_3.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_cloud_4.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_crater_colo.rel` | rooms | `floor_render_camera_entry_char` |
| `/Data/Relocatable Modules/D2_crater_colo_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_magma_1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_magma_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_magma_2.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_magma_3.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_out.rel` | rooms | `floor_render_camera_entry_char` |
| `/Data/Relocatable Modules/D2_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_pc_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_pc_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_rest_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_3.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_4.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_5.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_6.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_7.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_8.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_rest_9.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D2_valley_1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_valley_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D2_valley_2.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D2_valley_3.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/D4_casino_colo.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_casino_colo_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_dome_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_10.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_11.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_2_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_dome_3.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_4.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_5.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_6.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_7.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_8.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_dome_9.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_out.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_out_2.rel` | rooms | `floor_render_camera_entry_char` |
| `/Data/Relocatable Modules/D4_tower_1F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_1F_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_tower_1F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_1F_2_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_tower_1F_3.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_1F_3_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_tower_2F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_2F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/D4_tower_2F_2_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/D4_tower_2F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M1_carde_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_gym_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_gym_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M1_gym_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_houseA_1F.rel` | rooms | `floor_render_entry_char_offscreen` |
| `/Data/Relocatable Modules/M1_houseA_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M1_houseA_2F.rel` | rooms | `floor_render_offscreen_entry_char` |
| `/Data/Relocatable Modules/M1_houseB_1F.rel` | rooms | `floor_render_offscreen_entry_char` |
| `/Data/Relocatable Modules/M1_houseC_1F.rel` | rooms | `floor_render_entry_char_offscreen` |
| `/Data/Relocatable Modules/M1_out.rel` | rooms | `floor_entry_char_camera_render` |
| `/Data/Relocatable Modules/M1_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M1_pc_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_pc_B1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M1_shop_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_shop_2F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M1_stadium_1F.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M1_water_colo.rel` | rooms | `floor_render_entry` |
| `/Data/Relocatable Modules/M2_building_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_building_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M2_building_2F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_building_3F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_building_4F.rel` | rooms | `floor_render_offscreen_entry_char` |
| `/Data/Relocatable Modules/M2_cave_1F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_1F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_2F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_2F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_3F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_cave_3F_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M2_cave_3F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_earth_colo.rel` | rooms | `floor_render_entry` |
| `/Data/Relocatable Modules/M2_enter_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_enter_1F_2.rel` | rooms | `floor_char_entry_render` |
| `/Data/Relocatable Modules/M2_guild_1F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_guild_1F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_hotel_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_houseA_1F.rel` | rooms | `floor_render_entry_offscreen_char` |
| `/Data/Relocatable Modules/M2_out.rel` | rooms | `floor_render_camera_char_entry` |
| `/Data/Relocatable Modules/M2_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M2_police_1F.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M2_shop_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_uranai_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_windmill_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M2_windmill_2F.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/M3_cave_1F_1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_cave_1F_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M3_cave_1F_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_houseA_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_houseB_1F.rel` | rooms | `floor_render_entry_offscreen_char` |
| `/Data/Relocatable Modules/M3_houseC_1F.rel` | rooms | `floor_render_entry_offscreen_char` |
| `/Data/Relocatable Modules/M3_houseC_2F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_houseD_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_out.rel` | rooms+size | `floor_render_camera_entry_char_berry` |
| `/Data/Relocatable Modules/M3_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M3_pc_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_shop_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_shrine_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M3_shrine_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M3_shrine_1F_rl.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M4_bottom_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_bottom_colo.rel` | rooms | `floor_render_entry` |
| `/Data/Relocatable Modules/M4_cylinder_colo.rel` | rooms | `floor_render_entry` |
| `/Data/Relocatable Modules/M4_enter_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_enter_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_hotel_1F.rel` | rooms | `floor_render_entry_char_offscreen` |
| `/Data/Relocatable Modules/M4_hotel_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_houseA_1F.rel` | rooms | `floor_render_entry_offscreen_char` |
| `/Data/Relocatable Modules/M4_houseA_1F_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M4_junk_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_junk_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_kanpo_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_labo_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_labo_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_out.rel` | rooms | `floor_render_camera_entry_offscreen_char` |
| `/Data/Relocatable Modules/M4_out_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/M4_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M4_shop_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_subway_B1.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_subway_B2_1.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M4_subway_B2_1_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/M4_subway_B2_2.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/M4_subway_B3.rel` | rooms | `floor_render_entry_char_camera` |
| `/Data/Relocatable Modules/M4_train_1F.rel` | rooms | `floor_render_entry_char` |
| `/Data/Relocatable Modules/S1_out.rel` | rooms | `floor_camera_char_entry_render` |
| `/Data/Relocatable Modules/S1_out_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/S1_shop_1F.rel` | rooms | `floor_offscreen_char_entry_render` |
| `/Data/Relocatable Modules/S2_bossroom_1.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/S2_building_1F_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/S2_building_1F_2_bf.rel` | rooms | `floor_render` |
| `/Data/Relocatable Modules/S2_building_2F_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/S2_building_3F_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/S2_hallway_1.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/S2_out_1.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/S2_out_2.rel` | rooms | `floor_render_char_entry` |
| `/Data/Relocatable Modules/S2_out_3.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/S2_snatchroom_1.rel` | rooms | `floor_render_char` |
| `/Data/Relocatable Modules/T1_ancient_colo.rel` | rooms+size | `floor_render_entry` |
| `/Data/Relocatable Modules/mail.rel` | none | `untyped` |
| `/Data/Relocatable Modules/pda_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/pocket_menu.rel` | legacy:pocketMenu | `module_pocketMenu` |
| `/Data/Relocatable Modules/toolbattle_menu.rel` | none | `untyped` |
| `/Data/Relocatable Modules/worldmap_menu.rel` | none | `untyped` |

