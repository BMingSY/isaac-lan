#pragma once

namespace isaac::presentation {
struct HomeSleep {
    unsigned serial = 0;
    bool pending = false;
    bool observe(unsigned incoming, int stage, int kind) {
        if (incoming != serial) {
            pending = incoming && stage == 13 && kind == 0;
            serial = incoming;
        }
        if (pending && stage == 13 && kind == 1) {
            pending = false;
            return true;
        }
        return false;
    }
};
} // namespace isaac::presentation
