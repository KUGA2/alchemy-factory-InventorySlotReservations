-- Game-independent rules. Slot keys and item IDs must come from verified game data.
local Policy = {}
Policy.__index = Policy

function Policy.new()
    return setmetatable({ reservations = {} }, Policy)
end

-- Only an occupied slot can acquire a reservation. Existing reservations can
-- always be removed, including when the slot has since become empty.
function Policy:toggle(slotKey, itemId)
    assert(slotKey ~= nil, "slot key required")
    if self.reservations[slotKey] ~= nil then
        self.reservations[slotKey] = nil
        return false
    end
    if itemId == nil then
        return false
    end
    self.reservations[slotKey] = itemId
    return true
end

function Policy:allows(slotKey, incomingItemId)
    local reservedItemId = self.reservations[slotKey]
    return reservedItemId == nil or (incomingItemId ~= nil and reservedItemId == incomingItemId)
end

-- Returns the first admissible destination in the game's preferred order.
-- A bulk-transfer adapter must apply this rule *before* moving an item.
function Policy:firstAllowedSlot(slotKeys, incomingItemId, canFit)
    for _, slotKey in ipairs(slotKeys) do
        if self:allows(slotKey, incomingItemId) and canFit(slotKey) then
            return slotKey
        end
    end
    return nil
end

-- Swaps must validate both destinations, not only the dragged item.
function Policy:allowsSwap(firstSlot, firstItemId, secondSlot, secondItemId)
    return self:allows(firstSlot, secondItemId) and self:allows(secondSlot, firstItemId)
end

return Policy
