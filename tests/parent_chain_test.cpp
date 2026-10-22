#include "core/parent_chain.h"
#include "test_support.h"
#include <array>
#include <cstddef>
#include <vector>

namespace {
using isaac::core::parent_chain::accepts;
struct Node {
    Node* parent = nullptr;
};

struct Expected {
    bool accepted;
    std::size_t reachable;
};

// Independent oracle: retain every visited identity instead of using two
// cursors. The child is never dereferenced, including recycled self-links.
Expected walk(Node* child, Node* parent, Node* nodes, std::size_t count) {
    std::vector<bool> seen(count);
    std::size_t reachable = 0;
    while (parent) {
        if (parent == child)
            return {false, reachable};
        const auto index = static_cast<std::size_t>(parent - nodes);
        require(index < count, "Oracle received a node outside its graph");
        if (seen[index])
            return {false, reachable};
        seen[index] = true;
        ++reachable;
        parent = parent->parent;
    }
    return {true, reachable};
}

void compare(Node* child, Node* parent, Node* nodes, std::size_t count) {
    const auto expected = walk(child, parent, nodes, count);
    std::vector<Node*> before;
    for (std::size_t i = 0; i < count; ++i)
        before.push_back(nodes[i].parent);
    std::size_t reads = 0;
    const auto next = [&](Node* node) {
        require(node && node != child, "Parent check dereferenced null or the proposed child");
        require(++reads <= 3 * expected.reachable, "Parent check exceeded linear link reads");
        return node->parent;
    };
    require(accepts(child, parent, next) == expected.accepted,
            "Parent check disagreed with the visited-identity oracle");
    for (std::size_t i = 0; i < count; ++i)
        require(nodes[i].parent == before[i], "Parent check changed borrowed links");
}

void assignments() {
    std::array<Node, 5> nodes{};
    Node* child = &nodes.back();
    const auto noRead = [](Node*) -> Node* {
        require(false, "Clearing or rejecting self-parent read a node");
        return nullptr;
    };
    require(accepts(child, static_cast<Node*>(nullptr), noRead), "Clearing a parent was rejected");
    require(!accepts(child, child, noRead), "Recycled self-parent was accepted");

    nodes[0].parent = &nodes[1];
    nodes[1].parent = &nodes[2];
    for (unsigned repeat = 0; repeat < 3; ++repeat)
        compare(child, &nodes[0], nodes.data(), nodes.size());
    // Different children may share a valid tail; it is not a cycle.
    compare(&nodes[3], &nodes[1], nodes.data(), nodes.size());
    nodes[2].parent = child;
    compare(child, &nodes[0], nodes.data(), nodes.size());
    nodes[2].parent = &nodes[2];
    compare(child, &nodes[0], nodes.data(), nodes.size());
    nodes[2].parent = &nodes[0];
    compare(child, &nodes[0], nodes.data(), nodes.size());
    // Clearing/reusing caller-owned links must not leave cached rejection.
    nodes[2].parent = nullptr;
    compare(child, &nodes[0], nodes.data(), nodes.size());
    compare(child, static_cast<Node*>(nullptr), nodes.data(), nodes.size());
}

void allSmallGraphs() {
    constexpr std::size_t graphNodes = 5, choices = graphNodes + 1;
    std::array<Node, graphNodes + 1> nodes{};
    std::size_t graphCount = 1;
    for (std::size_t i = 0; i < graphNodes; ++i)
        graphCount *= choices;
    // Enumerate every map from five nodes to any node or null, including
    // disconnected cycles, odd/even rings, and tails entering those rings.
    for (std::size_t graph = 0; graph < graphCount; ++graph) {
        auto remaining = graph;
        for (std::size_t i = 0; i < graphNodes; ++i) {
            const auto link = remaining % choices;
            remaining /= choices;
            nodes[i].parent = link ? &nodes[link - 1] : nullptr;
        }
        // The final child lies outside each graph; other children are inside.
        for (auto& child : nodes)
            for (std::size_t parent = 0; parent < choices; ++parent)
                compare(&child, parent ? &nodes[parent - 1] : nullptr, nodes.data(), nodes.size());
    }
}

void longChains() {
    for (const std::size_t length : {1, 2, 3, 31, 1024, 65536}) {
        std::vector<Node> nodes(length + 1);
        for (std::size_t i = 1; i < length; ++i)
            nodes[i - 1].parent = &nodes[i];
        auto* child = &nodes.back();
        compare(child, nodes.data(), nodes.data(), nodes.size());
        compare(&nodes[length / 2], nodes.data(), nodes.data(), nodes.size());
        for (const auto entry : {std::size_t{0}, length / 2, length - 1}) {
            nodes[length - 1].parent = &nodes[entry];
            compare(child, nodes.data(), nodes.data(), nodes.size());
        }
        nodes[length - 1].parent = nullptr;
        compare(child, nodes.data(), nodes.data(), nodes.size());
    }
}
} // namespace

int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"assignments-and-reuse", assignments},
                     {"all-small-graphs", allSmallGraphs},
                     {"long-chains-linear-work", longChains}});
}
