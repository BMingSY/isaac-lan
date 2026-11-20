local root = assert(arg[1])
local fixture = dofile(root .. "/tests/fixtures/offline_entities.lua")(root)
local E = dofile(root .. "/src/bridge/sync/fields.lua").entity
local function entity(id, kind, parent, variant)
    return {
        [E.id] = id,
        [E.type] = kind,
        [E.variant] = variant or 0,
        [E.subtype] = 0,
        [E.parent] = parent or 0,
        [E.spawner] = parent or 0,
        [E.child] = 0,
        [E.target] = 0,
    }
end
local values = { entity(1, 2, -1), entity(2, 2, -1) }
fixture.apply("0:1", values)
local writes = fixture.linkWrites()
assert(writes == 4)
for _ = 1, 10 do
    fixture.apply("0:1", values)
end
assert(fixture.linkWrites() == writes, "Repeated view rebound unchanged native references")
-- A native callback may change a link without changing the incoming snapshot.
fixture.ref(1).Parent = fixture.ref(2)
fixture.apply("0:1", values)
assert(fixture.ref(1).Parent == fixture.ref(-1), "Native link drift was not repaired")
-- An existing authoritative ID may now refer to a different native allocation.
values = { entity(1, 2, 2), entity(2, 10) }
values[1][E.child], values[1][E.target] = 2, 2
fixture.apply("0:1", values)
local oldTarget = fixture.ref(2)
values[2] = entity(2, 10, nil, 1)
fixture.apply("0:1", values)
assert(not oldTarget.alive and fixture.ref(2) ~= oldTarget)
assert(fixture.ref(1).Parent == fixture.ref(2))
assert(fixture.ref(1).SpawnerEntity == fixture.ref(2))
assert(fixture.ref(1).Child == fixture.ref(2))
assert(fixture.ref(1).Target == fixture.ref(2))
values[1] = entity(1, 2)
fixture.apply("0:1", { values[1] })
assert(not fixture.ref(1).Parent and not fixture.ref(1).SpawnerEntity)
assert(not fixture.ref(1).Child and not fixture.ref(1).Target)
-- A factory call can evict a previously validated allocation later in the view.
fixture.reset()
fixture.apply("0:1", { entity(1, 2, -1), entity(2, 2, -1) }, false, false, 2)
fixture.apply("0:1", { entity(3, 2, -1), entity(1, 2, -1), entity(2, 2, -1) }, false, false, 2)
assert(fixture.ref(1) and fixture.ref(2), "Borrowed refs survived a pool eviction")
assert(fixture.ref(1).Parent == fixture.ref(-1))
-- View-local refs must not retain entities when another room is installed.
fixture.apply("0:2", { entity(4, 2, -1) })
assert(fixture.ref(4).Parent == fixture.ref(-1))
fixture.apply("0:1", {})
assert(not fixture.ref(1) and not fixture.ref(2))
print("Entity reconciliation preserves references and avoids repeated bindings")
