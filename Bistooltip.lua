-- BistooltipAddon: Enhance tooltips with BiS (Best in Slot) information
-- ----------------------------------------------------------------------------------
-- This script hooks into World of Warcraft tooltips to display additional
-- information about items, such as their Best in Slot (BiS) status, sources,
-- and relevance to specific classes and specs.
-- ----------------------------------------------------------------------------------

-- GLOBAL DEFINITIONS --------------------------------------------------------------
local eventFrame = CreateFrame("Frame", nil, UIParent) -- Creates an invisible frame to handle events.
Bistooltip_phases_string = "" -- A string to store phase information for BiS items.
local DataStore_Inventory = DataStore_Inventory or nil -- A fallback if DataStore_Inventory is unavailable.

-- UTILITY FUNCTIONS ---------------------------------------------------------------
-- Iterate through table keys in a case-insensitive sorted order
local function caseInsensitivePairs(t)
    -- Extract keys into an array for sorting
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return a:lower() < b:lower() end) -- Sort case-insensitively.

    local i = 0
    return function()
        i = i + 1
        return keys[i], t[keys[i]]
    end
end

-- Remove color codes and calculate string length
local function getStringLength(str)
    -- Strips WoW color codes (|c and |r) to get a clean string length.
    return string.len(str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Check if a table contains a specific value
function table.contains(tbl, element)
    -- Iterates through the table to see if the element exists.
    for _, value in pairs(tbl) do
        if value == element then
            return true
        end
    end
    return false
end

-- SPEC AND CLASS FILTERING --------------------------------------------------------
-- Check if a specific spec is highlighted
local function specHighlighted(class_name, spec_name)
    -- Compares the class and spec name with the highlighted spec in the addon's settings.
    local highlight = BistooltipAddon.db.char.highlight_spec
    return highlight.spec_name == spec_name and highlight.class_name == class_name
end

-- Determine if a spec should be filtered out
local function specFiltered(class_name, spec_name)
    -- If the spec is highlighted or ALT is held, it won't be filtered out.
    if specHighlighted(class_name, spec_name) or IsAltKeyDown() then
        return false
    end
    -- Check the addon's settings to see if this spec is explicitly filtered.
    local filter_specs = BistooltipAddon.db.char.filter_specs[class_name]
    return filter_specs and not filter_specs[spec_name]
end

-- Check if class name filtering is enabled
local function classNamesFiltered()
    -- Returns true if class name filtering is turned on in the settings.
    return BistooltipAddon.db.char.filter_class_names
end

-- Filter item specs based on active settings
local function getFilteredItem(item)
    -- Loops through all specs of an item and filters out those that should not be shown.
    local filtered_item = {}
    for _, spec in ipairs(item) do
        if not specFiltered(spec.class_name, spec.spec_name) then
            table.insert(filtered_item, spec) -- Adds the unfiltered spec to the list.
        end
    end
    return filtered_item -- Returns the filtered list of specs.
end

-- TOOLTIP RENDERING ---------------------------------------------------------------
-- Add class name to the tooltip
local function printClassName(tooltip, class_name)
    -- Appends the class name as a line in the tooltip, with custom color formatting.
    tooltip:AddLine(class_name, 1, 0.8, 0) -- Yellow-orange color.
end

-- Add spec information to the tooltip
local function printSpecLine(tooltip, slot, class_name, spec_name)
    -- Displays a spec icon and its associated ranks in the tooltip.

    -- Retrieve the name and rank information of the slot (e.g., "Weapon").
    local slot_name, slot_ranks = slot.name, slot.ranks
    local prefix = classNamesFiltered() and "" or "   " -- Adjusts indentation if class filtering is enabled.
    local icon = Bistooltip_spec_icons[class_name][spec_name] -- Retrieve the spec's icon.
    local left_text = prefix .. "|T" .. icon .. ":14|t " .. spec_name -- Prepends the icon to the spec name.

    -- Append additional information for weapons or off-hand items.
    if slot_name:find("Weapon") or slot_name == "Off hand" then
        left_text = left_text .. " (" .. slot_name .. ")"
    end

    -- Add the spec information to the tooltip.
    tooltip:AddDoubleLine(left_text, slot_ranks, 1, 0.8, 0) -- Yellow-orange text color.
end

-- Get the source of an item
local function GetItemSource(itemId)
    local source -- Stores the formatted string containing the item's source location.

    -- Formats the instance name to display proper raid sizes (e.g., "25" for Heroic).
    local function formatInstanceName(instance)
        return instance:gsub("%(Heroic%)", "(25)")
    end

    -- Search for the item in the predefined lootTable.
    for zone, bosses in pairs(lootTable) do
        for boss, items in pairs(bosses) do
            if table.contains(items, itemId) then
                local formattedZone = formatInstanceName(zone)
                source = (source or "") .. "|cFFFFFFFFSource:|r |cFF00FF00" .. formattedZone .. " - " .. boss .. "|r\n"
            end
        end
    end

    -- Fallback: Look for the item in DataStore_Inventory if lootTable doesn't have it.
    if not source and DataStore_Inventory then
        local instance, boss = DataStore_Inventory:GetSource(itemId)
        if instance and boss then
            source = "|cFFFFFFFFSource:|r |cFF00FF00" .. formatInstanceName(instance) .. " - " .. boss .. "|r"
        end
    end

    return source
end

-- CORE LOGIC ----------------------------------------------------------------------
-- Search for item ID in BiS lists
local function searchIDInBislistsClassSpec(structure, id, class, spec)
    local paths, seen = {}, {}
    local sortedPhases = {}

    -- Sort the phases according to their predefined order.
    for _, phase in ipairs(Bistooltip_wowtbc_phases) do
        if structure[class] and structure[class][spec] and structure[class][spec][phase] then
            table.insert(sortedPhases, phase)
        end
    end

    -- Look for the item ID in each phase of the specified class and spec.
    for _, phase in ipairs(sortedPhases) do
        local items = structure[class][spec][phase]
        for _, itemData in pairs(items) do
            if type(itemData) == "table" and itemData[1] then
                for i, itemId in ipairs(itemData) do
                    if itemId == id and i ~= "slot_name" and i ~= "enhs" then
                        local phaseLabel = (i == 1) and (phase .. " BIS") or (phase .. " alt " .. i)
                        if not seen[phaseLabel] then
                            table.insert(paths, phaseLabel)
                            seen[phaseLabel] = true
                        end
                    end
                end
            end
        end
    end

    return #paths > 0 and table.concat(paths, " / ") or nil -- Combine all paths into a single string.
end

-- Handle item tooltip modification
local function OnGameTooltipSetItem(tooltip)
    -- Only proceed if the tooltip is being modified with CTRL held (if required in settings).
    if BistooltipAddon.db.char.tooltip_with_ctrl and not IsControlKeyDown() then
        return
    end

    -- Retrieve the item link from the tooltip.
    local _, link = tooltip:GetItem()
    if not link then return end

    -- Extract the item ID from the link (e.g., "item:12345").
    local _, itemId = strsplit(":", link)
    itemId = tonumber(itemId)
    if not itemId then return end

    -- Add the BiS information header to the tooltip.
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffff0000BIS-TOOLTIP:|r") -- Red "BIS-TOOLTIP" header.

    -- Add the item's source location to the tooltip (if found).
    local itemSource = GetItemSource(itemId)
    if itemSource then
        tooltip:AddLine(itemSource)
    end

    -- Loop through all classes and specs, adding BiS data to the tooltip.
    for class, specs in caseInsensitivePairs(Bistooltip_spec_icons) do
        for spec, icon in pairs(specs) do
            if spec ~= "classIcon" then
                local foundPhases = searchIDInBislistsClassSpec(Bistooltip_bislists, itemId, class, spec)
                if foundPhases then
                    local iconString = string.format("|T%s:18|t", icon) -- Format the icon.
                    tooltip:AddDoubleLine(iconString .. " " .. class .. " - " .. spec, foundPhases, 1, 1, 0, 1, 1, 0)
                end
            end
        end
    end

    tooltip:AddLine(" ")
end

-- INITIALIZATION ------------------------------------------------------------------
function BistooltipAddon:initBisTooltip()
    -- Set up event handling for ALT key changes.
    eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
    eventFrame:SetScript("OnEvent", function(_, _, e_key)
        -- Skip logic if the tooltip owner has an item already.
        if GameTooltip:GetOwner() and GameTooltip:GetOwner().hasItem then
            return
        end

        -- Check if the ALT key is being pressed.
        if e_key == "RALT" or e_key == "LALT" then
            local _, link = GameTooltip:GetItem()
            if link then
                GameTooltip:SetHyperlink("|cff9d9d9d|Hitem:3299::::::::20:257::::::|h[Fractured Canine]|h|r")
                GameTooltip:SetHyperlink(link)
            end
        end
    end)

    -- Hook tooltips to add custom behavior when items are set.
    local function HookTooltipWithOnTooltipSetItem(tooltip)
        tooltip:HookScript("OnTooltipSetItem", function(self)
            OnGameTooltipSetItem(self)
        end)
    end

    -- Apply hooks to all relevant tooltips.
    HookTooltipWithOnTooltipSetItem(GameTooltip)
    HookTooltipWithOnTooltipSetItem(ItemRefTooltip)
    HookTooltipWithOnTooltipSetItem(AtlasLootTooltip)
    HookTooltipWithOnTooltipSetItem(ShoppingTooltip1)
    HookTooltipWithOnTooltipSetItem(ShoppingTooltip2)
    HookTooltipWithOnTooltipSetItem(ShoppingTooltip3)

    -- Initialization message (optional debug confirmation).
    print("BistooltipAddon initialized successfully.")
end