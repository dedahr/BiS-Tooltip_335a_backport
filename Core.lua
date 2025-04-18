BistooltipAddon = LibStub("AceAddon-3.0"):NewAddon("Bis-Tooltip")

Bistooltip_char_equipment = {}

local function collectItemIDs(bislists)
    local itemIDs = {}

    for _, classData in pairs(bislists) do
        for _, specData in pairs(classData) do
            for _, phaseData in pairs(specData) do
                for _, itemData in ipairs(phaseData) do
                    for key, value in pairs(itemData) do
                        if type(key) == "number" then
                            table.insert(itemIDs, value)
                        elseif key == "enhs" then
                            for _, enhData in pairs(value) do
                                if enhData.type == "item" and enhData.id then
                                    table.insert(itemIDs, enhData.id)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return itemIDs
end

local function createEquipmentWatcher()
    local frame = CreateFrame("Frame")
    frame:Hide()

    -- Update only on worn equipment change, old code produce lag on loot and
	-- every class which extensively use consumables/amo from bag in combat
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED") -- Triggered when equipment changes

    frame:SetScript("OnEvent", frame.Show)

    frame:SetScript("OnUpdate", function(self, elapsed)
        self:Hide() -- Hide the frame to stop updates once processing is done

        local collection = {}

        -- Check worn equipment (equipped items)
        for i = 1, 19 do
            local itemID = GetInventoryItemID("player", i)
            if itemID then
                collection[itemID] = 2 -- Mark item as equipped
            end
        end

        -- Store processed equipment data
        Bistooltip_char_equipment = collection
    end)
end

function BistooltipAddon:OnInitialize()
    createEquipmentWatcher()
    BistooltipAddon.AceAddonName = "Bis-Tooltip"
    BistooltipAddon.AddonNameAndVersion = "Bis-Tooltip 3.3.5a backport by Silver [DisruptionAuras]"
    BistooltipAddon:initConfig()
    BistooltipAddon:addMapIcon()
    BistooltipAddon:initBislists()
    BistooltipAddon:initBisTooltip()
end
