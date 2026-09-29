package.path = "InventorySlotReservations/Scripts/?.lua;" .. package.path

local function fname(value) return { ToString = function() return value end } end
local function slot(item, stack, filter)
    return { ItemName = fname(item), ItemStack = stack, SlotFilterName = fname(filter or "None") }
end
local player = {
    slot("Potion", 1, "Potion"), slot("None", 0, "Potion"),
    slot("None", 0), slot("Wood", 13),
}
local chest = { slot("Potion", 100), slot("Potion", 100), slot("Stone", 5) }
local chestArray = setmetatable({}, {
    __index = function(_, index)
        if type(index) == "number" then return chest[index] end
    end,
})
function chestArray:GetArrayNum() return #chest end
local chestComp = {
    FacilityContainer = { Slots = chestArray },
    IsA = function() return true end,
    GetFullName = function() return "IngredientContainerComponent test.chest" end,
}
local actor = {
    GetFullName = function() return "BP_SmallContainer_C /Game/Maps/Test.Chest" end,
    GetComponentByClass = function() return chestComp end,
}
local playerComp = {
    ContainerInventory = { Slots = player },
    GetFullName = function() return "BeltTDInventoryComponent test.player" end,
}
local update, useKey, visible, aimed, pending, scheduled = nil, nil, true, true, {}, {}
local exchanges = 0
function playerComp:TryExchangeInventorySlot(source, from, destination, to)
    assert(self == playerComp and source == chestComp and destination == playerComp)
    pending[#pending + 1] = { from = from, to = to }
    exchanges = exchanges + 1
end
local button = {
    enabled = true,
    GetFullName = function() return "Button /Engine/Transient.Btn_Rearrange" end,
    GetIsEnabled = function(self) return self.enabled end,
    SetIsEnabled = function(self, value) self.enabled = value end,
}
local panel = {
    GetFullName = function() return "WBP_PlayerInventoryPanel_C /Engine/Transient.Panel" end,
    IsVisible = function() return visible end,
    Btn_Rearrange = button,
}
package.preload.UEHelpers = function()
    return {
        GetPlayerController = function() return {
            Pawn = {}, PlayerInventory = playerComp, PlayerCameraManager = {
                GetCameraLocation = function() return {} end,
                GetCameraRotation = function() return {} end,
            },
        } end,
        FindOrAddFName = fname,
        GetKismetMathLibrary = function() return {
            GetForwardVector = function() return {} end,
            Multiply_VectorInt = function() return {} end,
            Add_VectorVector = function() return {} end,
        } end,
        GetKismetSystemLibrary = function() return {
            LineTraceSingle = function(_, _, _, _, _, _, _, _, result)
                if not aimed then return false end
                result.HitObjectHandle = { ReferenceObject = {
                    Get = function() return { GetOwner = function() return actor end } end,
                } }
                return true
            end,
        } end,
    }
end
Key = { N = 49 }
function StaticFindObject() return {} end
function RegisterKeyBind(key, callback) assert(key == Key.N); useKey = callback end
function ExecuteInGameThread(callback) callback() end
function ExecuteWithDelay(_, callback) scheduled[#scheduled + 1] = callback end
function RegisterHook(path, callback)
    if path == "/Script/BeltTD.BeltTDPlayerController:OnInventoryUpdate" then update = callback end
end
function FindAllOf(class)
    if class == "WBP_PlayerInventoryPanel_C" then return { panel } end
    if class == "WBP_InventoryItem_C" then return {} end
    error("unexpected class: " .. class)
end

dofile("InventorySlotReservations/Scripts/main.lua")
assert(useKey and update)

local function apply()
    local batch = pending
    pending = {}
    for _, move in ipairs(batch) do
        local source, target = chest[move.from + 1], player[move.to + 1]
        assert(source.ItemName:ToString() == "Potion")
        assert(target.SlotFilterName:ToString() == "Potion")
        local count = math.min(source.ItemStack, 100 - target.ItemStack)
        if count > 0 then
            source.ItemStack = source.ItemStack - count
            if source.ItemStack == 0 then source.ItemName = fname("None") end
            target.ItemName, target.ItemStack = fname("Potion"), target.ItemStack + count
            target.SlotFilterName = fname("None") -- game drops it on exchange
            update()
        end
    end
end
local function drain()
    for _ = 1, 200 do
        apply()
        if #scheduled == 0 and #pending == 0 then return end
        local callback = table.remove(scheduled, 1)
        if callback then callback() end
    end
    error("pull did not converge")
end

useKey() -- UI is open: no chest transfer
assert(exchanges == 0)
visible = false
aimed = false
useKey() -- not looking at a chest
assert(exchanges == 0)
aimed = true
useKey()
drain()
assert(player[1].ItemStack == 100 and player[2].ItemStack == 100)
assert(player[1].SlotFilterName:ToString() == "Potion")
assert(player[2].SlotFilterName:ToString() == "Potion")
assert(player[3].ItemName:ToString() == "None" and player[4].ItemStack == 13)
assert(chest[1].ItemName:ToString() == "None" and chest[2].ItemStack == 1)
assert(chest[3].ItemStack == 5 and not button.enabled)
local before = exchanges
useKey() -- both reservations are full; no further transfer
drain()
assert(player[1].ItemStack == 100 and player[2].ItemStack == 100)
assert(player[3].ItemName:ToString() == "None" and chest[2].ItemStack == 1)
assert(exchanges >= before)
print("Closed-chest integration checks passed")
