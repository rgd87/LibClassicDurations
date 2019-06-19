--[================[
LibClassicDurations
Author: d87
Description: tracking expiration times
--]================]


local MAJOR, MINOR = "LibClassicDurations", 4
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)
lib.frame = lib.frame or CreateFrame("Frame")

local weakKeysMeta = { __mode = "k" }
lib.guids = lib.guids or setmetatable({}, weakKeysMeta)
lib.spells = lib.spells or {

}
lib.npc_spells = lib.npc_spells or {}

lib.buffCache = lib.buffCache or setmetatable({}, weakKeysMeta)
local buffCache = lib.buffCache

lib.buffCacheValid = lib.buffCacheValid or setmetatable({}, weakKeysMeta)
local buffCacheValid = lib.buffCacheValid

lib.nameplateUnitMap = lib.nameplateUnitMap or {}
local nameplateUnitMap = lib.nameplateUnitMap

local f = lib.frame
local callbacks = lib.callbacks
local guids = lib.guids
local spells = lib.spells
local npc_spells = lib.npc_spells

local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local UnitGUID = UnitGUID
local UnitAura = UnitAura
local GetTime = GetTime
local unpack = unpack

f:SetScript("OnEvent", function(self, event, ...)
    return self[event](self, event, ...)
end)

local SpellDataVersions = {}

function lib:SetDataVersion(dataType, version)
    SpellDataVersions[dataType] = version
    npc_spells = lib.npc_spells
end

function lib:GetDataVersion(dataType)
    return SpellDataVersions[dataType] or 0
end


lib.AddAura = lib.AddAura or function(id, opts)
    if not opts then return end

    if type(id) == "table" then
        for _, spellID in ipairs(id) do
            spells[spellID] = opts
        end
    else
        spells[id] = opts
    end
end

lib.Talent = lib.Talent or function (...)
    for i=1, 5 do
        local spellID = select(i, ...)
        if not spellID then break end
        if IsPlayerSpell(spellID) then return i end
    end
    return 0
end


--------------------------
-- DIMINISHING RETURNS
--------------------------
local bit_band = bit.band
local DRResetTime = 18.4

local DRInfo = setmetatable({}, weakKeysMeta)
local COMBATLOG_OBJECT_TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER
local COMBATLOG_OBJECT_REACTION_FRIENDLY = COMBATLOG_OBJECT_REACTION_FRIENDLY

local DRMultipliers = { 0.5, 0.25, 0}
local function addDRLevel(dstGUID, category)
    local guidTable = DRInfo[dstGUID]
    if not guidTable then
        DRInfo[dstGUID] = {}
        guidTable = DRInfo[dstGUID]
    end

    local catTable = guidTable[category]
    if not catTable then
        guidTable[category] = {}
        catTable = guidTable[category]
    end

    local now = GetTime()
    local isExpired = (catTable.expires or 0) <= now
    if isExpired then
        catTable.level = 1
        catTable.expires = now + DRResetTime
    else
        catTable.level = catTable.level + 1
    end
end
local function clearDRs(dstGUID)
    DRInfo[dstGUID] = nil
end
local function getDRMul(dstGUID, spellID)
    local category = lib.DR_CategoryBySpellID[spellID]
    if not category then return 1 end

    local guidTable = DRInfo[dstGUID]
    if guidTable then
        local catTable = guidTable[category]
        if catTable then
            local now = GetTime()
            local isExpired = (catTable.expires or 0) <= now
            if isExpired then
                return 1
            else
                local mul = DRMultipliers[catTable.level]
                return mul or 1
            end
        end
    end
    return 1
end

local function CountDiminishingReturns(eventType, srcGUID, srcFlags, dstGUID, dstFlags, spellID, auraType)
    if auraType == "DEBUFF" then
        if eventType == "SPELL_AURA_REMOVED" or eventType == "SPELL_AURA_REFRESH" then
            local category = lib.DR_CategoryBySpellID[spellID]
            if not category then return end

            local isDstPlayer = bit_band(dstFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0
            -- local isFriendly = bit_band(dstFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY) > 0

            if not isDstPlayer then
                if not lib.DR_TypesPVE[category] then return end
            end

            addDRLevel(dstGUID, category)
        end
        if eventType == "UNIT_DIED" then
            clearDRs(dstGUID)
            buffCache[dstGUID] = nil
            buffCacheValid[dstGUID] = nil
        end
    end
end

------------------------
-- COMBO POINTS
------------------------

local GetComboPoints = GetComboPoints
local _, playerClass = UnitClass("player")
local cpWas = 0
local cpNow = 0
local function GetCP()
    if not cpNow then return GetComboPoints("player", "target") end
    return cpWas > cpNow and cpWas or cpNow
end

function f:PLAYER_TARGET_CHANGED(event)
    return self:UNIT_POWER_UPDATE(event, "player", "COMBO_POINTS")
end
function f:UNIT_POWER_UPDATE(event,unit, ptype)
    if ptype == "COMBO_POINTS" then
        cpWas = cpNow
        cpNow = GetComboPoints(unit, "target")
    end
end

---------------------------
-- COMBAT LOG
---------------------------

local function cleanDuration(duration, spellID, srcGUID)
    if type(duration) == "function" then
        local isSrcPlayer = srcGUID == UnitGUID("player")
        local comboPoints
        if isSrcPlayer and playerClass == "ROGUE" then
            comboPoints = GetCP()
        end
        return duration(spellID, isSrcPlayer, comboPoints)
    end
    return duration
end


local function SetTimer(srcGUID, dstGUID, dstName, dstFlags, spellID, spellName, opts, auraType, doRemove)
    if not opts then return end

    local guidTable = guids[dstGUID]
    if not guidTable then
        guids[dstGUID] = setmetatable({}, weakKeysMeta)
        guidTable = guids[dstGUID]
    end

    local isStacking = opts.stacking
    -- local auraUID = MakeAuraUID(spellID, isStacking and srcGUID)

    if doRemove then
        if guidTable[spellID] then
            if isStacking then
                if guidTable[spellID].applications then
                    guidTable[spellID].applications[srcGUID] = nil
                end
            else
                guidTable[spellID] = nil
            end
        end
        return
    end

    local spellTable = guidTable[spellID]
    if not spellTable then
        guidTable[spellID] = {}
        spellTable = guidTable[spellID]
        if isStacking then
            spellTable.applications = {}
        end
    end

    local applicationTable
    if isStacking then
        applicationTable = spellTable.applications[srcGUID]
        if not applicationTable then
            spellTable.applications[srcGUID] = {}
            applicationTable = spellTable.applications[srcGUID]
        end
    else
        applicationTable = spellTable
    end

    local duration = cleanDuration(opts.duration, spellID, srcGUID)
    if not duration or duration == 0 then
        return SetTimer(srcGUID, dstGUID, dstName, dstFlags, spellID, spellName, opts, auraType, true)
    end
    local mul = getDRMul(dstGUID, spellID)
    duration = duration * mul
    local now = GetTime()
    local expirationTime = now + duration
    applicationTable[1] = duration
    applicationTable[2] = expirationTime
    applicationTable[3] = auraType
end

---------------------------
-- COMBAT LOG HANDLER
---------------------------
function f:COMBAT_LOG_EVENT_UNFILTERED(event)

    local timestamp, eventType, hideCaster,
    srcGUID, srcName, srcFlags, srcFlags2,
    dstGUID, dstName, dstFlags, dstFlags2,
    spellID, spellName, spellSchool, auraType, amount = CombatLogGetCurrentEventInfo()

    CountDiminishingReturns(eventType, srcGUID, srcFlags, dstGUID, dstFlags, spellID, auraType)

    if auraType == "BUFF" or auraType == "DEBUFF" then
        local isDstFriendly = bit_band(dstFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY) > 0

        local opts = spells[spellID]
        if not opts then
            local npc_aura_duration = npc_spells[spellID]
            if npc_aura_duration then
                opts = { duration = npc_aura_duration }
            end
        end
        if opts then
            -- print(eventType, srcGUID, "=>", dstName, spellID, spellName, auraType )
            if  eventType == "SPELL_AURA_REFRESH" or
                eventType == "SPELL_AURA_APPLIED" or
                eventType == "SPELL_AURA_APPLIED_DOSE" then
                SetTimer(srcGUID, dstGUID, dstName, dstFlags, spellID, spellName, opts, auraType)
            elseif eventType == "SPELL_AURA_REMOVED" then
                SetTimer(srcGUID, dstGUID, dstName, dstFlags, spellID, spellName, opts, auraType, true)
            -- elseif eventType == "SPELL_AURA_REMOVED_DOSE" then
                -- self:RemoveDose(srcGUID, dstGUID, spellID, spellName, auraType, amount)
            end
            isDstFriendly = false
            if not isDstFriendly and auraType == "BUFF" then
                -- invalidate buff cache
                buffCacheValid[dstGUID] = nil

                if dstGUID == UnitGUID("target") then
                    callbacks:Fire("UNIT_BUFF", "target")
                end
                local nameplateUnit = nameplateUnitMap[dstGUID]
                if nameplateUnit then
                    callbacks:Fire("UNIT_BUFF", nameplateUnit)
                end
            end
        end
    end
    if eventType == "UNIT_DIED" then
        guids[dstGUID] = nil
    end
end

---------------------------
-- ENEMY BUFFS
---------------------------
local makeBuffInfo = function(spellID, bt)
    local name, rank, icon, castTime, minRange, maxRange, spellId = GetSpellInfo(spellID)
    -- buffName, icon, count, debuffType, duration, expirationTime, caster, canStealOrPurge, _ , spellId
    return { name, icon, 1, nil, bt[1], bt[2], nil, nil, nil, spellID }
end

local function RegenerateBuffList(dstGUID)
    local guidTable = guids[dstGUID]
    if not guidTable then
        return
    end

    local buffs = {}
    for spellID, t in pairs(guidTable) do
        if t.applications then
            for srcGUID, auraTable in pairs(t.applications) do
                if auraTable[3] == "BUFF" then -- TODO and if not expired
                    table.insert(buffs, makeBuffInfo(spellID, buffTable))
                end
            end
        else
            if t[3] == "BUFF" then
                table.insert(buffs, makeBuffInfo(spellID, t))
            end
        end
    end

    buffCache[dstGUID] = buffs
    buffCacheValid[dstGUID] = true
end

function lib.UnitAuraDirect(unit, index, filter)
    if not UnitIsFriend("player", unit) and filter == "HELPFUL" and not UnitAura(unit, 1, filter) then
        local unitGUID = UnitGUID(unit)
        if not buffCacheValid[unitGUID] then
            RegenerateBuffList(unitGUID)
        end

        local buffCacheHit = buffCache[unitGUID]
        if buffCacheHit then
            local buffReturns = buffCache[unitGUID][index]
            if buffReturns then
                return unpack(buffReturns)
            end
        end
    else
        return UnitAura(unit, index, filter)
    end
end

function lib:UnitAura(...)
    return self.UnitAuraDirect(...)
end

function f:NAME_PLATE_UNIT_ADDED(event, unit)
    local unitGUID = UnitGUID(unit)
    nameplateUnitMap[unitGUID] = unit
end
function f:NAME_PLATE_UNIT_REMOVED(event, unit)
    local unitGUID = UnitGUID(unit)
    if unitGUID then -- it returns correctly on death, but just in case
        nameplateUnitMap[unitGUID] = nil
    end
end

function callbacks.OnUsed()
    f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
end
function callbacks.OnUnused()
    f:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
    f:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
end

---------------------------
-- PUBLIC FUNCTIONS
---------------------------
local function GetGUIDAuraTime(dstGUID, spellID, srcGUID, isStacking)
    local guidTable = guids[dstGUID]
    if guidTable then
        -- local isStacking = opts.stacking
        local spellTable = guidTable[spellID]
        if spellTable then
            local applicationTable
            if isStacking then
                if srcGUID then
                    applicationTable = spellTable.applications[srcGUID]
                else -- return some duration
                    applicationTable = select(2,next(spellTable.applications))
                end
            else
                applicationTable = spellTable
            end
            if not applicationTable then return end
            local duration, expirationTime = unpack(applicationTable)
            if GetTime() <= expirationTime then
                return duration, expirationTime
            end
        end
    end
end

function lib:GetAuraDurationByUnit(unit, spellID, casterUnit)
    local opts = spells[spellID]
    if not opts then return end
    local dstGUID = UnitGUID(unit)
    local srcGUID = casterUnit and UnitGUID(casterUnit)
    return GetGUIDAuraTime(dstGUID, spellID, srcGUID, opts.stacking)
end
function lib:GetAuraDurationByGUID(dstGUID, spellID, srcGUID)
    local opts = spells[spellID]
    if not opts then return end
    return GetGUIDAuraTime(dstGUID, spellID, srcGUID, opts.stacking)
end

local activeFrames = {}
function lib:RegisterFrame(frame)
    activeFrames[frame] = true
    if next(activeFrames) then
        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        if playerClass == "ROGUE" then
            f:RegisterEvent("PLAYER_TARGET_CHANGED")
            f:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        end
    end
end

function lib:UnregisterFrame(frame)
    activeFrames[frame] = nil
    if not next(activeFrames) then
        f:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        if playerClass == "ROGUE" then
            f:UnregisterEvent("PLAYER_TARGET_CHANGED")
            f:UnregisterEvent("UNIT_POWER_UPDATE")
        end
    end
end


