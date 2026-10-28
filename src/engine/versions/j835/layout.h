#pragma once
#include "engine/versions/common/progress.h"
#include <array>
#include <cstddef>
#include <optional>

namespace isaac::engine::j835::layout {
namespace string {
inline constexpr unsigned size = 0x10, capacity = 0x14, inlineCapacity = 0xf;
} // namespace string
namespace stringTable {
inline constexpr unsigned categories = 0xc;
} // namespace stringTable
namespace stringTree {
inline constexpr unsigned head = 0, count = 4;
inline constexpr unsigned left = 0, parent = 4, right = 8, nil = 0xd, key = 0x10, value = 0x14;
} // namespace stringTree
namespace vector {
inline constexpr unsigned begin = 0, end = 4;
} // namespace vector
namespace inputManager {
inline constexpr unsigned begin = 4, end = 8, stride = 4;
} // namespace inputManager
namespace inputDevice {
inline constexpr unsigned id = 8;
} // namespace inputDevice
namespace manager {
inline constexpr unsigned nightmare = 0x211bc;
inline constexpr unsigned music = 0x29a78;
inline constexpr unsigned renderFrame = 0x4a264;
inline constexpr unsigned options = 0x29df8;
inline constexpr unsigned progress = 0x14, scene = 0x8;
inline constexpr unsigned stringTable = 0x4a234;
inline constexpr unsigned characterConfigs = 0x29f90;
inline constexpr unsigned saveState = 0xf34;
inline constexpr unsigned saveSlot = 0x10, continueAvailable = 0x209c4;
inline constexpr unsigned continueRequested = 0x1ea6c1, deleteSaveRequested = 0x1ea814;
inline constexpr unsigned cinematicActive = 0x1ea830;
inline constexpr unsigned menuRequested = 0x1ea818, requestedMenu = 0x1ea81c;
} // namespace manager
namespace options {
inline constexpr unsigned hudOffset = 0x44;
inline constexpr unsigned musicVolume = 0x18;
} // namespace options
namespace music {
inline constexpr unsigned currentId = 0x30c, queuedId = 0x310;
} // namespace music
namespace progress {
inline constexpr unsigned dirty = 0, readOnly = 1;
inline constexpr unsigned achievements = 0x38, counters = 0x2b8;
inline constexpr unsigned achievementCount = 638, counterCount = 496;
inline constexpr native_progress::Layout fields{achievements, achievementCount, counters,
                                                counterCount};
} // namespace progress
namespace gameState {
inline constexpr unsigned stream = 0x1fac8;
// Local primary/backup and Steam primary/backup MSVC strings. Native Clear
// preserves these; Read consults them only for logging and failure deletion.
inline constexpr std::array<unsigned, 4> fileNames{0x1fa60, 0x1fa78, 0x1fa98, 0x1fab0};
} // namespace gameState
namespace roomChangeFrame {
inline constexpr std::ptrdiff_t mazeRedirected = 0xf;
} // namespace roomChangeFrame
namespace challengeHudFrame {
inline constexpr std::ptrdiff_t noUnlocks = -0x99;
} // namespace challengeHudFrame
namespace challengeParams {
inline constexpr unsigned stage = 0x40, alternatePath = 0x6d, secretPath = 0x88;
} // namespace challengeParams
namespace game {
inline constexpr unsigned pixelation = 0x24363c, pixelationDuration = 0x243640;
inline constexpr unsigned dizzyIntensity = 0x283c04, dizzyTarget = 0x283c08, dizzyStep = 0x283c0c;
inline constexpr unsigned bloomTime = 0x1c3148, bloomDuration = 0x1c314c, bloomIntensity = 0x1c3150;
inline constexpr unsigned itemOverlay = 0x1bcc0, bossOverlay = 0x1cf20;
inline constexpr unsigned hud = 0x3da4c;
inline constexpr unsigned victoryPrompt = 0x1c33fc;
inline constexpr unsigned rewindBuffers = 0x243648, selectedRewindBuffer = 0x283b78;
inline constexpr unsigned roomTransition = 0x1b6c0;
inline constexpr unsigned frame = 0x1a30dc;
inline constexpr unsigned generatedItems = 0x283c20;
inline constexpr unsigned room = 0x18190;
inline constexpr unsigned roomIndex = 0x18194, dimension = 0x1819c, enterDoor = 0x181ac;
inline constexpr unsigned curses = 0xc, seedCurses = 0x1c3170;
inline constexpr unsigned playerManager = 0x1ba40;
inline constexpr unsigned players = 0x1ba50;
inline constexpr unsigned stage = 0, stageType = 4;
inline constexpr unsigned floorSeeds = 0x1bb1c, stateFlags = 0x1c3168;
inline constexpr unsigned pauseMenu = 0x10203c, console = 0x1bb60;
inline constexpr unsigned fadeAlpha = 0x1c31a8, fadeAction = 0x1c31b0;
inline constexpr unsigned restartHeldFrames = 0x1c31b4;
} // namespace game
namespace itemOverlay {
inline constexpr unsigned size = 0x1260, state = 0, id = 4, book = 8;
inline constexpr unsigned configs = 0x11c, configCount = 47, configStride = 0x58;
inline constexpr unsigned mega = 0x114c, delay = 0x1144;
} // namespace itemOverlay
namespace bossOverlay {
inline constexpr unsigned state = 0, id = 4, sprite = 8;
} // namespace bossOverlay
namespace nightmare {
inline constexpr unsigned home = 0x5e8, index = 0x3a0, background = 0x20, bubble = 0x134;
} // namespace nightmare
namespace prompt {
inline constexpr unsigned animation = 0x34, playing = 0x44;
inline constexpr unsigned selection = 0x80218, result = 0x8021c;
} // namespace prompt
namespace rewindBuffer {
inline constexpr unsigned valid = 0, state = 4, stride = 0x20298;
inline constexpr unsigned door = 0x1fad0, tick = 0x1fad4, counters = 0x1fad8;
} // namespace rewindBuffer
namespace roomTransition {
inline constexpr unsigned actor = 0x320, bossIntro = 0x328;
inline constexpr unsigned state = 0, index = 0x14, direction = 0x10;
inline constexpr unsigned animation = 0x1c, dimension = 0x18;
} // namespace roomTransition
namespace room {
inline constexpr unsigned gridCells = 0x24, doors = 0x724, doorIndices = 0x744;
inline constexpr unsigned width = 0xc, height = 0x10, railGrid = 0x7350, railOwner = 0x734c;
inline constexpr unsigned firstBoss = 0x1d1c, secondBoss = 0x1d20;
inline constexpr unsigned enemies = 0x12c8, delayedEnemies = 0x12cc, descriptor = 4;
inline constexpr unsigned enteredFrame = 0x11f0;
inline constexpr unsigned entities = 0x1218;
} // namespace room
namespace roomDescriptor {
inline constexpr unsigned data = 0x10, flags = 0x44;
} // namespace roomDescriptor
namespace roomConfig {
inline constexpr unsigned stage = 0, type = 8, variant = 12;
} // namespace roomConfig
namespace entityList {
inline constexpr unsigned renderArray = 0x40, data = 4, count = 0xc;
} // namespace entityList
namespace entity {
inline constexpr std::array<unsigned, 4> shadow{0x150, 0x154, 0x158, 0x2a8};
inline constexpr unsigned damageQueue = 8, damageRecordSize = 0x38, index = 0x20;
inline constexpr unsigned interpolated = 0x16d;
inline constexpr unsigned variant = 0x2c, subtype = 0x30;
inline constexpr unsigned velocity = 0x2b8, friction = 0x2c4;
inline constexpr unsigned hitPoints = 0x2d8, maxHitPoints = 0x2dc, collisionDamage = 0x2e0;
inline constexpr unsigned visible = 0x169, flipX = 0x13c, depthOffset = 0x2b0;
inline constexpr unsigned mass = 0x2d4, size = 0x2c8;
inline constexpr unsigned spriteRotation = 0xe0, spriteOffset = 0xd0, spriteScale = 0xd8;
inline constexpr unsigned createdFrame = 0x280, flags = 0x160, color = 0x1b0;
inline constexpr unsigned damageVtableSlot = 0x3c;
inline constexpr unsigned sprite = 0x3c, type = 0x28, initSeed = 0x344;
inline constexpr unsigned active = 0x16a, removeMethod = 0x28;
inline constexpr unsigned positionX = 0x294, positionY = 0x298;
inline constexpr unsigned previousX = 0x29c, previousY = 0x2a0;
} // namespace entity
namespace entityRef {
inline constexpr unsigned entity = 0x24;
} // namespace entityRef
namespace itemConfig {
inline constexpr unsigned type = 0, id = 4, name = 8, chargeType = 0xac;
inline constexpr int active = 3, trinket = 2, specialCharge = 2;
} // namespace itemConfig
namespace generatedItem {
inline constexpr unsigned config = 0, seed = 8, configId = 4;
} // namespace generatedItem
namespace inventoryNode {
inline constexpr unsigned left = 0, parent = 4, right = 8;
inline constexpr unsigned nil = 0xd, id = 0x10, count = 0x14;
} // namespace inventoryNode
namespace pickup {
inline constexpr unsigned touched = 0x47c, optionsIndex = 0x478;
inline constexpr unsigned price = 0x480, autoUpdatePrice = 0x484, shopItemId = 0x488;
inline constexpr unsigned timeout = 0x48c, wait = 0x490, state = 0x4d0;
inline constexpr unsigned charge = 0x474, varData = 0x4e8;
} // namespace pickup
namespace npc {
inline constexpr unsigned boss = 0xb8d;
} // namespace npc
namespace tear {
inline constexpr unsigned height = 0x360, fallingSpeed = 0x364, fallingAcceleration = 0x368;
inline constexpr unsigned scale = 0x370, rotation = 0x3a8, waitFrames = 0x388;
} // namespace tear
namespace effect {
inline constexpr unsigned state = 0x3a0, timeout = 0x3ac, lifeSpan = 0x3b0;
inline constexpr unsigned rotation = 0x3c4, scale = 0x3c8;
inline constexpr unsigned minRadius = 0x3a4, maxRadius = 0x3a8;
} // namespace effect
namespace familiar {
inline constexpr unsigned state = 0xcd4, fireCooldown = 0xc9c, headFrameDelay = 0xca0;
inline constexpr unsigned moveDirection = 0xca4, shootDirection = 0xca8, lastDirection = 0xcac;
inline constexpr unsigned orbitAngleOffset = 0xcb0, orbitLayer = 0xcc0, orbitSpeed = 0xcbc;
} // namespace familiar
namespace sprite {
inline constexpr unsigned shadow = 0x10c, speed = 0x104, flags = 0x110;
inline constexpr unsigned overlayFirst = 0x70, layers = 0x7c, layerCount = 0x80;
inline constexpr unsigned animationOwner = 0x30, overlayOwner = 0x50;
inline constexpr unsigned loaded = 0x109, playing = 0x44, frame = 0x40;
inline constexpr unsigned size = 0x114, path = 0, animation = 0x30, overlay = 0x50;
inline constexpr unsigned offset = 0x94, scale = 0x9c, rotation = 0xa4, color = 0xa8;
inline constexpr unsigned flipX = 0x100, flipY = 0x101;
} // namespace sprite
namespace spriteLayer {
inline constexpr unsigned size = 0x9c, data = 0, id = 0, path = 8, flags = 0x88;
inline constexpr std::array<unsigned, 3> booleans{0x32, 0x33, 0x74};
inline constexpr std::array<unsigned, 18> numbers{0x34, 0x38, 0x3c, 0x40, 0x44, 0x48,
                                                  0x4c, 0x50, 0x54, 0x58, 0x5c, 0x60,
                                                  0x64, 0x68, 0x6c, 0x70, 0x8c, 0x90};
inline constexpr std::array<std::optional<unsigned>, 5> blend{0x78, 0x7c, 0x80, 0x84, std::nullopt};
} // namespace spriteLayer
namespace animationState {
inline constexpr unsigned layerFrames = 8, nullFrames = 0xc;
inline constexpr unsigned playing = 0x14, events = 0x18, previousEvents = 0x1c;
inline constexpr unsigned data = 4, frame = 0x10;
} // namespace animationState
namespace animationData {
inline constexpr unsigned layers = 0x18, layerCount = 0x1c, nulls = 0x20, nullCount = 0x24;
inline constexpr unsigned layerMap = 0x38, totalFrames = 0x30;
} // namespace animationData
namespace animationLayer {
inline constexpr unsigned stride = 0x10, id = 0, frameCount = 8, nullFrameCount = 0xc;
} // namespace animationLayer
namespace color {
inline constexpr unsigned size = 0x2c;
inline constexpr unsigned red = 0, green = 4, blue = 8, alpha = 0xc;
inline constexpr unsigned colorize = 0x10, colorizeChannels = 4;
inline constexpr unsigned redOffset = 0x20, greenOffset = 0x24, blueOffset = 0x28;
} // namespace color
namespace player {
inline constexpr std::array<unsigned, 2> poseFlags{0x12e8, 0x12ea};
inline constexpr unsigned blinkTime = 0x1288, damageCooldown = 0x1308;
inline constexpr unsigned costumesBegin = 0x1170, costumesEnd = 0x1174, costumeLayers = 0x117c;
inline constexpr unsigned weapons = 0x1328, nightLightAngle = 0x1a04;
inline constexpr unsigned controlsEnabled = 0x360;
inline constexpr unsigned index = 0x1550, twin = 0x1d80, coopGhost = 0x1f88;
inline constexpr unsigned hourglassUses = 0x1cc8, hourglassFloorUses = 0x1ccc;
inline constexpr unsigned generatedInventoryHead = 0x1ec4, generatedInventorySize = 0x1ec8;
inline constexpr unsigned primaryActive = 0x14c4, activeStride = 0x1c, megaBlastLaser = 0x13a0;
inline constexpr unsigned controller = 0x154c;
} // namespace player
namespace hud {
inline constexpr unsigned visible = 0xc3eb6;
inline constexpr std::array<std::array<float, 2>, 4> heartOrigins{
    {{68, 24}, {-135, 24}, {80, -33}, {-135, -33}}};
inline constexpr std::array<std::array<float, 2>, 4> heartMargins{
    {{-20, -12}, {24, -12}, {-22, 6}, {16, 6}}};
} // namespace hud
namespace playerHud {
inline constexpr unsigned player = 0, root = 4, index = 8, size = 0x6b0;
} // namespace playerHud
namespace mouseFrame {
inline constexpr std::size_t bytes = 0x240;
inline constexpr std::ptrdiff_t active = -0x150, aimX = -0x15c, aimY = -0x158;
inline constexpr float roomScale = 0.65f, pixelScale = 0.02f;
} // namespace mouseFrame
namespace pauseMenu {
inline constexpr unsigned selection = 8, options = 0x806a8;
} // namespace pauseMenu
namespace pauseOptions {
inline constexpr unsigned selection = 4, entries = 0x260;
} // namespace pauseOptions
namespace console {
inline constexpr unsigned state = 0x20;
} // namespace console
namespace luaEngine {
inline constexpr unsigned state = 0x18;
} // namespace luaEngine
namespace weapon {
inline constexpr unsigned kind = 0x2c, modifiers = 0x30, maxChargeMethod = 6;
inline constexpr std::array<unsigned, 3> charge{0xc, 0x10, 0x14};
} // namespace weapon
namespace costume {
inline constexpr unsigned stride = 0x130, path = 0;
inline constexpr unsigned layerStride = 0x10, index = 0, layerId = 4, priority = 8, body = 0xc;
} // namespace costume
namespace grid {
inline constexpr unsigned sprite = 0x40, extraSprite = 0x164, type = 4, variant = 8, index = 0x24;
} // namespace grid
} // namespace isaac::engine::j835::layout
