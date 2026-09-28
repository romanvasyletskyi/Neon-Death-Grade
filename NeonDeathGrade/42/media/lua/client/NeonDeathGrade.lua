require "ISUI/ISPanel"

local pendingStats = nil
local delayTicks = 0
local activeScreen = nil
local comboHud = nil
-- Temporarily keep the gameplay combo counter hidden. Combo timing, scoring,
-- milestones and the COMBO row on the death screen continue to work.
local SHOW_COMBO_HUD = false

-- Gameplay combo: every credited kill inside this real-time window extends
-- the chain. Only active gameplay time is counted; a long pause is clamped.
local COMBO_WINDOW_MS = 6000
local COMBO_STEP_POINTS = 100
local COMBO_SCORE_KEY = "NeonDeathGradeComboScore"
local BEST_COMBO_KEY = "NeonDeathGradeBestCombo"
local FLEXIBILITY_SCORE_KEY = "NeonDeathGradeFlexibilityScore"
local FLEXIBILITY_METHOD_COUNT_KEY = "NeonDeathGradeFlexibilityMethods"
local FLEXIBILITY_METHOD_PREFIX = "NeonDeathGradeMethod_"
local MOBILITY_SCORE_KEY = "NeonDeathGradeMobilityScore"
local BOLDNESS_SCORE_KEY = "NeonDeathGradeBoldnessScore"
local SPECIAL_SCORE_KEY = "NeonDeathGradeSpecialScore"
local SPECIAL_EXECUTIONS_KEY = "NeonDeathGradeSpecialExecutions"
local SPECIAL_ROADKILLS_KEY = "NeonDeathGradeSpecialRoadkills"
local SPECIAL_MILESTONE_PREFIX = "NeonDeathGradeSpecialCombo_"

local FLEXIBILITY_NEW_METHOD_POINTS = 400
local SPECIAL_EXECUTION_POINTS = 200
local SPECIAL_EXECUTION_LIMIT = 5
local SPECIAL_ROADKILL_POINTS = 100
local SPECIAL_ROADKILL_LIMIT = 10
local SPECIAL_COMBO_MILESTONES = {
    [5] = 300,
    [10] = 700,
    [20] = 1500
}

local comboRuntime = {
    player = nil,
    lastKills = 0,
    currentCombo = 0,
    remainingMs = 0,
    lastTimestampMs = nil,
    lastKillX = nil,
    lastKillY = nil,
    lastKillZ = nil
}

-- Animation timing (OnTickEvenPaused ticks)
local KILLS_SCORE_START_TICK = 15
local KILLS_SCORE_DURATION = 24
local COMBO_SCORE_APPEAR_TICK = 43
local FLEXIBILITY_SCORE_APPEAR_TICK = 57
local MOBILITY_SCORE_APPEAR_TICK = 71
local BOLDNESS_SCORE_APPEAR_TICK = 85
local TIME_SCORE_START_TICK = 99
local TIME_SCORE_DURATION = 24
local SPECIAL_SCORE_APPEAR_TICK = 127
local SHORT_ROW_DURATION = 10
local FINAL_SCORE_START_TICK = 145
local FINAL_SCORE_DURATION = 36
local GRADE_LABEL_APPEAR_TICK = 195
local GRADE_LETTER_APPEAR_TICK = 203
local ANIMATION_END_TICK = 228
local COLOR_FRAME_COUNT = 12

-- Stable palette frames. Animated frames are now used only for one short
-- pulse on the currently-counting row instead of looping forever.
local STATIC_PURPLE_FRAME = 6
local STATIC_GOLD_FRAME = 6
local STATIC_SCORE_FRAME = 6
local STATIC_GRADE_FRAME = 1


-- =========================================================
-- SCORE AND GRADE
-- =========================================================

local function calculateGrade(score)
    if score >= 100000 then
        return "S"
    elseif score >= 60000 then
        return "A"
    elseif score >= 35000 then
        return "B"
    elseif score >= 20000 then
        return "C"
    elseif score >= 10000 then
        return "D"
    elseif score >= 3000 then
        return "E"
    else
        return "F"
    end
end


local function animatedNumber(target, currentTick, startTick, duration)
    if currentTick < startTick then
        return nil
    end

    if currentTick >= startTick + duration then
        return target
    end

    if target <= 0 then
        return 0
    end

    local progress = (currentTick - startTick) / duration
    return math.floor(target * progress)
end


-- =========================================================
-- TIME FORMATTING
-- =========================================================

local function formatUnit(value, singular, plural)
    if value == 1 then
        return tostring(value) .. " " .. singular
    end

    return tostring(value) .. " " .. plural
end


local function formatSurvivalTime(hoursSurvived)
    local totalSeconds = math.floor(hoursSurvived * 3600)
    local days = math.floor(totalSeconds / 86400)
    local remainingSeconds = totalSeconds % 86400
    local hours = math.floor(remainingSeconds / 3600)

    remainingSeconds = remainingSeconds % 3600

    local minutes = math.floor(remainingSeconds / 60)
    local seconds = remainingSeconds % 60

    if days > 0 then
        return formatUnit(days, "DAY", "DAYS")
            .. " "
            .. formatUnit(hours, "HOUR", "HOURS")
            .. " "
            .. formatUnit(minutes, "MINUTE", "MINUTES")
    elseif hours > 0 then
        return formatUnit(hours, "HOUR", "HOURS")
            .. " "
            .. formatUnit(minutes, "MINUTE", "MINUTES")
    else
        return formatUnit(minutes, "MINUTE", "MINUTES")
            .. " "
            .. formatUnit(seconds, "SECOND", "SECONDS")
    end
end


local function formatTotalTime(hoursSurvived)
    local totalSeconds = math.floor(hoursSurvived * 3600)
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60

    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end


-- =========================================================
-- TEXT HELPERS
-- =========================================================

local function drawShadowText(screen, text, x, y, font, r, g, b)
    screen:drawText(text, x + 3, y + 3, 0, 0, 0, 0.9, font)
    screen:drawText(text, x, y, r, g, b, 1, font)
end


local function drawShadowTextRight(screen, text, x, y, font, r, g, b)
    screen:drawTextRight(text, x + 3, y + 3, 0, 0, 0, 0.9, font)
    screen:drawTextRight(text, x, y, r, g, b, 1, font)
end


local function drawShadowTextCentre(screen, text, x, y, font, r, g, b)
    screen:drawTextCentre(text, x + 3, y + 3, 0, 0, 0, 0.9, font)
    screen:drawTextCentre(text, x, y, r, g, b, 1, font)
end


local function measureScaledText(text, font, scale)
    return getTextManager():MeasureStringX(font, text) * scale
end


local function drawScaledText(screen, text, x, y, font, scale, r, g, b)
    if screen.javaObject == nil then
        drawShadowText(screen, text, x, y, font, r, g, b)
        return
    end

    screen.javaObject:DrawText(
        font, text, x + 4, y + 4, scale, 0, 0, 0, 0.90
    )
    screen.javaObject:DrawText(
        font, text, x + 2, y, scale, 0.00, 0.55, 0.65, 0.55
    )
    screen.javaObject:DrawText(
        font, text, x, y, scale, r, g, b, 1.00
    )
end


local function drawScaledTextRight(
    screen, text, rightX, y, font, scale, r, g, b
)
    local x = rightX - measureScaledText(text, font, scale)
    drawScaledText(screen, text, x, y, font, scale, r, g, b)
end


local function drawScaledTextCentre(
    screen, text, centreX, y, font, scale, r, g, b
)
    local x = centreX - measureScaledText(text, font, scale) / 2
    drawScaledText(screen, text, x, y, font, scale, r, g, b)
end


local function spriteGlyphWidth(character, height)
    if character == ":" then
        return height * 0.38
    end

    return height * 0.75
end


local function measureSpriteText(text, height, spacingScale)
    local spacing = height * (spacingScale or 0.04)
    local width = 0

    for index = 1, string.len(text) do
        local character = string.sub(text, index, index)
        width = width + spriteGlyphWidth(character, height)

        if index < string.len(text) then
            width = width + spacing
        end
    end

    return width
end


local function loadGlyphTexture(fileName, legacyFileName)
    -- B42 reliably finds the background in this directory, so try it first.
    local texture = getTexture(
        "media/textures/NeonDeathGrade/" .. fileName
    )

    -- Some installations only index textures placed directly in this folder.
    if texture == nil then
        texture = getTexture("media/textures/" .. fileName)
    end

    -- Keep compatibility with the previous glyph test package.
    if texture == nil and legacyFileName ~= nil then
        texture = getTexture(
            "media/textures/NeonDeathGrade/Glyphs/"
                .. legacyFileName
        )
    end

    return texture
end


local function hasSpriteText(text, textures)
    for index = 1, string.len(text) do
        local character = string.sub(text, index, index)

        if textures[character] == nil then
            return false
        end
    end

    return true
end


local function drawSpriteText(
    screen, text, x, y, height, textures, alignment, spacingScale
)
    -- Never leave an empty value if a texture was not indexed by the game.
    if not hasSpriteText(text, textures) then
        local fallbackY = y + height * 0.15

        if alignment == "right" then
            drawShadowTextRight(
                screen, text, x, fallbackY,
                UIFont.Massive, 1.00, 0.02, 0.45
            )
        elseif alignment == "centre" then
            drawShadowTextCentre(
                screen, text, x, fallbackY,
                UIFont.Massive, 1.00, 0.88, 0.05
            )
        else
            drawShadowText(
                screen, text, x, fallbackY,
                UIFont.Medium, 1.00, 0.02, 0.45
            )
        end

        return
    end

    local totalWidth = measureSpriteText(text, height, spacingScale)
    local spacing = height * (spacingScale or 0.04)

    if alignment == "right" then
        x = x - totalWidth
    elseif alignment == "centre" then
        x = x - totalWidth / 2
    end

    for index = 1, string.len(text) do
        local character = string.sub(text, index, index)
        local width = spriteGlyphWidth(character, height)
        local texture = textures[character]

        if texture ~= nil then
            screen:drawTextureScaled(texture, x, y, width, height, 1.0)
        end

        x = x + width + spacing
    end
end


local function loadScreenTexture(fileName)
    return getTexture(
        "media/textures/NeonDeathGrade/" .. fileName
    )
end


local function loadColorFrames(prefix)
    local frames = {}

    for frameIndex = 1, COLOR_FRAME_COUNT do
        frames[frameIndex] = loadScreenTexture(
            string.format("%s_%02d.png", prefix, frameIndex)
        )
    end

    return frames
end


local function drawLabel(
    screen, texture, fallbackText, x, y, width, height, alpha
)
    if texture ~= nil then
        screen:drawTextureScaled(
            texture, x, y, width, height, alpha or 1.0
        )
        return
    end

    drawShadowText(
        screen,
        fallbackText,
        x,
        y + height * 0.15,
        UIFont.Massive,
        1.0,
        0.05,
        0.45
    )
end


local function activePulseFrame(tick, startTick, duration, stableFrame)
    if tick < startTick or tick >= startTick + duration then
        return stableFrame
    end

    local progress = (tick - startTick) / duration

    -- One dirty flash: dark purple -> brighter magenta -> dark purple.
    -- Avoid frames 1-2, whose almost-white highlight caused the glossy wave.
    if progress < 0.18 then
        return 6
    elseif progress < 0.36 then
        return 5
    elseif progress < 0.58 then
        return 4
    elseif progress < 0.78 then
        return 5
    end

    return 6
end


local function revealSlide(tick, startTick, duration, distance)
    if tick < startTick then
        return -distance
    end

    if tick >= startTick + duration then
        return 0
    end

    local progress = (tick - startTick) / duration
    local remaining = 1 - progress

    -- A short overshoot makes the row feel punched in rather than smoothly
    -- tweened like a modern mobile UI.
    return -distance * remaining
        + math.sin(progress * math.pi) * distance * 0.12
end


local function activeJitter(visualTick, rowIndex, active)
    if not active then
        return 0, 0
    end

    local phase = (visualTick + rowIndex * 3) % 8
    local xPattern = { 0.0, 0.8, -0.5, 0.2, 0.0, -0.7, 0.4, 0.0 }
    local yPattern = { 0.0, 0.0, 0.3, -0.2, 0.0, 0.2, 0.0, -0.2 }

    return xPattern[phase + 1], yPattern[phase + 1]
end


local function revealScale(tick, startTick, duration)
    if tick < startTick then
        return 0
    end

    if tick >= startTick + duration then
        return 1
    end

    local progress = (tick - startTick) / duration
    local inverse = 1 - progress

    -- Small overshoot, similar to the grade impact in the reference.
    return 1 + 0.28 * inverse * math.sin(progress * math.pi)
end


-- =========================================================
-- GAMEPLAY COMBO HUD
-- =========================================================

NeonComboHUD = ISPanel:derive("NeonComboHUD")


function NeonComboHUD:new()
    local screenHeight = getCore():getScreenHeight()

    -- Keep the real UI hitbox at one pixel. The combo glyphs are deliberately
    -- rendered outside it, so neither left nor right inventory actions can be
    -- swallowed by a large invisible panel.
    local hud = ISPanel:new(0, 0, 1, 1)

    setmetatable(hud, self)
    self.__index = self

    hud.combo = 0
    hud.punchTicks = 0
    hud.renderX = 0
    -- Pull the glyph face upward as well as the outer splatter. Part of the
    -- source texture is intentionally clipped beyond the top screen edge.
    hud.renderY = -math.floor(screenHeight * 0.048)
    -- Keep it large enough to read without dominating the PZ side toolbar.
    hud.renderHeight = math.floor(screenHeight * 0.23)
    hud.comboGlyphs = {}
    hud.comboLineHeight = 66
    hud.comboAssetPadding = 5
    hud.comboMetrics = {
        ["0"] = { width = 19, height = 20, xoffset = 0, yoffset = 24, xadvance = 19 },
        ["1"] = { width = 14, height = 28, xoffset = 0, yoffset = 17, xadvance = 14 },
        ["2"] = { width = 25, height = 38, xoffset = -2, yoffset = 9, xadvance = 19 },
        ["3"] = { width = 33, height = 36, xoffset = 0, yoffset = 11, xadvance = 19 },
        ["4"] = { width = 21, height = 22, xoffset = 0, yoffset = 23, xadvance = 20 },
        ["5"] = { width = 20, height = 24, xoffset = 0, yoffset = 21, xadvance = 20 },
        ["6"] = { width = 22, height = 28, xoffset = 0, yoffset = 21, xadvance = 22 },
        ["7"] = { width = 18, height = 22, xoffset = 0, yoffset = 23, xadvance = 18 },
        ["8"] = { width = 21, height = 26, xoffset = 0, yoffset = 21, xadvance = 22 },
        ["9"] = { width = 20, height = 26, xoffset = 0, yoffset = 23, xadvance = 21 },
        ["X"] = { width = 49, height = 54, xoffset = -11, yoffset = 0, xadvance = 20 }
    }

    for digit = 0, 9 do
        local character = tostring(digit)
        hud.comboGlyphs[character] = loadScreenTexture(
            string.format("NDG_Hud%s.png", character)
        )
    end

    hud.comboGlyphs["X"] = loadScreenTexture("NDG_HudX.png")

    hud.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    hud.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    hud.moveWithMouse = false
    hud:setAlwaysOnTop(true)
    hud:setCapture(false)

    return hud
end


-- These handlers are an additional safeguard for the panel's single pixel.
-- Returning false lets the UI below handle both ordinary and context clicks.
function NeonComboHUD:onMouseDown(x, y)
    return false
end


function NeonComboHUD:onMouseUp(x, y)
    return false
end


function NeonComboHUD:onRightMouseDown(x, y)
    return false
end


function NeonComboHUD:onRightMouseUp(x, y)
    return false
end


function NeonComboHUD:onMouseWheel(delta)
    return false
end


function NeonComboHUD:setCombo(value)
    value = math.max(0, math.floor(value or 0))

    if value ~= self.combo and value >= 2 then
        self.punchTicks = 8
    end

    self.combo = value
    self:setVisible(SHOW_COMBO_HUD and value >= 2)
end


function NeonComboHUD:updatePunch()
    if self.punchTicks > 0 then
        self.punchTicks = self.punchTicks - 1
    end
end


function NeonComboHUD:prerender()
    ISPanel.prerender(self)

    if self.combo < 2 then
        return
    end

    local comboText = tostring(self.combo) .. "X"
    local punch = self.punchTicks / 8
    local targetLineHeight = self.renderHeight * 0.82
        * (1 + punch * 0.15)
    local scale = targetLineHeight / self.comboLineHeight
    local padding = self.comboAssetPadding
    -- A little of the baked splatter may touch or cross the screen edge, like
    -- the original HUD, while the readable glyph face remains on-screen.
    local cursorX = self.renderX
    local baselineY = self.renderY + padding * scale

    for index = 1, string.len(comboText) do
        local character = string.sub(comboText, index, index)
        local texture = self.comboGlyphs[character]
        local metric = self.comboMetrics[character]

        if texture ~= nil and metric ~= nil then
            self:drawTextureScaled(
                texture,
                cursorX + (metric.xoffset - padding) * scale,
                baselineY + (metric.yoffset - padding) * scale,
                (metric.width + padding * 2) * scale,
                (metric.height + padding * 2) * scale,
                1.0
            )

            cursorX = cursorX + metric.xadvance * scale
        end
    end
end


local function ensureComboHud()
    if comboHud ~= nil then
        return
    end

    comboHud = NeonComboHUD:new()
    comboHud:initialise()

    -- The one-pixel hitbox is the primary protection. Disable Java-side mouse
    -- consumption too, so even that pixel does not block an element below it.
    if comboHud.javaObject ~= nil then
        comboHud.javaObject:setConsumeMouseEvents(false)
    end

    comboHud:addToUIManager()
    comboHud:setVisible(false)
end


local function normalizeStoredNumber(data, key)
    local value = tonumber(data[key]) or 0
    data[key] = math.max(0, math.floor(value))
end


local function getComboModData(player)
    local data = player:getModData()

    normalizeStoredNumber(data, COMBO_SCORE_KEY)
    normalizeStoredNumber(data, BEST_COMBO_KEY)
    normalizeStoredNumber(data, FLEXIBILITY_SCORE_KEY)
    normalizeStoredNumber(data, FLEXIBILITY_METHOD_COUNT_KEY)
    normalizeStoredNumber(data, MOBILITY_SCORE_KEY)
    normalizeStoredNumber(data, BOLDNESS_SCORE_KEY)
    normalizeStoredNumber(data, SPECIAL_SCORE_KEY)
    normalizeStoredNumber(data, SPECIAL_EXECUTIONS_KEY)
    normalizeStoredNumber(data, SPECIAL_ROADKILLS_KEY)

    return data
end


local function containsAny(text, needles)
    for _, needle in ipairs(needles) do
        if string.find(text, needle, 1, true) ~= nil then
            return true
        end
    end

    return false
end


local function getKillMethod(player)
    if player:getVehicle() ~= nil then
        return "VEHICLE"
    end

    local item = player:getAttackingWeapon()

    if item == nil then
        item = player:getPrimaryHandItem()
    end

    if item == nil then
        return "UNARMED"
    end

    -- getFullType and getType belong to InventoryItem itself, so these calls
    -- remain valid for vanilla and modded hand items alike.
    local descriptor = string.lower(tostring(item:getFullType() or ""))
        .. " " .. string.lower(tostring(item:getType() or ""))

    if containsAny(descriptor, {
        "throw", "molotov", "petrolbomb", "firebomb"
    }) then
        return "THROWING"
    end

    if containsAny(descriptor, {
        "pistol", "revolver", "handgun"
    }) then
        return "HANDGUN"
    end

    if containsAny(descriptor, {
        "firearm", "shotgun", "rifle", "assaultrifle", "gun"
    }) then
        return "FIREARM"
    end

    if containsAny(descriptor, {
        "smallblade", "knife", "dagger"
    }) then
        return "KNIFE"
    end

    if string.find(descriptor, "spear", 1, true) ~= nil then
        return "SPEAR"
    end

    if containsAny(descriptor, {
        "heavy", "twohand", "longblade", "katana", "machete", "axe",
        "sledge"
    }) then
        return "HEAVY"
    end

    if containsAny(descriptor, {
        "smallblunt", "shortblunt", "onehand", "hammer", "wrench",
        "nightstick", "baton"
    }) then
        return "ONE_HANDED"
    end

    if containsAny(descriptor, {
        "blunt", "baseballbat", "crowbar", "shovel", "pickaxe"
    }) then
        return "TWO_HANDED"
    end

    if string.find(descriptor, "chainsaw", 1, true) ~= nil then
        return "CHAINSAW"
    end

    -- A modded or unusual equipped weapon still counts as one stable method
    -- instead of creating a new method for every individual item type.
    return "OTHER_WEAPON"
end


local function awardFlexibility(data, player)
    local method = getKillMethod(player)
    local seenKey = FLEXIBILITY_METHOD_PREFIX .. method

    if data[seenKey] then
        return
    end

    data[seenKey] = true
    data[FLEXIBILITY_METHOD_COUNT_KEY] = (
        data[FLEXIBILITY_METHOD_COUNT_KEY] + 1
    )

    -- The first method establishes a baseline. Each genuinely new method
    -- after it earns the Hotline-style variety bonus.
    if data[FLEXIBILITY_METHOD_COUNT_KEY] > 1 then
        data[FLEXIBILITY_SCORE_KEY] = (
            data[FLEXIBILITY_SCORE_KEY]
            + FLEXIBILITY_NEW_METHOD_POINTS
        )
    end
end


local function mobilityPointsForDistance(distance)
    if distance >= 7 then
        return 300
    elseif distance >= 4 then
        return 200
    elseif distance >= 2 then
        return 100
    end

    return 0
end


local function awardMobility(data, player, continuedChain)
    local currentX = tonumber(player:getX()) or 0
    local currentY = tonumber(player:getY()) or 0
    local currentZ = tonumber(player:getZ()) or 0

    if continuedChain
            and comboRuntime.lastKillX ~= nil
            and comboRuntime.lastKillY ~= nil
            and comboRuntime.lastKillZ == currentZ then
        local deltaX = currentX - comboRuntime.lastKillX
        local deltaY = currentY - comboRuntime.lastKillY
        local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)

        data[MOBILITY_SCORE_KEY] = data[MOBILITY_SCORE_KEY]
            + mobilityPointsForDistance(distance)
    end

    comboRuntime.lastKillX = currentX
    comboRuntime.lastKillY = currentY
    comboRuntime.lastKillZ = currentZ
end


local function getNearbyLivingZombieCount(player, radius)
    local cell = getCell()

    if cell == nil then
        return 0
    end

    local zombies = cell:getZombieList()

    if zombies == nil then
        return 0
    end

    local playerX = tonumber(player:getX()) or 0
    local playerY = tonumber(player:getY()) or 0
    local playerZ = tonumber(player:getZ()) or 0
    local zombieCount = tonumber(zombies:size()) or 0
    local radiusSquared = radius * radius
    local nearby = 0

    for zombieIndex = 0, zombieCount - 1 do
        local zombie = zombies:get(zombieIndex)

        if zombie ~= nil and not zombie:isDead() then
            local zombieZ = tonumber(zombie:getZ()) or playerZ

            if zombieZ == playerZ then
                local deltaX = (tonumber(zombie:getX()) or playerX)
                    - playerX
                local deltaY = (tonumber(zombie:getY()) or playerY)
                    - playerY

                if deltaX * deltaX + deltaY * deltaY <= radiusSquared then
                    nearby = nearby + 1
                end
            end
        end
    end

    return nearby
end


local function boldnessPointsForThreats(nearby)
    if nearby >= 8 then
        return 300
    elseif nearby >= 5 then
        return 200
    elseif nearby >= 3 then
        return 100
    end

    return 0
end


local function awardBoldness(data, player)
    local nearby = getNearbyLivingZombieCount(player, 5)
    data[BOLDNESS_SCORE_KEY] = data[BOLDNESS_SCORE_KEY]
        + boldnessPointsForThreats(nearby)
end


local function addLimitedSpecial(
    data, counterKey, counterLimit, points
)
    if data[counterKey] >= counterLimit then
        return
    end

    data[counterKey] = data[counterKey] + 1
    data[SPECIAL_SCORE_KEY] = data[SPECIAL_SCORE_KEY] + points
end


local function awardSpecialKill(data, player)
    if player:getVehicle() ~= nil then
        addLimitedSpecial(
            data,
            SPECIAL_ROADKILLS_KEY,
            SPECIAL_ROADKILL_LIMIT,
            SPECIAL_ROADKILL_POINTS
        )
        return
    end

    local floorAim = tonumber(player:getAimAtFloorAmount()) or 0

    if floorAim >= 0.65 then
        addLimitedSpecial(
            data,
            SPECIAL_EXECUTIONS_KEY,
            SPECIAL_EXECUTION_LIMIT,
            SPECIAL_EXECUTION_POINTS
        )
    end
end


local function awardSpecialComboMilestone(data, combo)
    local milestonePoints = SPECIAL_COMBO_MILESTONES[combo]

    if milestonePoints == nil then
        return
    end

    local milestoneKey = SPECIAL_MILESTONE_PREFIX .. tostring(combo)

    if data[milestoneKey] then
        return
    end

    data[milestoneKey] = true
    data[SPECIAL_SCORE_KEY] = data[SPECIAL_SCORE_KEY] + milestonePoints
end


local function resetComboRuntime(player)
    comboRuntime.player = player
    comboRuntime.lastKills = player:getZombieKills()
    comboRuntime.currentCombo = 0
    comboRuntime.remainingMs = 0
    comboRuntime.lastTimestampMs = getTimestampMs()
    comboRuntime.lastKillX = nil
    comboRuntime.lastKillY = nil
    comboRuntime.lastKillZ = nil

    getComboModData(player)
    ensureComboHud()
    comboHud:setCombo(0)
end


local function updateComboState(player, countElapsedTime)
    if player == nil then
        return
    end

    if comboRuntime.player ~= player then
        resetComboRuntime(player)
    end

    local now = getTimestampMs()

    if countElapsedTime and comboRuntime.lastTimestampMs ~= nil then
        local elapsed = now - comboRuntime.lastTimestampMs

        if elapsed < 0 then
            elapsed = 0
        elseif elapsed > 250 then
            -- Do not destroy a chain because the game was paused or a frame
            -- stalled. Normal active gameplay still consumes the timer.
            elapsed = 250
        end

        if comboRuntime.currentCombo > 0 then
            comboRuntime.remainingMs = comboRuntime.remainingMs - elapsed

            if comboRuntime.remainingMs <= 0 then
                comboRuntime.currentCombo = 0
                comboRuntime.remainingMs = 0
            end
        end
    end

    comboRuntime.lastTimestampMs = now

    local kills = player:getZombieKills()

    if kills < comboRuntime.lastKills then
        resetComboRuntime(player)
        return
    end

    if kills > comboRuntime.lastKills then
        local newKills = kills - comboRuntime.lastKills
        local data = getComboModData(player)

        for _ = 1, newKills do
            local continuedChain = comboRuntime.currentCombo > 0
                and comboRuntime.remainingMs > 0

            awardFlexibility(data, player)
            awardMobility(data, player, continuedChain)
            awardBoldness(data, player)
            awardSpecialKill(data, player)

            if continuedChain then
                comboRuntime.currentCombo = comboRuntime.currentCombo + 1
            else
                comboRuntime.currentCombo = 1
            end

            comboRuntime.remainingMs = COMBO_WINDOW_MS

            if comboRuntime.currentCombo >= 2 then
                local earned = (comboRuntime.currentCombo - 1)
                    * COMBO_STEP_POINTS
                data[COMBO_SCORE_KEY] = data[COMBO_SCORE_KEY] + earned
            end

            if comboRuntime.currentCombo > data[BEST_COMBO_KEY] then
                data[BEST_COMBO_KEY] = comboRuntime.currentCombo
            end

            awardSpecialComboMilestone(data, comboRuntime.currentCombo)
        end

        comboRuntime.lastKills = kills
    end

    ensureComboHud()
    comboHud:setCombo(comboRuntime.currentCombo)
    comboHud:updatePunch()

    if SHOW_COMBO_HUD and comboRuntime.currentCombo >= 2 then
        comboHud:bringToTop()
    end
end


local function onComboTick()
    if activeScreen ~= nil or pendingStats ~= nil then
        if comboHud ~= nil then
            comboHud:setVisible(false)
        end

        return
    end

    local player = getPlayer()

    if player == nil then
        if comboHud ~= nil then
            comboHud:setVisible(false)
        end

        comboRuntime.player = nil
        return
    end

    updateComboState(player, true)
end


local function onCreatePlayer(playerNumber, player)
    resetComboRuntime(player)
end


-- =========================================================
-- DEATH SCREEN
-- =========================================================

NeonDeathScreen = ISPanel:derive("NeonDeathScreen")


function NeonDeathScreen:new(stats)
    local width = getCore():getScreenWidth()
    local height = getCore():getScreenHeight()
    local screen = ISPanel:new(0, 0, width, height)

    setmetatable(screen, self)
    self.__index = self

    screen.stats = stats
    screen.animationTick = 0
    screen.visualTick = 0
    screen.animationComplete = false
    screen.musicHandle = nil

    screen.backgroundTexture = loadScreenTexture(
        "NDG_BackgroundBase.png"
    )
    screen.reflectionTextures = {}

    for frameIndex = 1, 16 do
        screen.reflectionTextures[frameIndex] = loadScreenTexture(
            string.format("NDG_Reflection%02d.png", frameIndex)
        )
    end

    screen.labelTextureFrames = {
        kills = loadColorFrames("NDG_LabelKills"),
        combo = loadColorFrames("NDG_LabelCombo"),
        flexibility = loadColorFrames("NDG_LabelFlexibility"),
        mobility = loadColorFrames("NDG_LabelMobility"),
        boldness = loadColorFrames("NDG_LabelBoldness"),
        timeBonus = loadColorFrames("NDG_LabelTimeBonus"),
        special = loadColorFrames("NDG_LabelSpecial"),
        grade = loadColorFrames("NDG_LabelGrade"),
        levelScore = loadColorFrames("NDG_LabelLevelScore"),
        totalTime = loadColorFrames("NDG_LabelTotalTime")
    }
    screen.labelTextures = {
        kills = screen.labelTextureFrames.kills[1],
        combo = screen.labelTextureFrames.combo[1],
        flexibility = screen.labelTextureFrames.flexibility[1],
        mobility = screen.labelTextureFrames.mobility[1],
        boldness = screen.labelTextureFrames.boldness[1],
        timeBonus = screen.labelTextureFrames.timeBonus[1],
        special = screen.labelTextureFrames.special[1],
        grade = screen.labelTextureFrames.grade[1],
        levelScore = screen.labelTextureFrames.levelScore[1],
        totalTime = screen.labelTextureFrames.totalTime[1]
    }

    screen.rowGlyphFrames = {}
    screen.scoreGlyphFrames = {}
    screen.gradeGlyphFrames = {}

    for frameIndex = 1, COLOR_FRAME_COUNT do
        screen.rowGlyphFrames[frameIndex] = {}
        screen.scoreGlyphFrames[frameIndex] = {}
        screen.gradeGlyphFrames[frameIndex] = {}
    end

    for digit = 0, 9 do
        local character = tostring(digit)

        for frameIndex = 1, COLOR_FRAME_COUNT do
            screen.rowGlyphFrames[frameIndex][character] = (
                loadScreenTexture(
                    string.format(
                        "NDG_Row%s_%02d.png", character, frameIndex
                    )
                )
            )
            screen.scoreGlyphFrames[frameIndex][character] = (
                loadScreenTexture(
                    string.format(
                        "NDG_Score%s_%02d.png", character, frameIndex
                    )
                )
            )
        end
    end

    for frameIndex = 1, COLOR_FRAME_COUNT do
        screen.rowGlyphFrames[frameIndex][":"] = loadScreenTexture(
            string.format("NDG_RowColon_%02d.png", frameIndex)
        )
    end

    local gradeCharacters = { "S", "A", "B", "C", "D", "E", "F" }

    for _, character in ipairs(gradeCharacters) do
        for frameIndex = 1, COLOR_FRAME_COUNT do
            screen.gradeGlyphFrames[frameIndex][character] = (
                loadScreenTexture(
                    string.format(
                        "NDG_Grade%s_%02d.png", character, frameIndex
                    )
                )
            )
        end
    end

    screen.rowGlyphs = screen.rowGlyphFrames[1]
    screen.scoreGlyphs = screen.scoreGlyphFrames[1]
    screen.gradeGlyphs = screen.gradeGlyphFrames[1]

    screen.backgroundColor = {
        r = 0.015,
        g = 0.000,
        b = 0.025,
        a = 1.0
    }

    screen.borderColor = {
        r = 0,
        g = 0,
        b = 0,
        a = 0
    }

    screen.moveWithMouse = false
    screen:setAlwaysOnTop(true)
    screen:setCapture(true)

    return screen
end


function NeonDeathScreen:updateAnimation()
    self.visualTick = self.visualTick + 1

    if self.animationComplete then
        return
    end

    self.animationTick = self.animationTick + 1

    if self.animationTick >= ANIMATION_END_TICK then
        self.animationTick = ANIMATION_END_TICK
        self.animationComplete = true
    end
end


function NeonDeathScreen:startMusic()
    if self.musicHandle ~= nil then
        return
    end

    local soundManager = getSoundManager()

    -- Prevent the regular soundtrack from overlapping the score-screen track.
    soundManager:StopMusic()
    self.musicHandle = soundManager:playUISound("NeonDeathGradeMusic")
end


function NeonDeathScreen:stopMusic()
    if self.musicHandle == nil then
        return
    end

    getSoundManager():stopUISound(self.musicHandle)
    self.musicHandle = nil
end


function NeonDeathScreen:finishAnimation()
    self.animationTick = ANIMATION_END_TICK
    self.animationComplete = true
end


-- =========================================================
-- SCREEN DRAWING
-- =========================================================

function NeonDeathScreen:prerenderLegacy()
    ISPanel.prerender(self)

    local screenWidth = self:getWidth()
    local screenHeight = self:getHeight()
    local tick = self.animationTick

    if self.backgroundTexture ~= nil then
        local pulse = (math.sin(self.visualTick * 0.025) + 1) * 0.5

        self:drawTextureScaled(
            self.backgroundTexture,
            0,
            0,
            screenWidth,
            screenHeight,
            0.94 + pulse * 0.03
        )

        -- The labels are baked into the background, so keep the overlay light.
        self:drawRect(
            0,
            0,
            screenWidth,
            screenHeight,
            0.05,
            0,
            0,
            0
        )

        -- A slow moving scanline and a short periodic magenta glitch.
        local scanlineY = (self.visualTick * 3) % screenHeight
        self:drawRect(
            0,
            scanlineY,
            screenWidth,
            2,
            0.10,
            0.05,
            0.80,
            1.00
        )

        if self.visualTick % 180 < 5 then
            local glitchY = screenHeight * 0.50
                + (self.visualTick % 5) * 4

            self:drawRect(
                0,
                glitchY,
                screenWidth,
                3,
                0.20,
                1.00,
                0.02,
                0.42
            )
        end
    end

    -- Original HM2 labels are part of the texture. Lua only draws values.
    local valueX = screenWidth * 0.93
    local firstRowY = screenHeight * 0.125
    local rowDistance = screenHeight * 0.0735
    local rowGlyphHeight = screenHeight * 0.060

    local displayedKillScore = animatedNumber(
        self.stats.killScore,
        tick,
        KILLS_SCORE_START_TICK,
        30
    )

    if displayedKillScore ~= nil then
        drawSpriteText(
            self,
            tostring(displayedKillScore),
            valueX,
            firstRowY,
            rowGlyphHeight,
            self.rowGlyphs,
            "right"
        )
    end

    if tick >= COMBO_SCORE_APPEAR_TICK then
        drawSpriteText(
            self, "0", valueX, firstRowY + rowDistance,
            rowGlyphHeight, self.rowGlyphs, "right"
        )
    end

    if tick >= FLEXIBILITY_SCORE_APPEAR_TICK then
        drawSpriteText(
            self, tostring(self.stats.flexibilityScore or 0),
            valueX, firstRowY + rowDistance * 2,
            rowGlyphHeight, self.rowGlyphs, "right"
        )
    end

    if tick >= MOBILITY_SCORE_APPEAR_TICK then
        drawSpriteText(
            self, tostring(self.stats.mobilityScore or 0),
            valueX, firstRowY + rowDistance * 3,
            rowGlyphHeight, self.rowGlyphs, "right"
        )
    end

    if tick >= BOLDNESS_SCORE_APPEAR_TICK then
        drawSpriteText(
            self, tostring(self.stats.boldnessScore or 0),
            valueX, firstRowY + rowDistance * 4,
            rowGlyphHeight, self.rowGlyphs, "right"
        )
    end

    local displayedSurvivalScore = animatedNumber(
        self.stats.survivalScore,
        tick,
        TIME_SCORE_START_TICK,
        30
    )

    if displayedSurvivalScore ~= nil then
        drawSpriteText(
            self,
            tostring(displayedSurvivalScore),
            valueX,
            firstRowY + rowDistance * 5,
            rowGlyphHeight,
            self.rowGlyphs,
            "right"
        )
    end

    if tick >= SPECIAL_SCORE_APPEAR_TICK then
        drawSpriteText(
            self, tostring(self.stats.specialScore or 0),
            valueX, firstRowY + rowDistance * 6,
            rowGlyphHeight, self.rowGlyphs, "right"
        )
    end

    local displayedFinalScore = animatedNumber(
        self.stats.score,
        tick,
        FINAL_SCORE_START_TICK,
        FINAL_SCORE_DURATION
    )

    if displayedFinalScore ~= nil then
        drawSpriteText(
            self,
            tostring(displayedFinalScore),
            screenWidth * 0.72,
            screenHeight * 0.780,
            screenHeight * 0.080,
            self.scoreGlyphs,
            "centre"
        )

        if tick >= GRADE_LETTER_APPEAR_TICK then
            drawSpriteText(
                self,
                self.stats.grade,
                screenWidth * 0.43,
                screenHeight * 0.700,
                screenHeight * 0.110,
                self.gradeGlyphs,
                "centre"
            )
        end
    end

    if tick >= TIME_SCORE_START_TICK then
        drawSpriteText(
            self,
            self.stats.totalTime,
            screenWidth * 0.845,
            screenHeight * 0.855,
            screenHeight * 0.042,
            self.rowGlyphs,
            "left"
        )
    end

    if self.animationComplete then
        self:drawTextCentre(
            "CLICK TO CONTINUE",
            screenWidth / 2,
            screenHeight - 90,
            0.65,
            0.65,
            0.65,
            1,
            UIFont.Small
        )
    else
        self:drawTextCentre(
            "CLICK TO SKIP",
            screenWidth / 2,
            screenHeight - 90,
            0.45,
            0.45,
            0.45,
            1,
            UIFont.Small
        )
    end
end


function NeonDeathScreen:prerender()
    ISPanel.prerender(self)

    local screenWidth = self:getWidth()
    local screenHeight = self:getHeight()
    local tick = self.animationTick
    local visualTick = self.visualTick

    -- The background breathes continuously, but the interface itself only
    -- moves while a value is actively being counted.
    local reflectionFrame = math.floor(visualTick / 2) % 16 + 1
    local reflectionTexture = self.reflectionTextures[reflectionFrame]
    local driftX = math.sin(visualTick * 0.018) * screenWidth * 0.0020
    local driftY = math.cos(visualTick * 0.015) * screenHeight * 0.0015
    local backgroundScale = 1.012
        + math.sin(visualTick * 0.010) * 0.001
    local backgroundWidth = screenWidth * backgroundScale
    local backgroundHeight = screenHeight * backgroundScale
    local backgroundX = (screenWidth - backgroundWidth) / 2 + driftX
    local backgroundY = (screenHeight - backgroundHeight) / 2 + driftY

    if self.backgroundTexture ~= nil then
        self:drawTextureScaled(
            self.backgroundTexture,
            backgroundX,
            backgroundY,
            backgroundWidth,
            backgroundHeight,
            1.0
        )
    end

    if reflectionTexture ~= nil then
        self:drawTextureScaled(
            reflectionTexture,
            backgroundX + backgroundWidth * (610 / 1920),
            backgroundY + backgroundHeight * (540 / 1080),
            backgroundWidth * (700 / 1920),
            backgroundHeight * (440 / 1080),
            1.0
        )
    end

    -- Subtle CRT line and an occasional shared color tear. Individual rows no
    -- longer float independently after their count is complete.
    local scanlineY = (visualTick * 3) % screenHeight
    self:drawRect(
        0,
        scanlineY,
        screenWidth,
        2,
        0.07,
        0.03,
        0.82,
        1.00
    )

    if visualTick % 240 < 2 then
        local glitchY = screenHeight * 0.50
            + (visualTick % 2) * 3

        self:drawRect(
            0,
            glitchY,
            screenWidth,
            2,
            0.09,
            1.00,
            0.02,
            0.42
        )
    end

    local labelX = screenWidth * 0.055 + driftX
    local valueX = screenWidth * 0.93 + driftX
    local firstRowY = screenHeight * 0.125 + driftY
    local rowDistance = screenHeight * 0.0735
    local labelHeight = screenHeight * 0.063
    local rowGlyphHeight = screenHeight * 0.060

    local rows = {
        {
            textureFrames = self.labelTextureFrames.kills,
            text = "KILLS",
            width = 0.20,
            target = self.stats.killScore,
            startTick = KILLS_SCORE_START_TICK,
            duration = KILLS_SCORE_DURATION
        },
        {
            textureFrames = self.labelTextureFrames.combo,
            text = "COMBO",
            width = 0.23,
            target = self.stats.comboScore or 0,
            startTick = COMBO_SCORE_APPEAR_TICK,
            duration = SHORT_ROW_DURATION
        },
        {
            textureFrames = self.labelTextureFrames.flexibility,
            text = "FLEXIBILITY",
            width = 0.39,
            target = self.stats.flexibilityScore or 0,
            startTick = FLEXIBILITY_SCORE_APPEAR_TICK,
            duration = SHORT_ROW_DURATION
        },
        {
            textureFrames = self.labelTextureFrames.mobility,
            text = "MOBILITY",
            width = 0.31,
            target = self.stats.mobilityScore or 0,
            startTick = MOBILITY_SCORE_APPEAR_TICK,
            duration = SHORT_ROW_DURATION
        },
        {
            textureFrames = self.labelTextureFrames.boldness,
            text = "BOLDNESS",
            width = 0.35,
            target = self.stats.boldnessScore or 0,
            startTick = BOLDNESS_SCORE_APPEAR_TICK,
            duration = SHORT_ROW_DURATION
        },
        {
            textureFrames = self.labelTextureFrames.timeBonus,
            text = "TIME BONUS",
            width = 0.39,
            target = self.stats.survivalScore,
            startTick = TIME_SCORE_START_TICK,
            duration = TIME_SCORE_DURATION
        },
        {
            textureFrames = self.labelTextureFrames.special,
            text = "SPECIAL",
            width = 0.28,
            target = self.stats.specialScore or 0,
            startTick = SPECIAL_SCORE_APPEAR_TICK,
            duration = SHORT_ROW_DURATION
        }
    }

    for rowIndex, row in ipairs(rows) do
        local displayedValue = animatedNumber(
            row.target,
            tick,
            row.startTick,
            row.duration
        )

        -- Rows arrive one at a time. Once a row is complete, both its color
        -- and position freeze until the player closes the screen.
        if displayedValue ~= nil then
            local active = tick >= row.startTick
                and tick < row.startTick + row.duration
            local rowX, rowY = activeJitter(
                visualTick, rowIndex, active
            )
            local slideX = revealSlide(
                tick,
                row.startTick,
                7,
                screenWidth * 0.018
            )
            local y = firstRowY
                + rowDistance * (rowIndex - 1)
                + rowY
            local labelWidth = screenWidth * row.width
            local rowColorFrame = activePulseFrame(
                tick,
                row.startTick,
                row.duration,
                STATIC_PURPLE_FRAME
            )
            local rowTexture = row.textureFrames[rowColorFrame]
            local dirtyFlash = active
                and ((tick - row.startTick) % 9 < 2)

            if dirtyFlash then
                drawLabel(
                    self,
                    rowTexture,
                    row.text,
                    labelX + slideX + rowX - 2,
                    y + 1,
                    labelWidth,
                    labelHeight,
                    0.12
                )
            end

            drawLabel(
                self,
                rowTexture,
                row.text,
                labelX + slideX + rowX * 0.35,
                y,
                labelWidth,
                labelHeight,
                1.0
            )

            drawSpriteText(
                self,
                tostring(displayedValue),
                valueX + rowX,
                y,
                rowGlyphHeight,
                self.rowGlyphFrames[rowColorFrame],
                "right"
            )
        end
    end

    -- LEVEL SCORE is a separate final tally. It no longer climbs in parallel
    -- with the category rows.
    local scoreRevealTick = FINAL_SCORE_START_TICK - 8
    local finalActive = tick >= FINAL_SCORE_START_TICK
        and tick < FINAL_SCORE_START_TICK + FINAL_SCORE_DURATION

    if tick >= scoreRevealTick then
        local displayedFinalScore = animatedNumber(
            self.stats.score,
            tick,
            FINAL_SCORE_START_TICK,
            FINAL_SCORE_DURATION
        )

        if displayedFinalScore == nil then
            displayedFinalScore = 0
        end

        local scoreX, scoreY = activeJitter(
            visualTick, 8, finalActive
        )
        local scoreSlide = -revealSlide(
            tick,
            scoreRevealTick,
            8,
            screenWidth * 0.020
        )
        local scoreColorFrame = activePulseFrame(
            tick,
            FINAL_SCORE_START_TICK,
            FINAL_SCORE_DURATION,
            STATIC_GOLD_FRAME
        )
        local scoreLabelX = screenWidth * 0.49
            + driftX + scoreSlide + scoreX * 0.35
        local scoreLabelY = screenHeight * 0.705
            + driftY + scoreY
        local scoreLabelWidth = screenWidth * 0.44
        local scoreLabelHeight = screenHeight * 0.082

        if finalActive
                and ((tick - FINAL_SCORE_START_TICK) % 11 < 2) then
            drawLabel(
                self,
                self.labelTextureFrames.levelScore[scoreColorFrame],
                "LEVEL SCORE",
                scoreLabelX - 2,
                scoreLabelY + 1,
                scoreLabelWidth,
                scoreLabelHeight,
                0.12
            )
        end

        drawLabel(
            self,
            self.labelTextureFrames.levelScore[scoreColorFrame],
            "LEVEL SCORE",
            scoreLabelX,
            scoreLabelY,
            scoreLabelWidth,
            scoreLabelHeight,
            1.0
        )

        drawSpriteText(
            self,
            tostring(displayedFinalScore),
            screenWidth * 0.72
                + driftX + scoreSlide + scoreX,
            screenHeight * 0.790 + driftY + scoreY,
            screenHeight * 0.080,
            self.scoreGlyphFrames[
                finalActive and scoreColorFrame or STATIC_SCORE_FRAME
            ],
            "centre"
        )

        -- TOTAL TIME is intentionally stable and subordinate to the tally.
        drawLabel(
            self,
            self.labelTextureFrames.totalTime[STATIC_PURPLE_FRAME],
            "TOTAL TIME:",
            screenWidth * 0.68 + driftX + scoreSlide,
            screenHeight * 0.865 + driftY,
            screenWidth * 0.16,
            screenHeight * 0.047,
            1.0
        )

        drawSpriteText(
            self,
            self.stats.totalTime,
            screenWidth * 0.845 + driftX + scoreSlide,
            screenHeight * 0.865 + driftY,
            screenHeight * 0.042,
            self.rowGlyphFrames[STATIC_PURPLE_FRAME],
            "left"
        )
    end

    -- GRADE and the grade letter are two separate impacts. The letter uses a
    -- fixed canonical palette: red for F-A, gold for S.
    if tick >= GRADE_LABEL_APPEAR_TICK then
        local gradeColorFrame = activePulseFrame(
            tick,
            GRADE_LABEL_APPEAR_TICK,
            14,
            STATIC_PURPLE_FRAME
        )
        local gradeScale = revealScale(
            tick, GRADE_LABEL_APPEAR_TICK, 12
        )
        local gradeSlide = revealSlide(
            tick,
            GRADE_LABEL_APPEAR_TICK,
            8,
            screenWidth * 0.024
        )
        local gradeLabelWidth = screenWidth * 0.25 * gradeScale
        local gradeLabelHeight = screenHeight * 0.090 * gradeScale
        local gradeLabelX = screenWidth * 0.055
            + driftX + gradeSlide
            - (gradeLabelWidth - screenWidth * 0.25) / 2
        local gradeLabelY = screenHeight * 0.735 + driftY
            - (gradeLabelHeight - screenHeight * 0.090) / 2

        if tick < GRADE_LABEL_APPEAR_TICK + 5 then
            drawLabel(
                self,
                self.labelTextureFrames.grade[gradeColorFrame],
                "GRADE",
                gradeLabelX - 2,
                gradeLabelY + 1,
                gradeLabelWidth,
                gradeLabelHeight,
                0.14
            )
        end

        drawLabel(
            self,
            self.labelTextureFrames.grade[gradeColorFrame],
            "GRADE",
            gradeLabelX,
            gradeLabelY,
            gradeLabelWidth,
            gradeLabelHeight,
            1.0
        )
    end

    if tick >= GRADE_LETTER_APPEAR_TICK then
        local gradeActive = tick < GRADE_LETTER_APPEAR_TICK + 10
        local gradeX, gradeY = activeJitter(
            visualTick, 10, gradeActive
        )
        local gradeScale = revealScale(
            tick, GRADE_LETTER_APPEAR_TICK, 10
        )

        drawSpriteText(
            self,
            self.stats.grade,
            screenWidth * 0.38 + driftX + gradeX,
            screenHeight * 0.720 + driftY + gradeY,
            screenHeight * 0.120 * gradeScale,
            self.gradeGlyphFrames[STATIC_GRADE_FRAME],
            "centre"
        )
    end

    if self.animationComplete then
        self:drawTextCentre(
            "CLICK TO CONTINUE",
            screenWidth / 2,
            screenHeight - 54,
            0.65,
            0.65,
            0.65,
            1,
            UIFont.Small
        )
    else
        self:drawTextCentre(
            "CLICK TO SKIP",
            screenWidth / 2,
            screenHeight - 54,
            0.45,
            0.45,
            0.45,
            1,
            UIFont.Small
        )
    end
end


-- =========================================================
-- MOUSE INPUT
-- =========================================================

function NeonDeathScreen:onMouseDown(x, y)
    if not self.animationComplete then
        self:finishAnimation()
        return true
    end

    activeScreen = nil

    self:stopMusic()
    self:setCapture(false)
    self:setVisible(false)
    self:removeFromUIManager()

    return true
end


-- =========================================================
-- SCREEN EVENTS
-- =========================================================

local function keepDeathScreenOnTop()
    if activeScreen ~= nil then
        activeScreen:updateAnimation()
        activeScreen:bringToTop()
    end
end


local function showDeathScreen()
    delayTicks = delayTicks + 1

    if delayTicks < 20 then
        return
    end

    Events.OnTickEvenPaused.Remove(showDeathScreen)

    activeScreen = NeonDeathScreen:new(pendingStats)
    activeScreen:initialise()
    activeScreen:addToUIManager()
    activeScreen:bringToTop()
    activeScreen:startMusic()

    pendingStats = nil
end


local function onPlayerDeath(player)
    -- Catch a kill credited on the same update as the player's death before
    -- freezing the score-screen statistics.
    updateComboState(player, false)

    local hoursSurvived = player:getHoursSurvived()
    local minutesSurvived = math.floor(hoursSurvived * 60)
    local daysSurvived = math.floor(hoursSurvived / 24)
    local kills = player:getZombieKills()
    local comboData = getComboModData(player)
    local comboScore = comboData[COMBO_SCORE_KEY]
    local bestCombo = comboData[BEST_COMBO_KEY]
    local flexibilityScore = comboData[FLEXIBILITY_SCORE_KEY]
    local mobilityScore = comboData[MOBILITY_SCORE_KEY]
    local boldnessScore = comboData[BOLDNESS_SCORE_KEY]
    local specialScore = comboData[SPECIAL_SCORE_KEY]

    local killScore = kills * 100
    local survivalScore = minutesSurvived * 10
    local totalScore = killScore
        + comboScore
        + flexibilityScore
        + mobilityScore
        + boldnessScore
        + survivalScore
        + specialScore

    pendingStats = {
        survivalTime = formatSurvivalTime(hoursSurvived),
        totalTime = formatTotalTime(hoursSurvived),
        days = daysSurvived,
        kills = kills,
        killScore = killScore,
        comboScore = comboScore,
        bestCombo = bestCombo,
        flexibilityScore = flexibilityScore,
        mobilityScore = mobilityScore,
        boldnessScore = boldnessScore,
        specialScore = specialScore,
        survivalScore = survivalScore,
        score = totalScore,
        grade = calculateGrade(totalScore)
    }

    comboRuntime.currentCombo = 0
    comboRuntime.remainingMs = 0

    if comboHud ~= nil then
        comboHud:setVisible(false)
    end

    delayTicks = 0
    Events.OnTickEvenPaused.Add(showDeathScreen)
end


Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnTick.Add(onComboTick)
Events.OnTickEvenPaused.Add(keepDeathScreenOnTop)
Events.OnPlayerDeath.Add(onPlayerDeath)
