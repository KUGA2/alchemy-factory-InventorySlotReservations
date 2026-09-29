package.path = "InventorySlotReservations/Scripts/?.lua;" .. package.path

local ChestPull = require("chestpull")

local function slot(item, count, filter)
    return { item = item, stack = count, filter = filter or "None" }
end

local function limit(name)
    return ({ Wood = 200, Potion = 100, Stone = 50 })[name]
end

-- Only the partially filled reserved stack is eligible; the unfiltered
-- empty slot and matching unfiltered stack must not receive anything.
local player = {
    slot("Wood", 190, "Wood"),
    slot("None", 0, "None"),
    slot("Wood", 15, "None"),
    slot("None", 0, "Potion"),
}
local chest = { slot("Wood", 40), slot("Stone", 7), slot("Potion", 42) }
local plan = assert(ChestPull.plan(player, chest, limit))
assert(plan.source == 0 and plan.destination == 0 and plan.count == 10)
assert(plan.item == "Wood")
assert(not ChestPull.verify(plan, player, chest), "must wait for the native transfer")

chest[1] = slot("Wood", 30)
player[1] = slot("Wood", 200, "Wood")
assert(ChestPull.verify(plan, player, chest))

local nextPlan = assert(ChestPull.plan(player, chest, limit))
assert(nextPlan.source == 2 and nextPlan.destination == 3 and nextPlan.count == 42)
chest[3] = slot("None", 0)
player[4] = slot("Potion", 42, "Potion")
assert(ChestPull.verify(nextPlan, player, chest))
assert(ChestPull.plan(player, chest, limit) == nil, "free slots must not be used")
assert(player[2].item == "None" and player[3].stack == 15)

-- Empty reservations accept at most the item's native limit; a subsequent
-- plan may continue to fill another reserved slot, never a free slot.
player = { slot("None", 0, "Stone"), slot("None", 0, "Stone"), slot("None", 0) }
chest = { slot("Stone", 130) }
for index = 1, 2 do
    local move = assert(ChestPull.plan(player, chest, limit))
    assert(move.destination == index - 1 and move.count == 50)
    player[index] = slot("Stone", 50, "Stone")
    chest[1] = slot("Stone", chest[1].stack - 50)
    assert(ChestPull.verify(move, player, chest))
end
assert(ChestPull.plan(player, chest, limit) == nil)
assert(chest[1].stack == 30 and player[3].item == "None")

-- Without a separately exposed item maximum, the native game exchange
-- decides how much to merge. Verify its observed partial-transfer result.
do
    local p = { slot("Potion", 1, "Potion"), slot("None", 0) }
    local c = { slot("Potion", 100) }
    local native = assert(ChestPull.plan(p, c))
    assert(native.source == 0 and native.destination == 0 and native.count == nil)
    p[1], c[1] = slot("Potion", 100, "Potion"), slot("Potion", 1)
    local ok, moved = ChestPull.verify(native, p, c)
    assert(ok and moved == 99)
    assert(ChestPull.plan(p, c, nil, { ["0:0"] = true }) == nil)
end

-- A changed filter, unexpected quantity, unreadable or incompatible slot,
-- or unknown stack limit must stop rather than attempt a repair.
player = { slot("Wood", 180, "Wood") }
chest = { slot("Wood", 25) }
plan = assert(ChestPull.plan(player, chest, limit))
assert(plan.count == 20)
player[1] = slot("Wood", 200, "None")
assert(not ChestPull.verify(plan, player, chest))
player[1] = slot("Stone", 4, "Wood")
assert(ChestPull.plan(player, chest, limit) == nil)
player[1] = slot("None", 0, "UnknownItem")
assert(ChestPull.plan(player, chest, limit) == nil)
player[1] = slot("Wood", 180, "Wood")
chest[1] = { item = "Wood", stack = "25", filter = "None" }
assert(ChestPull.plan(player, chest, limit) == nil)

-- Randomized closed-loop simulation: no unfiltered player slot changes, no
-- reserved slot exceeds its item limit, and item counts are conserved.
math.randomseed(20260928)
for round = 1, 200 do
    local kinds = { "Wood", "Potion", "Stone" }
    local inventory, storage = {}, {}
    local free = {}
    for index = 1, 12 do
        local kind = kinds[math.random(#kinds)]
        local filtered = index % 3 ~= 0
        local count = math.random(0, limit(kind))
        inventory[index] = slot(count == 0 and "None" or kind, count,
            filtered and kind or "None")
        if not filtered then free[index] = { item = inventory[index].item, stack = count } end
    end
    for index = 1, 12 do
        local kind = kinds[math.random(#kinds)]
        local count = math.random(0, limit(kind))
        storage[index] = slot(count == 0 and "None" or kind, count)
    end
    local function totals()
        local result = {}
        for _, list in ipairs({ inventory, storage }) do
            for _, s in ipairs(list) do
                if s.item ~= "None" then result[s.item] = (result[s.item] or 0) + s.stack end
            end
        end
        return result
    end
    local before = totals()
    for _ = 1, 50 do
        local move = ChestPull.plan(inventory, storage, limit)
        if not move then break end
        local src, dst = storage[move.source + 1], inventory[move.destination + 1]
        assert(dst.filter == move.item and src.item == move.item)
        assert(move.count > 0 and move.count <= src.stack)
        assert(dst.stack + move.count <= limit(move.item))
        src.stack = src.stack - move.count
        if src.stack == 0 then src.item = "None" end
        dst.stack, dst.item = dst.stack + move.count, move.item
        assert(ChestPull.verify(move, inventory, storage))
    end
    for index, original in pairs(free) do
        local s = inventory[index]
        assert(s.item == original.item and s.stack == original.stack,
            "unfiltered slot changed in round " .. round)
    end
    local after = totals()
    for kind, count in pairs(before) do assert(after[kind] == count) end
end

print("Chest pull quantity planner checks passed")
