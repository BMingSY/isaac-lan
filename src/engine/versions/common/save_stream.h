#pragma once
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <new>
#include <span>
#include <vector>

// Shared x86 MSVC stream ABI, audited separately in Repentance+ and J835.
// Entry addresses, GameState layout and reader arity stay in each backend.
namespace isaac::engine::native_save {
inline constexpr std::size_t limit = 8 * 1024 * 1024;
struct Stream {
    const void* const* vtable;
    std::vector<std::uint8_t> bytes;
    std::size_t position = 0;
    bool failed = false, writing = false;
};
#define METHOD __attribute__((fastcall))
inline void METHOD freeStream(Stream*, void*, bool) {}
inline long METHOD size(Stream* s, void*) {
    return static_cast<long>(s->bytes.size());
}
inline long METHOD position(Stream* s, void*) {
    return static_cast<long>(s->position);
}
inline void METHOD seek(Stream* s, void*, long offset, int origin) {
    const std::int64_t base = origin == 0   ? 0
                              : origin == 1 ? s->position
                              : origin == 2 ? s->bytes.size()
                                            : -1;
    const auto next = base + offset;
    if (base < 0 || next < 0 || next > static_cast<std::int64_t>(s->bytes.size())) {
        s->failed = true;
        return;
    }
    s->position = static_cast<std::size_t>(next);
}
inline bool METHOD eof(Stream* s, void*) {
    return s->position >= s->bytes.size();
}
inline unsigned METHOD read(Stream* s, void*, void* buffer, unsigned element, unsigned count) {
    if (!element || !count)
        return 0;
    const auto available = (s->bytes.size() - s->position) / element;
    const auto n = std::min<std::size_t>(count, available);
    std::memcpy(buffer, s->bytes.data() + s->position, n * element);
    s->position += n * element;
    if (n != count)
        s->failed = true;
    return static_cast<unsigned>(n);
}
inline unsigned METHOD line(Stream* s, void*, char* buffer, unsigned maximum) {
    if (!maximum)
        return 0;
    unsigned n = 0;
    while (n + 1 < maximum && s->position < s->bytes.size()) {
        buffer[n++] = static_cast<char>(s->bytes[s->position++]);
        if (buffer[n - 1] == '\n')
            break;
    }
    buffer[n] = 0;
    return n;
}
inline unsigned METHOD write(Stream* s, void*, const void* buffer, unsigned element,
                             unsigned count) {
    const auto n = static_cast<std::uint64_t>(element) * count;
    if (!s->writing || n > limit || s->position > limit - n) {
        s->failed = true;
        return 0;
    }
    const auto end = s->position + static_cast<std::size_t>(n);
    if (end > s->bytes.size()) {
        try {
            s->bytes.resize(end);
        } catch (const std::bad_alloc&) {
            s->failed = true;
            return 0;
        }
    }
    if (n)
        std::memcpy(s->bytes.data() + s->position, buffer, static_cast<std::size_t>(n));
    s->position = end;
    return count;
}
inline void METHOD noop(Stream*, void*) {}
inline bool METHOD noOpen(Stream* s, void*, const char*) {
    s->failed = true;
    return false;
}
inline bool METHOD isOpen(Stream*, void*) {
    return true;
}
inline const char* METHOD path(Stream*, void*) {
    return "isaac-lan/session";
}
#undef METHOD
// Explicit MSVC-compatible vtable. C++ objects allocated by MinGW are never
// passed off as native STL containers or destroyed by the game's allocator.
inline const void* table[] = {reinterpret_cast<void*>(freeStream), reinterpret_cast<void*>(size),
                              reinterpret_cast<void*>(position),   reinterpret_cast<void*>(seek),
                              reinterpret_cast<void*>(eof),        reinterpret_cast<void*>(read),
                              reinterpret_cast<void*>(line),       reinterpret_cast<void*>(write),
                              reinterpret_cast<void*>(noop),       reinterpret_cast<void*>(noOpen),
                              reinterpret_cast<void*>(noOpen),     reinterpret_cast<void*>(noop),
                              reinterpret_cast<void*>(isOpen),     reinterpret_cast<void*>(noop),
                              reinterpret_cast<void*>(path)};
struct Context {
    Stream* stream;
    const char* path = "isaac-lan/session";
    unsigned version = 0, readChecksum = 0, flag = 0, writeChecksum = 0xfedcba76, mode = 1;
};
static_assert(sizeof(void*) == 4 && sizeof(Context) == 28);
// The engine borrows the stream only for a synchronous serializer call.
// The backing bytes always belong to the extension; native deletion is a no-op.
class Binding {
    std::uintptr_t& field;
    const std::uintptr_t previous;

  public:
    Binding(std::uintptr_t& field, Stream& stream) : field(field), previous(field) {
        field = reinterpret_cast<std::uintptr_t>(&stream);
    }
    ~Binding() {
        field = previous;
    }
    Binding(const Binding&) = delete;
    Binding& operator=(const Binding&) = delete;
};
template <class Write> std::vector<std::uint8_t> encode(std::uintptr_t& field, Write write) {
    Stream stream{table, {}, 0, false, true};
    Context context{&stream};
    Binding bound(field, stream);
    if (!write(context) || stream.failed)
        return {};
    return std::move(stream.bytes);
}
template <class Clear, class Read>
bool decode(std::uintptr_t& field, std::span<const std::uint8_t> bytes, Clear clear, Read read) {
    if (bytes.size() < 20 || bytes.size() > limit)
        return false;
    Stream stream{table, {bytes.begin(), bytes.end()}};
    Context context{&stream};
    clear();
    Binding bound(field, stream);
    return read(context) && !stream.failed;
}
} // namespace isaac::engine::native_save
