#include "test_support.h"
#include "engine/versions/common/entity_fields.cpp"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
#else
#include "engine/versions/j510/entrypoints.h"
namespace backend = isaac::engine::j510;
#endif
#include "support/native_entity_types.h"
#include "engine/versions/common/entity_size.h"
#include <memory>
#include <vector>

namespace {
namespace adapter = isaac::entity_fields;
using Address = std::uintptr_t;
// Minimal Lua stack fixture: the production compiler, validation, capture and
// restore entry points run unchanged. It does not implement property behavior.
struct Blob {
    std::vector<std::uint64_t> storage;
    std::size_t size;
    explicit Blob(std::size_t n) : storage((n + 7) / 8), size(n) {}
};
struct Value {
    int type = 0;
    bool integer = false;
    std::int64_t number = 0;
    double real = 0;
    std::string text;
    std::vector<Value> array;
    std::shared_ptr<Blob> blob;
    static Value boolean(bool b) {
        Value v;
        v.type = 1;
        v.number = b;
        return v;
    }
    static Value i(std::int64_t n) {
        Value v;
        v.type = 3;
        v.integer = true;
        v.number = n;
        v.real = static_cast<double>(n);
        return v;
    }
    static Value f(double n) {
        Value v;
        v.type = 3;
        v.real = n;
        return v;
    }
    static Value s(std::string text) {
        Value v;
        v.type = 4;
        v.text = std::move(text);
        return v;
    }
    static Value list(std::vector<Value> values) {
        Value v;
        v.type = 5;
        v.array = std::move(values);
        return v;
    }
    static Value data(std::size_t n) {
        Value v;
        v.type = 7;
        v.blob = std::make_shared<Blob>(n);
        return v;
    }
};
Value names(std::initializer_list<const char*> fields) {
    std::vector<Value> values;
    for (auto field : fields)
        values.push_back(Value::s(field));
    return Value::list(std::move(values));
}
bool same(const Value& a, const Value& b) {
    if (a.type != b.type)
        return false;
    if (a.type == 1)
        return a.number == b.number;
    if (a.type == 3)
        return a.integer && b.integer ? a.number == b.number : a.real == b.real;
    if (a.type == 4)
        return a.text == b.text;
    if (a.type != 5 || a.array.size() != b.array.size())
        return false;
    for (unsigned i = 0; i < a.array.size(); ++i)
        if (!same(a.array[i], b.array[i]))
            return false;
    return true;
}
bool replica = false, stackAvailable = true;
} // namespace
struct lua_State {
    std::vector<Value> stack;
    Value& at(int index) {
        return stack.at(index > 0 ? index - 1 : static_cast<int>(stack.size()) + index);
    }
};
namespace isaac::runtime {
bool replica() {
    return ::replica;
}
} // namespace isaac::runtime
namespace {
void connectLua() {
    auto& api = adapter::api;
    api.type = [](lua_State* L, int i) {
        const auto index = i > 0 ? i - 1 : static_cast<int>(L->stack.size()) + i;
        return index >= 0 && index < static_cast<int>(L->stack.size()) ? L->at(i).type : -1;
    };
    api.getTop = [](lua_State* L) { return static_cast<int>(L->stack.size()); };
    api.setTop = [](lua_State* L, int n) { L->stack.resize(n); };
    api.checkStack = [](lua_State*, int) { return int(stackAvailable); };
    api.toBoolean = [](lua_State* L, int i) { return int(L->at(i).number != 0); };
    api.toNumber = [](lua_State* L, int i, int*) { return L->at(i).real; };
    api.toInteger = [](lua_State* L, int i, int*) { return L->at(i).number; };
    api.isInteger = [](lua_State* L, int i) { return int(L->at(i).integer); };
    api.checkInteger = [](lua_State* L, int i) -> long long {
        require(L->at(i).integer, "Expected integer argument");
        return L->at(i).number;
    };
    api.toString = [](lua_State* L, int i, std::size_t* n) {
        if (n)
            *n = L->at(i).text.size();
        return L->at(i).text.c_str();
    };
    api.rawLength = [](lua_State* L, int i) -> std::size_t {
        auto& v = L->at(i);
        return v.type == 7 ? v.blob->size : v.type == 5 ? v.array.size() : v.text.size();
    };
    api.toUserdata = [](lua_State* L, int i) -> void* { return L->at(i).blob->storage.data(); };
    api.newUserdata = [](lua_State* L, std::size_t n) -> void* {
        L->stack.push_back(Value::data(n));
        return L->stack.back().blob->storage.data();
    };
    api.rawGetI = [](lua_State* L, int i, long long n) {
        auto value = L->at(i).array.at(n - 1);
        L->stack.push_back(std::move(value));
        return L->stack.back().type;
    };
    api.rawSetI = [](lua_State* L, int i, long long n) {
        auto& array = L->at(i).array;
        if (array.size() < static_cast<std::size_t>(n))
            array.resize(n);
        array[n - 1] = L->stack.back();
        L->stack.pop_back();
    };
    api.createTable = [](lua_State* L, int, int) { L->stack.push_back(Value::list({})); };
    api.pushBoolean = [](lua_State* L, int b) { L->stack.push_back(Value::boolean(b)); };
    api.pushInteger = [](lua_State* L, long long n) { L->stack.push_back(Value::i(n)); };
    api.pushNumber = [](lua_State* L, double n) { L->stack.push_back(Value::f(n)); };
    api.pushLString = [](lua_State* L, const char* s, std::size_t n) {
        L->stack.push_back(Value::s(std::string(s, n)));
        return L->stack.back().text.c_str();
    };
    api.pushString = [](lua_State* L, const char* s) {
        L->stack.push_back(Value::s(s));
        return L->stack.back().text.c_str();
    };
    api.error = [](lua_State* L) -> int { throw std::runtime_error(L->stack.back().text); };
}
Value call(isaac::lua::Function fn, std::initializer_list<Value> args) {
    lua_State L{args};
    require(fn(&L) == 1, "Native field entry returned an unexpected result count");
    return L.stack.back();
}
Value plan(unsigned type, const Value& fields) {
    return call(adapter::run<0>, {Value::i(type), fields});
}
template <class T> T& at(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
#ifdef ISAAC_LAN_TEST_J835
constexpr unsigned spriteOffset = 0x3c, activeOffset = 0x16a, frameOffset = 0x1a30dc;
constexpr unsigned sizeOffset = 0x2c8, colorOffset = 0x1b0, damageOffset = 0x2e0;
constexpr unsigned heightOffset = 0x360, scaleOffset = 0x370, priceOffset = 0x480;
constexpr unsigned bossOffset = 0xb8d, damageMethod = 0x3c;
constexpr unsigned positionOffset = 0x294, flagsOffset = 0x160, createdOffset = 0x280;
#else
constexpr unsigned spriteOffset = 0x48, activeOffset = 0x172, frameOffset = 0x26508;
constexpr unsigned sizeOffset = 0x370, colorOffset = 0x1b8, damageOffset = 0x388;
constexpr unsigned heightOffset = 0x410, scaleOffset = 0x420, priceOffset = 0x534;
constexpr unsigned bossOffset = 0xc3d, damageMethod = 0x40;
constexpr unsigned positionOffset = 0x33c, flagsOffset = 0x168, createdOffset = 0x328;
#endif
std::array<unsigned char, 0x1000> entity{};
std::vector<unsigned char> game(frameOffset + 16);
std::array<Address, 32> vtable{};
unsigned char* image;
std::vector<std::string> setters;
void verifyReceiver(void* self, const char* name) {
    require(self == entity.data(), "Setter received the wrong native object");
    setters.emplace_back(name);
}
void __cdecl setSize(void* self, float value) {
    verifyReceiver(self, "size");
    at<float>(self, sizeOffset) = value;
}
void __attribute__((thiscall)) setExplicitSize(void* self, float value,
                                               isaac::engine::native_entity_size::Multiplier, int) {
    setSize(self, value);
}
void __cdecl setColor(void* self, const void* value) {
    verifyReceiver(self, "color");
    std::memcpy(entity.data() + colorOffset, value, 44);
    for (unsigned i = 4; i < 8; ++i)
        require(static_cast<const float*>(value)[i] == 0, "Colorize was not initialized");
}
void __attribute__((thiscall)) setDamage(void* self, float value) {
    verifyReceiver(self, "damage");
    at<float>(self, damageOffset) = value;
}
void __attribute__((thiscall)) setHeight(void* self, float value) {
    verifyReceiver(self, "height");
    at<float>(self, heightOffset) = value;
}
void __attribute__((thiscall)) setScale(void* self, float value) {
    verifyReceiver(self, "scale");
    at<float>(self, scaleOffset) = value;
}
void __attribute__((thiscall)) setPrice(void* self, int value) {
    verifyReceiver(self, "price");
    at<int>(self, priceOffset) = value;
}
void jump(unsigned rva, Address target) {
    image[rva] = 0xe9;
    const auto delta = target - reinterpret_cast<Address>(image + rva + 5);
    std::memcpy(image + rva + 1, &delta, 4);
}
void reset(unsigned type) {
    entity.fill(0);
    at<Address>(entity.data(), 0) = reinterpret_cast<Address>(vtable.data());
    at<unsigned>(entity.data(), 0x28) = type;
    at<bool>(entity.data(), activeOffset) = true;
    at<unsigned>(entity.data(), createdOffset) = UINT32_MAX - 1;
    at<unsigned>(game.data(), frameOffset) = 5;
    setters.clear();
}
Value wrapper(void* sprite, unsigned size = 8) {
    auto value = Value::data(size);
    at<Address>(value.blob->storage.data(), 4) = reinterpret_cast<Address>(sprite);
    return value;
}
Value entitySprite() {
    return wrapper(entity.data() + spriteOffset);
}
std::string encode(const Value& value) {
    isaac::state_codec::Writer writer;
    const auto append = [&](auto&& self, const Value& v) -> void {
        if (v.type == 1)
            writer.boolean(v.number != 0);
        else if (v.type == 3 && v.integer)
            writer.number(v.number);
        else if (v.type == 3)
            writer.number(v.real);
        else if (v.type == 5) {
            writer.array(v.array.size());
            for (const auto& item : v.array)
                self(self, item);
        } else
            throw std::runtime_error("Fixture contains a nonnumeric value");
    };
    append(append, value);
    return {reinterpret_cast<const char*>(writer.data().data()), writer.data().size()};
}
enum class Sample { real, integer, boolean, vector, color, type, seed, frame, flags };
struct ExpectedField {
    const char* name;
    unsigned offset;
    Sample sample = Sample::real;
};
// Independent offsets from the audited native getters and Lua registrations.
// Each row exercises the named public plan through capture and restoration.
#ifdef ISAAC_LAN_TEST_J835
constexpr ExpectedField commonFields[]{{"Type", 0x28, Sample::type},
                                       {"Variant", 0x2c, Sample::integer},
                                       {"SubType", 0x30, Sample::integer},
                                       {"InitSeed", 0x344, Sample::seed},
                                       {"Position", 0x294, Sample::vector},
                                       {"Velocity", 0x2b8, Sample::vector},
                                       {"Friction", 0x2c4},
                                       {"HitPoints", 0x2d8},
                                       {"MaxHitPoints", 0x2dc},
                                       {"CollisionDamage", 0x2e0},
                                       {"Visible", 0x169, Sample::boolean},
                                       {"FlipX", 0x13c, Sample::boolean},
                                       {"DepthOffset", 0x2b0},
                                       {"Mass", 0x2d4},
                                       {"Size", 0x2c8},
                                       {"SpriteRotation", 0xe0},
                                       {"SpriteOffset", 0xd0, Sample::vector},
                                       {"SpriteScale", 0xd8, Sample::vector},
                                       {"FrameCount", 0x280, Sample::frame},
                                       {"EntityFlags", 0x160, Sample::flags},
                                       {"Color", 0x1b0, Sample::color}};
constexpr ExpectedField tears[]{{"FallingAcceleration", 0x368},
                                {"FallingSpeed", 0x364},
                                {"Height", 0x360},
                                {"Rotation", 0x3a8},
                                {"Scale", 0x370},
                                {"WaitFrames", 0x388, Sample::integer}};
constexpr ExpectedField effects[]{{"State", 0x3a0, Sample::integer},
                                  {"Timeout", 0x3ac, Sample::integer},
                                  {"LifeSpan", 0x3b0, Sample::integer},
                                  {"Rotation", 0x3c4},
                                  {"Scale", 0x3c8},
                                  {"FallingAcceleration", 0x368},
                                  {"FallingSpeed", 0x364},
                                  {"m_Height", 0x360},
                                  {"MinRadius", 0x3a4},
                                  {"MaxRadius", 0x3a8}};
constexpr ExpectedField familiars[]{{"State", 0xcd4, Sample::integer},
                                    {"FireCooldown", 0xc9c, Sample::integer},
                                    {"HeadFrameDelay", 0xca0, Sample::integer},
                                    {"MoveDirection", 0xca4, Sample::integer},
                                    {"ShootDirection", 0xca8, Sample::integer},
                                    {"LastDirection", 0xcac, Sample::integer},
                                    {"OrbitAngleOffset", 0xcb0},
                                    {"OrbitLayer", 0xcc0, Sample::integer},
                                    {"OrbitSpeed", 0xcbc}};
constexpr ExpectedField pickups[]{{"AutoUpdatePrice", 0x484, Sample::boolean},
                                  {"Charge", 0x474, Sample::integer},
                                  {"OptionsPickupIndex", 0x478, Sample::integer},
                                  {"Price", 0x480, Sample::integer},
                                  {"ShopItemId", 0x488, Sample::integer},
                                  {"State", 0x4d0, Sample::integer},
                                  {"Timeout", 0x48c, Sample::integer},
                                  {"Touched", 0x47c, Sample::boolean},
                                  {"Wait", 0x490, Sample::integer}};
#else
constexpr ExpectedField commonFields[]{{"Type", 0x28, Sample::type},
                                       {"Variant", 0x2c, Sample::integer},
                                       {"SubType", 0x30, Sample::integer},
                                       {"InitSeed", 0x3ec, Sample::seed},
                                       {"Position", 0x33c, Sample::vector},
                                       {"Velocity", 0x360, Sample::vector},
                                       {"Friction", 0x36c},
                                       {"HitPoints", 0x380},
                                       {"MaxHitPoints", 0x384},
                                       {"CollisionDamage", 0x388},
                                       {"Visible", 0x171, Sample::boolean},
                                       {"FlipX", 0x148, Sample::boolean},
                                       {"DepthOffset", 0x358},
                                       {"Mass", 0x37c},
                                       {"Size", 0x370},
                                       {"SpriteRotation", 0xec},
                                       {"SpriteOffset", 0xdc, Sample::vector},
                                       {"SpriteScale", 0xe4, Sample::vector},
                                       {"FrameCount", 0x328, Sample::frame},
                                       {"EntityFlags", 0x168, Sample::flags},
                                       {"Color", 0x1b8, Sample::color}};
constexpr ExpectedField tears[]{{"FallingAcceleration", 0x418},
                                {"FallingSpeed", 0x414},
                                {"Height", 0x410},
                                {"Rotation", 0x458},
                                {"Scale", 0x420},
                                {"WaitFrames", 0x438, Sample::integer}};
constexpr ExpectedField effects[]{{"State", 0x450, Sample::integer},
                                  {"Timeout", 0x45c, Sample::integer},
                                  {"LifeSpan", 0x460, Sample::integer},
                                  {"Rotation", 0x474},
                                  {"Scale", 0x478},
                                  {"FallingAcceleration", 0x418},
                                  {"FallingSpeed", 0x414},
                                  {"m_Height", 0x410},
                                  {"MinRadius", 0x454},
                                  {"MaxRadius", 0x458}};
constexpr ExpectedField familiars[]{{"State", 0xd88, Sample::integer},
                                    {"FireCooldown", 0xd4c, Sample::integer},
                                    {"HeadFrameDelay", 0xd50, Sample::integer},
                                    {"MoveDirection", 0xd54, Sample::integer},
                                    {"ShootDirection", 0xd58, Sample::integer},
                                    {"LastDirection", 0xd5c, Sample::integer},
                                    {"OrbitAngleOffset", 0xd60},
                                    {"OrbitLayer", 0xd70, Sample::integer},
                                    {"OrbitSpeed", 0xd6c}};
constexpr ExpectedField pickups[]{{"AutoUpdatePrice", 0x538, Sample::boolean},
                                  {"Charge", 0x524, Sample::integer},
                                  {"OptionsPickupIndex", 0x528, Sample::integer},
                                  {"Price", 0x534, Sample::integer},
                                  {"ShopItemId", 0x53c, Sample::integer},
                                  {"State", 0x584, Sample::integer},
                                  {"Timeout", 0x540, Sample::integer},
                                  {"Touched", 0x52c, Sample::boolean},
                                  {"Wait", 0x544, Sample::integer}};
#endif
constexpr ExpectedField spriteFields[]{{"FlipX", 0x100, Sample::boolean},
                                       {"FlipY", 0x101, Sample::boolean},
                                       {"Rotation", 0xa4},
                                       {"Scale", 0x9c, Sample::vector},
                                       {"Offset", 0x94, Sample::vector},
                                       {"Color", 0xa8, Sample::color}};
Value populate(unsigned type, const ExpectedField& field, bool second, bool sprite = false) {
    auto* object = entity.data() + (sprite ? spriteOffset : 0);
    const auto offset = field.offset;
    switch (field.sample) {
    case Sample::type:
        return Value::i(type);
    case Sample::seed:
        at<unsigned>(object, offset) = 0xf1234567;
        return Value::i(0xf1234567);
    case Sample::frame:
        return Value::i(7);
    case Sample::flags:
        at<std::uint64_t>(object, offset) = 0x8000000100000002ULL;
        return Value::i(std::bit_cast<std::int64_t>(0x8000000100000002ULL));
    case Sample::integer:
        at<int>(object, offset) = second ? 6 : 3;
        return Value::i(second ? 6 : 3);
    case Sample::real:
        at<float>(object, offset) = second ? -3.25f : 1.5f;
        return Value::f(second ? -3.25 : 1.5);
    case Sample::boolean:
        at<bool>(object, offset) = !second;
        return Value::boolean(!second);
    case Sample::vector:
    case Sample::color: {
        const unsigned count = field.sample == Sample::color ? 7 : 2;
        std::vector<Value> values;
        for (unsigned i = 0; i < count; ++i) {
            const float n = (second ? -1.0f : 1.0f) * (i + 0.25f);
            at<float>(object, offset + (i < 4 ? i : i + 4) * 4) = n;
            values.push_back(Value::f(n));
        }
        return Value::list(std::move(values));
    }
    }
    throw std::runtime_error("Unknown sample");
}
void checkFields(unsigned type, std::span<const ExpectedField> fields, bool sprite = false) {
    for (const auto& field : fields) {
        try {
            reset(type);
            const auto p = sprite ? call(adapter::run<3>, {names({field.name})})
                                  : plan(type, names({field.name}));
            const auto wanted = Value::list({populate(type, field, false, sprite)});
            const auto capture = sprite ? adapter::run<4> : adapter::run<1>;
            const auto apply = sprite ? adapter::run<5> : adapter::run<2>;
            require(same(call(capture, {entitySprite(), p}), wanted),
                    "Named field capture differs");
            if (!sprite)
                require(call(adapter::run<6>, {entitySprite(), p}).text == encode(wanted),
                        "Packed field capture differs");
            const auto initial = entity;
            const auto replacement = Value::list({populate(type, field, true, sprite)});
            entity = initial;
            replica = true;
            call(apply, {entitySprite(), p, replacement});
            require(same(call(capture, {entitySprite(), p}), replacement), "Field restore differs");
            if (!sprite) {
                entity = initial;
                call(apply, {entitySprite(), p, Value::s(encode(replacement))});
                require(same(call(capture, {entitySprite(), p}), replacement),
                        "Packed restore differs from table restore");
            }
            replica = false;
        } catch (const std::exception& e) {
            throw std::runtime_error(std::string(field.name) + ": " + e.what());
        }
    }
}
void checkWireAndLifetime() {
    reset(2);
    auto fields = names({"Position", "EntityFlags", "FrameCount"});
    fields.array.push_back(Value::boolean(false));
    const auto p = plan(2, fields);
    at<float>(entity.data(), positionOffset) = 1.5f;
    at<float>(entity.data(), positionOffset + 4) = -2.25f;
    at<std::uint64_t>(entity.data(), flagsOffset) = 0x8000000100000002ULL;
    // Frozen with bridge/sync/codec.lua, independently of the C++ writer.
    constexpr unsigned char golden[]{0x06, 0x00, 0x04, 0x06, 0x00, 0x02, 0x04, 0x3f,
                                     0xc0, 0x00, 0x00, 0x04, 0xc0, 0x10, 0x00, 0x00,
                                     0x03, 0x80, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
                                     0x02, 0x02, 0x00, 0x00, 0x00, 0x07, 0x00};
    const auto packed = call(adapter::run<6>, {entitySprite(), p}).text;
    require(packed == std::string(reinterpret_cast<const char*>(golden), sizeof(golden)),
            "Nested field bytes differ from the Lua codec contract");
    auto values = call(adapter::run<1>, {entitySprite(), p});
    values.array[1] = Value::i(0);
    values.array[2] = Value::i(900);
    replica = true;
    call(adapter::run<2>, {entitySprite(), p, values});
    require(call(adapter::run<6>, {entitySprite(), p}).text == packed,
            "Read-only flags or frame count were restored");
    replica = false;
    // A plan contains field descriptors, never the object from its last capture.
    auto nextEntity = entity;
    at<float>(nextEntity.data(), positionOffset) = 12.0f;
    const auto nextSprite = wrapper(nextEntity.data() + spriteOffset);
    require(call(adapter::run<1>, {nextSprite, p}).array[0].array[0].real == 12.0,
            "Plan retained the previous room's entity");
    require(call(adapter::run<6>, {entitySprite(), p}).text == packed,
            "Returning to the previous room changed its entity");
    at<unsigned>(game.data(), frameOffset) = 100;
    at<unsigned>(nextEntity.data(), createdOffset) = 98;
    require(call(adapter::run<1>, {nextSprite, p}).array[2].number == 2,
            "New run reused a captured frame count");
    rejects([&] { call(adapter::run<1>, {nextSprite, Value::data(8)}); },
            "Invalid plan handle size was accepted");
}
void checkOrderAndFailures() {
    reset(2);
    const auto p = plan(2, Value::list({names({"Size", "CollisionDamage", "Color"}),
                                        names({"Height", "Scale"}), Value::boolean(false)}));
    const auto values =
        Value::list({Value::list({Value::f(2), Value::f(3),
                                  Value::list({Value::f(1), Value::f(2), Value::f(3), Value::f(4),
                                               Value::f(5), Value::f(6), Value::f(7)})}),
                     Value::list({Value::f(-20), Value::f(1.25)}), Value::boolean(false)});
    const auto initial = entity;
    rejects([&] { call(adapter::run<2>, {entitySprite(), p, values}); },
            "Host wrote replica fields");
    require(entity == initial && setters.empty(), "Rejected host write changed native state");
    replica = true;
    auto bad = values;
    bad.array[1].array[1] = Value::f(std::numeric_limits<double>::quiet_NaN());
    rejects([&] { call(adapter::run<2>, {entitySprite(), p, bad}); }, "Late NaN accepted");
    require(entity == initial && setters.empty(), "Validation did not precede every native write");
    const auto bytes = encode(values);
    for (auto invalid :
         {bytes.substr(0, bytes.size() - 1), bytes + '\0', std::string(5000, '\0')}) {
        rejects([&] { call(adapter::run<2>, {entitySprite(), p, Value::s(invalid)}); },
                "Invalid packed shape was accepted");
        require(entity == initial && setters.empty(), "Bad packed fields partially applied");
    }
    for (const auto& input : {values, Value::s(bytes), Value::s(bytes)}) {
        setters.clear();
        call(adapter::run<2>, {entitySprite(), p, input});
        require(setters == std::vector<std::string>({"size", "damage", "color", "height", "scale"}),
                "Native setters were skipped, reordered or used the wrong calling convention");
    }
    reset(5);
    const auto shop = plan(5, names({"Price", "ShopItemId"}));
    for (int id : {INT32_MIN, -100, -2, 7, 100, INT32_MAX}) {
        call(adapter::run<2>, {entitySprite(), shop, Value::list({Value::i(-5), Value::i(id)})});
#ifdef ISAAC_LAN_TEST_J835
        const int expected = id;
#else
        const int expected = std::clamp(id, -2, 7);
#endif
        require(same(call(adapter::run<1>, {entitySprite(), shop}),
                     Value::list({Value::i(-5), Value::i(expected)})),
                "Native shop range changed");
    }
    require(setters == std::vector<std::string>(6, "price"),
            "Unchanged price bypassed native setter");
    const auto before = entity;
    for (auto value : {Value::i(INT64_MAX), Value::f(2.5), Value::s("3")}) {
        rejects(
            [&] {
                call(adapter::run<2>, {entitySprite(), shop, Value::list({Value::i(4), value})});
            },
            "Invalid integer accepted");
        require(entity == before, "Late integer failure changed price");
    }
    at<bool>(entity.data(), activeOffset) = false;
    rejects([&] { call(adapter::run<1>, {entitySprite(), shop}); }, "Dead entity accepted");
    reset(2);
    rejects([&] { call(adapter::run<1>, {entitySprite(), shop}); }, "Wrong entity type accepted");
    rejects([&] { call(adapter::run<1>, {wrapper(entity.data() + spriteOffset, 0x11c), p}); },
            "Owned Sprite was accepted as entity identity");
    rejects([&] { call(adapter::run<1>, {wrapper(nullptr), p}); }, "Null Sprite accepted");
    at<Address>(image, backend::globals::game) = 0;
    rejects([&] { call(adapter::run<1>, {entitySprite(), p}); },
            "Missing game captured entity frames");
    at<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
    call(adapter::run<1>, {entitySprite(), p});
    replica = false;
}
void checkPlansAndNpc() {
    require(same(plan(1, names({"Size"})), Value::boolean(false)), "Player accepted numeric plan");
    for (auto fields :
         {names({"NoSuchProperty"}), Value::s("Position"), Value::list({Value::boolean(true)}),
          Value::list(std::vector<Value>(128, Value::boolean(false))),
          Value::list({Value::list({Value::list({names({"Size"})})})})})
        rejects([&] { plan(2, fields); }, "Invalid template accepted");
    plan(2, Value::list(std::vector<Value>(127, Value::boolean(false))));
    stackAvailable = false;
    rejects([&] { plan(2, names({"Size"})); }, "Failed Lua stack reservation was ignored");
    stackAvailable = true;
    reset(10);
    isaac::test::NativeEntityTypes types{reinterpret_cast<Address>(image)};
    types.npc(reinterpret_cast<Address>(entity.data()));
    auto sprite = entitySprite();
    rejects([&] { call(adapter::npcBoss, {sprite, Value::boolean(true)}); },
            "Host changed NPC class");
    replica = true;
    for (bool boss : {true, false, true}) {
        call(adapter::npcBoss, {sprite, Value::boolean(boss)});
        require(at<bool>(entity.data(), bossOffset) == boss && entity[bossOffset - 1] == 0 &&
                    entity[bossOffset + 1] == 0,
                "NPC classification touched adjacent state or failed to clear");
    }
    rejects([&] { call(adapter::npcBoss, {sprite, Value::i(1)}); }, "NPC class accepted a number");
    for (unsigned type : {2, 5, 1000}) {
        reset(type);
        types.effect(reinterpret_cast<Address>(entity.data()));
        rejects([&] { call(adapter::npcBoss, {sprite, Value::boolean(true)}); },
                "Non-NPC accepted classification");
    }
    replica = false;
}
void nativeString(void* object, const std::string& text, const char* heap = nullptr) {
    std::memset(object, 0, 24);
    if (heap)
        at<Address>(object, 0) = reinterpret_cast<Address>(heap);
    else
        std::memcpy(object, text.data(), text.size());
    at<unsigned>(object, 0x10) = text.size();
    at<unsigned>(object, 0x14) = heap ? text.size() : 15;
}
void checkSprite() {
    reset(2);
    auto* sprite = entity.data() + spriteOffset;
    const std::string filename = "gfx/fixture/animation.anm2";
    nativeString(sprite, filename, filename.c_str());
    std::array<unsigned char, 24> animation{}, overlay{};
    nativeString(animation.data(), "Walk");
    nativeString(overlay.data(), "Overlay");
    at<Address>(sprite, 0x34) = reinterpret_cast<Address>(animation.data());
    at<Address>(sprite, 0x54) = reinterpret_cast<Address>(overlay.data());
    at<float>(sprite, 0x40) = -1.75;
    at<float>(sprite, 0x60) = -1.75;
    const auto p =
        call(adapter::run<3>,
             {names({"Filename", "Animation", "Frame", "OverlayAnimation", "OverlayFrame"})});
    const auto expected = Value::list(
        {Value::s(filename), Value::s("Walk"), Value::i(-2), Value::s("Overlay"), Value::i(-1)});
    for (unsigned size : {8U, 0x11cU})
        require(same(call(adapter::run<4>, {wrapper(sprite, size), p}), expected),
                "Sprite string, floor/truncation or wrapper ABI differs");
    replica = true;
    call(adapter::run<5>, {entitySprite(), p, expected});
    require(same(call(adapter::run<4>, {entitySprite(), p}), expected),
            "Read-only Sprite data changed");
    replica = false;
    const auto entityPlan = plan(2, names({"Position"}));
    rejects([&] { call(adapter::run<4>, {entitySprite(), entityPlan}); }, "Plan domains mixed");
    rejects([&] { call(adapter::run<6>, {entitySprite(), p}); },
            "Sprite plan encoded as an entity");
    at<Address>(sprite, 0x34) = 0;
    at<Address>(sprite, 0x54) = 0;
    require(same(call(adapter::run<4>, {entitySprite(), p}),
                 Value::list(
                     {Value::s(filename), Value::s(""), Value::i(-1), Value::s(""), Value::i(-1)})),
            "Empty animation retained old values");
    at<unsigned>(sprite, 0x10) = 1025;
    rejects([&] { call(adapter::run<4>, {entitySprite(), p}); },
            "Invalid native string length accepted");
    for (auto frame : {std::numeric_limits<float>::infinity(), 2147483648.0f}) {
        nativeString(sprite, "short");
        at<Address>(sprite, 0x34) = reinterpret_cast<Address>(animation.data());
        at<float>(sprite, 0x40) = frame;
        rejects([&] { call(adapter::run<4>, {entitySprite(), p}); },
                "Invalid frame converted to integer");
    }
}
} // namespace
int main() {
    try {
        connectLua();
        image = static_cast<unsigned char*>(VirtualAlloc(
            nullptr, privateGameImageBytes, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
        require(image, "Allocate isolated field fixture image");
        adapter::image = reinterpret_cast<Address>(image);
        at<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
        jump(backend::entry::entityLuaSetSize, reinterpret_cast<Address>(setSize));
        jump(backend::entry::entitySetSize, reinterpret_cast<Address>(setExplicitSize));
        jump(backend::entry::entityLuaSetColor, reinterpret_cast<Address>(setColor));
        jump(backend::entry::tearSetHeight, reinterpret_cast<Address>(setHeight));
        jump(backend::entry::tearSetScale, reinterpret_cast<Address>(setScale));
        jump(backend::entry::pickupSetPrice, reinterpret_cast<Address>(setPrice));
        vtable[damageMethod / 4] = reinterpret_cast<Address>(setDamage);
        FlushInstructionCache(GetCurrentProcess(), image, privateGameImageBytes);
        for (unsigned type : {2, 3, 5, 1000})
            checkFields(type, commonFields);
        checkFields(2, tears);
        checkFields(3, familiars);
        checkFields(5, pickups);
        checkFields(1000, effects);
        checkFields(2, spriteFields, true);
        checkWireAndLifetime();
        checkOrderAndFailures();
        checkPlansAndNpc();
        checkSprite();
        VirtualFree(image, 0, MEM_RELEASE);
        std::puts(
            "PASS entity field layouts, wire bytes, setters, validation and Sprite lifecycle");
        return 0;
    } catch (const std::exception& e) {
        std::fprintf(stderr, "%s\n", e.what());
        return 1;
    }
}
