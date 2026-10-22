#pragma once

namespace isaac::core::parent_chain {
// Accept only a terminating parent chain that does not contain the child.
// Nodes are borrowed: next must read a stable link from each non-null node.
// Floyd's walk uses O(1) space and O(reachable nodes) reads, without a depth
// cutoff. It neither changes links nor validates the caller's node storage.
template <class Node, class Next> bool accepts(Node child, Node parent, Next next) {
    Node slow = parent, fast = parent;
    while (fast) {
        if (fast == child)
            return false;
        fast = next(fast);
        if (!fast)
            return true;
        if (fast == child)
            return false;
        fast = next(fast);
        slow = next(slow);
        if (fast && slow == fast)
            return false;
    }
    return true;
}
} // namespace isaac::core::parent_chain
