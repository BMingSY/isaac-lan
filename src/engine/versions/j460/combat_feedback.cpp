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
struct Pending {
    Event event;
    std::vector<unsigned> records;
};
std::map<Address, Identity> identities;
std::map<Address, Flash> flashes;
std::map<unsigned, std::vector<Pending>> pending;
unsigned pendingCount = 0;
std::deque<Event> events;
unsigned nextIdentity = 0, serial = 0;
Address image = 0;
lua::API api;
template <class T> T& at(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
unsigned queuedDamage(Address target) {
    if (!target)
        return 0;
    const auto begin = at<Address>(target, entity::damageQueue + j460::layout::vector::begin);
    const auto end = at<Address>(target, entity::damageQueue + j460::layout::vector::end);
    return end >= begin ? static_cast<unsigned>((end - begin) / entity::damageRecordSize) : 0;
}
struct DamageObservation;
DamageObservation* observingDamage = nullptr;
struct DamageObservation {
    Address target;
    unsigned before;
    std::vector<std::pair<unsigned, unsigned>> nested;
    DamageObservation* previous = observingDamage;
    explicit DamageObservation(Address target) : target(target), before(queuedDamage(target)) {
        observingDamage = this;
    }
    DamageObservation(const DamageObservation&) = delete;
    ~DamageObservation() {
        observingDamage = previous;
    }
    std::vector<unsigned> records() {
        const auto after = queuedDamage(target);
        for (auto* parent = previous; parent; parent = parent->previous) {
            if (parent->target == target) {
                if (after > before)
                    parent->nested.emplace_back(before, after);
                break;
            }
        }
        std::vector<unsigned> result;
        for (unsigned index = before; index < after; ++index) {
            if (std::any_of(nested.begin(), nested.end(), [&](const auto& range) {
                    return index >= range.first && index < range.second;
                }))
                continue;
            result.push_back(index);
        }
        return result;
    }
};
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
void publish(Event event) {
    event.serial = ++serial;
    event.tick = runtime::tick();
    events.push_back(event);
}
void prune() {
    const auto tick = runtime::tick();
    while (!events.empty() &&
           (events.size() > maxEvents || events.front().epoch != runtime::worldEpoch() ||
            events.front().tick + retentionTicks < tick))
        events.pop_front();
    for (auto it = pending.begin(); it != pending.end();) {
        auto& entries = it->second;
        const auto old = entries.size();
        entries.erase(std::remove_if(entries.begin(), entries.end(),
                                     [&](const auto& p) {
                                         return p.event.epoch != runtime::worldEpoch() ||
                                                p.event.tick + retentionTicks < tick;
                                     }),
                      entries.end());
        pendingCount -= old - entries.size();
        if (entries.empty())
            it = pending.erase(it);
        else
            ++it;
    }
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
    DamageObservation observation(capture ? target : 0);
    const auto accepted = originalDamage(object, amount, flags, source, countdown);
    auto records = capture ? observation.records() : std::vector<unsigned>{};
    if (capture && std::isfinite(amount) && amount > 0) {
        prune();
        Event event{0,
                    runtime::tick(),
                    runtime::worldEpoch(),
                    audience,
                    sourceID,
                    targetID,
                    dimension,
                    room,
                    accepted,
                    0};
        if (records.empty()) {
            publish(event);
        } else if (pendingCount < maxEvents) {
            // A positive queued amount is still provisional. NPC Update can
            // later discard it. Publish once, only when that queue is drained.
            pending[targetID].push_back({event, std::move(records)});
            ++pendingCount;
        }
    }
    return accepted;
}
using SetColor = void(__attribute__((thiscall)) *)(void*, const Color*, int, int, bool, bool);
SetColor originalSetColor = nullptr;
void setColor(void* object, Address record, Address caller, const Color* color, int frames,
              int priority, bool fade, bool share) {
    const auto target = reinterpret_cast<Address>(object);
    if (caller == image + j460::entry::entityDamageColorReturn && rooms::soundAudience() &&
        !runtime::replica() && npc(target)) {
        const auto id = identify(target);
        const auto found = pending.find(id);
        if (found != pending.end()) {
            const auto begin = at<Address>(target, entity::damageQueue);
            const auto index = static_cast<unsigned>((record - begin) / entity::damageRecordSize);
            for (auto& p : found->second) {
                if (p.event.epoch == runtime::worldEpoch() &&
                    std::find(p.records.begin(), p.records.end(), index) != p.records.end())
                    p.event.duration = static_cast<unsigned>(std::clamp(frames, 1, 6));
            }
        }
        // Native damage still runs in full. Its transient visual now belongs
        // to the presentation clock, so it never becomes durable sprite state.
        flashes[target] = {
            at<unsigned>(target, entity::initSeed), at<unsigned>(target, entity::index),
            runtime::tick() + static_cast<unsigned>(std::clamp(frames, 1, 6)), false};
        return;
    }
    originalSetColor(object, color, frames, priority, fade, share);
}
void drain(Address target) {
    if (pending.empty() || runtime::replica() || !rooms::soundAudience())
        return;
    const auto identity = identities.find(target);
    if (identity == identities.end() ||
        identity->second.seed != at<unsigned>(target, entity::initSeed) ||
        identity->second.index != at<unsigned>(target, entity::index))
        return;
    const auto found = pending.find(identity->second.id);
    if (found == pending.end())
        return;
    for (const auto& p : found->second) {
        if (p.event.epoch == runtime::worldEpoch())
            publish(p.event);
    }
    pendingCount -= found->second.size();
    pending.erase(found);
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
    pending.clear();
    pendingCount = 0;
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

extern "C" {
void* isaac_lan_damage_drain_original = nullptr;
__attribute__((used,
               force_align_arg_pointer)) void __cdecl isaac_lan_damage_drained(Address target) {
    drain(target);
}
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_damage_color(
    void* object, Address record, Address caller, const Color* color, int frames, int priority,
    bool fade, bool share) {
    setColor(object, record, caller, color, frames, priority, fade, share);
}
// At the audited damage SetColor call ESI is the current queue record. Other
// callers are forwarded without inspecting ESI. Keep the original thiscall ABI.
__attribute__((naked)) void isaac_lan_damage_color_thunk() {
    __asm__ __volatile__("pushl %ebp\n\tmovl %esp, %ebp\n\t"
                         "pushl 24(%ebp)\n\tpushl 20(%ebp)\n\tpushl 16(%ebp)\n\t"
                         "pushl 12(%ebp)\n\tpushl 8(%ebp)\n\tpushl 4(%ebp)\n\t"
                         "pushl %esi\n\tpushl %ecx\n\tcall _isaac_lan_damage_color\n\t"
                         "addl $32, %esp\n\tpopl %ebp\n\tret $20");
}
// This site precedes queue.clear(), including queues skipped by immunity.
// Preserve the surrounding function's integer, flag and SSE state.
__attribute__((naked)) void isaac_lan_damage_drain_thunk() {
    __asm__ __volatile__("pushfl\n\tpushal\n\tsubl $128, %esp\n\t"
                         "movups %xmm0, 0(%esp)\n\tmovups %xmm1, 16(%esp)\n\t"
                         "movups %xmm2, 32(%esp)\n\tmovups %xmm3, 48(%esp)\n\t"
                         "movups %xmm4, 64(%esp)\n\tmovups %xmm5, 80(%esp)\n\t"
                         "movups %xmm6, 96(%esp)\n\tmovups %xmm7, 112(%esp)\n\t"
                         "pushl %edi\n\tcall _isaac_lan_damage_drained\n\taddl $4, %esp\n\t"
                         "movups 0(%esp), %xmm0\n\tmovups 16(%esp), %xmm1\n\t"
                         "movups 32(%esp), %xmm2\n\tmovups 48(%esp), %xmm3\n\t"
                         "movups 64(%esp), %xmm4\n\tmovups 80(%esp), %xmm5\n\t"
                         "movups 96(%esp), %xmm6\n\tmovups 112(%esp), %xmm7\n\t"
                         "addl $128, %esp\n\tpopal\n\tpopfl\n\t"
                         "jmp *_isaac_lan_damage_drain_original");
}
} // extern "C"

bool install(std::uintptr_t base) {
    image = base;
    return MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::npcTakeDamage),
                         reinterpret_cast<void*>(damage),
                         reinterpret_cast<void**>(&originalDamage)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::npcTakeDamage)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::entitySetColor),
                         reinterpret_cast<void*>(isaac_lan_damage_color_thunk),
                         reinterpret_cast<void**>(&originalSetColor)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::entitySetColor)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::entityDamageDrain),
                         reinterpret_cast<void*>(isaac_lan_damage_drain_thunk),
                         &isaac_lan_damage_drain_original) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::entityDamageDrain)) == MH_OK;
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
