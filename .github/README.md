# LibClassicDurations

Tracks all whitelisted aura applications and then returns UnitAura-friendly _duration, expirationTime_ pair.

Also can show enemy buff info. That's a completely optional feature with no impact on performance if it's not being used

Usage example 1: Simple UnitAura wrapper
-----------------

```lua
local UnitAura = _G.UnitAura

local LibClassicDurations = LibStub("LibClassicDurations", true)
if LibClassicDurations then
    LibClassicDurations:Register("YourAddon")
    UnitAura = LibClassicDurations.UnitAuraWrapper
end
```

Usage example 2: Enemy Buffs Setup Compatible With Retail
-----------------

```lua
local isClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC

local f = CreateFrame("Frame", nil, UIParent)
f:SetScript("OnEvent", function(self, event, ...)
    return self[event](self, event, ...)
end)

local UnitAura = _G.UnitAura

if isClassic then
    LibClassicDurations = LibStub("LibClassicDurations")
    LibClassicDurations:Register("YourAddon") -- tell library it's being used and should start working
    UnitAura = LibClassicDurations.UnitAuraWithBuffs
    LibClassicDurations.RegisterCallback("YourAddon", "UNIT_BUFF", function(event, unit)
        f:UNIT_AURA(event, unit)
    end)
end

function f:UNIT_AURA(event, unit)
    for i=1,100 do
        local name, _, _, _, duration, expirationTime, _, _, _, spellId = UnitAura(unit, i, "HELPFUL")
        if not name then break end
        print(name, duration, expirationTime)
    end
end
```

Usage example 3: No Wrappers
-----------------

```lua
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
```


Embedding in .pkgmeta
--------------------------

    externals:
      Libs/LibClassicDurations: https://repos.curseforge.com/wow/libclassicdurations


![Screenshot](https://i.imgur.com/ZE6IWys.jpg)