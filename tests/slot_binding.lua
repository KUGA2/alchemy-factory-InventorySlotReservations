package.path = "InventorySlotReservations/Scripts/?.lua;" .. package.path
local SlotBinding = require("slot_binding")
local function name(value) return { ToString = function() return value end } end
local slots = {
    { ItemName = name("wood"), SlotFilterName = name("None") },
    { ItemName = name("None"), SlotFilterName = name("None") },
}
local widget = { player = true, index = 0 }
local host = {
    isPlayerWidget = function(_, w) return w.player end,
    slotIndex = function(_, w) return w.index end,
    playerSlots = function() return slots end,
    read = function(_, entry) return entry end,
    field = function(_, entry, key) return entry[key] end,
    name = function(_, value) return value and value:ToString() end,
    makeName = function(_, value) return name(value) end,
    writeFilter = function(_, entry, value) entry.SlotFilterName = value; return true end,
    mark = function(_, w, state) w.marked = state; return true end,
}
local binding = SlotBinding.new(host)
local ok, message = binding:toggle(widget)
assert(ok and message == "reserved" and widget.marked)
assert(slots[1].SlotFilterName:ToString() == "wood")
slots[1].ItemName = name("None")
ok, message = binding:toggle(widget)
assert(ok and message == "unreserved" and not widget.marked)
widget.index = 1
assert(not binding:toggle(widget))
widget.index = 2
assert(not binding:toggle(widget))
widget.index = 0
widget.player = false
assert(not binding:toggle(widget))
widget.player = true
slots[1].ItemName = name("potion")
host.writeFilter = function() return true end -- write silently did not persist
assert(not binding:toggle(widget))
assert(not widget.marked)
host.writeFilter = function(_, entry, value) entry.SlotFilterName = value; return true end
host.mark = function() return false end
assert(not binding:toggle(widget))
assert(slots[1].SlotFilterName:ToString() == "None")
-- The actual property-backed TArray can expose a slot struct directly instead
-- of an element wrapper with :get().
local direct = { { ItemName = name("tea"), SlotFilterName = name("None") } }
host.playerSlots = function() return direct end
host.mark = function(_, w, state) w.marked = state; return true end
widget.index = 0
assert(binding:toggle(widget))
assert(direct[1].SlotFilterName:ToString() == "tea")
print("Live slot binding checks passed")
