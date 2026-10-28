#pragma once
#include "engine/versions/common/progress.h"
#include <array>
#include <cstddef>
#include <optional>
#include <cstdint>

// J460 object offsets and native container sizes. No ownership or gameplay policy.
namespace isaac::engine::j460::layout {
namespace string {
inline constexpr unsigned size = 0x10;
inline constexpr unsigned capacity = 0x14;
inline constexpr unsigned inlineBytes = 0x10;
inline constexpr unsigned inlineCapacity = 0xf;
} // namespace string
namespace vector {
inline constexpr unsigned begin = 0x0;
inline constexpr unsigned end = 0x4;
inline constexpr unsigned capacity = 0x8;
inline constexpr unsigned words = 0x3;
} // namespace vector
namespace inputManager {
inline constexpr unsigned begin = 8, end = 12, stride = 8;
inline constexpr unsigned queryMethod = 0x74;
} // namespace inputManager
namespace inputDevice {
inline constexpr unsigned id = 12;
} // namespace inputDevice
namespace manager {
inline constexpr unsigned nightmare = 0x21628;
inline constexpr unsigned renderFrame = 0x4abbc, buttonPrompts = 0x4a950;
inline constexpr unsigned options = 0x2a33c;
inline constexpr unsigned characterConfigs = 0x2a678;
inline constexpr unsigned scene = 0x8;
inline constexpr unsigned saveSlot = 0x10;
inline constexpr unsigned progress = 0x14;
inline constexpr unsigned saveState = 0xfa4;
inline constexpr unsigned continueAvailable = 0x20dcc;
inline constexpr unsigned cinematicActive = 0x21618;
inline constexpr unsigned music = 0x29fbc;
inline constexpr unsigned stringTable = 0x4a920;
inline constexpr unsigned continueRequested = 0x4b131;
inline constexpr unsigned deleteSaveRequested = 0x4b284;
inline constexpr unsigned menuRequested = 0x4b288;
inline constexpr unsigned requestedMenu = 0x4b28c;
inline constexpr unsigned chat = 0x4c608;
inline constexpr unsigned chatFont = 0x4ae74;
inline constexpr unsigned pendingEmote = 0x4ccac;
inline constexpr unsigned menuInputBlock = 0x4d074;
} // namespace manager
namespace options {
inline constexpr unsigned musicVolume = 0x18;
} // namespace options
namespace music {
inline constexpr unsigned currentId = 0x30c;
inline constexpr unsigned queuedId = 0x310;
} // namespace music
namespace progress {
inline constexpr unsigned achievementCount = 642, counterCount = 523;
inline constexpr native_progress::Layout fields{0x38, achievementCount, 0x2bc, counterCount};
inline constexpr unsigned readOnly = 0x1;
inline constexpr unsigned achievements = 0x38;
inline constexpr unsigned counters = 0x2bc;
} // namespace progress
namespace roomChangeFrame {
inline constexpr unsigned mazeRedirected = 0xb;
} // namespace roomChangeFrame
namespace playerRenderFrame {
inline constexpr std::ptrdiff_t mainPass = 0xc;
inline constexpr std::ptrdiff_t hologram = -0x6d;
} // namespace playerRenderFrame
namespace game {
inline constexpr unsigned itemOverlay = 0x1c034, bossOverlay = 0x1d2ec;
inline constexpr unsigned hud = 0x1da04, introPlayer = 0x1bb74, controlRestoreGuard = 0x26614;
inline constexpr unsigned victoryPrompt = 0x26778;
inline constexpr unsigned rewindBuffers = 0x269ec, selectedRewindBuffer = 0x676ac;
inline constexpr unsigned roomTransition = 0x1b83c;
inline constexpr unsigned transitionTailCounter = 0x265c0, transitionTailFlag = 0x67744;
inline constexpr unsigned bloomTime = 0x26528;
inline constexpr unsigned bloomDuration = 0x2652c;
inline constexpr unsigned bloomIntensity = 0x26530;
inline constexpr unsigned pixelation = 0x269e0;
inline constexpr unsigned pixelationDuration = 0x269e4;
inline constexpr unsigned dizzyIntensity = 0x67738;
inline constexpr unsigned dizzyTarget = 0x6773c;
inline constexpr unsigned dizzyStep = 0x67740;
inline constexpr unsigned curses = 0xc;
inline constexpr unsigned seedCurses = 0x26550;
inline constexpr unsigned stage = 0x0;
inline constexpr unsigned stageType = 0x4;
inline constexpr unsigned room = 0x18300;
inline constexpr unsigned roomIndex = 0x18304;
inline constexpr unsigned previousRoomIndex = 0x18308;
inline constexpr unsigned dimension = 0x1830c;
inline constexpr unsigned previousDimension = 0x18310;
inline constexpr unsigned leaveDoor = 0x18318;
inline constexpr unsigned enterDoor = 0x1831c;
inline constexpr unsigned playerManager = 0x1baa8, players = playerManager;
inline constexpr unsigned floorSeeds = 0x1bb84;
inline constexpr unsigned pauseMenu = 0x23a74;
inline constexpr unsigned emoteWheel = 0x25108;
inline constexpr unsigned minimap = 0x25ecc;
inline constexpr unsigned frame = 0x264f8;
inline constexpr unsigned stateFlags = 0x26548;
inline constexpr unsigned console = 0x68d78;
inline constexpr unsigned fadeAlpha = 0x265b0;
inline constexpr unsigned fadeAction = 0x265bc;
inline constexpr unsigned restartHeldFrames = 0x265c4;
inline constexpr unsigned generatedItems = 0x67758;
} // namespace game
namespace itemOverlay {
inline constexpr unsigned size = 0x12b8, state = 0, id = 4, book = 8;
inline constexpr unsigned configs = 0x11c, configCount = 48, configStride = 0x58;
inline constexpr unsigned mega = 0x11a4, delay = 0x119c;
} // namespace itemOverlay
namespace bossOverlay {
inline constexpr unsigned state = 0, id = 4, sprite = 8;
} // namespace bossOverlay
namespace nightmare {
inline constexpr unsigned home = 0x5e8, index = 0x3a0, background = 0x20, bubble = 0x134;
} // namespace nightmare
namespace prompt {
inline constexpr unsigned animation = 0x34, playing = 0x44;
inline constexpr unsigned selection = 0x128, result = 0x12c, nativeVote = 0x130;
} // namespace prompt
namespace rewindBuffer {
inline constexpr unsigned valid = 0, state = 4, stride = 0x20660;
inline constexpr unsigned door = 0x1fe2c, tick = 0x1fe30, counters = 0x1fe34;
} // namespace rewindBuffer
namespace roomTransition {
inline constexpr unsigned state = 0, index = 0x14, direction = 0x10;
inline constexpr unsigned animation = 0x1c, dimension = 0x18, active = 0x238;
} // namespace roomTransition
namespace pauseMenu {
inline constexpr unsigned selection = 8, options = 0x5b0, playerIndex = 0xfac;
} // namespace pauseMenu
namespace pauseOptions {
inline constexpr unsigned selection = 8, entries = 0x27c;
} // namespace pauseOptions
namespace gameState {
inline constexpr unsigned stream = 0x1fe24;
inline constexpr std::array<unsigned, 4> fileNames{0x1fdac, 0x1fdc4, 0x1fdf4, 0x1fe0c};
} // namespace gameState
namespace room {
inline constexpr unsigned gridCells = 0x24, doors = 0x724, doorIndices = 0x744;
inline constexpr unsigned width = 0xc, height = 0x10, railGrid = 0x746c, railOwner = 0x7468;
inline constexpr unsigned firstBoss = 0x1bb0, secondBoss = 0x1bb4;
inline constexpr unsigned enemies = 0x12c8, delayedEnemies = 0x12cc, descriptor = 4;
inline constexpr unsigned size = 0x7898;
inline constexpr unsigned enteredFrame = 0x11f0;
inline constexpr unsigned nextEntityIndex = 0x1214;
inline constexpr unsigned entities = 0x1218;
} // namespace room
namespace roomDescriptor {
inline constexpr unsigned flags = 0x44;
inline constexpr unsigned safeGridIndex = 0x4;
inline constexpr unsigned data = 0x10;
inline constexpr unsigned overrideData = 0x14;
inline constexpr unsigned allowedDoors = 0x18;
inline constexpr unsigned doors = 0x1c;
inline constexpr unsigned doorCount = 8;
inline constexpr unsigned visitedCount = 0x40;
} // namespace roomDescriptor
namespace roomConfig {
inline constexpr unsigned stage = 0;
inline constexpr unsigned type = 0x8;
inline constexpr unsigned variant = 0xc;
inline constexpr unsigned doors = 0x38;
inline constexpr unsigned shape = 0x48;
inline constexpr int anyVariant = -1;
inline constexpr int normalMode = 0;
inline constexpr int specialStage = 0;
inline constexpr int maxType = 29;
inline constexpr int maxDifficulty = 10;
} // namespace roomConfig
namespace entityList {
inline constexpr unsigned firstArray = 0x20;
inline constexpr unsigned lastArray = 0x90;
inline constexpr unsigned arrayStride = 0x10;
inline constexpr unsigned renderArray = 0x40;
inline constexpr unsigned data = 0x4;
inline constexpr unsigned count = 0xc;
} // namespace entityList
namespace entity {
inline constexpr unsigned minecart = 0x3d4;
inline constexpr std::array<unsigned, 4> shadow{0x15c, 0x160, 0x164, 0x350};
inline constexpr unsigned damageQueue = 0x8;
inline constexpr unsigned damageRecordSize = 0x38;
inline constexpr unsigned removeMethod = 0x28;
inline constexpr unsigned subtype = 0x30;
inline constexpr unsigned initSeed = 0x3ec;
inline constexpr unsigned velocity = 0x360;
inline constexpr unsigned friction = 0x36c;
inline constexpr unsigned hitPoints = 0x380;
inline constexpr unsigned maxHitPoints = 0x384;
inline constexpr unsigned collisionDamage = 0x388;
inline constexpr unsigned visible = 0x171;
inline constexpr unsigned flipX = 0x148;
inline constexpr unsigned depthOffset = 0x358;
inline constexpr unsigned mass = 0x37c;
inline constexpr unsigned size = 0x370;
inline constexpr unsigned spriteRotation = 0xec;
inline constexpr unsigned spriteOffset = 0xdc;
inline constexpr unsigned spriteScale = 0xe4;
inline constexpr unsigned createdFrame = 0x328;
inline constexpr unsigned flags = 0x168;
inline constexpr unsigned damageVtableSlot = 0x40;
inline constexpr unsigned color = 0x1b8;
inline constexpr unsigned index = 0x20;
inline constexpr unsigned type = 0x28;
inline constexpr unsigned sprite = 0x48;
inline constexpr unsigned variant = 0x2c;
inline constexpr unsigned registered = 0x170;
inline constexpr unsigned active = 0x172;
inline constexpr unsigned interpolated = 0x175;
inline constexpr unsigned positionX = 0x33c;
inline constexpr unsigned positionY = 0x340;
inline constexpr unsigned previousX = 0x344;
inline constexpr unsigned previousY = 0x348;
inline constexpr unsigned parent = 0x3bc;
} // namespace entity
namespace entityRef {
inline constexpr unsigned entity = 0x24;
} // namespace entityRef
namespace npc {
// EntityNPC::IsBoss reads this classification byte, independently of BossID.
inline constexpr unsigned boss = 0xc3d;
} // namespace npc
namespace tear {
inline constexpr unsigned height = 0x410;
inline constexpr unsigned fallingSpeed = 0x414;
inline constexpr unsigned fallingAcceleration = 0x418;
inline constexpr unsigned scale = 0x420;
inline constexpr unsigned rotation = 0x458;
inline constexpr unsigned waitFrames = 0x438;
} // namespace tear
namespace effect {
inline constexpr unsigned state = 0x450;
inline constexpr unsigned timeout = 0x45c;
inline constexpr unsigned lifeSpan = 0x460;
inline constexpr unsigned rotation = 0x474;
inline constexpr unsigned scale = 0x478;
inline constexpr unsigned minRadius = 0x454;
inline constexpr unsigned maxRadius = 0x458;
} // namespace effect
namespace familiar {
inline constexpr unsigned state = 0xd88;
inline constexpr unsigned fireCooldown = 0xd4c;
inline constexpr unsigned headFrameDelay = 0xd50;
inline constexpr unsigned moveDirection = 0xd54;
inline constexpr unsigned shootDirection = 0xd58;
inline constexpr unsigned lastDirection = 0xd5c;
inline constexpr unsigned orbitAngleOffset = 0xd60;
inline constexpr unsigned orbitSpeed = 0xd6c;
inline constexpr unsigned orbitLayer = 0xd70;
} // namespace familiar
namespace sprite {
inline constexpr unsigned shadow = 0x10c, speed = 0x104, flags = 0x110;
inline constexpr unsigned overlayFirst = 0x70, layers = 0x7c, layerCount = 0x80;
inline constexpr unsigned loaded = 0x109, playing = 0x44, frame = 0x40;
inline constexpr unsigned size = 0x114;
inline constexpr unsigned path = 0x0;
inline constexpr unsigned animation = 0x30;
inline constexpr unsigned overlay = 0x50;
inline constexpr unsigned offset = 0x94;
inline constexpr unsigned scale = 0x9c;
inline constexpr unsigned rotation = 0xa4;
inline constexpr unsigned color = 0xa8;
inline constexpr unsigned flipX = 0x100;
inline constexpr unsigned flipY = 0x101;
// Both native animation states store a non-owning pointer to their ANM2.
inline constexpr unsigned animationOwner = 0x30;
inline constexpr unsigned overlayOwner = 0x50;
} // namespace sprite
namespace spriteLayer {
inline constexpr unsigned size = 0xa0, data = 0, id = 0, path = 8, flags = 0x8c;
inline constexpr std::array<unsigned, 3> booleans{0x32, 0x33, 0x74};
inline constexpr std::array<unsigned, 18> numbers{0x34, 0x38, 0x3c, 0x40, 0x44, 0x48,
                                                  0x4c, 0x50, 0x54, 0x58, 0x5c, 0x60,
                                                  0x64, 0x68, 0x6c, 0x70, 0x90, 0x94};
inline constexpr std::array<std::optional<unsigned>, 5> blend{0x78, 0x7c, 0x80, 0x84, 0x88};
} // namespace spriteLayer
namespace animationState {
inline constexpr unsigned data = 0x4;
inline constexpr unsigned layerFrames = 0x8, nullFrames = 0xc;
inline constexpr unsigned frame = 0x10;
inline constexpr unsigned playing = 0x14, events = 0x18, previousEvents = 0x1c;
} // namespace animationState
namespace animationData {
inline constexpr unsigned layers = 0x18, layerCount = 0x1c;
inline constexpr unsigned nulls = 0x20, nullCount = 0x24;
inline constexpr unsigned layerMap = 0x38;
inline constexpr unsigned totalFrames = 0x30;
} // namespace animationData
namespace animationLayer {
inline constexpr unsigned stride = 0x10, id = 0x0, frameCount = 0x8;
inline constexpr unsigned nullFrameCount = 0xc;
} // namespace animationLayer
namespace color {
inline constexpr unsigned size = 0x2c;
inline constexpr unsigned red = 0x0, green = 0x4, blue = 0x8, alpha = 0xc;
inline constexpr unsigned colorize = 0x10, colorizeChannels = 4;
inline constexpr unsigned redOffset = 0x20, greenOffset = 0x24, blueOffset = 0x28;
} // namespace color
namespace itemConfig {
inline constexpr unsigned type = 0, id = 4, name = 8;
inline constexpr int active = 3, trinket = 2;
} // namespace itemConfig
namespace pickup {
inline constexpr unsigned charge = 0x524, touched = 0x52c, pool = 0x530, varData = 0x59c;
inline constexpr unsigned optionsIndex = 0x528, price = 0x534, autoUpdatePrice = 0x538;
inline constexpr unsigned shopItemId = 0x53c, timeout = 0x540, wait = 0x544, state = 0x584;
} // namespace pickup
namespace player {
inline constexpr unsigned heldEntity = 0x1410;
inline constexpr std::array<unsigned, 2> poseFlags{0x1398, 0x139a};
inline constexpr unsigned blinkTime = 0x1338, damageCooldown = 0x13bc;
inline constexpr unsigned costumesBegin = 0x1220, costumesEnd = 0x1224, costumeLayers = 0x122c;
inline constexpr unsigned controlsEnabled = 0x410;
inline constexpr unsigned hourglassUses = 0x1da8, hourglassFloorUses = 0x1dac;
inline constexpr unsigned weapons = 0x13dc;
inline constexpr unsigned babySkin = 0x1aec;
inline constexpr int lastBabySkin = 0x47;
inline constexpr unsigned roomTransitionTarget = 0x1b1c;
inline constexpr unsigned primaryActive = 0x1580;
inline constexpr unsigned megaBlastLaser = 0x1458;
inline constexpr unsigned redemptionEffect = 0x1f04;
inline constexpr unsigned megaBlastDuration = 0x18f4;
inline constexpr unsigned emote = 0x26d8;
inline constexpr unsigned type = 0x13c0;
inline constexpr unsigned controller = 0x1618;
inline constexpr unsigned index = 0x161c;
inline constexpr unsigned twin = 0x1e68;
inline constexpr unsigned coopGhost = 0x20a9;
inline constexpr unsigned nightLightAngle = 0x1ae4;
inline constexpr unsigned generatedInventoryHead = 0x1fcc;
inline constexpr unsigned generatedInventorySize = 0x1fd0;
} // namespace player
namespace weapon {
inline constexpr std::array<unsigned, 3> charge{0xc, 0x10, 0x14};
inline constexpr unsigned kind = 0x30;
inline constexpr unsigned modifiers = 0x34;
inline constexpr unsigned maxChargeMethod = 6;
} // namespace weapon
namespace tether {
inline constexpr unsigned extraData = 0xee0, points = 0x8, capacity = 0xc;
inline constexpr unsigned first = 0x10, count = 0x14, sprite = 0x18, size = 0x158;
inline constexpr unsigned maxPoints = 256;
inline constexpr unsigned dataVtable = 0x71d264;
} // namespace tether
namespace familiarBody {
inline constexpr unsigned extraData = 0xee0, dataVtable = 0x764914;
inline constexpr unsigned sprites = 0x4, spriteCount = 5;
inline constexpr unsigned layers = 0x568, layerCount = 4;
} // namespace familiarBody
namespace emote {
inline constexpr unsigned id = 0x4;
inline constexpr int lastId = 58;
inline constexpr unsigned duration = 90;
} // namespace emote
namespace emoteWheel {
inline constexpr unsigned state = 0x4, radius = 0x840;
inline constexpr unsigned participantBytes = 0x37c, participantDevice = 0x378, controllerId = 0xc;
} // namespace emoteWheel
namespace generatedItem {
inline constexpr unsigned config = 0x0;
inline constexpr unsigned seed = 0x8;
inline constexpr unsigned configId = 0x4;
} // namespace generatedItem
namespace inventoryNode {
inline constexpr unsigned left = 0x0;
inline constexpr unsigned parent = 0x4;
inline constexpr unsigned right = 0x8;
inline constexpr unsigned nil = 0xd;
inline constexpr unsigned id = 0x10;
inline constexpr unsigned count = 0x14;
} // namespace inventoryNode
namespace menuManager {
inline constexpr unsigned inputBlocked = 0xd;
inline constexpr unsigned page = 0x40;
} // namespace menuManager
namespace mainMenu {
inline constexpr unsigned selection = 0x4;
} // namespace mainMenu
namespace console {
inline constexpr unsigned state = 0;
} // namespace console
namespace chat {
inline constexpr unsigned size = 0x628;
inline constexpr unsigned text = 0xc;
inline constexpr unsigned textLayout = 0x24;
inline constexpr unsigned inputState = 0x68;
inline constexpr unsigned style = 0x5d8;
inline constexpr unsigned styleSize = 0x44;
} // namespace chat
namespace statHud {
inline constexpr unsigned player = 0x114;
inline constexpr unsigned cacheStride = 0xcc;
inline constexpr unsigned cacheCount = 0x2;
} // namespace statHud
namespace playerHud {
inline constexpr unsigned size = 0x6dc;
inline constexpr unsigned player = 0x0;
inline constexpr unsigned root = 0x4;
inline constexpr unsigned refreshFlags = 0x6ac;
inline constexpr unsigned refreshAll = 0x101;
} // namespace playerHud
namespace challengeHudFrame {
inline constexpr std::ptrdiff_t noUnlocks = -0xa2;
} // namespace challengeHudFrame
namespace challengeParams {
inline constexpr unsigned stage = 0x40, destinationType = 0x80;
} // namespace challengeParams
namespace hud {
inline constexpr unsigned visible = 0x54cc;
inline constexpr unsigned pocketOffsetX = 0x594c, pocketOffsetY = 0x5950;
inline constexpr unsigned history = 0x5c54;
} // namespace hud
namespace minimap {
inline constexpr unsigned small = 0x18;
inline constexpr unsigned large = 0x178;
} // namespace minimap
namespace mapConfig {
inline constexpr unsigned texture = 0x114;
inline constexpr unsigned cellWidth = 0x124;
inline constexpr unsigned cellHeight = 0x128;
inline constexpr unsigned cellSpacing = 0x130;
inline constexpr unsigned anchorX = 0x140;
inline constexpr unsigned anchorY = 0x144;
} // namespace mapConfig
namespace texture {
inline constexpr unsigned width = 0x10;
inline constexpr unsigned height = 0x14;
inline constexpr unsigned renderVtableSlot = 0x10;
} // namespace texture
namespace renderQuad {
inline constexpr unsigned pixels = 0x20;
} // namespace renderQuad
namespace luaEngine {
inline constexpr unsigned state = 0x18;
} // namespace luaEngine
namespace costume {
inline constexpr unsigned stride = 0x130, path = 0;
inline constexpr unsigned layerStride = 0x10, index = 0, layerId = 4, priority = 8, body = 0xc;
} // namespace costume
namespace grid {
inline constexpr unsigned sprite = 0x40, extraSprite = 0x27c, type = 4, variant = 8, index = 0x24;
} // namespace grid
namespace heldBombs {
inline constexpr unsigned container = 0xbf0, map = 4, capacity = 8, first = 0xc, count = 0x10,
                          blockElements = 4;
} // namespace heldBombs
} // namespace isaac::engine::j460::layout
