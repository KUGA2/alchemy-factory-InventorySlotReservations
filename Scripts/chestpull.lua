-- Pure planner for the game's destination-specific inventory exchange. The
-- game merges matching items and enforces the native per-item stack limit.
-- A slot is { item = string, stack = integer, filter = string }.
local ChestPull = {}

local function valid(slot)
    return type(slot) == "table"
        and type(slot.item) == "string"
        and type(slot.filter) == "string"
        and type(slot.stack) == "number"
        and slot.stack >= 0
        and slot.stack % 1 == 0
        and (slot.item ~= "None" or slot.stack == 0)
end

-- Source and destination indices are zero-based, like the game's API.
-- Existing filtered stacks take priority over empty filtered slots.
function ChestPull.plan(player, chest, maximumStack, excluded)
    if type(player) ~= "table" or type(chest) ~= "table"
        or (maximumStack ~= nil and type(maximumStack) ~= "function") then
        return nil, "inventory or stack limit unavailable"
    end
    for _, slots in ipairs({ player, chest }) do
        for _, slot in ipairs(slots) do
            if not valid(slot) then return nil, "unreadable inventory slot" end
        end
    end
    for index, target in ipairs(player) do
        if target.filter ~= "None" and target.item ~= "None"
            and target.item ~= target.filter then
            return nil, "reservation contains an incompatible item at " .. (index - 1)
        end
    end
    local candidates = {}
    for destination, target in ipairs(player) do
        if target.filter ~= "None" and (target.item == "None" or target.item == target.filter) then
            candidates[#candidates + 1] = { index = destination, slot = target }
        end
    end
    -- Attempt small occupied stacks first. Full stacks are last, which also
    -- makes no-op detection safe when the native maximum is unavailable.
    table.sort(candidates, function(a, b)
        local aEmpty, bEmpty = a.slot.item == "None", b.slot.item == "None"
        if aEmpty ~= bEmpty then return not aEmpty end
        if a.slot.stack ~= b.slot.stack then return a.slot.stack < b.slot.stack end
        return a.index < b.index
    end)
    for _, candidate in ipairs(candidates) do
        local target, destination = candidate.slot, candidate.index
        local limit = maximumStack and maximumStack(target.filter)
        if maximumStack and (type(limit) ~= "number" or limit < 1 or limit % 1 ~= 0) then
            return nil, "unknown stack limit for " .. target.filter
        end
        local available = limit and limit - target.stack
        if not available or available > 0 then
            for source, stock in ipairs(chest) do
                if stock.item == target.filter and stock.stack > 0
                    and not (excluded and excluded[(source - 1) .. ":" .. (destination - 1)]) then
                    return {
                        source = source - 1,
                        destination = destination - 1,
                        item = stock.item,
                        count = available and math.min(stock.stack, available) or nil,
                        beforeSource = { item = stock.item, stack = stock.stack, filter = stock.filter },
                        beforeDestination = { item = target.item, stack = target.stack, filter = target.filter },
                    }
                end
            end
        end
    end
    return nil, "nothing fits in reserved slots"
end

-- Confirm a native move before planning another one. Never roll back a move
-- that already happened, and never assume it succeeded because a call returned.
function ChestPull.verify(plan, player, chest)
    local source = chest and chest[plan.source + 1]
    local target = player and player[plan.destination + 1]
    if not valid(source) or not valid(target) then return false, "slot unreadable" end
    local previousSource, previousTarget = plan.beforeSource, plan.beforeDestination
    if source.filter ~= previousSource.filter or target.filter ~= previousTarget.filter then
        return false, "slot filter changed"
    end
    local moved = target.stack - previousTarget.stack
    if target.item ~= plan.item or moved <= 0
        or moved > previousSource.stack
        or (plan.count and moved ~= plan.count) then
        return false, "destination quantity differs"
    end
    if source.stack ~= previousSource.stack - moved
        or (source.stack > 0 and source.item ~= plan.item)
        or (source.stack == 0 and source.item ~= "None" and source.item ~= plan.item) then
        return false, "source quantity differs"
    end
    return true, moved
end

return ChestPull
