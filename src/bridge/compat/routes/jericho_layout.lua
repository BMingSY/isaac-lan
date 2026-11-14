-- World-space layout shared by authority contacts and local artwork.
local layout = { plateRadius = 23, hornRadius = 30, aimCosine = 0.65, wallRadius = 40 }
layout.plates = {
    { -160, -80 },
    { 160, -80 },
    { -160, 0 },
    { 160, 0 },
    { -160, 80 },
    { 160, 80 },
}
layout.horns = { { 0, -120 }, { 0, 120 } }
layout.walls = {
    { -40, -40 },
    { 0, -40 },
    { 40, -40 },
    { -40, 0 },
    { 40, 0 },
    { -40, 40 },
    { 0, 40 },
    { 40, 40 },
}
local function inside(x, y, point, radius)
    return (x - point[1]) ^ 2 + (y - point[2]) ^ 2 <= radius ^ 2
end
function layout.contact(x, y, shootX, shootY, side)
    local plate
    for index = side, #layout.plates, 2 do
        if inside(x, y, layout.plates[index], layout.plateRadius) then
            plate = index
            break
        end
    end
    local horn, standing = false, nil
    for index, point in ipairs(layout.horns) do
        if inside(x, y, point, layout.hornRadius) then
            standing = index
            local length = math.sqrt((x * x + y * y) * (shootX * shootX + shootY * shootY))
            horn = length > 0 and (-x * shootX - y * shootY) / length >= layout.aimCosine
        end
    end
    return plate, horn, standing
end
return layout
