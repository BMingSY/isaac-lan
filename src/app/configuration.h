#pragma once
#include "core/config.h"
#include <filesystem>

namespace isaac::configuration {
Parsed load(const std::filesystem::path& path);
}
