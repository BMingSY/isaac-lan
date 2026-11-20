#include "test_support.h"
#include "engine/versions/common/entity_pose.cpp"
#include "engine/versions/common/sprite_state.cpp"
#include <cstring>
#include <iostream>
#include <limits>
#ifdef ISAAC_LAN_TEST_J835
constexpr unsigned spriteOffset = 0x3c, costumeBegin = 0x1170, costumeEnd = 0x1174;
constexpr unsigned layerBegin = 0x117c, flagFirst = 0x12e8, flagSecond = 0x12ea;
constexpr unsigned blinkTime = 0x1288, damageCooldown = 0x1308, nightAngle = 0x1a04;
constexpr unsigned weaponsBegin = 0x1328, weaponKind = 0x2c, weaponModifiers = 0x30;
constexpr std::array<unsigned, 4> shadowOffsets{0x150, 0x154, 0x158, 0x2a8};
#else
constexpr unsigned spriteOffset = 0x48, costumeBegin = 0x1220, costumeEnd = 0x1224;
constexpr unsigned layerBegin = 0x122c, flagFirst = 0x139c, flagSecond = 0x139e;
constexpr unsigned blinkTime = 0x1338, damageCooldown = 0x13c0, nightAngle = 0x1ae4;
constexpr unsigned weaponsBegin = 0x13e0, weaponKind = 0x30, weaponModifiers = 0x34;
constexpr std::array<unsigned, 4> shadowOffsets{0x15c, 0x160, 0x164, 0x350};
#endif
struct lua_State {
    int top = 1;
    std::size_t userdataBytes = 8;
    std::array<std::uintptr_t, 2> wrapper{};
    bool validWrapper = true, success = false;
    std::string input, output;
};
namespace {
namespace pose = isaac::engine::native_entity_pose;
using Address = std::uintptr_t;
bool replica = false;
std::string error;
float queryResult = -2.5f;
std::vector<void*> queryReceivers;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
Address address(const void* pointer) {
    return reinterpret_cast<Address>(pointer);
}
std::string hexBytes(const std::string& text) {
    std::string result;
    for (unsigned i = 0; i < text.size(); i += 2)
        result += static_cast<char>(std::stoul(text.substr(i, 2), nullptr, 16));
    return result;
}
float __attribute__((fastcall)) maximum(void* weapon, void*) {
    queryReceivers.push_back(weapon);
    return queryResult;
}
struct Player {
    std::array<unsigned char, 0x1b00> object;
    std::array<std::array<unsigned char, 0x130>, 4> costumes;
    std::array<std::array<unsigned char, 0x40>, 5> weapons;
    std::array<Address, 7> methods{};
    Player() {
        object.fill(0xa5);
        field<unsigned>(object.data(), 0x28) = 1;
        field<Address>(object.data(), costumeBegin) = address(costumes.data());
        field<Address>(object.data(), costumeEnd) = address(costumes.data());
        field<bool>(object.data(), flagFirst) = true;
        field<bool>(object.data(), flagSecond) = false;
        field<unsigned>(object.data(), blinkTime) = 17;
        field<unsigned>(object.data(), damageCooldown) = 23;
        field<float>(object.data(), nightAngle) = 90;
        methods[6] = address(reinterpret_cast<void*>(maximum));
        for (unsigned i = 0; i < weapons.size(); ++i) {
            weapons[i].fill(0xa5);
            field<Address>(object.data(), weaponsBegin + 4 * i) = 0;
            field<Address>(weapons[i].data(), 0) = address(methods.data());
            field<Address>(weapons[i].data(), 4) = address(object.data());
            field<unsigned>(weapons[i].data(), weaponKind) = i + 1;
            field<float>(weapons[i].data(), 0xc) = 1;
            field<float>(weapons[i].data(), 0x10) = 2;
            field<float>(weapons[i].data(), 0x14) = 3;
            field<unsigned>(weapons[i].data(), weaponModifiers) = 0x87654321;
        }
        for (unsigned i = 0; i < 4; ++i) {
            costumes[i].fill(0xa5);
            field<float>(object.data(), shadowOffsets[i]) = static_cast<float>(i) - 2;
        }
        for (unsigned i = 0; i < 15; ++i) {
            auto* layer = object.data() + layerBegin + i * 0x10;
            field<int>(layer, 0) = -1;
            field<unsigned>(layer, 4) = i;
            field<unsigned>(layer, 8) = 9;
            field<bool>(layer, 12) = true;
        }
    }
    void setCostumes(std::initializer_list<std::string_view> paths) {
        unsigned i = 0;
        for (auto path : paths) {
            require(path.size() <= 15, "Fixture costume must fit the inline string");
            auto* native = costumes[i++].data();
            std::memcpy(native, path.data(), path.size());
            field<unsigned>(native, 0x10) = path.size();
            field<unsigned>(native, 0x14) = 15;
        }
        field<Address>(object.data(), costumeEnd) = address(costumes.data()) + i * 0x130;
    }
    void enableWeapon(unsigned slot) {
        field<Address>(object.data(), weaponsBegin + 4 * slot) = address(weapons[slot].data());
    }
};
struct Snapshot {
    decltype(Player::object) object;
    decltype(Player::costumes) costumes;
    decltype(Player::weapons) weapons;
    explicit Snapshot(const Player& value)
        : object(value.object), costumes(value.costumes), weapons(value.weapons) {}
    bool matches(const Player& value) const {
        return object == value.object && costumes == value.costumes && weapons == value.weapons;
    }
};
lua_State invoke(Player& player, bool shadow = false, const std::string* packet = nullptr) {
    lua_State L;
    L.wrapper = {0x87654321, address(player.object.data()) + spriteOffset};
    if (packet) {
        L.top = 2;
        L.input = *packet;
    }
    error.clear();
    require((shadow ? pose::entityShadow(&L) : pose::actorPose(&L)) == 1,
            "Pose return count changed");
    return L;
}
void configureLua() {
    pose::lua.getTop = [](lua_State* L) { return L->top; };
    pose::lua.toUserdata = [](lua_State* L, int) -> void* {
        return L->validWrapper ? L->wrapper.data() : nullptr;
    };
    pose::lua.rawLength = [](lua_State* L, int) { return L->userdataBytes; };
    pose::lua.checkString = [](lua_State* L, int, std::size_t* size) {
        *size = L->input.size();
        return L->input.c_str();
    };
    pose::lua.pushLString = [](lua_State* L, const char* value, std::size_t size) -> const char* {
        L->output.assign(value, size);
        return L->output.c_str();
    };
    pose::lua.pushBoolean = [](lua_State* L, int value) { L->success = value; };
}
} // namespace
namespace isaac::runtime {
bool replica() {
    return ::replica;
}
void abort(const std::string& reason) {
    error = reason;
}
} // namespace isaac::runtime
int main() {
    try {
        configureLua();
        Player empty;
        const Snapshot emptyBefore(empty);
        const auto prefix = hexBytes("0100000000110000001742b40000");
        auto emptyGolden = prefix + std::string(7, '\0'); // Five absent weapons and zero costumes.
        for (unsigned i = 0; i < 15; ++i)
            emptyGolden += hexBytes("ffffffff000000") + std::string(1, static_cast<char>(i)) +
                           hexBytes("0000000901");
        require(invoke(empty).output == emptyGolden && emptyBefore.matches(empty),
                "Actor wire prefix or costume layer encoding changed");
        require(!invoke(empty, false, &emptyGolden).success && emptyBefore.matches(empty),
                "Authority accepted actor pose writes");
        replica = true;
        require(invoke(empty, false, &emptyGolden).success && emptyBefore.matches(empty),
                "Repeated empty actor pose changed resources");
        auto invalidWrapper = invoke(empty);
        for (auto size : {0u, 4u, 12u, 0x11cu}) {
            invalidWrapper.userdataBytes = size;
            invalidWrapper.output.clear();
            pose::actorPose(&invalidWrapper);
            require(invalidWrapper.output.empty() && !invalidWrapper.success,
                    "Actor pose accepted an owning or malformed Sprite");
            pose::entityShadow(&invalidWrapper);
            require(invalidWrapper.output.empty() && !invalidWrapper.success,
                    "Shadow pose accepted an owning or malformed Sprite");
        }
        Player host, guest;
        host.setCostumes({"hat", "hat", "boots", "missing"});
        guest.setCostumes({"hat", "boots", "hat"});
        for (unsigned i = 0; i < 15; ++i) {
            auto* layer = host.object.data() + layerBegin + 16 * i;
            field<int>(layer, 0) = i % 4;
            field<unsigned>(layer, 4) = 14 - i;
        }
        for (unsigned i = 0; i < 5; ++i)
            host.enableWeapon(i);
        for (unsigned i : {0u, 1u, 2u, 4u})
            guest.enableWeapon(i);
        field<unsigned>(guest.weapons[1].data(), weaponKind) =
            20; // A different locally owned weapon.
        field<unsigned>(guest.object.data(), blinkTime) = 99;
        field<unsigned>(guest.object.data(), damageCooldown) = 100;
        field<float>(guest.object.data(), nightAngle) = -45;
        for (auto& weapon : guest.weapons) {
            field<float>(weapon.data(), 0xc) = 10;
            field<float>(weapon.data(), 0x10) = 20;
            field<float>(weapon.data(), 0x14) = 30;
            field<unsigned>(weapon.data(), weaponModifiers) = 0;
        }
        queryReceivers.clear();
        const auto packet = invoke(host).output;
        require(packet.substr(0, 14) == prefix &&
                    packet.substr(14, 25) ==
                        hexBytes("01000000013f8000004000000040400000c020000087654321"),
                "Native weapon kind, x87 charge query or modifier layout changed the wire record");
        require(queryReceivers.size() == 5, "Actor capture missed a native weapon slot");
        for (unsigned i = 0; i < 5; ++i)
            require(queryReceivers[i] == host.weapons[i].data(),
                    "Native maximum query used the wrong receiver or slot");
        const Snapshot guestBefore(guest);
        for (unsigned length = 0; length < packet.size(); ++length) {
            auto bad = packet.substr(0, length);
            require(!invoke(guest, false, &bad).success && guestBefore.matches(guest),
                    "Truncated actor packet partially changed the player or weapons");
        }
        for (unsigned kind = 0; kind < 9; ++kind) {
            auto bad = packet;
            if (kind == 0)
                bad += 'x';
            if (kind == 1)
                bad[0] = 2;
            if (kind == 2)
                bad[14] = 2;
            if (kind == 3)
                bad.replace(10, 4, hexBytes("7fc00000"));
            if (kind == 4)
                bad.replace(19, 4, hexBytes("7f800000"));
            if (kind == 5)
                bad.replace(31, 4, hexBytes("ff800000"));
            if (kind == 6)
                bad.back() = 2;
            if (kind == 7)
                bad.replace(bad.size() - 15 * 13 + 4, 4, hexBytes("00000040"));
            if (kind == 8)
                bad.replace(14 + 5 * 25, 2, hexBytes("1001"));
            require(!invoke(guest, false, &bad).success && guestBefore.matches(guest),
                    "Invalid actor state reached native memory before full validation");
        }
        require(invoke(guest, false, &packet).success, "Valid actor snapshot failed");
        const std::array<int, 4> mapping{0, 2, 1, -1};
        for (unsigned i = 0; i < 15; ++i) {
            auto* layer = guest.object.data() + layerBegin + i * 16;
            const auto local = mapping[i % 4];
            require(
                field<int>(layer, 0) == local &&
                    field<unsigned>(layer, 4) == (local < 0 ? i : 14 - i),
                "Costumes were matched by array position or duplicate paths lost occurrence order");
            require(std::memcmp(layer + 13, guestBefore.object.data() + layerBegin + i * 16 + 13,
                                3) == 0,
                    "Actor pose wrote layer padding");
        }
        require(guest.costumes == guestBefore.costumes,
                "Actor pose transferred costume/Sprite resource ownership");
        for (unsigned i = 0; i < 5; ++i) {
            const bool matches = i != 1 && i != 3;
            require(field<float>(guest.weapons[i].data(), 0xc) == (matches ? 1 : 10) &&
                        field<float>(guest.weapons[i].data(), 0x14) == (matches ? 3 : 30),
                    "Pose created an absent weapon or wrote a mismatched kind");
            auto expected = guestBefore.weapons[i];
            if (matches) {
                for (unsigned offset : {0xcu, 0x10u, 0x14u, weaponModifiers})
                    field<unsigned>(expected.data(), offset) =
                        field<unsigned>(host.weapons[i].data(), offset);
            }
            require(expected == guest.weapons[i],
                    "Pose changed weapon pointers, native kind, or read-only maximum");
        }
        require(field<unsigned>(guest.object.data(), blinkTime) == 17 &&
                    field<unsigned>(guest.object.data(), damageCooldown) == 23 &&
                    field<float>(guest.object.data(), nightAngle) == 90,
                "Blink, damage cooldown or Night Light angle used another version's field");
        const Snapshot repeated(guest);
        require(invoke(guest, false, &packet).success && repeated.matches(guest),
                "Repeated actor snapshot did not settle");
        // Replacing the borrowed player must not reuse the previous costume mapping.
        Player replacement;
        replacement.setCostumes({"boots"});
        require(invoke(replacement, false, &packet).success &&
                    field<int>(replacement.object.data(), layerBegin) == -1 &&
                    field<int>(replacement.object.data(), layerBegin + 32) == 0,
                "New player retained a previous player's costume mapping");
        queryResult = std::numeric_limits<float>::quiet_NaN();
        require(invoke(host).output.empty(), "Non-finite native maximum escaped capture");
        queryResult = -2.5f;
        field<Address>(host.object.data(), costumeEnd) += 1;
        require(invoke(host).output.empty(), "Malformed native costume vector was walked");
        field<Address>(host.object.data(), costumeEnd) -= 1;
        field<unsigned>(host.object.data(), 0x28) = 3;
        require(invoke(host).output.empty(), "Actor pose accepted a familiar");
        field<unsigned>(host.object.data(), 0x28) = 1;

        const auto shadowPacket = invoke(host, true).output;
        require(shadowPacket == hexBytes("c0000000bf800000000000003f800000"),
                "Entity shadow packet read the wrong size, position or altitude");
        field<unsigned>(guest.object.data(), 0x28) = 3; // Shadow capability also serves nonplayers.
        for (auto offset : shadowOffsets)
            field<float>(guest.object.data(), offset) = 100;
        const Snapshot beforeShadow(guest);
        for (unsigned length = 0; length < shadowPacket.size(); ++length) {
            auto bad = shadowPacket.substr(0, length);
            require(!invoke(guest, true, &bad).success && beforeShadow.matches(guest),
                    "Truncated shadow packet partially applied");
        }
        for (unsigned offset = 0; offset < 16; offset += 4) {
            auto bad = shadowPacket;
            bad.replace(offset, 4, hexBytes("7fc00000"));
            require(!invoke(guest, true, &bad).success && beforeShadow.matches(guest),
                    "Invalid shadow number partially applied");
        }
        auto trailing = shadowPacket + 'x';
        require(!invoke(guest, true, &trailing).success && beforeShadow.matches(guest),
                "Shadow packet accepted trailing data");
        replica = false;
        require(!invoke(guest, true, &shadowPacket).success && beforeShadow.matches(guest),
                "Authority accepted a shadow write");
        replica = true;
        require(invoke(guest, true, &shadowPacket).success &&
                    invoke(guest, true).output == shadowPacket,
                "Shadow state did not restore");
        auto expected = beforeShadow.object;
        for (auto offset : shadowOffsets)
            field<unsigned>(expected.data(), offset) = field<unsigned>(host.object.data(), offset);
        require(expected == guest.object && guest.costumes == beforeShadow.costumes &&
                    guest.weapons == beforeShadow.weapons,
                "Shadow state changed adjacent entity fields or owned resources");
        std::cout << "Entity pose layouts, fixed bytes, costume ownership, weapon ABI and atomic "
                     "validation passed\n";
    } catch (const std::exception& failure) {
        std::cerr << failure.what() << '\n';
        return 1;
    }
}
