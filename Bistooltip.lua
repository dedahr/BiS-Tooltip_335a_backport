-- GLOBAL DEFINITIONS --------------------------------------------------------------
local eventFrame = CreateFrame("Frame", nil, UIParent) -- Event handler for ALT key presses
Bistooltip_phases_string = "" -- String to store BiS phase information
local DataStore_Inventory = DataStore_Inventory or nil -- Fallback for item source retrieval

-- UTILITY FUNCTIONS ---------------------------------------------------------------
-- Iterate through table keys in a case-insensitive sorted order
local function caseInsensitivePairs(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys, function(a, b) return a:lower() < b:lower() end)
    
    local i = 0
    return function()
        i = i + 1
        local k = keys[i]
        if k then return k, t[k] end
    end
end

-- Remove color codes from a string and calculate its length
local function getStringLength(str)
    return string.len(str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Check if a table contains a specific element
function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then return true end
    end
    return false
end

-- FILTERING LOGIC ---------------------------------------------------------------
-- Check if a specific spec is highlighted
local function specHighlighted(class_name, spec_name)
    return (BistooltipAddon.db.char.highlight_spec.spec_name == spec_name and
        BistooltipAddon.db.char.highlight_spec.class_name == class_name)
end

-- Determine if a spec should be filtered out
local function specFiltered(class_name, spec_name)
    if specHighlighted(class_name, spec_name) then return false end
    if IsAltKeyDown() then return false end
    if BistooltipAddon.db.char.filter_specs[class_name] then
        return not BistooltipAddon.db.char.filter_specs[class_name][spec_name]
    end
    return false
end

-- Check if class name filtering is enabled
local function classNamesFiltered()
    return BistooltipAddon.db.char.filter_class_names and true or false
end

-- Filter item specs based on the active settings
local function getFilteredItem(item)
    local filtered_item = {}
    for _, spec in ipairs(item) do
        local class_name = spec.class_name
        local spec_name = spec.spec_name
        if not specFiltered(class_name, spec_name) then
            table.insert(filtered_item, spec)
        end
    end
    return filtered_item
end

-- TOOLTIP RENDERING --------------------------------------------------------------
-- Add class name to the tooltip
local function printClassName(tooltip, class_name)
    -- Adds the class name as a single line in the tooltip with a yellow-orange color
    tooltip:AddLine(class_name, 1, 0.8, 0)
end

-- Add spec information to the tooltip
local function printSpecLine(tooltip, slot, class_name, spec_name)
    -- Displays spec name along with its icon and ranks in the tooltip
    local slot_name, slot_ranks = slot.name, slot.ranks
    local prefix = classNamesFiltered() and "" or "   " -- Adjust indentation if class filtering is active
    local icon = Bistooltip_spec_icons[class_name][spec_name]
    local left_text = prefix .. "|T" .. icon .. ":14|t " .. spec_name

    -- Append additional details for weapons/off-hand items
    if slot_name:find("Weapon") or slot_name == "Off hand" then
        left_text = left_text .. " (" .. slot_name .. ")"
    end

    -- Add the prepared line to the tooltip with proper formatting
    tooltip:AddDoubleLine(left_text, slot_ranks, 1, 0.8, 0)
end

-- Retrieve the source information for an item
local function GetItemSource(itemId)
    local source -- String to store formatted source information

    -- Helper to normalize instance names for readability
    local function formatInstanceName(instance)
        local tmpInstance = string.lower(instance)
        if tmpInstance == "the obsidian sanctum (heroic)" then
            return "The Obsidian Sanctum(25)"
        elseif tmpInstance == "the eye of eternity (heroic)" then
            return "The Eye Of Eternity (25)"
        elseif tmpInstance == "naxxramas (heroic)" then
            return "Naxxramas (25)"
        elseif tmpInstance == "ulduar (heroic)" then
            return "Ulduar (25)"
        end
        return instance
    end

    -- Search for the item in the predefined lootTable
    for zone, bosses in pairs(lootTable) do
        for boss, items in pairs(bosses) do
            if table.contains(items, itemId) then
                local formattedZone = formatInstanceName(zone)
                source = (source or "") .. "|cFFFFFFFFSource:|r |cFF00FF00" .. formattedZone .. " - " .. boss .. "|r\n"
            end
        end
        if source then break end -- Stop searching once the source is found
    end

    -- Fallback: Search for the item in DataStore_Inventory
    if not source and DataStore_Inventory then
        local instance, boss = DataStore_Inventory:GetSource(itemId)
        if instance and boss then
            local formattedInstance = formatInstanceName(instance)
            source = "|cFFFFFFFFSource:|r |cFF00FF00" .. formattedInstance .. " - " .. boss .. "|r"
        end
    end

    return source -- Return the final formatted source string
end

-- MAIN LOGIC ----------------------------------------------------------------------
-- Search for an item ID in BiS lists for a specific class and spec
local function searchIDInBislistsClassSpec(structure, id, class, spec)
    local paths, seen = {}, {} -- `paths` holds phase labels; `seen` prevents duplicates
    local sortedPhases = {}

    -- Sort the phases according to their predefined order
    for _, phase in ipairs(Bistooltip_wowtbc_phases) do
        if structure[class] and structure[class][spec] and structure[class][spec][phase] then
            table.insert(sortedPhases, phase)
        end
    end

    -- Iterate through phases to find item ID matches
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

    -- Return all paths as a concatenated string or nil if none are found
    return #paths > 0 and table.concat(paths, " / ") or nil
end

-- Modify item tooltip with BiS information
local function OnGameTooltipSetItem(tooltip)
    if BistooltipAddon.db.char.tooltip_with_ctrl and not IsControlKeyDown() then return end

    local _, link = tooltip:GetItem()
    if not link then return end

    local _, itemId = strsplit(":", link)
    itemId = tonumber(itemId)
    if not itemId then return end

    -- Add BiS information header
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffff0000BIS-TOOLTIP:|r") -- Display header in red

    -- Add item source information if available
    local itemSource = GetItemSource(itemId)
    if itemSource then tooltip:AddLine(itemSource) end

    -- Add BiS phases for each class/spec
    for class, specs in caseInsensitivePairs(Bistooltip_spec_icons) do
        for spec, icon in pairs(specs) do
            if spec ~= "classIcon" then
                local foundPhases = searchIDInBislistsClassSpec(Bistooltip_bislists, itemId, class, spec)
                if foundPhases then
                    local iconString = string.format("|T%s:18|t", icon) -- Format spec icon
                    local lineText = string.format("%s %s - %s", iconString, class, spec)
                    tooltip:AddDoubleLine(lineText, foundPhases, 1, 1, 0, 1, 1, 0)
                end
            end
        end
    end

    tooltip:AddLine(" ")
end

-- INITIALIZATION ------------------------------------------------------------------
function BistooltipAddon:initBisTooltip()
    eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED") -- Listen for ALT key presses
    eventFrame:SetScript("OnEvent", function(_, _, e_key)
        if GameTooltip:GetOwner() and GameTooltip:GetOwner().hasItem then return end

        -- React to ALT key presses
        if e_key == "RALT" or e_key == "LALT" then
            local _, link = GameTooltip:GetItem()
            if link then
                GameTooltip:SetHyperlink("|cff9d9d9d|Hitem:3299::::::::20:257::::::|h[Fractured Canine]|h|r")
                GameTooltip:SetHyperlink(link)
            end
        end
    end)

    -- Hook tooltips to add custom functionality
    local function HookTooltipWithOnTooltipSetItem(tooltip)
        tooltip:HookScript("OnTooltipSetItem", function(self)
            OnGameTooltipSetItem(self)
        end)
    end

    -- Apply hooks to relevant tooltips
    HookTooltipWithOnTooltipSetItem(GameTooltip)
    HookTooltipWithOnTooltipSetItem(ItemRefTooltip)

    -- Check if AtlasLoot is loaded and running
    if IsAddOnLoaded("AtlasLoot") then
        print("AtlasLoot is loaded and running!") -- Debug message
        HookTooltipWithOnTooltipSetItem(AtlasLootTooltip)
    else
        print("AtlasLoot is not loaded or running.") -- Debug message
    end

    -- Hook additional shopping tooltips
    HookTooltipWithOnTooltipSetItem(ShoppingTooltip1)
    HookTooltipWithOnTooltipSetItem(ShoppingTooltip2)
    HookTooltipWithOnTooltipSetItem(ShoppingTooltip3)
end