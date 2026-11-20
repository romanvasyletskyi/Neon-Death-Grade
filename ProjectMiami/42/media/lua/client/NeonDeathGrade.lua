require "ISUI/ISPanel"

local pendingStats = nil
local activeScreen = nil
local comboHud = nil
local pointPopupHud = nil

-- Gameplay combo: every credited kill inside this real-time window extends
-- the chain. Only active gameplay time is counted; a long pause is clamped.
local COMBO_WINDOW_MS = 6000
local COMBO_STEP_POINTS = 100
local POINT_POPUP_BASE_POINTS = 100
local POINT_POPUP_LIFETIME_MS = 1250
local POINT_POPUP_PAIR_TIMEOUT_MS = 700
local COMBO_PUNCH_MS = 133
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

local KILL_POINTS = 100
local TIME_BONUS_POINTS_PER_MINUTE = 10
-- Long runs still earn a solid time bonus, but survival time alone can no
-- longer carry a character to an S grade without any fighting.
local TIME_BONUS_MAX_MINUTES = 48 * 60

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

local pendingPointAwards = {}
local pendingPointDeaths = {}

-- Animation timing in virtual ticks. The death screen derives them from real
-- time, so the animation runs at the same speed at 30, 60 or 144 FPS.
local ANIMATION_TICKS_PER_SECOND = 60
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

-- Stable palette frames. Animated frames are now used only for one short
-- pulse on the currently-counting row instead of looping forever.
local STATIC_PURPLE_FRAME = 6
local STATIC_GOLD_FRAME = 6
local STATIC_SCORE_FRAME = 6
local STATIC_GRADE_FRAME = 1

-- Only these palette frames ship with the mod: activePulseFrame() returns
-- 4-6 and every STATIC_* frame above is one of them. Using another frame
-- number requires adding its PNG files back.
local PULSE_FRAMES = { 4, 5, 6 }
local GRADE_FRAMES = { STATIC_GRADE_FRAME }


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


local function loadColorFrames(prefix, frameNumbers)
    local frames = {}

    for _, frameIndex in ipairs(frameNumbers or PULSE_FRAMES) do
        frames[frameIndex] = loadScreenTexture(
            string.format("%s_%02d.png", prefix, frameIndex)
        )
    end

    return frames
end


-- Death-screen art is loaded once and shared. Loading it at game start keeps
-- the moment of death free of a burst of texture reads.
local deathScreenAssets = nil

local function getDeathScreenAssets()
    if deathScreenAssets ~= nil then
        return deathScreenAssets
    end

    local assets = {
        background = loadScreenTexture("NDG_BackgroundBase.png"),
        reflections = {},
        labels = {
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
        },
        rowGlyphs = {},
        scoreGlyphs = {},
        gradeGlyphs = {}
    }

    for frameIndex = 1, 16 do
        assets.reflections[frameIndex] = loadScreenTexture(
            string.format("NDG_Reflection%02d.png", frameIndex)
        )
    end

    for _, frameIndex in ipairs(PULSE_FRAMES) do
        local rowGlyphs = {}
        local scoreGlyphs = {}

        for digit = 0, 9 do
            local character = tostring(digit)

            rowGlyphs[character] = loadScreenTexture(
                string.format("NDG_Row%s_%02d.png", character, frameIndex)
            )
            scoreGlyphs[character] = loadScreenTexture(
                string.format("NDG_Score%s_%02d.png", character, frameIndex)
            )
        end

        rowGlyphs[":"] = loadScreenTexture(
            string.format("NDG_RowColon_%02d.png", frameIndex)
        )

        assets.rowGlyphs[frameIndex] = rowGlyphs
        assets.scoreGlyphs[frameIndex] = scoreGlyphs
    end

    for _, frameIndex in ipairs(GRADE_FRAMES) do
        local gradeGlyphs = {}

        for _, character in ipairs({ "S", "A", "B", "C", "D", "E", "F" }) do
            gradeGlyphs[character] = loadScreenTexture(
                string.format("NDG_Grade%s_%02d.png", character, frameIndex)
            )
        end

        assets.gradeGlyphs[frameIndex] = gradeGlyphs
    end

    deathScreenAssets = assets
    return assets
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

-- Pixel rectangles, bearings, and advances from the original combo font.
-- The small x is the solid multiplier mark used for the HUD.
local COMBO_GLYPHS = {
    ["0"] = { 312, 227, 19, 20, 0, 24, 19 },
    ["1"] = { 496, 108, 14, 28, 0, 17, 14 },
    ["2"] = { 95, 52, 25, 38, -2, 9, 19 },
    ["3"] = { 370, 39, 33, 36, 0, 11, 19 },
    ["4"] = { 329, 199, 21, 22, 0, 23, 20 },
    ["5"] = { 141, 216, 20, 24, 0, 21, 20 },
    ["6"] = { 344, 143, 22, 28, 0, 21, 22 },
    ["7"] = { 391, 198, 18, 22, 0, 23, 18 },
    ["8"] = { 305, 172, 21, 26, 0, 21, 22 },
    ["9"] = { 327, 172, 20, 26, 0, 23, 21 },
    x = { 231, 207, 25, 23, -1, 21, 23 },
}

NeonComboHUD = ISPanel:derive("NeonComboHUD")

function NeonComboHUD:new()
    -- The art is drawn outside this hitbox so the inventory remains clickable.
    local hud = ISPanel.new(self, 0, 0, 1, 1)
    hud.combo = 0
    hud.remainingMs = 0
    hud.punchUntilMs = 0
    hud.fontTexture = getTexture("media/textures/NeonDeathGrade/HotlineMiami2/fntCombo_0.png")
    hud.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    hud.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    hud.moveWithMouse = false
    hud:setWantMouseEvents(false)
    hud:setAlwaysOnTop(true)
    return hud
end

function NeonComboHUD:setCombo(value, remainingMs)
    if value ~= self.combo and value >= 2 then
        self.punchUntilMs = getTimestampMs() + COMBO_PUNCH_MS
    end
    if (self.combo >= 2) ~= (value >= 2) then
        self:setVisible(value >= 2)
    end
    self.combo = value
    self.remainingMs = remainingMs or 0
end

function NeonComboHUD:drawCombo(text, x, baseline, scale, alpha, r, g, b)
    for i = 1, #text do
        local glyph = COMBO_GLYPHS[string.sub(text, i, i)]
        self:drawSubTexture(self.fontTexture, glyph[1], glyph[2], glyph[3], glyph[4],
            x + glyph[5] * scale, baseline + (glyph[6] - 45) * scale,
            glyph[3] * scale, glyph[4] * scale, alpha, r, g, b)
        x = x + (glyph[7] + 2) * scale
    end
end

function NeonComboHUD:prerender()
    local player = comboRuntime.player
    if self.combo < 2 or not player or not isIngameState()
            or (ISUIHandler and not ISUIHandler.allUIVisible) then
        return
    end

    local slot = player:getPlayerNum()
    local width = getPlayerScreenWidth(slot)
    local height = getPlayerScreenHeight(slot)
    local x = getPlayerScreenLeft(slot) + math.max(55, math.floor(width * 0.05))
    local baseline = getPlayerScreenTop(slot) + math.floor(height * 0.15)
    local punch = math.max(
        0,
        (self.punchUntilMs - getTimestampMs()) / COMBO_PUNCH_MS
    )
    local scale = math.min(5, math.max(1, height / 270)) * (1 + punch * 0.15)
    local alpha = math.min(1, self.remainingMs / 450)
    local text = string.format("%d", self.combo)

    if not self.fontTexture then
        drawShadowText(self, text .. "X", x, baseline - 36, UIFont.Large, 1, 0.06, 0.13)
        return
    end

    text = text .. "x"
    self:drawCombo(text, x + scale, baseline + scale * 1.5, scale, alpha, 0.13, 0.01, 0.04)
    self:drawCombo(text, x + scale * 0.5, baseline + scale * 0.75, scale, alpha, 0.58, 0.02, 0.15)
    self:drawCombo(text, x, baseline, scale, alpha, 1, 0.045, 0.12)
end

local function ensureComboHud()
    if comboHud ~= nil then
        return
    end
    comboHud = NeonComboHUD:new()
    comboHud:initialise()
    comboHud:addToUIManager()
    comboHud:setVisible(false)
end


-- =========================================================
-- WORLD-SPACE KILL POINT POPUPS
-- =========================================================

NeonPointPopupHUD = ISPanel:derive("NeonPointPopupHUD")


function NeonPointPopupHUD:new()
    -- As with the old combo HUD, the real element occupies only one pixel.
    -- The visible sprites are drawn outside it and never block inventory input.
    local hud = ISPanel:new(0, 0, 1, 1)

    setmetatable(hud, self)
    self.__index = self

    hud.popups = {}
    hud.glyphs = {}
    hud.lineHeight = 26
    hud.assetPadding = 5
    hud.metrics = {
        ["0"] = { width = 20, height = 16, xoffset = 0, yoffset = 6, xadvance = 17 },
        ["1"] = { width = 13, height = 16, xoffset = 2, yoffset = 6, xadvance = 12 },
        ["2"] = { width = 20, height = 16, xoffset = 0, yoffset = 6, xadvance = 17 },
        ["3"] = { width = 20, height = 16, xoffset = 0, yoffset = 6, xadvance = 17 },
        ["4"] = { width = 21, height = 16, xoffset = 1, yoffset = 6, xadvance = 19 },
        ["5"] = { width = 19, height = 16, xoffset = 0, yoffset = 6, xadvance = 17 },
        ["6"] = { width = 21, height = 16, xoffset = 0, yoffset = 6, xadvance = 17 },
        ["7"] = { width = 18, height = 16, xoffset = 3, yoffset = 6, xadvance = 17 },
        ["8"] = { width = 20, height = 16, xoffset = 0, yoffset = 6, xadvance = 17 },
        ["9"] = { width = 21, height = 16, xoffset = 0, yoffset = 6, xadvance = 17 },
        ["P"] = { width = 23, height = 19, xoffset = 0, yoffset = 3, xadvance = 21 },
        ["T"] = { width = 22, height = 19, xoffset = 3, yoffset = 3, xadvance = 21 },
        ["S"] = { width = 23, height = 19, xoffset = 1, yoffset = 3, xadvance = 21 }
    }

    for digit = 0, 9 do
        local character = tostring(digit)
        hud.glyphs[character] = loadScreenTexture(
            string.format("NDG_Points%s.png", character)
        )
    end

    for _, character in ipairs({ "P", "T", "S" }) do
        hud.glyphs[character] = loadScreenTexture(
            string.format("NDG_Points%s.png", character)
        )
    end

    hud.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    hud.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    hud.moveWithMouse = false
    hud:setAlwaysOnTop(true)
    hud:setCapture(false)

    return hud
end


function NeonPointPopupHUD:onMouseDown(x, y)
    return false
end


function NeonPointPopupHUD:onMouseUp(x, y)
    return false
end


function NeonPointPopupHUD:onRightMouseDown(x, y)
    return false
end


function NeonPointPopupHUD:onRightMouseUp(x, y)
    return false
end


function NeonPointPopupHUD:onMouseWheel(delta)
    return false
end


function NeonPointPopupHUD:addPopup(worldX, worldY, worldZ, points)
    table.insert(self.popups, {
        x = worldX,
        y = worldY,
        z = worldZ,
        points = math.max(0, math.floor(points or 0)),
        bornMs = getTimestampMs()
    })

    -- A giant burning horde should not leave hundreds of live UI objects.
    while #self.popups > 24 do
        table.remove(self.popups, 1)
    end

    self:setVisible(true)
end


function NeonPointPopupHUD:clearPopups()
    self.popups = {}
    self:setVisible(false)
end


function NeonPointPopupHUD:measureText(text, scale)
    local width = 0

    for index = 1, string.len(text) do
        local character = string.sub(text, index, index)
        local metric = self.metrics[character]

        if metric ~= nil then
            width = width + metric.xadvance * scale
        end
    end

    return width
end


function NeonPointPopupHUD:worldToScreen(worldX, worldY, worldZ)
    local zoom = getCore():getZoom(0)

    if zoom == nil or zoom <= 0 then
        zoom = 1
    end

    local screenX = IsoUtils.XToScreen(worldX, worldY, worldZ, 0)
        - IsoCamera.getOffX(0)
    local screenY = IsoUtils.YToScreen(worldX, worldY, worldZ, 0)
        - IsoCamera.getOffY(0)

    screenX = screenX / zoom + IsoCamera.getScreenLeft(0)
    screenY = screenY / zoom + IsoCamera.getScreenTop(0)

    return screenX, screenY
end


function NeonPointPopupHUD:drawPopup(popup, now)
    local age = now - popup.bornMs
    local progress = math.max(
        0,
        math.min(1, age / POINT_POPUP_LIFETIME_MS)
    )
    local alpha = 1

    if progress > 0.58 then
        alpha = (1 - progress) / 0.42
    end

    local impactScale = 1

    if progress < 0.14 then
        impactScale = 1.28 - 0.28 * (progress / 0.14)
    end

    local screenHeight = getCore():getScreenHeight()
    local targetLineHeight = screenHeight * 0.038 * impactScale
    local scale = targetLineHeight / self.lineHeight
    local rise = screenHeight * 0.040 * progress
    local screenX, screenY = self:worldToScreen(
        popup.x, popup.y, popup.z
    )
    local text = tostring(popup.points) .. "PTS"
    local cursorX = screenX - self:measureText(text, scale) / 2
    local baselineY = screenY - screenHeight * 0.078 - rise
    local padding = self.assetPadding

    for index = 1, string.len(text) do
        local character = string.sub(text, index, index)
        local texture = self.glyphs[character]
        local metric = self.metrics[character]

        if texture ~= nil and metric ~= nil then
            self:drawTextureScaled(
                texture,
                cursorX + (metric.xoffset - padding) * scale,
                baselineY + (metric.yoffset - padding) * scale,
                (metric.width + padding * 2) * scale,
                (metric.height + padding * 2) * scale,
                alpha
            )
        end

        if metric ~= nil then
            cursorX = cursorX + metric.xadvance * scale
        end
    end
end


function NeonPointPopupHUD:prerender()
    ISPanel.prerender(self)

    local now = getTimestampMs()

    for index = #self.popups, 1, -1 do
        local popup = self.popups[index]

        if now - popup.bornMs >= POINT_POPUP_LIFETIME_MS then
            table.remove(self.popups, index)
        else
            self:drawPopup(popup, now)
        end
    end

    if #self.popups == 0 then
        self:setVisible(false)
    end
end


local function ensurePointPopupHud()
    if pointPopupHud ~= nil then
        return
    end

    pointPopupHud = NeonPointPopupHUD:new()
    pointPopupHud:initialise()

    if pointPopupHud.javaObject ~= nil then
        pointPopupHud.javaObject:setConsumeMouseEvents(false)
    end

    pointPopupHud:addToUIManager()
    pointPopupHud:setVisible(false)
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


local function awardBoldness(data, nearby)
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


local function clearPointPopupRuntime()
    pendingPointAwards = {}
    pendingPointDeaths = {}

    if pointPopupHud ~= nil then
        pointPopupHud:clearPopups()
    end
end


local function findCreditedPointDeath()
    for index, death in ipairs(pendingPointDeaths) do
        if death.credited then
            return index
        end
    end

    return nil
end


local function updatePointPopupPairing()
    local now = getTimestampMs()

    -- Match a score detected through the authoritative player kill counter to
    -- the position supplied by OnZombieDead. The two notifications are not
    -- guaranteed to arrive in the same order or on the same frame.
    while #pendingPointAwards > 0 and #pendingPointDeaths > 0 do
        local deathIndex = findCreditedPointDeath()

        if deathIndex == nil then
            local oldestDeath = pendingPointDeaths[1]

            -- Briefly wait for a positively credited death before accepting a
            -- generic candidate. This catches delayed fire and vehicle deaths
            -- without pairing instantly to an unrelated environmental death.
            if now - oldestDeath.createdMs < 120 then
                break
            end

            deathIndex = 1
        end

        local award = table.remove(pendingPointAwards, 1)
        local death = table.remove(pendingPointDeaths, deathIndex)

        ensurePointPopupHud()
        pointPopupHud:addPopup(
            death.x, death.y, death.z, award.points
        )
    end

    for index = #pendingPointDeaths, 1, -1 do
        if now - pendingPointDeaths[index].createdMs
                > POINT_POPUP_PAIR_TIMEOUT_MS then
            table.remove(pendingPointDeaths, index)
        end
    end

    -- If a modded damage source increments zombieKills without producing a
    -- usable OnZombieDead object, show the score over the player rather than
    -- silently losing the feedback.
    while #pendingPointAwards > 0
            and now - pendingPointAwards[1].createdMs
                > POINT_POPUP_PAIR_TIMEOUT_MS do
        local award = table.remove(pendingPointAwards, 1)
        local player = getPlayer()

        if player ~= nil then
            ensurePointPopupHud()
            pointPopupHud:addPopup(
                player:getX(),
                player:getY(),
                player:getZ(),
                award.points
            )
        end
    end
end


local function queuePointPopupAward(points)
    table.insert(pendingPointAwards, {
        points = points,
        createdMs = getTimestampMs()
    })

    updatePointPopupPairing()
end


local function onZombieDead(zombie)
    if zombie == nil or activeScreen ~= nil or pendingStats ~= nil then
        return
    end

    local player = getPlayer()

    if player == nil then
        return
    end

    local credited = zombie:getAttackedBy() == player

    -- Some roadkills do not retain attackedBy through the death transition.
    -- A zombie dying beside the vehicle is kept as a strong candidate; the
    -- player kill counter still decides whether an award actually exists.
    if not credited and player:getVehicle() ~= nil then
        local deltaX = player:getX() - zombie:getX()
        local deltaY = player:getY() - zombie:getY()
        local deltaZ = math.abs(player:getZ() - zombie:getZ())

        credited = deltaZ < 0.5
            and deltaX * deltaX + deltaY * deltaY <= 36
    end

    table.insert(pendingPointDeaths, {
        x = zombie:getX(),
        y = zombie:getY(),
        z = zombie:getZ(),
        credited = credited,
        createdMs = getTimestampMs()
    })

    updatePointPopupPairing()
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

    clearPointPopupRuntime()
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
        -- Fire or a vehicle can credit many kills on one tick. The nearby
        -- crowd is the same for all of them, so scan the zombie list once.
        local nearbyThreats = getNearbyLivingZombieCount(player, 5)

        for _ = 1, newKills do
            local continuedChain = comboRuntime.currentCombo > 0
                and comboRuntime.remainingMs > 0

            awardFlexibility(data, player)
            awardMobility(data, player, continuedChain)
            awardBoldness(data, nearbyThreats)
            awardSpecialKill(data, player)

            if continuedChain then
                comboRuntime.currentCombo = comboRuntime.currentCombo + 1
            else
                comboRuntime.currentCombo = 1
            end

            comboRuntime.remainingMs = COMBO_WINDOW_MS
            local popupPoints = POINT_POPUP_BASE_POINTS

            if comboRuntime.currentCombo >= 2 then
                local earned = (comboRuntime.currentCombo - 1)
                    * COMBO_STEP_POINTS
                data[COMBO_SCORE_KEY] = data[COMBO_SCORE_KEY] + earned
                popupPoints = popupPoints + earned
            end

            if comboRuntime.currentCombo > data[BEST_COMBO_KEY] then
                data[BEST_COMBO_KEY] = comboRuntime.currentCombo
            end

            awardSpecialComboMilestone(data, comboRuntime.currentCombo)
            queuePointPopupAward(popupPoints)
        end

        comboRuntime.lastKills = kills
    end

    updatePointPopupPairing()

    ensureComboHud()
    comboHud:setCombo(comboRuntime.currentCombo, comboRuntime.remainingMs)
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

        clearPointPopupRuntime()
        comboRuntime.player = nil
        return
    end

    updateComboState(player, true)
end


local function onCreatePlayer(playerNumber, player)
    -- The combo, popups and death screen follow the first local player only.
    if playerNumber ~= 0 then
        return
    end

    resetComboRuntime(player)
end


-- =========================================================
-- DEATH SCREEN
-- =========================================================

local function muteRegularMusic()
    local soundManager = getSoundManager()

    if soundManager ~= nil and soundManager:getMusicVolume() ~= 0 then
        soundManager:setMusicVolume(0)
    end
end


local function restoreRegularMusic()
    local soundManager = getSoundManager()

    if soundManager ~= nil then
        soundManager:setMusicVolume(getCore():getOptionMusicVolume() / 10)
    end
end


-- Controller support: the first joypad player is the one the screen serves.
local function getDeathScreenJoypad()
    if JoypadState == nil or JoypadState.players == nil then
        return nil
    end

    return JoypadState.players[1]
end


NeonDeathScreen = ISPanel:derive("NeonDeathScreen")


function NeonDeathScreen:new(stats)
    local width = getCore():getScreenWidth()
    local height = getCore():getScreenHeight()
    local screen = ISPanel:new(0, 0, width, height)

    setmetatable(screen, self)
    self.__index = self

    screen.stats = stats
    screen.startedMs = getTimestampMs()
    screen.animationTick = 0
    screen.visualTick = 0
    screen.animationComplete = false
    screen.musicHandle = nil
    screen.restoreJoypadFocus = nil

    local assets = getDeathScreenAssets()

    screen.backgroundTexture = assets.background
    screen.reflectionTextures = assets.reflections
    screen.labelTextureFrames = assets.labels
    screen.rowGlyphFrames = assets.rowGlyphs
    screen.scoreGlyphFrames = assets.scoreGlyphs
    screen.gradeGlyphFrames = assets.gradeGlyphs

    -- The category rows never change while the screen is open, so they are
    -- built once here instead of on every rendered frame.
    screen.rows = {
        {
            textureFrames = assets.labels.kills,
            text = "KILLS",
            width = 0.20,
            target = stats.killScore,
            startTick = KILLS_SCORE_START_TICK,
            duration = KILLS_SCORE_DURATION
        },
        {
            textureFrames = assets.labels.combo,
            text = "COMBO",
            width = 0.23,
            target = stats.comboScore or 0,
            startTick = COMBO_SCORE_APPEAR_TICK,
            duration = SHORT_ROW_DURATION
        },
        {
            textureFrames = assets.labels.flexibility,
            text = "FLEXIBILITY",
            width = 0.39,
            target = stats.flexibilityScore or 0,
            startTick = FLEXIBILITY_SCORE_APPEAR_TICK,
            duration = SHORT_ROW_DURATION
        },
        {
            textureFrames = assets.labels.mobility,
            text = "MOBILITY",
            width = 0.31,
            target = stats.mobilityScore or 0,
            startTick = MOBILITY_SCORE_APPEAR_TICK,
            duration = SHORT_ROW_DURATION
        },
        {
            textureFrames = assets.labels.boldness,
            text = "BOLDNESS",
            width = 0.35,
            target = stats.boldnessScore or 0,
            startTick = BOLDNESS_SCORE_APPEAR_TICK,
            duration = SHORT_ROW_DURATION
        },
        {
            textureFrames = assets.labels.timeBonus,
            text = "TIME BONUS",
            width = 0.39,
            target = stats.survivalScore,
            startTick = TIME_SCORE_START_TICK,
            duration = TIME_SCORE_DURATION
        },
        {
            textureFrames = assets.labels.special,
            text = "SPECIAL",
            width = 0.28,
            target = stats.specialScore or 0,
            startTick = SPECIAL_SCORE_APPEAR_TICK,
            duration = SHORT_ROW_DURATION
        }
    }

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
    local elapsedMs = math.max(0, getTimestampMs() - self.startedMs)

    self.visualTick = math.floor(
        elapsedMs * ANIMATION_TICKS_PER_SECOND / 1000
    )

    if self.animationComplete then
        return
    end

    self.animationTick = self.visualTick

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
    -- The volume stays muted while the screen is open (see muteRegularMusic)
    -- because the soundtrack module restores it when the player dies.
    muteRegularMusic()
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

    for rowIndex, row in ipairs(self.rows) do
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
-- INPUT
-- =========================================================

function NeonDeathScreen:close()
    if activeScreen == self then
        activeScreen = nil
    end

    self:stopMusic()
    restoreRegularMusic()

    if getDeathScreenJoypad() ~= nil then
        setJoypadFocus(0, self.restoreJoypadFocus)
    end

    self.restoreJoypadFocus = nil
    self:setCapture(false)
    self:setVisible(false)
    self:removeFromUIManager()
end


-- One input both skips the tally and, once it has finished, closes it.
function NeonDeathScreen:advance()
    if not self.animationComplete then
        self:finishAnimation()
        return
    end

    self:close()
end


function NeonDeathScreen:onMouseDown(x, y)
    self:advance()
    return true
end


function NeonDeathScreen:onJoypadDown(button)
    if button == Joypad.AButton then
        self:advance()
    end
end


local function onDeathScreenKeyPressed(key)
    if activeScreen == nil then
        return
    end

    if key == Keyboard.KEY_SPACE
            or key == Keyboard.KEY_RETURN
            or key == Keyboard.KEY_NUMPADENTER then
        activeScreen:advance()
    end
end


-- =========================================================
-- SCREEN EVENTS
-- =========================================================

local DEATH_SCREEN_DELAY_MS = 333
local pendingSinceMs = 0


local function keepDeathScreenOnTop()
    if activeScreen == nil then
        return
    end

    activeScreen:updateAnimation()
    activeScreen:bringToTop()
    muteRegularMusic()

    -- The vanilla post-death UI may take the controller focus after this
    -- screen appears. Take it back and hand it over again on close.
    local joypadData = getDeathScreenJoypad()

    if joypadData ~= nil and joypadData.focus ~= activeScreen then
        activeScreen.restoreJoypadFocus = joypadData.focus
        setJoypadFocus(0, activeScreen)
    end
end


local function showDeathScreen()
    muteRegularMusic()

    if getTimestampMs() - pendingSinceMs < DEATH_SCREEN_DELAY_MS then
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
    -- Only the first local player gets the score screen. In multiplayer or
    -- split-screen this event can also report other characters.
    if player == nil or player ~= getPlayer() then
        return
    end

    -- Catch a kill credited on the same update as the player's death before
    -- freezing the score-screen statistics.
    updateComboState(player, false)

    local hoursSurvived = player:getHoursSurvived()
    local minutesSurvived = math.floor(hoursSurvived * 60)
    local kills = player:getZombieKills()
    local comboData = getComboModData(player)
    local comboScore = comboData[COMBO_SCORE_KEY]
    local flexibilityScore = comboData[FLEXIBILITY_SCORE_KEY]
    local mobilityScore = comboData[MOBILITY_SCORE_KEY]
    local boldnessScore = comboData[BOLDNESS_SCORE_KEY]
    local specialScore = comboData[SPECIAL_SCORE_KEY]

    local killScore = kills * KILL_POINTS
    local survivalScore = math.min(minutesSurvived, TIME_BONUS_MAX_MINUTES)
        * TIME_BONUS_POINTS_PER_MINUTE
    local totalScore = killScore
        + comboScore
        + flexibilityScore
        + mobilityScore
        + boldnessScore
        + survivalScore
        + specialScore

    pendingStats = {
        totalTime = formatTotalTime(hoursSurvived),
        killScore = killScore,
        comboScore = comboScore,
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
    clearPointPopupRuntime()

    if comboHud ~= nil then
        comboHud:setVisible(false)
    end

    pendingSinceMs = getTimestampMs()
    Events.OnTickEvenPaused.Remove(showDeathScreen)
    Events.OnTickEvenPaused.Add(showDeathScreen)
end


local function onMainMenuEnter()
    Events.OnTickEvenPaused.Remove(showDeathScreen)
    pendingStats = nil

    if activeScreen ~= nil then
        activeScreen:close()
    end

    clearPointPopupRuntime()

    if pointPopupHud ~= nil then
        pointPopupHud:removeFromUIManager()
        pointPopupHud = nil
    end

    if comboHud ~= nil then
        comboHud:removeFromUIManager()
        comboHud = nil
    end

    comboRuntime.player = nil
end


-- Load the score-screen art while the game starts instead of when the
-- player dies.
local function onGameStart()
    getDeathScreenAssets()
end


Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnGameStart.Add(onGameStart)
Events.OnMainMenuEnter.Add(onMainMenuEnter)
Events.OnTick.Add(onComboTick)
Events.OnZombieDead.Add(onZombieDead)
Events.OnTickEvenPaused.Add(keepDeathScreenOnTop)
Events.OnKeyPressed.Add(onDeathScreenKeyPressed)
Events.OnPlayerDeath.Add(onPlayerDeath)
