// Private x86 memory only. No game process or hook is installed.
#include "test_support.h"
#include "engine/versions/j460/combat_feedback.cpp"
#include <array>

namespace isaac::runtime {
std::uint32_t testTick = 10, testEpoch = 2;
bool replica() {
    return false;
}
std::uint32_t tick() {
    return testTick;
}
std::uint32_t worldEpoch() {
    return testEpoch;
}
void abort(const std::string& error) {
    throw std::runtime_error(error);
}
} // namespace isaac::runtime
namespace isaac::rooms {
unsigned soundAudience() {
    return 3;
}
} // namespace isaac::rooms

namespace {
namespace feedback = isaac::combat_feedback;
namespace native = isaac::engine::j460;
using Address = std::uintptr_t;
enum class Result { contactOnly, ignored, flash, rejected, nested, nestedSame };
Result behavior = Result::contactOnly;
std::array<unsigned char, 0x1000> other{};
std::array<unsigned char, 16 * native::layout::entity::damageRecordSize> otherQueue{};
bool __attribute__((thiscall)) nativeDamage(void* object, float, std::uint64_t, void*, int) {
    const auto target = reinterpret_cast<Address>(object);
    if (behavior == Result::nested || behavior == Result::nestedSame) {
        const auto enclosing = behavior;
        behavior = Result::flash;
        feedback::damage(enclosing == Result::nestedSame ? object : other.data(), nullptr, 30, 0,
                         nullptr, 0);
        behavior = enclosing;
    }
    if (behavior != Result::rejected && behavior != Result::ignored) {
        auto& end = feedback::at<Address>(target, native::layout::entity::damageQueue +
                                                      native::layout::vector::end);
        feedback::at<float>(end, 0) = 3.5f;
        end += native::layout::entity::damageRecordSize;
    }
    return behavior != Result::rejected;
}
struct Fixture {
    unsigned char* image =
        static_cast<unsigned char*>(VirtualAlloc(nullptr, native::globals::game + sizeof(Address),
                                                 MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
    std::array<unsigned char, 0x20000> game{};
    std::array<unsigned char, 0x1000> target{};
    std::array<unsigned char, 16 * native::layout::entity::damageRecordSize> queue{};
    Fixture() {
        require(image != nullptr, "Private ABI image allocation failed");
        feedback::image = reinterpret_cast<Address>(image);
        feedback::at<Address>(feedback::image, native::globals::game) =
            reinterpret_cast<Address>(game.data());
        feedback::originalDamage = nativeDamage;
        for (const auto& [object, records] : std::array<std::pair<Address, Address>, 2>{
                 {{reinterpret_cast<Address>(target.data()),
                   reinterpret_cast<Address>(queue.data())},
                  {reinterpret_cast<Address>(other.data()),
                   reinterpret_cast<Address>(otherQueue.data())}}}) {
            feedback::at<unsigned>(object, native::layout::entity::type) = 10;
            feedback::at<Address>(object, native::layout::entity::damageQueue +
                                              native::layout::vector::begin) = records;
            feedback::at<Address>(object, native::layout::entity::damageQueue +
                                              native::layout::vector::end) = records;
        }
        feedback::events.clear();
        feedback::flashes.clear();
        feedback::pending.clear();
        feedback::pendingCount = 0;
        feedback::identities.clear();
        feedback::serial = feedback::nextIdentity = 0;
        isaac::runtime::testTick = 10;
        isaac::runtime::testEpoch = 2;
    }
    ~Fixture() {
        VirtualFree(image, 0, MEM_RELEASE);
    }
    bool hit(Result result) {
        behavior = result;
        const auto accepted = feedback::damage(target.data(), nullptr, 30, 0, nullptr, 0);
        require(!feedback::observingDamage, "Damage observation leaked outside its call");
        return accepted;
    }
};
void flash(Address object, unsigned record, int frames) {
    const auto begin = feedback::at<Address>(object, native::layout::entity::damageQueue);
    feedback::setColor(
        reinterpret_cast<void*>(object), begin + record * native::layout::entity::damageRecordSize,
        feedback::image + native::entry::entityDamageColorReturn, nullptr, frames, 0, false, false);
}
void contacts() {
    Fixture f;
    const auto target = reinterpret_cast<Address>(f.target.data());
    require(f.hit(Result::ignored) && feedback::events.back().duration == 0,
            "Ignored contact acquired feedback");
    feedback::events.clear();
    require(f.hit(Result::contactOnly), "Native contact result changed");
    require(feedback::events.empty(), "Provisional queued damage was published early");
    feedback::drain(target); // NPC Update discarded the positive queued amount.
    require(feedback::events.size() == 1 && feedback::events.back().accepted &&
                feedback::events.back().duration == 0,
            "Immune contact invented a native hurt flash");
    require(f.hit(Result::flash), "Native damage return changed");
    flash(target, 1, 2); // Deferred native SetColor chooses the actual duration.
    feedback::drain(target);
    require(feedback::events.back().duration == 2,
            "Confirmed feedback ignored the actual native presentation");
    require(f.hit(Result::contactOnly), "No-flash contact return changed");
    feedback::drain(target);
    require(feedback::events.back().duration == 0, "Previous flash leaked into later damage");
    require(!f.hit(Result::rejected) && !feedback::events.back().accepted &&
                feedback::events.back().duration == 0,
            "A rejected hit acquired feedback");
    require(feedback::pending.empty() && feedback::pendingCount == 0,
            "Drained observations were retained");
}
void nested() {
    Fixture f;
    const auto target = reinterpret_cast<Address>(f.target.data());
    const auto otherTarget = reinterpret_cast<Address>(other.data());
    require(f.hit(Result::nested), "Nested native damage result changed");
    require(feedback::events.empty(), "Nested queue was confirmed before Update");
    flash(otherTarget, 0, 2);
    feedback::drain(otherTarget);
    feedback::drain(target);
    require(feedback::events.size() == 2 && feedback::events[0].duration == 2 &&
                feedback::events[1].duration == 0,
            "Nested damage assigned its flash to the enclosing target");
    require(feedback::events[0].target != feedback::events[1].target,
            "Nested target identities were conflated");
    feedback::events.clear();
    require(f.hit(Result::nestedSame), "Nested same-target result changed");
    flash(target, 1, 3);
    feedback::drain(target);
    require(feedback::events.size() == 2 && feedback::events[0].duration == 3 &&
                feedback::events[1].duration == 0,
            "Nested damage was attributed to a contact-only enclosing call");
}
void relocationAndLifetime() {
    Fixture f;
    const auto target = reinterpret_cast<Address>(f.target.data());
    require(f.hit(Result::flash), "Queued damage failed");
    auto relocated = f.queue;
    feedback::at<Address>(target, native::layout::entity::damageQueue) =
        reinterpret_cast<Address>(relocated.data());
    flash(target, 0, 4);
    // A later rejected contact may be published before deferred native damage.
    require(!f.hit(Result::rejected), "Rejection changed");
    feedback::drain(target);
    require(feedback::events.size() == 2 && !feedback::events[0].accepted &&
                feedback::events[1].duration == 4 &&
                feedback::events[0].serial < feedback::events[1].serial,
            "Relocation or delayed publication lost the source confirmation");
    feedback::at<Address>(target, native::layout::entity::damageQueue) =
        reinterpret_cast<Address>(f.queue.data());
    require(f.hit(Result::flash), "Second queued damage failed");
    ++isaac::runtime::testEpoch;
    feedback::drain(target);
    require(feedback::events.size() == 2 && feedback::pendingCount == 0,
            "A previous world published a late confirmation");
    require(f.hit(Result::flash), "Expiring damage failed");
    isaac::runtime::testTick += feedback::retentionTicks + 1;
    feedback::prune();
    require(feedback::pending.empty() && feedback::pendingCount == 0,
            "Removed/frozen entities retained unbounded observations");
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"contacts", contacts},
                     {"nested", nested},
                     {"relocation-and-lifetime", relocationAndLifetime}});
}
