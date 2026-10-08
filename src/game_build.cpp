#include "game_build.h"
#include <windows.h>
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <span>
#include <stdexcept>
#include <vector>

namespace isaac::build {
namespace {
constexpr std::uint32_t versionRva = 0x77b2f4;
struct Signature {
    std::uint32_t rva;
    const char* name;
    std::array<unsigned char, 16> bytes;
    std::uint16_t mask;
};
constexpr Signature signatures[] = {
#include "game_signatures.inc"
};
std::string conflict(const Signature& signature) {
    char address[32];
    std::snprintf(address, sizeof(address), " at RVA 0x%08lx",
                  static_cast<unsigned long>(signature.rva));
    return std::string("Engine code differs: ") + signature.name + address +
           ". A patch may have changed this entry point; LAN hooks were not installed.";
}
bool matches(const Signature& signature, const unsigned char* bytes) {
    for (unsigned i = 0; i < signature.bytes.size(); ++i)
        if ((signature.mask & (1u << i)) && bytes[i] != signature.bytes[i])
            return false;
    return true;
}
class FileImage {
    std::vector<unsigned char> bytes;
    std::vector<IMAGE_SECTION_HEADER> sections;
    template <class T> T read(std::size_t offset) const {
        if (offset > bytes.size() || sizeof(T) > bytes.size() - offset)
            throw std::runtime_error("Truncated PE header.");
        T value;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }

  public:
    explicit FileImage(const std::filesystem::path& path) {
        std::ifstream stream(path, std::ios::binary | std::ios::ate);
        const auto length = stream.tellg();
        if (!stream || length < 64 || length > 512 * 1024 * 1024)
            throw std::runtime_error("Cannot read a valid game executable.");
        bytes.resize(static_cast<std::size_t>(length));
        stream.seekg(0);
        if (!stream.read(reinterpret_cast<char*>(bytes.data()), bytes.size()))
            throw std::runtime_error("Cannot read game executable.");
        const auto dos = read<IMAGE_DOS_HEADER>(0);
        if (dos.e_magic != IMAGE_DOS_SIGNATURE || dos.e_lfanew < 64)
            throw std::runtime_error("Not a Windows PE executable.");
        const auto nt = static_cast<std::size_t>(dos.e_lfanew);
        if (read<DWORD>(nt) != IMAGE_NT_SIGNATURE)
            throw std::runtime_error("Invalid PE signature.");
        const auto file = read<IMAGE_FILE_HEADER>(nt + sizeof(DWORD));
        if (file.Machine != IMAGE_FILE_MACHINE_I386 ||
            !(file.Characteristics & IMAGE_FILE_EXECUTABLE_IMAGE) ||
            (file.Characteristics & IMAGE_FILE_DLL))
            throw std::runtime_error("Expected the 32-bit Isaac game executable.");
        if (file.SizeOfOptionalHeader < sizeof(IMAGE_OPTIONAL_HEADER32) ||
            file.NumberOfSections == 0 || file.NumberOfSections > 96)
            throw std::runtime_error("Invalid game PE layout.");
        const auto optionalOffset = nt + sizeof(DWORD) + sizeof(IMAGE_FILE_HEADER);
        const auto optional = read<IMAGE_OPTIONAL_HEADER32>(optionalOffset);
        if (optional.Magic != IMAGE_NT_OPTIONAL_HDR32_MAGIC || optional.SizeOfImage < 0x89caa4)
            throw std::runtime_error("Unsupported game image layout; expected Repentance+ J460.");
        for (unsigned i = 0; i < file.NumberOfSections; ++i) {
            const auto section = read<IMAGE_SECTION_HEADER>(
                optionalOffset + file.SizeOfOptionalHeader + i * sizeof(IMAGE_SECTION_HEADER));
            const std::uint64_t end =
                static_cast<std::uint64_t>(section.PointerToRawData) + section.SizeOfRawData;
            const std::uint64_t virtualEnd =
                static_cast<std::uint64_t>(section.VirtualAddress) +
                std::max(section.Misc.VirtualSize, section.SizeOfRawData);
            if (end > bytes.size() || virtualEnd > optional.SizeOfImage)
                throw std::runtime_error("Truncated or invalid PE section.");
            sections.push_back(section);
        }
        auto covers = [&](std::uint32_t start, std::uint32_t size, DWORD flags) {
            return std::any_of(sections.begin(), sections.end(), [&](const auto& section) {
                return start >= section.VirtualAddress &&
                       static_cast<std::uint64_t>(start) + size <=
                           static_cast<std::uint64_t>(section.VirtualAddress) +
                               section.Misc.VirtualSize &&
                       (section.Characteristics & flags) == flags;
            });
        };
        if (!covers(0x1000, 0x716134, IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_READ) ||
            !covers(0x718000, 0xdf948, IMAGE_SCN_MEM_READ) ||
            !covers(0x7f8000, 0xa4aa4, IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE))
            throw std::runtime_error("Unsupported game section layout; expected Repentance+ J460.");
        const auto marker = at(versionRva, sizeof(version));
        if (std::memcmp(marker.data(), version, sizeof(version) - 1) != 0 || marker.back() != '-')
            throw std::runtime_error(
                "Unsupported game build. This extension requires Repentance+ 1.9.7.17.J460.");
    }
    std::span<const unsigned char> at(std::uint32_t rva, std::size_t size) const {
        for (const auto& section : sections) {
            if (rva < section.VirtualAddress)
                continue;
            const auto delta = rva - section.VirtualAddress;
            if (delta > section.SizeOfRawData || size > section.SizeOfRawData - delta)
                continue;
            return {bytes.data() + section.PointerToRawData + delta, size};
        }
        throw std::runtime_error("Required game address is not backed by a PE section.");
    }
};
} // namespace
std::string checkFile(const std::filesystem::path& path, bool checkCode) {
    try {
        FileImage file(path);
        if (checkCode)
            for (const auto& signature : signatures)
                if (!matches(signature, file.at(signature.rva, signature.bytes.size()).data()))
                    return conflict(signature);
        return {};
    } catch (const std::exception& error) {
        return error.what();
    }
}
std::string checkMemory(std::uintptr_t image) {
    for (const auto& signature : signatures) {
        std::array<unsigned char, 16> bytes{};
        SIZE_T size = 0;
        if (!ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<void*>(image + signature.rva),
                               bytes.data(), bytes.size(), &size) ||
            size != bytes.size() || !matches(signature, bytes.data()))
            return conflict(signature);
    }
    return {};
}
} // namespace isaac::build
