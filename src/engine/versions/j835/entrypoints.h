#pragma once
#include <cstdint>

// J835 entries audited against the original executable. This is not a complete
// backend: there is no sources.cmake and builds must reject selection.
namespace isaac::engine::j835 {
namespace entry {
inline constexpr std::uint32_t victoryPromptControls = 0x3f21f0;
inline constexpr std::uint32_t victoryPromptHide = 0x3f2340;
inline constexpr std::uint32_t victoryPromptRender = 0x3f1f30;
inline constexpr std::uint32_t craftingBagHudRender = 0x500570;
inline constexpr std::uint32_t playerHudPocketRender = 0x4fe8e0;
inline constexpr std::uint32_t playerGetActiveItem = 0xf3f10;
inline constexpr std::uint32_t hUDChallengeDestination = 0x5050ab;
inline constexpr std::uint32_t hUDChallengeParamsRead = 0x505584;
inline constexpr std::uint32_t npcTakeDamage = 0x2ac370;
inline constexpr std::uint32_t entitySetColor = 0x28a380;
inline constexpr std::uint32_t entityDamageColorReturn = 0x286ff9;
inline constexpr std::uint32_t entityDamageDrain = 0x28701d;
inline constexpr std::uint32_t gameStoreHourglass = 0x2d7f80;
inline constexpr std::uint32_t engineRoomsTransition = 0x2d07d0;
inline constexpr std::uint32_t engineRoomsStageTransition = 0x2d0aa0;
inline constexpr std::uint32_t roomTransitionStart = 0x3e9650;
inline constexpr std::uint32_t menuCharacterAvailable = 0x4a1ea0;
inline constexpr std::uint32_t stringTableLookup = 0x56b880;
inline constexpr std::uint32_t luaEngineInit = 0x3fcb00;
inline constexpr std::uint32_t runtimeNetCapture = 0x2cc850;
inline constexpr std::uint32_t runtimeNetClear = 0x520160;
inline constexpr std::uint32_t engineSaveWrite = 0x521a00;
inline constexpr std::uint32_t engineSaveRead = 0x524320;
inline constexpr std::uint32_t managerSave = 0x4b3850;
inline constexpr std::uint32_t managerDeleteSave = 0x4b3b70;
inline constexpr std::uint32_t managerSaveRerun = 0x4b3bb0;
inline constexpr std::uint32_t managerExecuteMenu = 0x4b43d0;
inline constexpr std::uint32_t managerExecuteStart = 0x4b3fd0;
inline constexpr std::uint32_t progressSerialize = 0x4836a0;
inline constexpr std::uint32_t progressPersist = 0x4848f0;
inline constexpr std::uint32_t gameStart = 0x2c97e0;
inline constexpr std::uint32_t gameUpdate = 0x2cdcf0;
inline constexpr std::uint32_t gameControls = 0x2cda60;
inline constexpr std::uint32_t consoleUpdate = 0x263550;
inline constexpr std::uint32_t consoleRunCommand = 0x2655c0;
inline constexpr std::uint32_t consolePrint = 0x26aec0;
inline constexpr std::uint32_t runtimeNetExecuteStart = 0x515b50;
inline constexpr std::uint32_t frontendAssign = 0x7c80;
inline constexpr std::uint32_t frontendMenuUpdate = 0x7be0;
inline constexpr std::uint32_t runtimeNetParseSeed = 0x53e080;
inline constexpr std::uint32_t runtimeNetSeedConstructor = 0x53bc50;
inline constexpr std::uint32_t runtimeNetSetSeed = 0x53e220;
inline constexpr std::uint32_t runtimeNetStartGame = 0x4b3470;
inline constexpr std::uint32_t inputPressed = 0x56a520;
inline constexpr std::uint32_t inputTriggered = 0x56a5e0;
inline constexpr std::uint32_t inputValue = 0x56a6c0;
inline constexpr std::uint32_t inputEnumerateDevices = 0x59d3b0;
inline constexpr std::uint32_t inputPollDevices = 0x59d720;
inline constexpr std::uint32_t inputUpdate = 0x56a150;
inline constexpr std::uint32_t pauseMenuControls = 0x515ba0;
inline constexpr std::uint32_t pauseMenuShow = 0x5178e0;
inline constexpr std::uint32_t pauseMenuHide = 0x517810;
inline constexpr std::uint32_t optionsSave = 0x4805a0;
inline constexpr std::uint32_t playerMouseBegin = 0x3439ac;
inline constexpr std::uint32_t playerMouseEnd = 0x343ca2;
inline constexpr std::uint32_t windowClientHeight = 0x561100;
inline constexpr std::uint32_t playerShootingEntity = 0x341840;
inline constexpr std::uint32_t playerManagerSpawn = 0x518810;
inline constexpr std::uint32_t playerAssignController = 0x36b140;
inline constexpr std::uint32_t playerInitialize = 0x380810;
inline constexpr std::uint32_t gameGetHUD = 0x127c0;
inline constexpr std::uint32_t hudAssignPlayers = 0x506f10;
inline constexpr std::uint32_t playerAddCollectible = 0x32b260;
inline constexpr std::uint32_t playerQueueItem = 0x32a500;
inline constexpr std::uint32_t edensBlessingGranted = 0x382207;
inline constexpr std::uint32_t pickupQueuedCollectible = 0x2c1610;
inline constexpr std::uint32_t playerReviveCollectible = 0x367370;
inline constexpr std::uint32_t playerReviveTrinket = 0x3687c0;
inline constexpr std::uint32_t managerGetItemConfig = 0x27930;
inline constexpr std::uint32_t itemConfigGetCollectible = 0x2fe5e0;
inline constexpr std::uint32_t playerHasCollectible = 0x33af30;
inline constexpr std::uint32_t playerDropCollectible = 0x3570e0;
inline constexpr std::uint32_t playerActiveMaxCharge = 0x357e40;
inline constexpr std::uint32_t playerAddActiveCharge = 0x358030;
inline constexpr std::uint32_t levelTryInitializeBlueRoom = 0x31a1f0;
inline constexpr std::uint32_t entityPtrAssign = 0x28cf00;
inline constexpr std::uint32_t levelRoomEntryResolved = 0x30d7fe;
inline constexpr std::uint32_t levelRoomChangeReturn = 0x30db01;
inline constexpr std::uint32_t levelMazeBranch = 0x30d1a8;
inline constexpr std::uint32_t levelMazeBranchEnd = 0x30d650;
inline constexpr std::uint32_t gameAddedSeedCurses = 0x2ccc80;
inline constexpr std::uint32_t gameRemovedSeedCurses = 0x2cce10;
inline constexpr std::uint32_t audioPlay = 0x488de0;
inline constexpr std::uint32_t musicPlay = 0x3a2070;
inline constexpr std::uint32_t musicCrossfade = 0x3a2170;
inline constexpr std::uint32_t roomUpdateMusic = 0x3a9f20;
inline constexpr std::uint32_t generatedItemCreate = 0x532980;
inline constexpr std::uint32_t generatedItemRestoreCall = 0x535cbb;
inline constexpr std::uint32_t generatedInventoryQuery = 0x33afcf;
inline constexpr std::uint32_t generatedInventoryCountRead = 0x535e2e;
inline constexpr std::uint32_t pickupUpdateGhosts = 0x2b81c0;
inline constexpr std::uint32_t entityLuaSetSize = 0x40e460;
inline constexpr std::uint32_t entityLuaSetColor = 0x40e430;
inline constexpr std::uint32_t tearSetHeight = 0x2500f0;
inline constexpr std::uint32_t tearSetScale = 0x250250;
inline constexpr std::uint32_t pickupSetPrice = 0x2b91e0;
inline constexpr std::uint32_t roomUpdate = 0x3bf630;
inline constexpr std::uint32_t gameUpdateHalf = 0x2d0400;
inline constexpr std::uint32_t gameRender = 0x2ce770;
} // namespace entry
namespace globals {
inline constexpr std::uint32_t logicalWidth = 0x7fec08, logicalHeight = 0x7fec68;
inline constexpr std::uint32_t characterMenuPages = 0x60d698;
inline constexpr std::uint32_t characterMenuEntries = 0x60d6b0;
inline constexpr std::uint32_t game = 0x7fd65c;
inline constexpr std::uint32_t manager = 0x7fd680;
inline constexpr std::uint32_t inputManager = 0x7e7c98;
inline constexpr std::uint32_t viewportReferenceHeight = 0x7aa930;
} // namespace globals
} // namespace isaac::engine::j835
