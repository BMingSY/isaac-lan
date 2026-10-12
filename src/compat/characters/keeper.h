#pragma once

namespace isaac::compat::characters {
inline int sharedKeeperShopSubtype(int subtype, bool keeper) {
    return keeper && subtype >= 0 && subtype < 100 ? subtype + 100 : subtype;
}
} // namespace isaac::compat::characters
