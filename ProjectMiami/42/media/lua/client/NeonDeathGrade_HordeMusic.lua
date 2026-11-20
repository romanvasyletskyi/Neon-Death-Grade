-- Local soundtrack only: the cue never emits an in-world noise.
local FUTURE_SOUND = "NeonDeathGradeFutureClub"
local LOADING_SOUND = "NeonDeathGradeLoadingInterlude"
local CALM_SOUNDS = {
    "NeonDeathGradeCalmRust",
    "NeonDeathGradeCalmDagUnenge",
    "NeonDeathGradeCalmMissMinnie",
    "NeonDeathGradeCalmCrystals",
}
local COMBAT_SOUNDS = {
    "NeonDeathGradeCombatSexualizer",
    "NeonDeathGradeCombatDivide",
    "NeonDeathGradeCombatDecadeDance",
    "NeonDeathGradeCombatNewWaveHookers",
}
local WOUNDED_WAKE_SOUND = "NeonDeathGradeWakeFlatline"
local HEALTHY_WAKE_SOUND = "NeonDeathGradeWakeDeepCover"
local FUTURE_COUNT = 20
local RADIUS_SQUARED = 15 * 15
local SCAN_MS = 250
local FUTURE_RELEASE_MS = 10000
local COMBAT_GROUP_COUNT = 3
local COMBAT_GROUP_MS = 1500
local COMBAT_PRESSURE_MS = 6000
local COMBAT_KILL_COUNT = 3
local COMBAT_KILL_WINDOW_MS = 10000
local COMBAT_MINIMUM_MS = 45000
local COMBAT_QUIET_MS = 20000
local FADE_MS = 1600
local TRACK_GAIN = 0.8
local LOCATION_REENTRY_MS = 120000
local POLICE_SOUND = "NeonDeathGradeLocationKnockKnock"
local POLICE_RUIN = { sound = POLICE_SOUND }
local ROSEWOOD_PRISON = { sound = "NeonDeathGradeLocationLePerv" }

-- Site footprints include outdoor tiles, stairs, and every floor.
-- Each rectangle is { left, top, right, bottom }, with exclusive upper bounds.
local AREAS = {
    {
        sound = "NeonDeathGradeLocationRollerMobster",
        rectangles = {
            { 12750, 1511, 12794, 1545 }, -- Bateman tower, entrances, and roof
        },
    },
    {
        sound = "NeonDeathGradeLocationTheWayHome",
        rectangles = {
            { 12004, 1534, 12152, 1721 }, -- Main industrial yard and buildings
            { 12004, 1721, 12062, 1800 }, -- Southwest extension along the river
            { 12016, 1503, 12138, 1534 }, -- Staff parking and north entrance
        },
    },
}

-- Interior tiles verified against the vanilla Build 42 map.
local LOCATIONS = {
    { x = 12674, y = 6411, sound = "NeonDeathGradeLocationMiamiDisco" }, -- Pole Position
    { x = 12958, y = 2042, sound = "NeonDeathGradeLocationFlatline" }, -- Louisville General Hospital
    { x = 12615, y = 1313, sound = "NeonDeathGradeLocationHotline" }, -- The Havisham Hotel Suites
    { x = 12686, y = 2339, sound = "NeonDeathGradeLocationParis" }, -- Louisville Train Station
    { x = 12522, y = 1748, sound = "NeonDeathGradeLocationInnerAnimal" }, -- Romero Center for the Performing Arts
    { x = 10608, y = 9612, sound = "NeonDeathGradeLocationTechnoir" }, -- Zippee Market, Muldraugh
    { x = 10605, y = 9407, sound = "NeonDeathGradeLocationRemorse" }, -- Bert's Garage, Muldraugh
    { x = 2048, y = 5687, sound = "NeonDeathGradeLocationBloodline" }, -- PS Delilah, Brandenburg
    { x = 12166, y = 6940, sound = "NeonDeathGradeLocationRun" }, -- West Point Train Station
    { x = 9940, y = 12625, maxZ = -1, sound = "NeonDeathGradeLocationAbyss" }, -- March Ridge bunker
    { x = 10760, y = 10547, sound = "NeonDeathGradeLocationBlackTar" }, -- The Rusty Rifle, Muldraugh

    -- Kentucky State Prison and its separate blocks share one visit and cue.
    { x = 7620, y = 11800, location = ROSEWOOD_PRISON },
    { x = 7369, y = 11712, location = ROSEWOOD_PRISON },
    { x = 7363, y = 11802, location = ROSEWOOD_PRISON },
    { x = 7776, y = 11913, location = ROSEWOOD_PRISON },

    { x = 2036, y = 5968, sound = POLICE_SOUND }, -- Brandenburg
    { x = 2483, y = 13938, sound = POLICE_SOUND }, -- Irvington
    { x = 6084, y = 5258, sound = POLICE_SOUND }, -- Riverside
    { x = 6086, y = 5222, sound = POLICE_SOUND }, -- Riverside police annex
    { x = 7263, y = 8388, sound = POLICE_SOUND }, -- Fallas Lake
    { x = 8057, y = 11752, sound = POLICE_SOUND }, -- Rosewood police department
    { x = 10643, y = 10407, sound = POLICE_SOUND }, -- Muldraugh
    { x = 11808, y = 6803, sound = POLICE_SOUND }, -- West Point
    { x = 12466, y = 1609, sound = POLICE_SOUND }, -- Louisville Police Department and Detention Services
    { x = 12951, y = 1368, sound = POLICE_SOUND }, -- Downtown Louisville station
    { x = 13052, y = 2839, sound = POLICE_SOUND }, -- Louisville mounted police
    { x = 13208, y = 3088, sound = POLICE_SOUND }, -- South Louisville station
    { x = 13782, y = 2553, sound = POLICE_SOUND }, -- East Louisville station
    { x = 15541, y = 2469, sound = POLICE_SOUND }, -- Outpost east of Louisville
}

local handle, manager, emitter, player
local playingKind, playingLocation
local location, locationReady
local locationLeftAt = {}
local resumeLocation
local musicLevel = 0
local lastPlaylistIndex = {}
local wasAsleep = false
local lastTime
local scanIn = 0
local fade = 0
local combatRemaining, futureRemaining = 0, 0
local combatMinimumRemaining = 0
local threatDuration, groupDuration = 0, 0
local gameplayTime, scanElapsed = 0, 0
local recentKillTimes = {}
local lastKills = 0
local retryAt = 0
local loadingPhase = false

local function stopTrack()
    if handle ~= nil then
        manager:stopUISound(handle)
    end
    handle, playingKind, playingLocation = nil, nil, nil
    fade = 0
end

local function reset(keepLoadingTrack)
    if keepLoadingTrack ~= true then
        stopTrack()
        if manager ~= nil then
            manager:setMusicVolume(getCore():getOptionMusicVolume() / 10)
        end
        manager, emitter = nil, nil
    end
    loadingPhase = false
    player, lastTime = nil, nil
    wasAsleep = false
    scanIn, combatRemaining, futureRemaining = 0, 0, 0
    combatMinimumRemaining = 0
    threatDuration, groupDuration = 0, 0
    gameplayTime, scanElapsed = 0, 0
    recentKillTimes = {}
    lastKills, retryAt = 0, 0
    location, locationReady = nil, false
    locationLeftAt = {}
    resumeLocation = nil
    lastPlaylistIndex = {}
end

local function getMusicLocation(character)
    local square = character:getCurrentSquare()
    if square == nil then return nil end
    local z = square:getZ()
    local x, y = square:getX(), square:getY()
    for _, area in ipairs(AREAS) do
        -- A small exit margin keeps movement along a fence or ledge in one visit.
        local margin = area == location and 3 or 0
        for _, rect in ipairs(area.rectangles) do
            if x >= rect[1] - margin and x < rect[3] + margin
                and y >= rect[2] - margin and y < rect[4] + margin then
                return area
            end
        end
    end
    -- The burned station has an L-shaped footprint and can be open to the sky.
    if z == 0 and x >= 13666 and x < 13674 and y >= 4112 and y < 4124
        and (y >= 4119 or x >= 13669) then
        return POLICE_RUIN
    end
    if square:isOutside() then return nil end
    local building = square:getBuilding()
    if building == nil then return nil end
    local def = building:getDef()
    local left, top, right, bottom = def:getX(), def:getY(), def:getX2(), def:getY2()
    for _, candidate in ipairs(LOCATIONS) do
        if (candidate.maxZ == nil or z <= candidate.maxZ)
            and candidate.x >= left and candidate.x < right
            and candidate.y >= top and candidate.y < bottom then
            return candidate.location or candidate
        end
    end
    return nil
end

local function updateLocation(character, now)
    local nextLocation = getMusicLocation(character)
    if nextLocation == location then return end
    if location ~= nil then locationLeftAt[location] = now end
    location = nextLocation
    if resumeLocation ~= location then resumeLocation = nil end
    local leftAt = location and locationLeftAt[location]
    locationReady = location ~= nil and (leftAt == nil or now - leftAt >= LOCATION_REENTRY_MS)
end

local function countThreats(target)
    local cell = getCell()
    if cell == nil then return 0, 0 end
    local zombies = cell:getZombieList()
    local x, y, z = target:getX(), target:getY(), math.floor(target:getZ())
    local nearby, pursuers = 0, 0

    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if zombie ~= nil and not zombie:isDead()
            and math.floor(zombie:getZ()) == z then
            local dx, dy = zombie:getX() - x, zombie:getY() - y
            if dx * dx + dy * dy <= RADIUS_SQUARED then
                nearby = nearby + 1
                if zombie:getTarget() == target then pursuers = pursuers + 1 end
                if nearby >= FUTURE_COUNT then break end
            end
        end
    end
    return nearby, pursuers
end

local function updateCombat(current, nearby, pursuers, elapsed)
    local kills = current:getZombieKills()
    local newKills = math.max(0, kills - lastKills)
    lastKills = kills
    -- Keep just the kills needed to recognize a short fight, using gameplay time.
    for _ = 1, math.min(newKills, COMBAT_KILL_COUNT) do
        table.insert(recentKillTimes, gameplayTime)
    end
    while #recentKillTimes > 0 and (#recentKillTimes > COMBAT_KILL_COUNT
        or gameplayTime - recentKillTimes[1] > COMBAT_KILL_WINDOW_MS) do
        table.remove(recentKillTimes, 1)
    end

    local engaged = pursuers > 0 or (nearby > 0 and current:isAttacking())
    threatDuration = engaged and (threatDuration + elapsed) or 0
    groupDuration = pursuers >= COMBAT_GROUP_COUNT and (groupDuration + elapsed) or 0
    local confirmed = threatDuration >= COMBAT_PRESSURE_MS
        or groupDuration >= COMBAT_GROUP_MS
        or (newKills > 0 and #recentKillTimes >= COMBAT_KILL_COUNT)
    local active = combatRemaining > 0 or combatMinimumRemaining > 0
        or playingKind == "combat"
    if confirmed and not active then
        combatMinimumRemaining = COMBAT_MINIMUM_MS
    end
    if confirmed or (active and (engaged or newKills > 0)) then
        combatRemaining = COMBAT_QUIET_MS
    end
end

local function wakeSound(character)
    local parts = character:getBodyDamage():getBodyParts()
    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        if part:HasInjury() or part:stitched() then
            return WOUNDED_WAKE_SOUND
        end
    end
    return HEALTHY_WAKE_SOUND
end

local function prepareMusic()
    if manager == nil then
        manager = getSoundManager()
        if manager == nil then return false end
        emitter = manager:getUIEmitter()
        if emitter == nil then
            manager = nil
            return false
        end
    end
    musicLevel = getCore():getOptionMusicVolume() / 10
    if manager:getMusicVolume() ~= 0 then manager:setMusicVolume(0) end
    return true
end

local function startTrack(sound, kind, site)
    if musicLevel <= 0 then return false end
    local id = manager:playUISound(sound)
    if id == nil or id == 0 then
        retryAt = getTimestampMs() + 3000
        return false
    end
    if handle ~= nil then manager:stopUISound(handle) end
    handle, playingKind, playingLocation = id, kind, site
    fade, retryAt = 0, 0
    emitter:setVolume(handle, TRACK_GAIN * musicLevel)
    return true
end

local function startPlaylist(kind, sounds)
    local previous = lastPlaylistIndex[kind]
    local index
    if previous ~= nil then
        index = ZombRand(#sounds - 1) + 1
        if index >= previous then index = index + 1 end
    else
        index = ZombRand(#sounds) + 1
    end
    if startTrack(sounds[index], kind) then
        lastPlaylistIndex[kind] = index
    end
end

local function selectTrack(current, wokeUp)
    if getTimestampMs() < retryAt then return end
    if futureRemaining > 0 then
        if playingKind ~= "future" then
            local interrupted = playingLocation == location and playingLocation or nil
            if startTrack(FUTURE_SOUND, "future") and interrupted ~= nil then
                resumeLocation = interrupted
            end
        end
        return
    end
    -- Let a departing cue finish fading before a lower-priority one begins.
    if playingKind == "future" or playingKind == "location" or playingKind == "loading" then return end
    if location ~= nil and (locationReady or resumeLocation == location) then
        if startTrack(location.sound, "location", location) then
            locationReady = false
            resumeLocation = nil
        end
        return
    end
    if wokeUp then
        startTrack(wakeSound(current), "wake")
        return
    end
    if playingKind == "wake" then return end
    local combatActive = combatRemaining > 0 or combatMinimumRemaining > 0
    local kind = combatActive and "combat" or "calm"
    if handle == nil then
        startPlaylist(kind, kind == "combat" and COMBAT_SOUNDS or CALM_SOUNDS)
    end
end

local function fadeOutTrack(dt)
    fade = fade + dt
    if fade >= FADE_MS then
        stopTrack()
    else
        emitter:setVolume(handle, TRACK_GAIN * musicLevel * (1 - fade / FADE_MS))
    end
end

local function tick()
    if loadingPhase then return end
    local current = getPlayer()
    if current == nil or current:isDead() then
        if player ~= nil then reset() end
        return
    end
    if player ~= current then
        reset(playingKind == "loading")
        player = current
        wasAsleep = current:isAsleep()
        lastKills = current:getZombieKills()
    end

    local now = getTimestampMs()
    local dt = lastTime and math.max(0, math.min(now - lastTime, 100)) or 0
    lastTime = now
    if isGamePaused() then return end

    if not prepareMusic() then return end

    local asleep = current:isAsleep()
    local wokeUp = wasAsleep and not asleep
    wasAsleep = asleep
    if musicLevel <= 0 and playingLocation ~= nil and playingLocation == location then
        resumeLocation = location
    end
    if asleep or musicLevel <= 0 then
        stopTrack()
        combatRemaining, futureRemaining = 0, 0
        combatMinimumRemaining = 0
        threatDuration, groupDuration, scanElapsed = 0, 0, 0
        recentKillTimes = {}
        lastKills = current:getZombieKills()
        return
    end
    combatRemaining = math.max(0, combatRemaining - dt)
    combatMinimumRemaining = math.max(0, combatMinimumRemaining - dt)
    futureRemaining = math.max(0, futureRemaining - dt)
    gameplayTime = gameplayTime + dt
    scanElapsed = scanElapsed + dt
    if handle ~= nil and not manager:isPlayingUISound(handle) then
        stopTrack()
    end

    scanIn = scanIn - dt
    if scanIn <= 0 or wokeUp then
        updateLocation(current, now)
        scanIn = SCAN_MS
        local nearby, pursuers = countThreats(current)
        updateCombat(current, nearby, pursuers, scanElapsed)
        scanElapsed = 0
        if nearby >= FUTURE_COUNT then futureRemaining = FUTURE_RELEASE_MS end
        selectTrack(current, wokeUp)
    end

    if handle == nil then return end
    local combatActive = combatRemaining > 0 or combatMinimumRemaining > 0
    local shouldFade = (playingKind == "future" and futureRemaining <= 0)
        or (playingKind == "location" and playingLocation ~= location)
        or (playingKind == "combat" and not combatActive)
        or (playingKind == "calm" and combatActive)
        or playingKind == "loading"
    if shouldFade then
        fadeOutTrack(dt)
    else
        fade = 0
        emitter:setVolume(handle, TRACK_GAIN * musicLevel)
    end
end

NeonDeathGradeSoundtrack = {}

function NeonDeathGradeSoundtrack.startLoading()
    reset()
    loadingPhase = true
    if prepareMusic() then
        startTrack(LOADING_SOUND, "loading")
    end
end

Events.OnTick.Add(tick)
Events.OnGameStart.Add(function()
    loadingPhase = false
end)
Events.OnPlayerDeath.Add(function(dead)
    if dead == player then reset() end
end)
Events.OnMainMenuEnter.Add(reset)
