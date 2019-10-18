# LibClassicDurations

Tracks all whitelisted aura applications and then returns UnitAura-friendly _duration, expirationTime_ pair.

Also can show enemy buff info. That's a completely optional feature with no impact on performance if it's not being used

Usage example 1:
-----------------

    -- Using UnitAura wrapper
    local UnitAura = _G.UnitAura

    local LibClassicDurations = LibStub("LibClassicDurations", true)
    if LibClassicDurations then
        LibClassicDurations:Register("YourAddon")
        UnitAura = LibClassicDurations.UnitAuraWrapper
    end

Usage example 2:
-----------------

    -- Simply get the expiration time and duration

    local LibClassicDurations = LibStub("LibClassicDurations")
    LibClassicDurations:Register("YourAddon") -- tell library it's being used and should start working

    hooksecurefunc("CompactUnitFrame_UtilSetBuff", function(buffFrame, unit, index, filter)
        local name, _, _, _, duration, expirationTime, unitCaster, _, _, spellId = UnitBuff(unit, index, filter);

        local durationNew, expirationTimeNew = LibClassicDurations:GetAuraDurationByUnit(unit, spellId, unitCaster, name)
        if duration == 0 and durationNew then
            duration = durationNew
            expirationTime = expirationTimeNew
        end

        local enabled = expirationTime and expirationTime ~= 0;
        if enabled then
            local startTime = expirationTime - duration;
            CooldownFrame_Set(buffFrame.cooldown, startTime, duration, true);
        else
            CooldownFrame_Clear(buffFrame.cooldown);
        end
    end)

Usage example 3:
-----------------

    -- Use library's UnitAura replacement function, that shows enemy buffs and
    -- automatically tries to add duration to everything else

    local LCD = LibStub("LibClassicDurations")
    LCD:Register("YourAddon") -- tell library it's being used and should start working

    local f = CreateFrame("frame", nil, UIParent)
    f:RegisterUnitEvent("UNIT_AURA", "target")

    local EventHandler = function(self, event, unit)
        for i=1,100 do
            local name, _, _, _, duration, expirationTime, _, _, _, spellId = LCD:UnitAura(unit, i, "HELPFUL")
            if not name then break end
            print(name, duration, expirationTime)
        end
    end

    f:SetScript("OnEvent", EventHandler)

    -- NOTE: Enemy buff tracking won't start until you register UNIT_BUFF
    LCD.RegisterCallback(addon, "UNIT_BUFF", function(event, unit)
        EventHandler(f, "UNIT_AURA", unit)
    end)

    -- Optional:
    LCD.RegisterCallback(addon, "UNIT_BUFF_GAINED", function(event, unit, spellID)
        print("Gained", GetSpellInfo(spellID))
    end)


Embedding in .pkgmeta
--------------------------

    externals:
      Libs/LibClassicDurations: https://repos.curseforge.com/wow/libclassicdurations


![Screenshot](https://i.imgur.com/ZE6IWys.jpg)