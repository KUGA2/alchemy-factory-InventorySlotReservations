-- Adapter around the live FBeltTDInventory.Slots array. All indices passed to
-- this module are game (zero-based) slot indices; Lua tables are one-based.
local SlotBinding = {}
SlotBinding.__index = SlotBinding

function SlotBinding.new(host)
    assert(type(host) == "table", "host adapter required")
    return setmetatable({ host = host }, SlotBinding)
end

function SlotBinding:slot(widget)
    if not self.host:isPlayerWidget(widget) then return nil, "not a player slot" end
    local index = self.host:slotIndex(widget)
    if type(index) ~= "number" or index < 0 or index % 1 ~= 0 then
        return nil, "invalid slot index"
    end
    local slots = self.host:playerSlots()
    if not slots or index >= #slots then return nil, "slot outside player inventory" end
    local slot = self.host:read(slots[index + 1])
    if not slot then return nil, "slot data unavailable" end
    return slot, index
end

function SlotBinding:toggle(widget)
    local slot, index = self:slot(widget)
    if not slot then return false, index end

    local item = self.host:name(self.host:field(slot, "ItemName"))
    local filter = self.host:name(self.host:field(slot, "SlotFilterName"))
    if not item or not filter then return false, "unreadable slot names" end

    local target
    if filter ~= "None" then
        target = "None"
    elseif item ~= "None" then
        target = item
    else
        return false, "empty slot cannot be reserved"
    end

    local fname = self.host:makeName(target)
    if not fname or self.host:name(fname) ~= target then
        return false, "cannot create filter name"
    end
    if not self.host:writeFilter(slot, fname) then
        return false, "filter write failed"
    end

    -- Read through the component again: GetInventoryRef may return a copy.
    local updated = self:slot(widget)
    if not updated or self.host:name(self.host:field(updated, "SlotFilterName")) ~= target then
        return false, "filter write did not persist"
    end

    local marked = target ~= "None"
    if not self.host:mark(widget, marked) then
        local original = self.host:makeName(filter)
        if original then self.host:writeFilter(updated, original) end
        return false, "circle marker could not be drawn; filter restored"
    end
    return true, marked and "reserved" or "unreserved"
end

return SlotBinding
