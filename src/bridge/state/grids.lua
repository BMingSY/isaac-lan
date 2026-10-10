-- Replace grid allocations before applying the snapshot, using immediate removal.
return function(values, env)
    local present = {}
    for _, value in ipairs(values) do
        local index = value[1]
        present[index] = true
        local grid = env.get(index)
        if grid and grid:GetType() ~= value[2] then
            env.remove(index)
            grid = nil
        end
        if not grid then
            env.spawn(value)
            grid = assert(env.get(index), "Authoritative grid could not be created")
        end
        env.apply(grid, value)
    end
    for index = 0, env.size() - 1 do
        if not present[index] and env.get(index) then
            env.remove(index)
        end
    end
end
