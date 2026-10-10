#pragma once

namespace isaac::compat::routes {
inline bool escapeFollower(unsigned entityType, int dimension, bool escaping, bool lastOccupant) {
    return entityType == 867 && dimension == 1 && escaping && lastOccupant;
}
} // namespace isaac::compat::routes
