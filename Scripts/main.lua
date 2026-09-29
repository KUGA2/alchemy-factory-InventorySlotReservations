-- Experimental single-player slot reservations. The circle marker is only shown
-- after the game's live player-inventory slot filter accepts the change.
-- Native G / Take All filtering was verified in an isolated single-player test.
local UEHelpers = require("UEHelpers")
local SlotBinding = require("slot_binding")
local ChestPull = require("chestpull")

local function log(message)
    print("[InventorySlotReservations] " .. message .. "\n")
end

local configOk, config = pcall(require, "config")
if not configOk or type(config) ~= "table" then
    log("Could not load config.lua; using N")
    config = {}
end
local keyName = config.toggleKey or "N"
local key = type(keyName) == "string" and Key[keyName] or nil
if not key then
    log("Invalid toggleKey in config.lua: " .. tostring(keyName) .. "; using N")
    keyName, key = "N", Key.N
end

local function attempt(callback)
    local ok, value = pcall(callback)
    if ok then return value end
    return nil
end
local host = {}

function host:isPlayerWidget(widget)
    local controller = attempt(function() return UEHelpers.GetPlayerController() end)
    local player = attempt(function() return controller.PlayerInventory end)
    local context = attempt(function() return widget.ContextComp end)
    local playerName = attempt(function() return player:GetFullName() end)
    return playerName ~= nil and playerName == attempt(function() return context:GetFullName() end)
end

function host:slotIndex(widget)
    return attempt(function() return widget.SlotIndex end)
end

function host:playerSlots()
    local controller = attempt(function() return UEHelpers.GetPlayerController() end)
    local component = attempt(function() return controller.PlayerInventory end)
    -- GetInventoryRef() returns a struct by value. Changing its SlotFilterName
    -- appeared successful but was lost on the next read. This property is
    -- owned by the live component instead.
    local inventory = attempt(function() return component.ContainerInventory end)
    return attempt(function() return inventory.Slots end)
end

function host:read(entry)
    local unwrapped = attempt(function() return entry:get() end)
    if unwrapped then return unwrapped end
    if attempt(function() return entry.ItemName end) ~= nil then return entry end
    return nil
end

function host:field(slot, key)
    return attempt(function() return slot[key] end)
end

function host:name(value)
    return attempt(function() return value:ToString() end)
end

function host:makeName(value)
    return attempt(function() return UEHelpers.FindOrAddFName(value) end)
end

function host:writeFilter(slot, value)
    local ok, message = pcall(function() slot.SlotFilterName = value end)
    if not ok then log("Slot filter assignment failed: " .. tostring(message)) end
    return ok
end

-- Reservation marker uses only the slot's own circular Border_Liquid layer.
-- Brush tinting corrupted border rendering (black instead of blue, and
-- invisible borders after restore), and hiding the item icon risked
-- invisible items. Visibility flags are safe: the game toggles them itself
-- and rebuilds them whenever the inventory UI reopens.
function host:mark(widget, enabled)
    local liquid = attempt(function() return widget.Border_Liquid end)
    if liquid == nil then
        log("Marker failed: slot has no Border_Liquid")
        return false
    end
    if enabled then
        local ok = pcall(function() liquid:SetVisibility(0) end) -- Visible
        if not ok then
            log("Marker failed: circular border rejected visibility change")
            return false
        end
        return true
    end

    -- Do not restore a previously observed "visible" state: on a saved
    -- filter the game or the SetVisibility hook may already have made the
    -- circle visible before the first mark() call. Restoring that state
    -- left a stuck circle after unreserving an occupied saved slot.
    pcall(function() liquid:SetVisibility(2) end) -- Hidden
    -- Never hide the item icon: a stale ghost texture on an empty slot is
    -- the game's own rendering state and disappears when the inventory UI
    -- reopens. Hiding it risked invisible items later in the same session.
    local icon = attempt(function() return widget.Img_IngredientIcon end)
    if icon then pcall(function() icon:SetVisibility(0) end) end -- Visible
    return true
end

local binding = SlotBinding.new(host)
local reservations = {}
local reportedBreaches = {}

local pullFromChest
local pullState
-- UE4SS may return a new Lua wrapper for the same Button on each access.
-- Use the Unreal full name instead of the wrapper as the lookup key.
local sortButtons = {}

-- The native rearrange operation ignores SlotFilterName and can move an
-- incompatible item into a reserved slot. Disable only the player's sort
-- button while filters exist; never try to undo a completed sort.
local function updateSortButton()
    local blocked = next(reservations) ~= nil
    local panels = attempt(function() return FindAllOf("WBP_PlayerInventoryPanel_C") end) or {}
    for _, panel in ipairs(panels) do
        local fullName = attempt(function() return panel:GetFullName() end)
        if fullName and fullName:find("/Engine/Transient", 1, true) then
            local button = attempt(function() return panel.Btn_Rearrange end)
            if button then
                local buttonName = attempt(function() return button:GetFullName() end)
                if buttonName and blocked and sortButtons[buttonName] == nil then
                    local previous = attempt(function() return button:GetIsEnabled() end)
                    if previous ~= nil then sortButtons[buttonName] = previous end
                end
                if blocked then
                    pcall(function() button:SetIsEnabled(false) end)
                elseif buttonName and sortButtons[buttonName] ~= nil then
                    local previous = sortButtons[buttonName]
                    pcall(function() button:SetIsEnabled(previous) end)
                    sortButtons[buttonName] = nil
                end
            end
        end
    end
end

local function inventoryUiVisible()
    local panels = attempt(function() return FindAllOf("WBP_PlayerInventoryPanel_C") end) or {}
    for _, panel in ipairs(panels) do
        local name = attempt(function() return panel:GetFullName() end)
        if name and name:find("/Engine/Transient", 1, true)
            and attempt(function() return panel:IsVisible() end) == true then
            return true
        end
    end
    return false
end

-- Trace the same nearby object the player's crosshair is pointing at. The
-- hit is often a mesh component, so resolve its owner before looking for an
-- actual ingredient-container component. Unlike inventory widgets, this
-- works with the chest closed (the same situation as the G prompt).
local function focusedChest()
    if inventoryUiVisible() then return nil end
    local controller = attempt(function() return UEHelpers.GetPlayerController() end)
    local pawn = controller and attempt(function() return controller.Pawn end)
    local camera = controller and attempt(function() return controller.PlayerCameraManager end)
    if not pawn or not camera then return nil end
    local actor = attempt(function()
        local system = UEHelpers.GetKismetSystemLibrary()
        local mathLibrary = UEHelpers.GetKismetMathLibrary()
        local origin = camera:GetCameraLocation()
        local endpoint = mathLibrary:Add_VectorVector(origin,
            mathLibrary:Multiply_VectorInt(mathLibrary:GetForwardVector(camera:GetCameraRotation()), 600))
        local hit = {}
        local color = { R = 0, G = 0, B = 0, A = 0 }
        if not system:LineTraceSingle(pawn, origin, endpoint, 0, false, {}, 0,
            hit, true, color, color, 0.0) then return nil end
        local object = hit.HitObjectHandle.ReferenceObject:Get()
        return attempt(function() return object:GetOwner() end) or object
    end)
    if not actor then return nil end
    local name = attempt(function() return actor:GetFullName() end)
    if not name or not name:find("/Game/Maps/", 1, true) then return nil end
    local component = attempt(function()
        local class = StaticFindObject("/Script/BeltTD.IngredientContainerComponent")
        return actor:GetComponentByClass(class)
    end)
    -- Some Blueprint actors expose their native component directly.
    if not attempt(function() return component:GetFullName() end) then
        component = attempt(function() return actor.IngredientContainer end)
    end
    if not attempt(function() return component:IsA(StaticFindObject(
        "/Script/BeltTD.IngredientContainerComponent")) end) then return nil end
    return component, name
end

local function playerComponent()
    local controller = attempt(function() return UEHelpers.GetPlayerController() end)
    return controller and attempt(function() return controller.PlayerInventory end)
end

local function snapshot(entries, count)
    if not entries or type(count) ~= "number" then return nil end
    local slots = {}
    for index = 1, count do
        local slot = host:read(attempt(function() return entries[index] end))
        local item = slot and host:name(host:field(slot, "ItemName"))
        local stack = slot and host:field(slot, "ItemStack")
        local filter = slot and host:name(host:field(slot, "SlotFilterName"))
        if not item or type(stack) ~= "number" or not filter then return nil end
        slots[index] = { item = item, stack = stack, filter = filter }
    end
    return slots
end

local function inventoryState(component)
    local playerEntries = host:playerSlots()
    local chestEntries = attempt(function() return component.FacilityContainer.Slots end)
    local chestCount = attempt(function() return chestEntries:GetArrayNum() end)
    if not playerEntries or not chestCount then return nil end
    local player = snapshot(playerEntries, #playerEntries)
    local chest = snapshot(chestEntries, chestCount)
    if player and chest then return player, chest end
    return nil
end

local function unchangedExcept(before, after, exempt)
    if #before ~= #after then return false end
    for index, original in ipairs(before) do
        local current = after[index]
        if index ~= exempt and (not current or current.item ~= original.item
            or current.stack ~= original.stack or current.filter ~= original.filter) then
            return false
        end
    end
    return true
end

local function endPull(reason)
    log("Chest pull " .. reason .. "; moved " .. tostring(pullState and pullState.moves or 0) .. " stacks")
    pullState = nil
end

local pullStep
local function schedulePull()
    ExecuteWithDelay(150, function()
        ExecuteInGameThread(function() if pullState then pullStep() end end)
    end)
end

pullStep = function()
    local state = pullState
    if not state then return end
    state.checks = state.checks + 1
    if state.checks > 600 then endPull("stopped: too many checks") return end
    local focused, actorName = focusedChest()
    if not focused or actorName ~= state.actorName then
        endPull("stopped: no longer looking at the same closed chest")
        return
    end
    local player, chest = inventoryState(state.component)
    if not player then endPull("stopped: inventory became unreadable") return end
    local pending = state.pending
    if pending then
        local plan = pending.plan
        local target = player[plan.destination + 1]
        -- The game's drag/exchange path sometimes drops the slot filter.
        -- Restoring the filter is not an item transfer or rollback.
        if target and target.filter == "None" and target.item == plan.item then
            local entries = host:playerSlots()
            local slot = entries and host:read(entries[plan.destination + 1])
            local name = host:makeName(plan.beforeDestination.filter)
            if not slot or not name or not host:writeFilter(slot, name) then
                endPull("stopped: could not preserve reservation") return
            end
            player, chest = inventoryState(state.component)
            if not player then endPull("stopped: filter reread failed") return end
        end
        if not unchangedExcept(pending.player, player, plan.destination + 1)
            or not unchangedExcept(pending.chest, chest, plan.source + 1) then
            endPull("stopped: another inventory slot changed") return
        end
        local ok, moved = ChestPull.verify(plan, player, chest)
        if ok then
            state.moves = state.moves + 1
            state.pending = nil
            state.excluded = {}
            schedulePull()
            return
        end
        local source = chest[plan.source + 1]
        target = player[plan.destination + 1]
        if source and target and (source.item ~= plan.beforeSource.item
            or source.stack ~= plan.beforeSource.stack
            or target.item ~= plan.beforeDestination.item
            or target.stack ~= plan.beforeDestination.stack
            or target.filter ~= plan.beforeDestination.filter) then
            endPull("stopped: native transfer differed (" .. tostring(moved) .. ")")
            return
        end
        pending.waits = pending.waits + 1
        if pending.waits > 20 then
            -- No change after three seconds: this pair does not have space.
            state.excluded[plan.source .. ":" .. plan.destination] = true
            state.pending = nil
        end
        schedulePull()
        return
    end
    local plan, reason = ChestPull.plan(player, chest, nil, state.excluded)
    if not plan then endPull("done: " .. tostring(reason)) return end
    if state.moves > 256 then endPull("stopped: too many moves") return end
    state.pending = { plan = plan, player = player, chest = chest, waits = 0 }
    local owner = playerComponent()
    local ok, result = pcall(function()
        return owner:TryExchangeInventorySlot(state.component, plan.source,
            owner, plan.destination)
    end)
    if not ok or result == false then
        endPull("stopped: native exchange failed " .. tostring(result)) return
    end
    schedulePull()
end

pullFromChest = function()
    if pullState then log("Chest pull already running") return end
    local component, actorName = focusedChest()
    if not component then return end
    local player, chest = inventoryState(component)
    if not player then log("Chest pull unavailable: inventory unreadable") return end
    local anyReserved = false
    for index, slot in ipairs(player) do
        if slot.filter ~= "None" then
            reservations[index - 1] = slot.filter
            anyReserved = true
        end
    end
    if not anyReserved then log("Chest pull: no reserved slots") return end
    updateSortButton()
    pullState = { component = component, actorName = actorName,
        pending = nil, excluded = {}, checks = 0, moves = 0 }
    log("Chest pull started")
    pullStep()
end

-- The game hides Border_Liquid whenever it refreshes the inventory widget.
-- Override only this one visibility argument for a filtered player slot.
-- This retains the circular outline without changing unrelated UI widgets.
local circleHook = pcall(RegisterHook, "/Script/UMG.Widget:SetVisibility", function(self, visibility)
    local border = attempt(function() return self:get() end)
    if attempt(function() return border:GetFName():ToString() end) ~= "Border_Liquid" then return end
    local widget = attempt(function() return border:GetOuter():GetOuter() end)
    if not widget or not host:isPlayerWidget(widget) then return end
    local slot = binding:slot(widget)
    local filter = slot and host:name(host:field(slot, "SlotFilterName"))
    if filter and filter ~= "None" then
        -- Inventory opening calls SetVisibility even when OnInventoryUpdate
        -- has not fired yet. Recover saved filters before the player can sort.
        local index = host:slotIndex(widget)
        if index and not reservations[index] then
            reservations[index] = filter
            updateSortButton()
        end
        if attempt(function() return visibility:get() end) ~= 0 then
            pcall(function() visibility:set(0) end) -- Visible
        end
    end
end)
if not circleHook then log("Could not keep the circular border visible") end

-- N on a hovered player slot toggles its reservation. Elsewhere N pulls from
-- the currently aimed closed chest, if there are reserved player slots.
local function onUseKey()
    local widgets = attempt(function() return FindAllOf("WBP_InventoryItem_C") end) or {}
    for _, widget in ipairs(widgets) do
        if attempt(function() return widget:IsHovered() end) == true and host:isPlayerWidget(widget) then
            local success, status = binding:toggle(widget)
            log(string.format("Toggle slot %s: %s", tostring(host:slotIndex(widget)), status))
            if success then
                local index = host:slotIndex(widget)
                local slot = binding:slot(widget)
                local filter = slot and host:name(host:field(slot, "SlotFilterName"))
                reservations[index] = filter ~= "None" and filter or nil
                reportedBreaches[index] = nil
                updateSortButton()
            end
            return
        end
    end
    pullFromChest()
end

RegisterKeyBind(key, function()
    -- Unreal object reads/writes must happen on the game thread.
    ExecuteInGameThread(onUseKey)
end)

-- Observation only. A post-transfer callback cannot safely undo a G transfer.
local ok = pcall(RegisterHook, "/Script/BeltTD.BeltTDPlayerController:OnInventoryUpdate", function()
    local slots = host:playerSlots()
    if not slots then return end
    -- Recover saved native filters when the game loads or Lua restarts. The
    -- game persists SlotFilterName, but this Lua table is only in memory.
    -- Existing player filters are treated as reservations too; they enforce
    -- the same item-type rule.
    for index = 0, #slots - 1 do
        if not reservations[index] then
            local slot = host:read(slots[index + 1])
            local filter = slot and host:name(host:field(slot, "SlotFilterName"))
            if filter and filter ~= "None" then reservations[index] = filter end
        end
    end
    updateSortButton()
    if not next(reservations) then return end
    local widgets = attempt(function() return FindAllOf("WBP_InventoryItem_C") end) or {}
    for index, expected in pairs(reservations) do
        local slot = host:read(slots[index + 1])
        local item = slot and host:name(host:field(slot, "ItemName"))
        local filter = slot and host:name(host:field(slot, "SlotFilterName"))
        -- The game's drag/exchange path replaces the slot struct and clears
        -- SlotFilterName when its last item leaves. Restore the filter at the
        -- inventory-update notification, before the next Take All command.
        -- Never change a slot holding a different item: a post-transfer
        -- rollback or attempted repair could lose or duplicate items.
        if filter == "None" and (item == "None" or item == expected) then
            local name = host:makeName(expected)
            if name and host:writeFilter(slot, name) then
                local reread = host:read(host:playerSlots()[index + 1])
                if host:name(host:field(reread, "SlotFilterName")) == expected then
                    log(string.format("Restored filter on slot %d after inventory update", index))
                else
                    log(string.format("Filter restoration did not persist at slot %d", index))
                end
            else
                log(string.format("Filter restoration failed at slot %d", index))
            end
        end
        if item and item ~= "None" and item ~= expected and not reportedBreaches[index] then
            reportedBreaches[index] = true
            log(string.format("G/transfer protection FAILED at slot %d: expected %s, got %s", index, expected, item))
        end
        for _, widget in ipairs(widgets) do
            if host:slotIndex(widget) == index and host:isPlayerWidget(widget) then
                host:mark(widget, true)
            end
        end
    end
end)
if not ok then log("Could not register inventory update verification hook") end

log("Loaded experimental single-player reservations; use key: " .. keyName)
