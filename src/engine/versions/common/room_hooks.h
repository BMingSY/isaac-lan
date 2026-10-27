#pragma once
#include <cstdint>

// Borrowed game objects and the original thiscall ABI never leave the backend.
namespace isaac::rooms {
using RoomCall = void(__attribute__((thiscall)) *)(void*);
bool update(void* room, RoomCall original);
bool half(void (*original)());
bool render(void* game, RoomCall original, int slot);
std::uintptr_t presentationPlayer(void* explicitPlayer = nullptr);
} // namespace isaac::rooms
