package.path = "InventorySlotReservations/Scripts/?.lua;" .. package.path

local function fname(value) return { ToString = function() return value end } end
local slot = { ItemName = fname("wood"), ItemStack = 2, SlotFilterName = fname("None") }
local entry = { get = function() return slot end }
local component = {
    GetFullName = function() return "local-player-inventory" end,
    ContainerInventory = { Slots = { entry } },
    -- A UFunction return value is a copy: edits here must not be relied on.
    GetInventoryRef = function()
        return { Slots = { { get = function() return {
            ItemName = slot.ItemName,
            SlotFilterName = fname("None"),
        } end } } }
    end,
}
local border = {
    visibility = 0,
    GetVisibility = function(self) return self.visibility end,
    SetVisibility = function(self, value) self.visibility = value end,
}
local ringBorder = setmetatable({ visibility = 2 }, { __index = border })
-- Note: no SetBrushColor/SetContentColorAndOpacity mocks on purpose. The mod
-- must never call them; border tinting corrupted border rendering in-game.
local ghost = {
    visibility = 0,
    SetVisibility = function(self, value) self.visibility = value end,
}
local sortButton = {
    enabled = true,
    GetFullName = function() return "Button /Engine/Transient.Panel.Btn_Rearrange" end,
    GetIsEnabled = function(self) return self.enabled end,
    SetIsEnabled = function(self, enabled) self.enabled = enabled end,
}
local panel = {
    GetFullName = function() return "WBP_PlayerInventoryPanel_C /Engine/Transient.Panel" end,
    Btn_Rearrange = sortButton,
}
local widget = {
    ContextComp = component, SlotIndex = 0, Border_Liquid = ringBorder,
    Img_IngredientIcon = ghost,
    GetFullName = function() return "WBP_InventoryItem_C /Engine/Transient.Panel.Item0" end,
    hovered = true,
    IsHovered = function(self) return self.hovered end,
}

package.preload.UEHelpers = function()
    return {
        GetPlayerController = function() return { PlayerInventory = component } end,
        FindOrAddFName = fname,
    }
end

Key = { N = 49, F10 = 68, MIDDLE_MOUSE_BUTTON = 4 }
local click, inventoryUpdate, circleVisibility, boundKey
function RegisterKeyBind(key, callback)
    assert(key == Key.N or key == Key.F10)
    boundKey = key
    click = callback
end
function ExecuteInGameThread(callback) callback() end
function RegisterHook(path, callback)
    if path == "/Script/BeltTD.BeltTDPlayerController:OnInventoryUpdate" then
        inventoryUpdate = callback
    elseif path == "/Script/UMG.Widget:SetVisibility" then
        circleVisibility = callback
    else
        error("unexpected hook: " .. tostring(path))
    end
end
function FindAllOf(name)
    if name == "WBP_InventoryItem_C" then return { widget } end
    if name == "WBP_PlayerInventoryPanel_C" then return { panel } end
    error("unexpected widget class: " .. tostring(name))
end

dofile("InventorySlotReservations/Scripts/main.lua")
assert(click and inventoryUpdate and circleVisibility)
assert(boundKey == Key.N)
click()
assert(slot.SlotFilterName:ToString() == "wood")
assert(ringBorder.visibility == 0)
assert(sortButton.enabled == false)
local visibility = { value = 2, get = function(self) return self.value end, set = function(self, value) self.value = value end }
local ring = {
    GetFName = function() return fname("Border_Liquid") end,
    GetOuter = function() return { GetOuter = function() return widget end } end,
}
circleVisibility({ get = function() return ring end }, visibility)
assert(visibility.value == 0)
-- The game's drag path replaces the slot and drops its filter as it empties.
slot.ItemName, slot.ItemStack, slot.SlotFilterName = fname("None"), 0, fname("None")
inventoryUpdate()
assert(slot.SlotFilterName:ToString() == "wood")
click()
assert(slot.SlotFilterName:ToString() == "None")
assert(sortButton.enabled == true)
assert(ghost.visibility == 0)
assert(ringBorder.visibility == 2)
visibility.value = 2
circleVisibility({ get = function() return ring end }, visibility)
assert(visibility.value == 2)
-- A Lua restart must rediscover persisted filters before a later drag clears them.
slot.ItemName, slot.ItemStack, slot.SlotFilterName = fname("wood"), 2, fname("wood")
dofile("InventorySlotReservations/Scripts/main.lua")
visibility.value = 2
circleVisibility({ get = function() return ring end }, visibility)
assert(visibility.value == 0 and sortButton.enabled == false)
ringBorder.visibility = 0 -- saved marker already visible before the update
inventoryUpdate() -- previously captured 0 as its "original" visibility
click()
assert(slot.SlotFilterName:ToString() == "None")
assert(sortButton.enabled == true)
assert(ringBorder.visibility == 2, "saved occupied filter removal must clear the circle")
inventoryUpdate()
assert(slot.SlotFilterName:ToString() == "None", "inventory update must not resurrect an explicitly removed saved filter")
widget.hovered = false
click()
assert(slot.ItemStack == 2 and slot.SlotFilterName:ToString() == "None",
    "without a hovered player slot N must not start an unverified chest transfer")
widget.hovered = true
-- The key can be changed through config.lua without changing the mod script.
package.loaded.config = { toggleKey = "F10" }
dofile("InventorySlotReservations/Scripts/main.lua")
assert(boundKey == Key.F10)
print("Game integration mock checks passed")
