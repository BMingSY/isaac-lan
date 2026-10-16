#pragma once

// Portable subsets of the game's EntityType, PlayerType, LevelStage, StageType
// and Difficulty enums. Values match the existing J460 policies; these are
// gameplay IDs, never native object layouts or network message tags.
// Reference: https://wofsauge.github.io/IsaacDocs/rep/enums/EntityType.html
namespace isaac::compat::ids {
namespace entity {
inline constexpr unsigned bomb = 4;
inline constexpr unsigned hornfel = 906;
inline constexpr unsigned hornyBoys = 920;
inline constexpr unsigned rotgut = 911;
inline constexpr unsigned effect = 1000;
inline constexpr unsigned isaac = 102;
inline constexpr unsigned lamb = 273;
inline constexpr unsigned megaSatan = 274;
inline constexpr unsigned megaSatanSecond = 275;
inline constexpr unsigned ultraGreed = 406;
inline constexpr unsigned hush = 407;
inline constexpr unsigned delirium = 412;
inline constexpr unsigned darkEsau = 866;
inline constexpr unsigned mothersShadow = 867;
inline constexpr unsigned mother = 912;
inline constexpr unsigned dogma = 950;
inline constexpr unsigned beast = 951;
inline constexpr unsigned genericProp = 960;
} // namespace entity
namespace effect {
inline constexpr unsigned waterSplash = 99;
} // namespace effect
namespace player {
inline constexpr int soulB = 40;
inline constexpr int cainB = 23;
inline constexpr int keeper = 14;
inline constexpr int keeperB = 33;
inline constexpr int lostB = 31;
inline constexpr int lazarusB = 29;
inline constexpr int jacobB = 37;
inline constexpr int lazarusSecondB = 38;
inline constexpr int jacobSecondB = 39;
} // namespace player
namespace collectible {
inline constexpr int nightLight = 425;
inline constexpr int compass = 21;
inline constexpr int treasureMap = 54;
inline constexpr int steamSale = 64;
inline constexpr int blueMap = 246;
inline constexpr int blackCandle = 260;
inline constexpr int restock = 376;
inline constexpr int damoclesPassive = 656;
inline constexpr int sacredOrb = 691;
inline constexpr int tmtrainer = 721;
} // namespace collectible
namespace stage {
inline constexpr int greedFinal = 7;
inline constexpr int chapterFourSecond = 8;
inline constexpr int blueWomb = 9;
inline constexpr int chestOrDarkRoom = 11;
inline constexpr int voidFloor = 12;
inline constexpr int home = 13;
} // namespace stage
namespace stageType {
inline constexpr int original = 0;
inline constexpr int wrathOfTheLamb = 1;
inline constexpr int repentance = 4;
inline constexpr int repentanceB = 5;
} // namespace stageType
namespace difficulty {
inline constexpr unsigned greed = 2;
inline constexpr unsigned greedier = 3;
} // namespace difficulty
namespace dimension {
inline constexpr int minesEscape = 1;
} // namespace dimension
} // namespace isaac::compat::ids
