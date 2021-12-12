Experience = LibStub("AceAddon-3.0"):NewAddon("Experience", "AceConsole-3.0", "AceEvent-3.0")

local CombatLogGetCurrentEventInfo = _G.CombatLogGetCurrentEventInfo

Experience.mobs = {}
Experience.killed_mobs = {}
Experience.xp_gains = {}
Experience.timers = {}

function count(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

function Experience:OnInitialize()
    -- self:Print("initialized")
end

function Experience:OnEnable()
    -- self:Print("enabled")

    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("UNIT_TARGET", "UNIT_TARGET")
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_ADDED")
    self:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_COMBAT_XP_GAIN")
end

function Experience:OnDisable()
    -- self:Print("disabled")
end

function Experience:COMBAT_LOG_EVENT_UNFILTERED()
    local _, eventType, _, _, _, _, _, dstGUID = CombatLogGetCurrentEventInfo()

    -- self:Print(CombatLogGetCurrentEventInfo())

    if eventType == "PARTY_KILL" then
        if self.mobs[dstGUID] ~= nil then
            -- self:Print("Killed: ", self.mobs[dstGUID].name, self.mobs[dstGUID].level)

            self.killed_mobs[dstGUID] = {
                name = self.mobs[dstGUID].name,
                level = self.mobs[dstGUID].level,
                time = time()
            }

            self.mobs[dstGUID] = nil
        end
    end
end

function Experience:UNIT_TARGET(event, target)
    self:SaveUnitData(target .. "target")
end

function Experience:NAME_PLATE_UNIT_ADDED(event, plate)
    self:SaveUnitData(plate)
end

function Experience:CHAT_MSG_COMBAT_XP_GAIN(event, text)

    local xp_gained = string.match(text, "(%d+) experience") or "0"
    xp_gained = tonumber(xp_gained)
    local rested_bonus = string.match(text, "%+(%d+) exp Rested bonus") or "0"
    rested_bonus = tonumber(rested_bonus)

    local name = string.match(text, "([%a%s]+) dies")
    local time = time()

    self:Print(time, event, xp_gained, rested_bonus, name)

    xp_gain = {
        time = time,
        name = name,
        xp = xp_gained - rested_bonus
    }

    if self.xp_gains[time] == nil then
        self.xp_gains[time] = {}
    end

    -- Use as a Set container
    self.xp_gains[time][xp_gain] = true

    if self.timers[time] == nil then
        self.timers[time] = C_Timer.NewTimer(2, function()
            self:SaveXpData(time) 
        end)
    end

    -- C_Timer.After(2, function() 
    --     self:SaveXpData(time, name, xp_gained - rested_bonus) 
    -- end)
end

function Experience:SaveUnitData(unitId)
    if UnitGUID(unitId) ~= nil and not UnitIsPlayer(unitId1) then
        -- self:Print(UnitName(unitId) .. " " .. UnitLevel(unitId) .. " " .. UnitGUID(unitId))

        self.mobs[UnitGUID(unitId)] = {
            name = UnitName(unitId),
            level = UnitLevel(unitId)
        }
    end
end

function Experience:ComputeDistance(unit1, unit2)
    local y1, x1, _, instance1 = UnitPosition(unit1)
    local y2, x2, _, instance2 = UnitPosition(unit2)
    return instance1 == instance2 and ((x2 - x1) ^ 2 + (y2 - y1) ^ 2) ^ 0.5
end

function Experience:IsInDistance(unit)
    distance = self:ComputeDistance("player", unit)

    -- We are getting experience from mobs killed at 250 yards. However we can only
    -- calculate a distance to someone else from the party, not the mob.
    -- So we don't want to have wrong values in our dataset so we are ignoring results
    -- that are generated when anyone in the party is further away than 150 yards (arbitrary number)
    -- Although this still doesn't make us safe from wrong values (for instance someone could have 
    -- dotted a mob and then run closer than 150 yards but the mob is still farther than 250 yards)
    -- but the errored values should be much scarcer
    if distance then
        return distance <= 150
    else
        return false
    end
end

function Experience:SaveXpData(time)
    self.timers[time] = nil

    if count(self.xp_gains[time]) > 1 then
        self:Print("Too many XP gains, ignoring data for now.")
        self:CleanUp(time)

        return
    end

    -- Should find just one
    for xp_gain, _ in pairs(self.xp_gains[time]) do

        if IsInRaid() then
            self:Print("In Raid - skip data for now.")
            self:CleanUp(time, xp_gain.name)
    
            return
        end

        if count(self.killed_mobs) > 1 then
            self:Print("Found too many killed mobs, ignoring data for now. (shouldn't ever go here)4")
            self:CleanUp(time, xp_gain.name)
    
            return
        end

        for guid, mob in pairs(self.killed_mobs) do
            if mob.time == time and mob.name == xp_gain.name then
                group = {}

                group_count = GetNumGroupMembers() - 1

                for i=1,group_count do
                    if not self:IsInDistance("party" .. i) then
                        self:Print("Party member is too far away - ignoring data for now.")
                        self:CleanUp(time, xp_gain.name)

                        return
                    end

                    group[i] = UnitLevel("party" .. i)
                    self:Print("Party " .. i .. " level: " .. group[i])
                end

                player = UnitLevel("player")
        
                self:Print(time, xp_gain.name, xp_gain.xp, mob.level, player)
                self:CleanUp(time, xp_gain.name)

                return
            end
        end
    end
end

function Experience:CleanUp(time, name)
    self.xp_gains[time] = nil

    if name ~= nil then
        for guid, mob in pairs(self.killed_mobs) do
            if mob.time == time and mob.name == name then
                self.killed_mobs[guid] = nil
            end
        end
    end
end
  