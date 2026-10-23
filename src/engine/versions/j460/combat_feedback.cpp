#include "engine/combat_feedback.h"
#include "engine/lua_api.h"
#include "engine/rooms.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "net/protocol.h"
#include "runtime/session.h"
#include <MinHook.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <deque>
#include <map>
#include <vector>

namespace isaac::combat_feedback {
namespace {
namespace j460 = engine::j460;
namespace entity = j460::layout::entity;
using Address = std::uintptr_t;
using Color = std::array<float, j460::layout::color::size / sizeof(float)>;
constexpr unsigned retentionTicks = 90, maxEvents = 512;
constexpr unsigned spriteColor = entity::sprite + j460::layout::sprite::color;
constexpr unsigned noDamageBlink = 0x02000000u;
struct Identity {
    unsigned seed, index, id;
};
struct Event {
    unsigned serial, tick, epoch, audience, source, target;
    int dimension, room;
    bool accepted;
    unsigned duration;
};
struct Flash {
    unsigned seed, index, until;
    bool local;
};
std::map<Address, Identity> identities;
std::map<Address, Flash> flashes;
std::deque<Event> events;
unsigned nextIdentity = 0, serial = 0;
Address image = 0;
lua::API api;
template <class T> T& at(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
bool npc(Address p) {
    const auto type = at<unsigned>(p, entity::type);
    return type >= 10 && type < 1000;
}
unsigned identify(Address p) {
    if (!p)
        return 0;
    const auto seed = at<unsigned>(p, entity::initSeed);
    const auto index = at<unsigned>(p, entity::index);
    auto [it, inserted] = identities.try_emplace(p);
    if (inserted || it->second.seed != seed || it->second.index != index)
        it->second = {seed, index, ++nextIdentity};
    return it->second.id;
}
unsigned duration(float damage) {
    // J460's damage presentation: clamp((int(damage + .5) + 2) / 3, 1, 6).
    return static_cast<unsigned>(
        std::clamp(std::floor((std::floor(damage + .5f) + 2) / 3), 1.f, 6.f));
}
void prune() {
    const auto tick = runtime::tick();
    while (!events.empty() &&
           (events.size() > maxEvents || events.front().epoch != runtime::worldEpoch() ||
            events.front().tick + retentionTicks < tick))
        events.pop_front();
}
using Damage = bool(__attribute__((thiscall)) *)(void*, float, std::uint64_t, void*, int);
Damage originalDamage = nullptr;
bool __attribute__((fastcall)) damage(void* object, void*, float amount, std::uint64_t flags,
                                      void* source, int countdown) {
    const auto audience = rooms::soundAudience();
    const bool capture = audience && !runtime::replica();
    const auto target = reinterpret_cast<Address>(object);
    const auto sourceAddress =
        source ? at<Address>(reinterpret_cast<Address>(source), j460::layout::entityRef::entity)
               : 0;
    // The callback can remove the source. Resolve identity before calling it,
    // and publish only the final native result, after every Mod callback.
    const auto targetID = capture ? identify(target) : 0;
    const auto sourceID = capture ? identify(sourceAddress) : 0;
    const auto game = capture ? at<Address>(image, j460::globals::game) : 0;
    const auto dimension = capture ? at<int>(game, j460::layout::game::dimension) : 0;
    const auto room = capture ? at<int>(game, j460::layout::game::roomIndex) : 0;
    const bool blink = capture && !(at<unsigned>(target, entity::flags) & noDamageBlink);
    const auto accepted = originalDamage(object, amount, flags, source, countdown);
    if (capture && std::isfinite(amount) && amount > 0) {
        events.push_back({++serial, runtime::tick(), runtime::worldEpoch(), audience, sourceID,
                          targetID, dimension, room, accepted,
                          accepted && blink ? duration(amount) : 0});
        prune();
    }
    return accepted;
}
using SetColor = void(__attribute__((thiscall)) *)(void*, const Color*, int, int, bool, bool);
SetColor originalSetColor = nullptr;
void __attribute__((fastcall)) setColor(void* object, void*, const Color* color, int frames,
                                        int priority, bool fade, bool share) {
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0)) - image;
    const auto target = reinterpret_cast<Address>(object);
    if (caller == j460::entry::entityDamageColorReturn && rooms::soundAudience() &&
        !runtime::replica() && npc(target)) {
        // Native damage still runs in full. Its transient visual now belongs
        // to the presentation clock, so it never becomes durable sprite state.
        flashes[target] = {
            at<unsigned>(target, entity::initSeed), at<unsigned>(target, entity::index),
            runtime::tick() + static_cast<unsigned>(std::clamp(frames, 1, 6)), false};
        return;
    }
    originalSetColor(object, color, frames, priority, fade, share);
}
Address checkedEntity(lua_State* L) {
    auto wrapper = static_cast<Address*>(api.toUserdata(L, 1));
    if (!wrapper || api.rawLength(L, 1) != 8 || wrapper[1] < entity::sprite)
        throw std::runtime_error("Invalid combat entity Sprite");
    return wrapper[1] - entity::sprite;
}
int identity(lua_State* L) {
    try {
        if (runtime::replica())
            throw std::runtime_error("Only authority assigns combat identity");
        api.pushInteger(L, identify(checkedEntity(L)));
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        api.pushBoolean(L, false);
    }
    return 1;
}
int captureEvents(lua_State* L) {
    try {
        const auto slot = api.checkInteger(L, 1);
        if (runtime::replica() || slot < 0 || slot >= lan::maxPlayers)
            throw std::runtime_error("Invalid combat event audience");
        prune();
        lan::Writer w(lan::Message::world);
        const auto count = std::count_if(events.begin(), events.end(), [&](const auto& e) {
            return (e.audience & (1u << slot)) != 0;
        });
        w.u32(count);
        for (const auto& e : events) {
            if (!(e.audience & (1u << slot)))
                continue;
            for (auto v : {e.serial, e.tick, e.epoch, static_cast<unsigned>(e.dimension),
                           static_cast<unsigned>(e.room), e.source, e.target})
                w.u32(v);
            w.u8(e.accepted);
            w.u8(e.duration);
        }
        api.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1), w.bytes.size() - 1);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        api.pushBoolean(L, false);
    }
    return 1;
}
int present(lua_State* L) {
    try {
        if (!api.getTop(L)) {
            flashes.clear();
        } else {
            if (!runtime::replica())
                throw std::runtime_error("Only replicas select local hit feedback");
            const auto target = checkedEntity(L);
            if (!npc(target))
                throw std::runtime_error("Hit feedback requires an NPC");
            flashes[target] = {at<unsigned>(target, entity::initSeed),
                               at<unsigned>(target, entity::index), 0, true};
        }
        api.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        api.pushBoolean(L, false);
    }
    return 1;
}
int reset(lua_State* L) {
    identities.clear();
    events.clear();
    flashes.clear();
    serial = nextIdentity = 0;
    api.pushBoolean(L, true);
    return 1;
}
Color hurtColor(unsigned type) {
    // These are the two native damage styles at entityDamageColorReturn.
    const bool pale = type == 407 || type == 951;
    Color color{};
    color[0] = color[1] = .5f;
    color[2] = pale ? .33f : .5f;
    color[3] = 1;
    color[8] = pale ? 100.f / 255.f : 200.f / 255.f;
    return color;
}
} // namespace

bool install(std::uintptr_t base) {
    image = base;
    return MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::npcTakeDamage),
                         reinterpret_cast<void*>(damage),
                         reinterpret_cast<void**>(&originalDamage)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::npcTakeDamage)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::entitySetColor),
                         reinterpret_cast<void*>(setColor),
                         reinterpret_cast<void**>(&originalSetColor)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::entitySetColor)) == MH_OK;
}
bool bind(lua_State* L, HMODULE module) {
    if (!api.load(module,
                  {lua::Symbol::pushClosure, lua::Symbol::setField, lua::Symbol::checkInteger,
                   lua::Symbol::pushInteger, lua::Symbol::pushLString, lua::Symbol::getTop,
                   lua::Symbol::pushBoolean, lua::Symbol::toUserdata, lua::Symbol::rawLength}))
        return false;
    for (const auto& [name, fn] :
         std::array<std::pair<const char*, lua::Function>, 4>{{{"combat_identity", identity},
                                                               {"combat_events", captureEvents},
                                                               {"combat_present", present},
                                                               {"combat_reset", reset}}}) {
        api.pushClosure(L, fn, 0);
        api.setField(L, -2, name);
    }
    return true;
}
void withPresentation(std::uintptr_t room, const std::function<void()>& draw) {
    struct Saved {
        Address entity;
        Color color;
    };
    struct Restore {
        std::vector<Saved> saved;
        ~Restore() {
            for (const auto& s : saved)
                at<Color>(s.entity, spriteColor) = s.color;
        }
    } restore;
    std::erase_if(flashes, [](const auto& entry) {
        return !entry.second.local && entry.second.until <= runtime::tick();
    });
    // The room owns these objects through Render; removal retires them at update.
    const auto list = room + j460::layout::room::entities + j460::layout::entityList::renderArray;
    const auto data = at<Address>(list, j460::layout::entityList::data),
               count = at<unsigned>(list, j460::layout::entityList::count);
    for (unsigned i = 0; i < count; ++i) {
        const auto p = at<Address>(data, i * 4);
        const auto found = flashes.find(p);
        if (found == flashes.end())
            continue;
        const auto& f = found->second;
        if (f.seed != at<unsigned>(p, entity::initSeed) ||
            f.index != at<unsigned>(p, entity::index) || (!f.local && f.until <= runtime::tick())) {
            flashes.erase(found);
            continue;
        }
        restore.saved.push_back({p, at<Color>(p, spriteColor)});
        at<Color>(p, spriteColor) = hurtColor(at<unsigned>(p, entity::type));
    }
    draw();
}
} // namespace isaac::combat_feedback
