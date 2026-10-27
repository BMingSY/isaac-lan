#include "engine/versions/j835/mouse_input.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
#include <MinHook.h>
#include <array>
#include <cmath>

namespace isaac::engine::j835::mouse_input {
namespace {
using Address = std::uintptr_t;
Address image;
void* originalBegin;
void* originalEnd;
native_mouse::Router router;
bool installed;
thread_local Address captureFrame;
template <class T> T& at(Address address, std::ptrdiff_t offset) {
    return *reinterpret_cast<T*>(address + offset);
}
float scale() {
    using Height = int(__cdecl*)();
    const auto height = reinterpret_cast<Height>(image + entry::windowClientHeight)();
    const float reference = at<float>(image, globals::viewportReferenceHeight);
    if (height <= 0 || !std::isfinite(reference) || reference <= 0)
        return 0;
    return static_cast<float>(height) / reference * layout::mouseFrame::roomScale *
           layout::mouseFrame::pixelScale;
}
} // namespace
extern "C" {
__attribute__((naked)) void isaac_lan_j835_mouse_return() {
    __asm__ __volatile__("ret");
}
// The native block consumes EDI=player and EBP=its local frame. Its temporary
// calls balance ESP; the end boundary returns here only for this borrowed frame.
__attribute__((naked)) void __cdecl isaac_lan_j835_mouse_capture(void*, void*, void*) {
    __asm__ __volatile__("pushl %ebp\n\tpushl %ebx\n\tpushl %esi\n\tpushl %edi\n\t"
                         "movl 20(%esp), %edi\n\tmovl 24(%esp), %ebp\n\t"
                         "call *28(%esp)\n\t"
                         "popl %edi\n\tpopl %esi\n\tpopl %ebx\n\tpopl %ebp\n\tret");
}
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_j835_mouse_prepare(
    Address* registers, unsigned boundary) {
    enum Register : unsigned { player = 0, frame = 2, continuation = 9 };
    const auto nativeFrame = registers[frame];
    if (boundary) {
        registers[continuation] =
            reinterpret_cast<Address>(captureFrame && captureFrame == nativeFrame
                                          ? reinterpret_cast<void*>(isaac_lan_j835_mouse_return)
                                          : originalEnd);
        return;
    }
    registers[continuation] = reinterpret_cast<Address>(originalBegin);
    native_mouse::Vector aim;
    const auto result = router(reinterpret_cast<void*>(registers[player]), &aim);
    if (result == native_mouse::Result::passthrough)
        return;
    // Inactive native mouse input leaves earlier keyboard/shooting locals intact.
    registers[continuation] = image + entry::playerMouseEnd;
    if (result != native_mouse::Result::active)
        return;
    const float ratio = scale() / native_mouse::canonicalScale;
    if (ratio <= 0 || !std::isfinite(ratio) || !std::isfinite(aim.x) || !std::isfinite(aim.y))
        return;
    const float x = aim.x * ratio, y = aim.y * ratio;
    if (!std::isfinite(x) || !std::isfinite(y))
        return;
    at<bool>(nativeFrame, layout::mouseFrame::active) = true;
    at<float>(nativeFrame, layout::mouseFrame::aimX) = x;
    at<float>(nativeFrame, layout::mouseFrame::aimY) = y;
}
// Preserve all live integer/flag/SSE/x87 state around the C++ router. The extra
// slot is consumed by RET as the selected native continuation, not by the caller.
#define MOUSE_BOUNDARY(NAME, INDEX)                                                                \
    __attribute__((naked)) void NAME() {                                                           \
        __asm__ __volatile__("pushl $0\n\tpushfl\n\tpushal\n\tmovl %esp, %eax\n\t"                 \
                             "subl $528, %esp\n\tandl $-16, %esp\n\tfxsave (%esp)\n\t"             \
                             "movl %eax, 512(%esp)\n\tpushl $" #INDEX "\n\tpushl %eax\n\t"         \
                             "call _isaac_lan_j835_mouse_prepare\n\taddl $8, %esp\n\t"             \
                             "fxrstor (%esp)\n\tmovl 512(%esp), %esp\n\tpopal\n\tpopfl\n\tret");   \
    }
MOUSE_BOUNDARY(isaac_lan_j835_mouse_begin, 0)
MOUSE_BOUNDARY(isaac_lan_j835_mouse_end, 1)
#undef MOUSE_BOUNDARY
} // extern "C"
namespace {
bool __attribute__((thiscall)) physical(void* player, native_mouse::Vector* result, bool) {
    if (!installed || !player || !result)
        return false;
    alignas(16) std::array<unsigned char, layout::mouseFrame::bytes> locals{};
    const auto frame = reinterpret_cast<Address>(locals.data() + locals.size());
    struct Restore {
        Address previous = captureFrame;
        ~Restore() {
            captureFrame = previous;
        }
    } restore;
    captureFrame = frame;
    isaac_lan_j835_mouse_capture(player, reinterpret_cast<void*>(frame), originalBegin);
    if (!at<bool>(frame, layout::mouseFrame::active))
        return false;
    const float nativeScale = scale();
    if (nativeScale <= 0 || !std::isfinite(nativeScale))
        return false;
    const native_mouse::Vector aim{
        at<float>(frame, layout::mouseFrame::aimX) / nativeScale * native_mouse::canonicalScale,
        at<float>(frame, layout::mouseFrame::aimY) / nativeScale * native_mouse::canonicalScale};
    if (!std::isfinite(aim.x) || !std::isfinite(aim.y))
        return false;
    *result = aim;
    return true;
}
} // namespace
bool install(Address base, native_mouse::Router route, native_mouse::Aim& bypass) {
    if (!base || !route || installed)
        return false;
    image = base;
    router = route;
    std::array<void*, 2> targets{};
    unsigned created = 0;
    auto hook = [&](unsigned rva, auto detour, void*& original) {
        auto* target = reinterpret_cast<void*>(base + rva);
        if (MH_CreateHook(target, reinterpret_cast<void*>(detour), &original) != MH_OK)
            return false;
        targets[created++] = target;
        return true;
    };
    bool success = hook(entry::playerMouseBegin, isaac_lan_j835_mouse_begin, originalBegin) &&
                   hook(entry::playerMouseEnd, isaac_lan_j835_mouse_end, originalEnd);
    if (success) {
        bypass = physical;
        installed = true;
        for (unsigned i = 0; i < created; ++i)
            if (MH_QueueEnableHook(targets[i]) != MH_OK) {
                success = false;
                break;
            }
        if (success)
            success = MH_ApplyQueued() == MH_OK;
    }
    if (!success) {
        while (created)
            MH_RemoveHook(targets[--created]);
        bypass = nullptr;
        installed = false;
        originalBegin = originalEnd = nullptr;
        image = 0;
        router = nullptr;
    }
    return success;
}
} // namespace isaac::engine::j835::mouse_input
