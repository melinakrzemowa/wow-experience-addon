Experience = LibStub("AceAddon-3.0"):NewAddon("Experience", "AceConsole-3.0", "AceEvent-3.0")

local CombatLogGetCurrentEventInfo = _G.CombatLogGetCurrentEventInfo

Experience.mobs = {}
Experience.killed_mobs = {}
Experience.xp_gains = {}
Experience.timers = {}

function count(T, callback)
    local count = 0
    for k,v in pairs(T) do 
        if callback then
            if callback(k, v) then
                count = count + 1
            end
        else
            count = count + 1
        end 
    end
    return count
end

function Experience:OnInitialize()
    -- self:Print("initialized")

    local defaults = {
        char = {
            xp_gains = {}
        }
      }

    self.db = LibStub("AceDB-3.0"):New("ExperienceDB", defaults)
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
                type = self.mobs[dstGUID].type,
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

    in_instance, instance_type = IsInInstance()

    group = {}

    group_count = GetNumGroupMembers() - 1

    for i=1,group_count do
        if not self:IsInDistance("party" .. i) then
            self:Print("Party member is too far away - ignoring data for now.")
            self:CleanUp(time, name)

            return
        end

        table.insert(group, UnitLevel("party" .. i))
        -- self:Print("Party " .. i .. " level: " .. group[i])
    end

    table.sort(group, function(p1, p2) return p1 > p2 end)

    player_level = UnitLevel("player")

    -- self:Print(time, event, xp_gained, rested_bonus, name)

    xp_gain = {
        time = time,
        name = name,
        xp = xp_gained - rested_bonus,
        player = {
            player_level = player_level,
            group = group,
            in_instance = in_instance,
            instance_type = instance_type
        }
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
end

function Experience:SaveUnitData(unitId)
    guid = UnitGUID(unitId)

    if guid ~= nil and string.sub(guid,1,string.len("Creature")) == "Creature" then
        -- self:Print(UnitName(unitId) .. " " .. UnitLevel(unitId) .. " " .. UnitGUID(unitId))

        self.mobs[guid] = {
            name = UnitName(unitId),
            level = UnitLevel(unitId),
            type = UnitClassification(unitId)
        }
    end
end

function Experience:ComputeDistance(unit1, unit2)
    local y1, x1, _, instance1 = UnitPosition(unit1)
    local y2, x2, _, instance2 = UnitPosition(unit2)

    if instance1 == instance2 and instance1 > 0 then
        -- for now let's assume that if we are in any instance we are close enough
        return 10
    else
        return instance1 == instance2 and ((x2 - x1) ^ 2 + (y2 - y1) ^ 2) ^ 0.5
    end
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

        mob_callback = function(_, mob) 
            return mob.name == xp_gain.name and mob.time == time
        end

        if count(self.killed_mobs, mob_callback) > 1 then
            self:Print("Found too many killed mobs, ignoring data for now. (shouldn't ever go here)")
            self:CleanUp(time, xp_gain.name)
    
            return
        end

        for guid, mob in pairs(self.killed_mobs) do
            if mob.time == time and mob.name == xp_gain.name then
                kill_data = {
                    time = time,
                    mob = mob,
                    xp = xp_gain.xp,
                    player = xp_gain.player
                }

                DevTools_Dump(kill_data)

                table.insert(self.db.char.xp_gains, kill_data)

                self:CleanUp(time, xp_gain.name)

                return
            end
        end
    end
end

function Experience:CleanUp(time, name)
    self.xp_gains[time] = nil

    for guid, mob in pairs(self.killed_mobs) do
        if mob.time == time and (mob.name == name or name == nil) then
            self.killed_mobs[guid] = nil
        end
    end
end
  