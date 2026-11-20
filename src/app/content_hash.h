#pragma once
#include <windows.h>
#include <bcrypt.h>
#include <array>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>

namespace isaac::app {
class ContentHash {
    BCRYPT_ALG_HANDLE algorithm{};
    BCRYPT_HASH_HANDLE hash{};

  public:
    ContentHash(const ContentHash&) = delete;
    ContentHash& operator=(const ContentHash&) = delete;
    ContentHash() {
        if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0 ||
            BCryptCreateHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0) < 0)
            throw std::runtime_error("Cannot initialize manifest hash");
    }
    ~ContentHash() {
        if (hash)
            BCryptDestroyHash(hash);
        if (algorithm)
            BCryptCloseAlgorithmProvider(algorithm, 0);
    }
    void add(const void* bytes, std::size_t size) {
        if (BCryptHashData(hash, reinterpret_cast<PUCHAR>(const_cast<void*>(bytes)),
                           static_cast<ULONG>(size), 0) < 0)
            throw std::runtime_error("Cannot hash manifest");
    }
    void text(const std::string& value) {
        add(value.data(), value.size());
        const char zero = 0;
        add(&zero, 1);
    }
    void file(const std::filesystem::path& path) {
        std::ifstream stream(path, std::ios::binary);
        if (!stream)
            throw std::runtime_error("Cannot read a fingerprinted file");
        std::array<char, 65536> buffer;
        while (stream) {
            stream.read(buffer.data(), buffer.size());
            add(buffer.data(), static_cast<std::size_t>(stream.gcount()));
        }
        if (!stream.eof())
            throw std::runtime_error("Fingerprinted file read failed");
    }
    std::string finish() {
        std::array<unsigned char, 32> bytes{};
        if (BCryptFinishHash(hash, bytes.data(), bytes.size(), 0) < 0)
            throw std::runtime_error("Cannot finish manifest hash");
        std::string out;
        for (auto c : bytes) {
            out += "0123456789abcdef"[c >> 4];
            out += "0123456789abcdef"[c & 15];
        }
        return out;
    }
};
} // namespace isaac::app
