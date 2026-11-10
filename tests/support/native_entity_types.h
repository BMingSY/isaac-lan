#pragma once
#include "engine/versions/j460/entrypoints.h"
#include "test_support.h"
#include <windows.h>
#include <array>
#include <cstring>

namespace isaac::test {
// Synthetic MSVC x86 RTTI, consumed by the actual Windows CRT. No game objects,
// game executable, hooks or entity-type-based stand-in for dynamic_cast.
class NativeEntityTypes {
    using Address = std::uintptr_t;
    struct Type {
        Address vtable = 0, spare = 0;
        char name[64]{};
    };
    struct Hierarchy;
    struct Base {
        Type* type;
        unsigned contained;
        int member = 0, vbtable = -1, vbase = 0;
        unsigned attributes = 0;
        Hierarchy* hierarchy = nullptr;
    };
    struct Hierarchy {
        unsigned signature = 0, attributes = 0, count = 2;
        Base** bases;
    };
    struct Locator {
        unsigned signature = 0, offset = 0, constructor = 0;
        Type* type;
        Hierarchy* hierarchy;
    };
    struct Class {
        std::array<Base, 2> records;
        std::array<Base*, 2> bases;
        Hierarchy hierarchy;
        Locator locator;
        std::array<Address, 2> vtable;
        Class(Type* type, Type* entity)
            : records{{{type, 1}, {entity, 0}}}, bases{&records[0], &records[1]},
              hierarchy{0, 0, 2, bases.data()}, locator{0, 0, 0, type, &hierarchy},
              vtable{reinterpret_cast<Address>(&locator), 0} {}
        void assign(Address object) const {
            *reinterpret_cast<Address*>(object) = reinterpret_cast<Address>(&vtable[1]);
        }
    };
    HMODULE runtime_ = LoadLibraryW(L"vcruntime140.dll");
    FARPROC cast_ = runtime_ ? GetProcAddress(runtime_, "__RTDynamicCast") : nullptr;
    Type effect_{};
    Class npc_, effectClass_;

  public:
    explicit NativeEntityTypes(Address image)
        : npc_(reinterpret_cast<Type*>(image + engine::j460::rtti::npc),
               reinterpret_cast<Type*>(image + engine::j460::rtti::entity)),
          effectClass_(&effect_, reinterpret_cast<Type*>(image + engine::j460::rtti::entity)) {
        static_assert(sizeof(Address) == 4 && sizeof(Base) == 28 && sizeof(Locator) == 20);
        require(image != 0, "Private native image allocation failed");
        require(cast_ != nullptr, "MSVC x86 RTTI runtime unavailable");
        const auto name = [&](Address descriptor, const char* value) {
            std::memcpy(reinterpret_cast<void*>(descriptor + engine::j460::rtti::name), value,
                        std::strlen(value) + 1);
        };
        name(image + engine::j460::rtti::entity, ".?AVEntity@IsaacRepentancePlus@@");
        name(image + engine::j460::rtti::npc, ".?AVEntity_NPC@IsaacRepentancePlus@@");
        name(reinterpret_cast<Address>(&effect_), ".?AVEntity_Effect@IsaacRepentancePlus@@");
        // Match the audited game's import thunk, redirected to the real CRT.
        const std::array<unsigned char, 2> jump{0xff, 0x25};
        std::memcpy(reinterpret_cast<void*>(image + engine::j460::entry::entityDynamicCast),
                    jump.data(), jump.size());
        *reinterpret_cast<Address*>(image + engine::j460::entry::entityDynamicCast + jump.size()) =
            reinterpret_cast<Address>(&cast_);
        FlushInstructionCache(
            GetCurrentProcess(),
            reinterpret_cast<void*>(image + engine::j460::entry::entityDynamicCast), 6);
    }
    NativeEntityTypes(const NativeEntityTypes&) = delete;
    ~NativeEntityTypes() {
        if (runtime_)
            FreeLibrary(runtime_);
    }
    void npc(Address object) const {
        npc_.assign(object);
    }
    void effect(Address object) const {
        effectClass_.assign(object);
    }
};
} // namespace isaac::test
