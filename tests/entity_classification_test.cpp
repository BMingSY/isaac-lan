// Production Lua binding, actual MSVC RTTI and private x86 objects only.
#include "engine/versions/j460/entity_fields.cpp"
#include "support/native_entity_types.h"
#include <array>

namespace isaac::runtime {
bool testReplica = true;
bool replica() {
    return testReplica;
}
} // namespace isaac::runtime

namespace {
namespace adapter = isaac::entity_fields;
namespace native = isaac::engine::j460;
using Address = std::uintptr_t;
struct Fixture {
    void* image = VirtualAlloc(nullptr, native::rtti::npc + 128, MEM_COMMIT | MEM_RESERVE,
                               PAGE_EXECUTE_READWRITE);
    isaac::test::NativeEntityTypes types{reinterpret_cast<Address>(image)};
    std::array<unsigned char, 0x1000> object{};
    std::array<Address, 2> sprite{0, reinterpret_cast<Address>(object.data()) +
                                         native::layout::entity::sprite};
    ~Fixture() {
        VirtualFree(image, 0, MEM_RELEASE);
    }
};
std::string error;
bool desired = true, result = false;
int firstType = 7, secondType = 1;
std::size_t length = 8;
Fixture* current;
void apply(bool boss) {
    desired = boss;
    result = false;
    error.clear();
    require(adapter::npcBoss(nullptr) == 1 && result && error.empty(),
            "NPC classification did not restore");
}
void reject(const char* expected) {
    const auto before = current->object;
    result = false;
    rejects([] { adapter::npcBoss(nullptr); }, "Invalid NPC classification accepted");
    require(error == expected && !result && current->object == before,
            "Rejected classification changed entity state or lost its error");
}
void classification() {
    Fixture f;
    current = &f;
    adapter::image = reinterpret_cast<Address>(f.image);
    adapter::api.type = [](lua_State*, int index) { return index == 1 ? firstType : secondType; };
    adapter::api.rawLength = [](lua_State*, int) { return length; };
    adapter::api.toUserdata = [](lua_State*, int) -> void* { return current->sprite.data(); };
    adapter::api.toBoolean = [](lua_State*, int) { return int(desired); };
    adapter::api.pushBoolean = [](lua_State*, int value) { result = value != 0; };
    adapter::api.pushString = [](lua_State*, const char* value) {
        error = value;
        return error.c_str();
    };
    adapter::api.error = [](lua_State*) -> int { throw std::runtime_error(error); };
    const auto object = reinterpret_cast<Address>(f.object.data());
    f.types.npc(object);
    adapter::at<bool>(object, native::layout::entity::active) = true;
    for (const auto kind : {10u, 999u, 1000u, 6617u, 6621u, 0xffffffffu}) {
        adapter::at<unsigned>(object, native::layout::entity::type) = kind;
        for (const auto boss : {false, true, true, false}) {
            auto expected = f.object;
            expected[native::layout::npc::boss] = boss;
            apply(boss);
            require(f.object == expected, "Classification changed unrelated NPC bytes");
        }
    }
    require(native::entity_cast::npc(adapter::image, 0) == 0, "Null entity was cast");
    // Numeric IDs never authorize writing NPC fields into another native class.
    f.types.effect(object);
    for (const auto kind : {10u, 6617u, 1000u}) {
        adapter::at<unsigned>(object, native::layout::entity::type) = kind;
        reject("NPC classification requires an NPC");
    }
    f.types.npc(object);
    adapter::at<bool>(object, native::layout::entity::active) = false;
    reject("Entity is no longer active");
    adapter::at<bool>(object, native::layout::entity::active) = true;
    isaac::runtime::testReplica = false;
    reject("NPC classification requires a replica and a boolean");
    isaac::runtime::testReplica = true;
    secondType = 3;
    reject("NPC classification requires a replica and a boolean");
    secondType = 1;
    firstType = 5;
    reject("Expected borrowed entity Sprite");
    firstType = 7;
    length = native::layout::sprite::size + 8;
    reject("Expected borrowed entity Sprite");
    length = 8;
    f.sprite[1] = 0;
    reject("Invalid entity Sprite");
    f.sprite[1] = object + native::layout::entity::sprite;
    apply(true);
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv, {{"classification", classification}});
}
